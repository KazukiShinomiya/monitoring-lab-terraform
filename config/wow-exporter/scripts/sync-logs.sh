#!/bin/bash
set -euo pipefail

# 実接続先はコンテナ env WOW_VPS_HOST で注入する（terragrunt.hcl → .env 由来）。
# 実FQDNのハードコード禁止（2026-06 監査 H-1: 機密露出）
VPS_HOST="${WOW_VPS_HOST:?WOW_VPS_HOST is not set (env 注入漏れ。terragrunt.hcl と .env を確認)}"
HTTP_LOG_DIR="/home/ubuntu/WOWHoneypot-master/log"
HTTPS_LOG_DIR="/home/ubuntu/WOWHoneypot-new/log"
LOCAL_LOG_DIR="/data/wow-logs"
SSH_KEY="/root/.ssh/id_ed25519"
STATE_FILE="/data/wow-logs/.sync_state"

mkdir -p "$LOCAL_LOG_DIR"

RSYNC_SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# HTTP access_log: --append で差分バイトのみ転送
rsync -az --append \
    -e "$RSYNC_SSH" \
    "${VPS_HOST}:${HTTP_LOG_DIR}/access_log" \
    "$LOCAL_LOG_DIR/access_log"

# HTTP wowhoneypot.log
rsync -az --append \
    -e "$RSYNC_SSH" \
    "${VPS_HOST}:${HTTP_LOG_DIR}/wowhoneypot.log" \
    "$LOCAL_LOG_DIR/wowhoneypot.log"

# HTTPS access_log (--ignore-missing-args: ファイル未生成時もエラーにしない)
rsync -az --append --ignore-missing-args \
    -e "$RSYNC_SSH" \
    "${VPS_HOST}:${HTTPS_LOG_DIR}/access_log" \
    "$LOCAL_LOG_DIR/access_log_https"

# HTTPS wowhoneypot.log
rsync -az --append --ignore-missing-args \
    -e "$RSYNC_SSH" \
    "${VPS_HOST}:${HTTPS_LOG_DIR}/wowhoneypot.log" \
    "$LOCAL_LOG_DIR/wowhoneypot_https.log"

# 転送後のファイルサイズを記録
ACCESS_LINES=$(wc -l < "$LOCAL_LOG_DIR/access_log")
WOW_LINES=$(wc -l < "$LOCAL_LOG_DIR/wowhoneypot.log")
ACCESS_HTTPS_LINES=$([ -f "$LOCAL_LOG_DIR/access_log_https" ] && wc -l < "$LOCAL_LOG_DIR/access_log_https" || echo 0)
WOW_HTTPS_LINES=$([ -f "$LOCAL_LOG_DIR/wowhoneypot_https.log" ] && wc -l < "$LOCAL_LOG_DIR/wowhoneypot_https.log" || echo 0)

cat > "$STATE_FILE" <<EOF
last_sync=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
access_log_lines=$ACCESS_LINES
wowhoneypot_log_lines=$WOW_LINES
access_log_https_lines=$ACCESS_HTTPS_LINES
wowhoneypot_https_log_lines=$WOW_HTTPS_LINES
EOF

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] sync complete: http=${ACCESS_LINES} lines, https=${ACCESS_HTTPS_LINES} lines"
