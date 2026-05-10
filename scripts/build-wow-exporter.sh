#!/bin/bash
set -euo pipefail

REMOTE_HOST="root@YOUR_SERVER_IP"
SSH_KEY="/home/ubuntu/.ssh/id_ed25519"
REMOTE_BUILD_DIR="/tmp/wow-exporter-build"
IMAGE_NAME="wow-exporter:latest"

echo "==> Syncing build context to ${REMOTE_HOST}..."
rsync -az --delete \
    -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
    "$(dirname "$0")/../config/wow-exporter/" \
    "${REMOTE_HOST}:${REMOTE_BUILD_DIR}/"

echo "==> Building Docker image on remote host..."
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${REMOTE_HOST}" \
    "docker build -t ${IMAGE_NAME} ${REMOTE_BUILD_DIR}"

echo "==> Build complete: ${IMAGE_NAME}"
