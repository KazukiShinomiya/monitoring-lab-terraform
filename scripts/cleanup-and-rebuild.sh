#!/bin/bash
# ==========================================
# 開発環境のクリーンアップと再構築スクリプト
# ==========================================
# このスクリプトは、開発コンテナとDockerリソースを
# クリーンアップして再構築します

set -e

echo "================================================"
echo "開発環境のクリーンアップ開始"
echo "================================================"
echo ""

# カレントディレクトリ確認（WSL2の場合は /mnt/e/work/labo、それ以外は現在地）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "📁 Working directory: $PROJECT_ROOT"
echo ""

echo "📋 現在のコンテナ状態:"
docker ps -a --filter "label=project=monitoring-lab" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
echo ""

echo "🛑 既存のコンテナを停止・削除中..."
docker compose down 2>/dev/null || true

echo "🗑️  monitoring-lab関連のコンテナを削除中..."
docker rm -f $(docker ps -aq --filter 'label=project=monitoring-lab') 2>/dev/null || true

echo "🗑️  monitoring-lab関連のボリュームを削除中..."
docker volume rm $(docker volume ls -q --filter 'name=monitoring-lab') 2>/dev/null || true

echo "🗑️  使われていないネットワークを削除中..."
docker network prune -f

echo "🗑️  使われていないイメージを削除中..."
docker image prune -a -f

echo ""
echo "================================================"
echo "開発環境の再構築開始"
echo "================================================"
echo ""

echo "🚀 最新のdocker-compose.ymlで起動中..."
docker compose up -d

echo ""
echo "⏳ コンテナ起動待機中..."
sleep 5

echo ""
echo "📋 新しいコンテナ状態:"
docker compose ps

echo ""
echo "✅ クリーンアップと再構築が完了しました！"
echo ""
echo "次のステップ:"
echo "  1. docker compose exec terragrunt sh"
echo "  2. cd terraform/envs/local"
echo "  3. terragrunt run-all init"
echo ""
