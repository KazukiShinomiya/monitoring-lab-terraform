#!/bin/bash
# Zabbix MCP server 用の自己署名証明書を作る。秘密鍵はリポジトリに置かない。
# 使い方: zabbix-mcp-tls.sh <絶対パス or docker volume 名> <SAN 例: IP:192.0.2.1 or DNS:zbx-mcp>
# 実行した Docker デーモンの上で作る。本番なら本番ホストで実行する。既存の鍵は上書きしない。
set -euo pipefail

DEST="${1:?保存先を指定する}"
SAN="${2:?SAN を指定する}"

docker run --rm -e SAN="$SAN" -v "$DEST:/d" alpine:3.24 sh -euc '
  [ ! -e /d/server.key ] || { echo "/d/server.key が既にある。上書きしない" >&2; exit 1; }
  apk add --no-cache --quiet openssl
  openssl req -x509 -newkey rsa:3072 -sha256 -days 825 -nodes \
    -subj "/CN=zabbix-mcp" -addext "subjectAltName=$SAN" \
    -keyout /d/server.key -out /d/server.crt 2>/dev/null
  chown 1997:1997 /d/server.key /d/server.crt
  chmod 0400 /d/server.key
  chmod 0444 /d/server.crt
'
echo "==> 証明書を作成した: $DEST/server.crt（SAN: $SAN）"
