#!/bin/bash
# ==========================================
# Container Environment Setup Script
# ==========================================
# このスクリプトは、Terraform/Terragruntコンテナ環境を
# セットアップします

set -e

# ----- 色定義 -----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# ----- コンテナ環境起動 -----
step "Terraform/Terragrunt開発環境を起動しています..."

# Docker Composeでコンテナを起動
docker-compose up -d

# コンテナの起動を待つ
info "コンテナの起動を待っています..."
sleep 5

# ----- Vaultの初期化確認 -----
step "Vaultの起動確認..."

# Vaultのヘルスチェック
VAULT_STATUS=$(docker exec monitoring-lab-vault-dev vault status -format=json | grep -o '"sealed":false' || echo "")

if [ -z "$VAULT_STATUS" ]; then
    warn "Vaultが起動していますが、Sealed状態の可能性があります"
    warn "開発モードでは自動的にUnsealされるはずです"
else
    info "✓ Vault is ready (Unsealed)"
fi

# ----- Terragruntバージョン確認 -----
step "Terragruntのバージョン確認..."

info "Terragrunt (includes Terraform):"
docker exec monitoring-lab-terragrunt terragrunt --version
docker exec monitoring-lab-terragrunt terraform version

# ----- スクリプトに実行権限を付与 -----
step "ヘルパースクリプトに実行権限を付与..."
chmod +x scripts/tg.sh
chmod +x scripts/setup-remote-config.sh
chmod +x scripts/cleanup-and-rebuild.sh

info "✓ 実行権限を付与しました"

# ----- 完了メッセージ -----
echo ""
info "セットアップが完了しました！"
echo ""
echo "=================================="
echo "  使用方法"
echo "=================================="
echo ""
echo "Terragruntコマンド実行 (推奨):"
echo "  ./scripts/tg.sh <command>"
echo "  例: ./scripts/tg.sh run-all init"
echo ""
echo "リモートサーバーへ設定ファイル転送:"
echo "  ./scripts/setup-remote-config.sh"
echo ""
echo "Vaultへのアクセス:"
echo "  URL: http://localhost:8200"
echo "  Token: root"
echo ""
echo "Terragruntコンテナシェルに入る:"
echo "  docker exec -it monitoring-lab-terragrunt sh"
echo ""
echo "コンテナを停止:"
echo "  docker compose down"
echo ""
echo "=================================="
