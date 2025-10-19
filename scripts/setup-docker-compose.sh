#!/bin/bash
# Docker Compose プラグインインストールスクリプト (リモートサーバー上で実行)

set -e

echo "=== Docker Compose Plugin Installation ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo ""

# 1. Docker Composeプラグインのインストール
echo "[1/3] Installing docker-compose-plugin..."
sudo apt update
sudo apt install -y docker-compose-plugin

# 2. バージョン確認
echo ""
echo "[2/3] Verifying installation..."
docker compose version

# 3. 動作テスト
echo ""
echo "[3/3] Testing docker compose..."
docker compose --help | head -10

echo ""
echo "✅ Docker Compose plugin installed successfully!"
