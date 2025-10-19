#!/bin/bash
# ==========================================
# Remote Server Docker Engine Setup Script
# ==========================================
# このスクリプトはリモートサーバー (YOUR_SERVER_IP) 上で実行してください

set -e

echo "=========================================="
echo "Docker Engine Setup for Monitoring Lab"
echo "=========================================="
echo ""

# Docker Engine のインストール状態を確認
if command -v docker &> /dev/null; then
    echo "✅ Docker is already installed:"
    docker --version
    echo ""
else
    echo "📦 Installing Docker Engine..."
    sudo apt update
    sudo apt install -y docker.io
    echo "✅ Docker Engine installed successfully"
    echo ""
fi

# Docker サービスの起動と自動起動設定
echo "🚀 Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker
echo "✅ Docker service started and enabled"
echo ""

# 現在のユーザーを docker グループに追加
echo "👤 Adding current user ($USER) to docker group..."
sudo usermod -aG docker $USER
echo "✅ User added to docker group"
echo ""

# Docker の状態確認
echo "📊 Docker service status:"
sudo systemctl status docker --no-pager | head -10
echo ""

# Docker グループ確認
echo "👥 Current user groups:"
groups
echo ""

echo "=========================================="
echo "✅ Docker Engine setup completed!"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT:"
echo "   You need to log out and log back in (or run 'newgrp docker')"
echo "   for the group changes to take effect."
echo ""
echo "To verify Docker works without sudo:"
echo "   docker ps"
echo ""
