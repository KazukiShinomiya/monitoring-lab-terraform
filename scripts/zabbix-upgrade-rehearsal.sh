#!/bin/bash
# DB ダンプの写しを、外へ出られない使い捨て環境で新しい Zabbix に移行して確かめる。
# 使い方: zabbix-upgrade-rehearsal.sh <dump(pg_dump -Fc)> <タグ 例: alpine-8.0.0>
# 環境変数: REHEARSAL_ZABBIX_USER(既定 Admin) / REHEARSAL_ZABBIX_PASSWORD（API と MCP の確認に使う）
# --internal のネットワークで動かすので、監視対象や外部 API には届かない。
set -uo pipefail

DUMP="${1:?dump を指定する}"; TAG="${2:?タグを指定する}"
[ -f "$DUMP" ] || { echo "dump が無い: $DUMP" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P=zbx-rehearsal; NET=$P-net; TLS=$P-tls; SUBNET=172.31.254
SERVER_IMAGE="$P-server:$TAG"
CURL_IMAGE=curlimages/curl:8.10.1
DBPASS="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
ZUSER="${REHEARSAL_ZABBIX_USER:-Admin}"; ZPASS="${REHEARSAL_ZABBIX_PASSWORD:-}"
FAILS=0

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS+1)); }
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
cleanup() {
  docker rm -f $P-db $P-server $P-web $P-mcp $P-agent >/dev/null 2>&1
  docker network rm $NET >/dev/null 2>&1
  docker volume rm $TLS >/dev/null 2>&1
  docker rmi "$SERVER_IMAGE" >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

# ネットワークを閉じる前に、要るイメージをすべて揃える
for i in postgres:15-alpine "zabbix/zabbix-web-apache-pgsql:$TAG" "zabbix/zabbix-agent2:$TAG" "zabbix/zabbix-mcp-server:$TAG" "$CURL_IMAGE"; do
  docker pull -q "$i" >/dev/null || { echo "取得できない: $i" >&2; exit 2; }
done
docker build -q --pull --build-arg ZBX_IMAGE_TAG="$TAG" -t "$SERVER_IMAGE" "$ROOT/config/zabbix/server" >/dev/null \
  || { echo "派生イメージを作れない" >&2; exit 2; }
docker network create --internal --subnet $SUBNET.0/24 $NET >/dev/null

echo "==> DB を復元"
docker run -d --name $P-db --network $NET --network-alias postgres \
  -e POSTGRES_DB=zabbix -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="$DBPASS" \
  -e 'POSTGRES_INITDB_ARGS=--encoding=UTF-8 --locale=C' postgres:15-alpine >/dev/null
for _ in $(seq 60); do docker exec $P-db pg_isready -U zabbix -d zabbix -h 127.0.0.1 >/dev/null 2>&1 && break; sleep 2; done
docker exec -i $P-db pg_restore -U zabbix -d zabbix --no-owner --exit-on-error < "$DUMP" \
  || { echo "復元に失敗" >&2; exit 1; }
sql() { docker exec $P-db psql -U zabbix -d zabbix -Atc "$1"; }
BEFORE="$(sql 'select mandatory from dbversion')"; echo "      移行前 dbversion=$BEFORE"

echo "==> server を起動（DB 移行）"
START=$(date +%s)
docker run -d --name $P-server --network $NET --network-alias zbx_server \
  -e DB_SERVER_HOST=postgres -e DB_SERVER_PORT=5432 -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="$DBPASS" -e POSTGRES_DB=zabbix \
  -e ZBX_DB_NAME=zabbix -e ZBX_CACHESIZE=128M -e ZBX_HISTORYCACHESIZE=64M -e ZBX_TRENDCACHESIZE=32M -e ZBX_VALUECACHESIZE=128M \
  -e ZBX_STARTPOLLERS=10 -e ZBX_STARTPINGERS=5 -e ZBX_STARTDISCOVERERS=3 -e PHP_TZ=Asia/Tokyo \
  -e SWITCHBOT_TOKEN=dummy -e SWITCHBOT_SECRET=dummy -e SWITCHBOT_TIMEOUT=10 \
  -v "$ROOT/config/zabbix/scripts/externalscripts:/usr/lib/zabbix/externalscripts:ro" \
  "$SERVER_IMAGE" >/dev/null
UP=0
for _ in $(seq "${REHEARSAL_TIMEOUT_TICKS:-360}"); do
  docker logs $P-server 2>&1 | grep -qE 'server #[0-9]+ started' && { UP=1; break; }
  [ "$(docker inspect -f '{{.State.Running}}' $P-server)" = true ] || break
  sleep 5
done
AFTER="$(sql 'select mandatory from dbversion')"
echo "      所要 $(( $(date +%s) - START )) 秒、移行後 dbversion=$AFTER"
if [ "$UP" = 1 ]; then pass "server が起動した"; else fail "server が起動しない"; docker logs --tail 40 $P-server 2>&1; fi
if [ "$AFTER" != "$BEFORE" ]; then pass "DB スキーマが移行された"; else fail "dbversion が変わっていない"; fi
docker logs $P-server 2>&1 | grep -iE 'cannot|error|failed' | grep -v 'check_switchbot' | sort | uniq -c | sort -rn | head -10 | sed 's/^/      log: /'

as_srv() { docker exec $P-server sh -c "$1"; }
check "server が非 root で動く"          test "$(docker exec $P-server id -u)" = 1997
check "python3 と requests が使える"     as_srv 'python3 -c "import requests"'
check "外部スクリプトを起動できる"        as_srv '/usr/lib/zabbix/externalscripts/check_switchbot.py --help >/dev/null'
check "SWITCHBOT の環境変数が server に届く" as_srv 'tr "\0" "\n" </proc/1/environ | grep -q "^SWITCHBOT_TOKEN="'

echo "==> web を起動"
docker run -d --name $P-web --network $NET --network-alias zbx_web \
  -e ZBX_SERVER_HOST=zbx_server -e ZBX_SERVER_PORT=10051 -e DB_SERVER_HOST=postgres -e DB_SERVER_PORT=5432 \
  -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="$DBPASS" -e POSTGRES_DB=zabbix -e ZBX_DB_NAME=zabbix -e PHP_TZ=Asia/Tokyo \
  -e "ZBX_SERVER_NAME=Monitoring Lab" -e ZBX_MAXEXECUTIONTIME=600 -e ZBX_MEMORYLIMIT=256M -e ZBX_POSTMAXSIZE=32M -e ZBX_UPLOADMAXFILESIZE=16M \
  "zabbix/zabbix-web-apache-pgsql:$TAG" >/dev/null

# curl の実行元は ALLOWEDIP に入れた .50。接続拒否の確認だけ .51 から打つ
hcurl() { docker run --rm --network $NET --ip $SUBNET.50 -v $TLS:/certs:ro "$CURL_IMAGE" -sS --max-time 30 "$@"; }
api() { hcurl -H 'Content-Type: application/json' -d "$1" http://zbx_web:8080/api_jsonrpc.php; }
docker volume create $TLS >/dev/null
bash "$ROOT/scripts/zabbix-mcp-tls.sh" $TLS DNS:zbx-mcp >/dev/null || fail "証明書を作れない"
API_VER=""
for _ in $(seq 60); do
  API_VER="$(api '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}' 2>/dev/null | sed -nE 's/.*"result":"([^"]+)".*/\1/p')"
  [ -n "$API_VER" ] && break; sleep 3
done
if [ -n "$API_VER" ]; then pass "web の API が応答した（$API_VER）"; else fail "web の API が応答しない"; docker logs --tail 20 $P-web 2>&1; fi

echo "==> agent2 を起動"
docker run -d --name $P-agent --network $NET --network-alias zbx_agent \
  -e ZBX_PASSIVE_ALLOW=true -e ZBX_PASSIVESERVERS=zbx_server -e ZBX_ACTIVE_ALLOW=false \
  -e "ZBX_HOSTNAME=Zabbix server" -e ZBX_METADATA=Linux -e TZ=Asia/Tokyo -e ZBX_DEBUGLEVEL=3 \
  "zabbix/zabbix-agent2:$TAG" >/dev/null
AGENT_VER=""
for _ in $(seq 20); do
  AGENT_VER="$(docker exec $P-server zabbix_get -s zbx_agent -k agent.version 2>/dev/null)" && [ -n "$AGENT_VER" ] && break; sleep 2
done
if [ -n "$AGENT_VER" ]; then pass "server から agent2 に問い合わせできた（$AGENT_VER）"; else fail "agent2 に問い合わせできない"; docker logs --tail 20 $P-agent 2>&1; fi

echo "==> MCP server を起動（読み取り専用の設定）"
docker run -d --name $P-mcp --network $NET --network-alias zbx-mcp \
  -e ZBX_FRONTEND_URL=http://zbx_web:8080/api_jsonrpc.php -e ZBX_ALLOWEDIP=$SUBNET.50 \
  -e ZBX_TLSACCEPT=cert -e ZBX_TLSCERTFILE=server.crt -e ZBX_TLSKEYFILE=server.key \
  -e 'ZBX_ALLOWTOOL_REGEXP_0=^(hostgroup|templategroup|host|template|problem|maintenance|trigger)_get$' -e 'ZBX_DENYTOOL_1=*' \
  -v $TLS:/var/lib/zabbix/enc:ro "zabbix/zabbix-mcp-server:$TAG" >/dev/null
sleep 5
if [ "$(docker inspect -f '{{.State.Running}}' $P-mcp)" = true ]; then pass "MCP server が起動した"; else fail "MCP server が起動しない"; docker logs --tail 20 $P-mcp 2>&1; fi
CODE="$(docker run --rm --network $NET --ip $SUBNET.51 -v $TLS:/certs:ro "$CURL_IMAGE" -sS --max-time 15 -o /dev/null -w '%{http_code}' --cacert /certs/server.crt -X POST https://zbx-mcp:8443/mcp 2>/dev/null)"
if [ "$CODE" = 403 ]; then pass "許可外の IP は 403"; else fail "許可外の IP が 403 でない（$CODE）"; fi

if [ -z "$ZPASS" ]; then
  echo "SKIP  API トークンと MCP ツールの確認（REHEARSAL_ZABBIX_PASSWORD が無い）"
else
  # 使い捨て DB の中だけで作るトークン。表示せず、環境ごと消える
  SESSION="$(api "$(printf '{"jsonrpc":"2.0","method":"user.login","params":{"username":"%s","password":"%s"},"id":1}' "$ZUSER" "$ZPASS")" | sed -nE 's/.*"result":"([^"]+)".*/\1/p')"
  auth=(-H "Authorization: Bearer $SESSION" -H 'Content-Type: application/json')
  TID="$(hcurl "${auth[@]}" -d '{"jsonrpc":"2.0","method":"token.create","params":{"name":"rehearsal","userid":"1"},"id":2}' http://zbx_web:8080/api_jsonrpc.php | sed -nE 's/.*"tokenids":\["([0-9]+)".*/\1/p')"
  TOKEN="$(hcurl "${auth[@]}" -d "{\"jsonrpc\":\"2.0\",\"method\":\"token.generate\",\"params\":[\"$TID\"],\"id\":3}" http://zbx_web:8080/api_jsonrpc.php | sed -nE 's/.*"token":"([0-9a-f]+)".*/\1/p')"
  if [ -n "$TOKEN" ]; then pass "API トークンを発行できた"; else fail "API トークンを発行できない"; fi
  mcp() { hcurl --cacert /certs/server.crt -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d "$1" https://zbx-mcp:8443/mcp; }
  INIT="$(mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"rehearsal","version":"1"}}}')"
  case "$INIT" in *'"serverInfo"'*) pass "MCP の initialize が通った（TLS 検証あり）";; *) fail "MCP の initialize が失敗: $INIT";; esac
  TOOLS="$(mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | grep -oE '"name":"[a-z_]+"' | cut -d'"' -f4 | sort | tr '\n' ' ')"
  echo "      公開ツール: $TOOLS"
  case " $TOOLS" in *" host_get "*) pass "読み取りツールが見える";; *) fail "host_get が見えない";; esac
  case " $TOOLS" in *" history_get "*|*" macro_get "*|*" item_get "*|*" problem_close "*|*" maintenance_create "*) fail "拒否すべきツールが見える";; *) pass "機微なツールと書き込みツールは見えない";; esac
  HOSTS="$(mcp '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"host_get","arguments":{"limit":5}}}')"
  case "$HOSTS" in *'"isError":true'*|*'"error"'*|'') fail "host_get が失敗: $HOSTS";; *) pass "host_get が結果を返した";; esac
  DENIED="$(mcp '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"maintenance_delete","arguments":{"maintenanceids":["1"]}}}')"
  case "$DENIED" in *'"isError":true'*|*'"error"'*) pass "拒否したツールの呼び出しが弾かれた";; *) fail "maintenance_delete が弾かれない: $DENIED";; esac
fi

echo; echo "失敗 $FAILS 件"
[ "$FAILS" = 0 ]
