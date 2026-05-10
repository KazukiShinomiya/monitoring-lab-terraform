#!/bin/bash
set -euo pipefail

VPS_HOST="root@ik1-427-45900.vs.sakura.ne.jp"
VPS_LOG_DIR="/home/ubuntu/WOWHoneypot-master/log"
LOCAL_LOG_DIR="/data/wow-logs"
SSH_KEY="/root/.ssh/id_ed25519"
STATE_FILE="/data/wow-logs/.sync_state"

mkdir -p "$LOCAL_LOG_DIR"

ssh_cmd() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$VPS_HOST" "$@"
}

# access_log: --append で差分バイトのみ転送
rsync -az --append \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    "${VPS_HOST}:${VPS_LOG_DIR}/access_log" \
    "$LOCAL_LOG_DIR/access_log"

# wowhoneypot.log: 同様に差分転送
rsync -az --append \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10" \
    "${VPS_HOST}:${VPS_LOG_DIR}/wowhoneypot.log" \
    "$LOCAL_LOG_DIR/wowhoneypot.log"

# 転送後のファイルサイズを記録
ACCESS_LINES=$(wc -l < "$LOCAL_LOG_DIR/access_log")
WOW_LINES=$(wc -l < "$LOCAL_LOG_DIR/wowhoneypot.log")

cat > "$STATE_FILE" <<EOF
last_sync=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
access_log_lines=$ACCESS_LINES
wowhoneypot_log_lines=$WOW_LINES
EOF

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] sync complete: access_log=${ACCESS_LINES} lines, wowhoneypot.log=${WOW_LINES} lines"
