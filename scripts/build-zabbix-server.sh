#!/bin/bash
# 本番ホストで Zabbix server の派生イメージを作る。使い方: build-zabbix-server.sh alpine-8.0.0
set -euo pipefail

TAG="${1:?使い方: $0 <公式イメージのタグ 例: alpine-8.0.0>}"
REMOTE_HOST="${TARGET_USER:-ubuntu}@${TARGET_HOST:?TARGET_HOST is not set (.env を読み込んでから実行)}"
REMOTE_PORT="${TARGET_PORT:-22}"
CONTEXT="$(cd "$(dirname "$0")/../config/zabbix/server" && pwd)"

tar -C "$CONTEXT" -cf - Dockerfile | ssh -p "$REMOTE_PORT" "$REMOTE_HOST" \
  "docker build --pull --build-arg ZBX_IMAGE_TAG='${TAG}' -t 'zabbix-server-local:${TAG}' -"
echo "==> Build complete: zabbix-server-local:${TAG}"
