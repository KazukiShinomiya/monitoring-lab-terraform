# Zabbix 7.4 → 8.0 移行手順

対象は server / web / agent2 の更新と MCP server の追加。DB は移行すると 7.4 に戻せないので、切り戻しはダンプの復元で行う。
下の `$TAG` は `alpine-8.0.0` のような公式タグ、`$HOST` は本番ホスト。

## 1. イメージの確認

4 つのリポジトリすべてに `$TAG` があることを確かめる。

```bash
for r in zabbix-server-pgsql zabbix-web-apache-pgsql zabbix-agent2 zabbix-mcp-server; do
  docker manifest inspect "zabbix/$r:$TAG" >/dev/null && echo "ok $r" || echo "MISSING $r"
done
```

タグが `alpine-8.0.0` でなければ、`terraform/envs/local/zabbix/terragrunt.hcl`（server / web / MCP）、`terraform/envs/local/zabbix-agent/terragrunt.hcl`、`config/zabbix/server/Dockerfile` の既定値を直す。

## 2. リハーサル（本番を止めない）

ダンプには認証情報が含まれる。権限を絞って扱い、リハーサルが終わったら手元の写しを消す。

```bash
ssh "$HOST" 'umask 077; docker exec monitoring-lab-postgres pg_dump -U zabbix -Fc zabbix > ~/zabbix-rehearsal.dump'
umask 077; scp "$HOST:zabbix-rehearsal.dump" /tmp/zabbix-rehearsal.dump
REHEARSAL_ZABBIX_PASSWORD='<Admin のパスワード>' bash scripts/zabbix-upgrade-rehearsal.sh /tmp/zabbix-rehearsal.dump "$TAG"
shred -u /tmp/zabbix-rehearsal.dump; ssh "$HOST" 'shred -u ~/zabbix-rehearsal.dump'
```

全項目が PASS になること。表示される所要時間が、本番の DB 移行の目安になる。

## 3. 本番の事前準備

ここまではサービスに影響しない。

1. GitHub secret `ZBX_MCP_ALLOWEDIP` に接続元を入れる（WSL からなら、本番から見た送信元の IP）。
2. 本番ホストで証明書を作る。`mkdir -p ~/monitoring-lab/zabbix/mcp-tls` のあと、リポジトリの `scripts/zabbix-mcp-tls.sh` を本番ホストで `/home/ubuntu/monitoring-lab/zabbix/mcp-tls IP:<本番の IP>` を引数に実行する。
3. 派生イメージを作る: `bash scripts/build-zabbix-server.sh "$TAG"`（`.env` を読み込んでから）。

## 4. 本番の移行

```bash
ssh "$HOST" docker stop monitoring-lab-zbx_server
ssh "$HOST" 'umask 077; docker exec monitoring-lab-postgres pg_dump -U zabbix -Fc zabbix > ~/zabbix-pre-8.0.dump && ls -l ~/zabbix-pre-8.0.dump'
```

ダンプの大きさが 0 でないことを確かめてから、PR をマージする。apply が `zabbix` → `zabbix-agent` の順に作り直す。

## 5. 移行後の確認

- `select mandatory from dbversion` が移行前より上がっている
- server のログに `database upgrade fully completed` と `server #1 started` がある
- Web UI に入れる。ホスト 2 台の監視データが増えている
- `check_switchbot.py` の項目が値を取れている（`Timeout` は移行前から出ているので、頻度を比べる）
- Grafana の統合ダッシュボードで Zabbix のパネルが出る（trend を読むパネルも）
- 使っているテンプレートに新しい版が要るか確かめる（自動では更新されない）

## 6. MCP の接続

1. Zabbix に読み取り権限のみのユーザーを作り、役割で API アクセスを許し、期限付きの API トークンを発行する。
2. `.mcp.json.example` の `zabbix` を `.mcp.json` に写して IP を書き換える。
3. 自己署名なので、本番の `mcp-tls/server.crt` を手元に写す。環境変数 `ZABBIX_MCP_TOKEN` にトークンを、`NODE_EXTRA_CA_CERTS` に証明書のパスを入れて Claude Code を起動する。

ツールの出力には監視対象の文字列が混ざる。指示として扱わない。

## 7. 切り戻し

```bash
ssh "$HOST" docker stop monitoring-lab-zbx_server monitoring-lab-zbx_web
ssh "$HOST" 'docker exec monitoring-lab-postgres dropdb -U zabbix --maintenance-db=postgres zabbix
docker exec monitoring-lab-postgres createdb -U zabbix --maintenance-db=postgres -E UTF8 -T template0 --locale=C zabbix
docker exec -i monitoring-lab-postgres pg_restore -U zabbix -d zabbix --no-owner --exit-on-error < ~/zabbix-pre-8.0.dump'
```

そのあと PR を revert して apply する。7.4 の起動にはリポジトリから消した `init-zabbix-server.sh` が要る。本番ホストのファイルは消さずに残しておく。

## 8. 片付け

- `home_env` の `environments.yaml` の版数とポート（8443）を更新する
- 安定を確かめてから、本番の `zabbix-pre-8.0.dump` と `zabbix/scripts/init-zabbix-server.sh` を消す
