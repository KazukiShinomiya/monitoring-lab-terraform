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

# VPS 側のファイルの大きさを返す（無ければ空）。
# VPS 側は rrsync -ro なので ssh でコマンドは打てないが、--list-only の一覧は取れる
remote_size() {
    rsync --list-only --no-human-readable --ignore-missing-args \
        -e "$RSYNC_SSH" "${VPS_HOST}:$1" | awk 'NR == 1 { print $2 }'
}

# 1 本を --append で引く。VPS 側がローテーションされていれば前の世代を引き切ってから入れ替える。
# --append は VPS 側が手元より小さいと終了コード 0 のまま黙って飛ばすため、大きさを先に比べる。
# VPS 側は番号付き・nodateext・delaycompress なので、直前の世代は常に圧縮なしの <名前>.1 にある。
# 手元が縮んでも exporter（main.py）はオフセットを 0 に戻すので、入れ替えには耐える
sync_log() {
    local remote="$1" local_path="$2" optional="$3"
    local rsize lsize prev_size

    rsize=$(remote_size "$remote")
    if [ -z "$rsize" ]; then
        [ "$optional" = optional ] && return 0
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ERROR: ${remote} が VPS 側に無い" >&2
        return 1
    fi

    lsize=$(stat -c %s "$local_path" 2>/dev/null || echo 0)
    if [ "$rsize" -lt "$lsize" ]; then
        prev_size=$(remote_size "${remote}.1")
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] rotation detected: ${remote} (VPS ${rsize} < local ${lsize}, .1 ${prev_size:-missing})"
        if [ -n "$prev_size" ] && [ "$prev_size" -ge "$lsize" ]; then
            rsync -az --append -e "$RSYNC_SSH" "${VPS_HOST}:${remote}.1" "$local_path"
        else
            # .1 が手元より小さい（2 回以上回った等）なら継ぎ足しようがない。取りこぼしとして記録して進む
            echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] WARN: ${remote}.1 から引き切れない。前の世代の末尾を取りこぼす" >&2
        fi
        mv -f "$local_path" "${local_path}.1"
    fi

    rsync -az --append -e "$RSYNC_SSH" "${VPS_HOST}:${remote}" "$local_path"
}

sync_log "${HTTP_LOG_DIR}/access_log"       "$LOCAL_LOG_DIR/access_log"           required
sync_log "${HTTP_LOG_DIR}/wowhoneypot.log"  "$LOCAL_LOG_DIR/wowhoneypot.log"      required
# HTTPS はファイル未生成時もエラーにしない
sync_log "${HTTPS_LOG_DIR}/access_log"      "$LOCAL_LOG_DIR/access_log_https"     optional
sync_log "${HTTPS_LOG_DIR}/wowhoneypot.log" "$LOCAL_LOG_DIR/wowhoneypot_https.log" optional

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
