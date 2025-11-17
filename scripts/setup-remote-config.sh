#!/bin/bash
# ==========================================
# リモートサーバー完全セットアップスクリプト
# ==========================================
# このスクリプトは以下を実行します:
# 1. SSH接続確認
# 2. リモートディレクトリ作成
# 3. 設定ファイルの作成と転送
# 4. 権限設定

set -e

# 色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 環境変数から取得
TARGET_HOST=${TARGET_HOST:-YOUR_SERVER_IP}
TARGET_USER=${TARGET_USER:-ubuntu}
# ホームディレクトリ配下に変更（sudo不要）
REMOTE_BASE_DIR=${REMOTE_BASE_DIR:-~/monitoring-lab}

echo "================================================"
echo "リモートサーバー完全セットアップ"
echo "================================================"
echo "Target: ${TARGET_USER}@${TARGET_HOST}"
echo "Remote Dir: ${REMOTE_BASE_DIR}"
echo ""

# ========== STEP 1: SSH接続確認 ==========
step "1/4: SSH接続確認..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 ${TARGET_USER}@${TARGET_HOST} exit 2>/dev/null; then
    info "✓ SSH接続成功"
else
    error "SSH接続に失敗しました。以下を確認してください:
  - ホスト: ${TARGET_HOST}
  - ユーザー: ${TARGET_USER}
  - SSH鍵が正しく設定されているか (~/.ssh/id_rsa)
  - サーバーが起動しているか"
fi
echo ""

# ========== STEP 2: リモートディレクトリ作成 ==========
step "2/4: リモートディレクトリ作成..."
ssh ${TARGET_USER}@${TARGET_HOST} "mkdir -p ${REMOTE_BASE_DIR}/{prometheus,grafana/provisioning/{datasources,dashboards},zabbix/scripts/{externalscripts,alertscripts,userparameters}} && \
chmod -R 755 ${REMOTE_BASE_DIR}"
info "✓ ディレクトリ作成完了: ${REMOTE_BASE_DIR}"
echo ""

# ========== STEP 3: 設定ファイルの作成と転送 ==========
step "3/4: 設定ファイルの作成と転送..."

# Prometheus設定ファイルをリモートで直接作成
info "Creating prometheus.yml on remote server..."
ssh ${TARGET_USER}@${TARGET_HOST} "cat > ${REMOTE_BASE_DIR}/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF"
info "✓ prometheus.yml created"

# Grafana datasources設定ファイルをリモートで直接作成
info "Creating datasources.yml on remote server..."
ssh ${TARGET_USER}@${TARGET_HOST} "cat > ${REMOTE_BASE_DIR}/grafana/provisioning/datasources/datasources.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF"
info "✓ datasources.yml created"

# Zabbix外部スクリプトの転送
info "Transferring Zabbix external scripts..."
# ローカルの外部スクリプトディレクトリからリモートへコピー
if [ -d "config/zabbix/scripts/externalscripts" ]; then
    scp -r config/zabbix/scripts/externalscripts/* ${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE_DIR}/zabbix/scripts/externalscripts/
    info "✓ External scripts transferred"
else
    warn "config/zabbix/scripts/externalscripts not found, skipping script transfer"
fi

# 初期化スクリプトの転送
if [ -f "config/zabbix/scripts/init-zabbix-server.sh" ]; then
    scp config/zabbix/scripts/init-zabbix-server.sh ${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE_DIR}/zabbix/scripts/
    info "✓ Init script transferred"
else
    warn "config/zabbix/scripts/init-zabbix-server.sh not found"
fi

# 実行権限を付与
ssh ${TARGET_USER}@${TARGET_HOST} "chmod +x ${REMOTE_BASE_DIR}/zabbix/scripts/externalscripts/*.py ${REMOTE_BASE_DIR}/zabbix/scripts/externalscripts/*.sh ${REMOTE_BASE_DIR}/zabbix/scripts/init-zabbix-server.sh 2>/dev/null || true"
info "✓ Script permissions set"

echo ""

# ========== STEP 4: 権限確認 ==========
step "4/4: 権限とファイル確認..."
ssh ${TARGET_USER}@${TARGET_HOST} "ls -la ${REMOTE_BASE_DIR}/ && \
echo '' && \
echo '=== Prometheus config ===' && \
cat ${REMOTE_BASE_DIR}/prometheus/prometheus.yml && \
echo '' && \
echo '=== Grafana datasources ===' && \
cat ${REMOTE_BASE_DIR}/grafana/provisioning/datasources/datasources.yml"

echo ""
echo "================================================"
info "✅ リモートサーバーのセットアップ完了！"
echo "================================================"
echo ""
echo "次のステップ:"
echo "  1. 開発コンテナを起動:"
echo "     docker compose up -d"
echo ""
echo "  2. Terragruntコンテナに接続:"
echo "     docker compose exec terragrunt sh"
echo ""
echo "  3. Terragrunt初期化:"
echo "     cd terraform/envs/local"
echo "     terragrunt run-all init"
echo ""
echo "  4. デプロイ実行:"
echo "     terragrunt run-all apply"
echo ""
