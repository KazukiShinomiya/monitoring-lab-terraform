#!/bin/bash
set -euo pipefail

# 接続先は root.hcl と同じ環境変数（.env 由来）で決める。実IPのハードコード禁止
# 鍵の選択とホスト鍵の検査は ssh の既定（ssh_config・agent・known_hosts）に任せる
REMOTE_HOST="${TARGET_USER:-ubuntu}@${TARGET_HOST:?TARGET_HOST is not set (.env を読み込んでから実行)}"
REMOTE_PORT="${TARGET_PORT:-22}"
REMOTE_BUILD_DIR="/tmp/wow-exporter-build"
IMAGE_NAME="wow-exporter:latest"

echo "==> Syncing build context to ${REMOTE_HOST}..."
rsync -az --delete \
    -e "ssh -p ${REMOTE_PORT}" \
    "$(dirname "$0")/../config/wow-exporter/" \
    "${REMOTE_HOST}:${REMOTE_BUILD_DIR}/"

echo "==> Building Docker image on remote host..."
ssh -p "${REMOTE_PORT}" "${REMOTE_HOST}" \
    "docker build -t ${IMAGE_NAME} ${REMOTE_BUILD_DIR}"

echo "==> Build complete: ${IMAGE_NAME}"
