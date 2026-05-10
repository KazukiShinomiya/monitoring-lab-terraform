#!/bin/sh
set -e

# SSH鍵の権限を修正（read_onlyマウントの場合はスキップ）
if [ -f /root/.ssh/id_ed25519 ]; then
    chmod 600 /root/.ssh/id_ed25519 2>/dev/null || true
fi

# 初回同期（起動時に即時実行）
echo "[entrypoint] Running initial log sync..."
/app/scripts/sync-logs.sh || echo "[entrypoint] Initial sync failed, will retry on cron"

# cron ジョブ登録（10分ごとに同期 - スパイク抑制のため）
echo "*/10 * * * * /app/scripts/sync-logs.sh >> /var/log/wow-sync.log 2>&1" | crontab -
crond

echo "[entrypoint] Starting exporter on port ${EXPORTER_PORT:-9200}..."
exec python3 -m exporter.main
