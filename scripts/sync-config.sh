#!/bin/bash
# ==========================================
# 設定ファイル同期スクリプト
# ==========================================
# ローカルの config/ をリモートサーバーに転送してサービスをリロードする
#
# 使い方:
#   ./scripts/sync-config.sh prometheus     # prometheus.yml + alerts.yml → ホットリロード
#   ./scripts/sync-config.sh alertmanager   # alertmanager.yml (URL置換) → ホットリロード
#   ./scripts/sync-config.sh grafana        # dashboards/ + datasources.yml → 再起動
#   ./scripts/sync-config.sh snmp           # snmp.yml → SNMP Exporter 再起動
#   ./scripts/sync-config.sh tekken-update  # tekken_bot プロジェクトから tekken.json をコピー
#   ./scripts/sync-config.sh all            # 全サービス（tekken-update は含まない）
#
# 前提条件:
#   - WSL2 Ubuntu-24.04 上で実行、またはリモートへ SSH 接続可能な環境
#   - .env に SLACK_WEBHOOK_URL が設定済み（alertmanager 同期時に使用）
#   - tekken-update: TEKKEN_SOURCE_DIR が設定済み、または /mnt/e/work/tekken_bot がマウント済み

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }
step()  { echo -e "${BLUE}[>>]${NC}  $1"; }

# .env から変数を読み込む（スクリプトのあるディレクトリの親 = リポジトリルートを探す）
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.env"
  set +a
fi

TARGET_HOST="${TARGET_HOST:-10.0.0.220}"
TARGET_USER="${TARGET_USER:-ubuntu}"
REMOTE_BASE="${REMOTE_BASE_DIR:-/home/ubuntu/monitoring-lab}"
TEKKEN_SOURCE="${TEKKEN_SOURCE_DIR:-/mnt/e/work/tekken_bot}/grafana/tekken.json"

# ========== サービス別同期関数 ==========

sync_prometheus() {
  step "prometheus: 設定ファイルを転送中..."
  scp "${REPO_ROOT}/config/prometheus/prometheus.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/prometheus/prometheus.yml"
  scp "${REPO_ROOT}/config/prometheus/alerts.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/prometheus/alerts.yml"
  step "prometheus: ホットリロード中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "curl -sf -X POST http://localhost:9090/-/reload"
  info "prometheus 同期完了"
}

sync_alertmanager() {
  step "alertmanager: 設定ファイルを転送中（Webhook URL を置換）..."
  if [ -z "${SLACK_WEBHOOK_URL}" ]; then
    error ".env に SLACK_WEBHOOK_URL が設定されていません"
  fi
  # ローカルで URL 置換 → /tmp に一時ファイル → scp → 削除
  TMPFILE=$(mktemp /tmp/alertmanager_deploy.XXXXXX.yml)
  sed "s|<YOUR_SLACK_WEBHOOK_URL>|${SLACK_WEBHOOK_URL}|g" \
      "${REPO_ROOT}/config/alertmanager/alertmanager.yml" > "${TMPFILE}"
  scp "${TMPFILE}" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/alertmanager/alertmanager.yml"
  rm -f "${TMPFILE}"
  step "alertmanager: ホットリロード中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "curl -sf -X POST http://localhost:9093/-/reload"
  info "alertmanager 同期完了"
}

sync_grafana() {
  step "grafana: dashboards.yml を転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" \
      "mkdir -p ${REMOTE_BASE}/grafana/provisioning/{dashboards,datasources}"
  scp "${REPO_ROOT}/config/grafana/provisioning/dashboards/dashboards.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/grafana/provisioning/dashboards/dashboards.yml"
  step "grafana: ダッシュボード JSON を転送中..."
  scp "${REPO_ROOT}/config/grafana/provisioning/dashboards/"*.json \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/grafana/provisioning/dashboards/" 2>/dev/null || \
      warn "ダッシュボード JSON が見つかりません（スキップ）"
  step "grafana: datasources.yml を転送中..."
  scp "${REPO_ROOT}/config/grafana/provisioning/datasources/datasources.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/grafana/provisioning/datasources/datasources.yml"
  step "grafana: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-grafana"
  info "grafana 同期完了"
}

sync_snmp() {
  step "snmp: snmp.yml を転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/snmp"
  scp "${REPO_ROOT}/config/snmp/snmp.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/snmp/snmp.yml"
  step "snmp-exporter: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-snmp-exporter"
  info "snmp 同期完了"
}

sync_tekken_update() {
  step "tekken: ソースプロジェクトから tekken.json をコピー中..."
  if [ ! -f "${TEKKEN_SOURCE}" ]; then
    error "tekken.json が見つかりません: ${TEKKEN_SOURCE}\n  TEKKEN_SOURCE_DIR 環境変数で上書き可能"
  fi
  cp "${TEKKEN_SOURCE}" "${REPO_ROOT}/config/grafana/provisioning/dashboards/tekken.json"
  info "tekken.json をコピーしました（git add して grafana を sync してください）"
  echo "  次のステップ: ./scripts/sync-config.sh grafana"
}

# ========== メイン ==========

SERVICE="${1:-}"

case "${SERVICE}" in
  prometheus)      sync_prometheus ;;
  alertmanager)    sync_alertmanager ;;
  grafana)         sync_grafana ;;
  snmp)            sync_snmp ;;
  tekken-update)   sync_tekken_update ;;
  all)
    sync_prometheus
    sync_alertmanager
    sync_grafana
    sync_snmp
    info "全サービス同期完了"
    ;;
  *)
    echo "使い方: $0 {prometheus|alertmanager|grafana|snmp|tekken-update|all}"
    echo ""
    echo "  prometheus      prometheus.yml + alerts.yml → ホットリロード"
    echo "  alertmanager    alertmanager.yml (URL置換) → ホットリロード"
    echo "  grafana         dashboards/ + datasources.yml → コンテナ再起動"
    echo "  snmp            snmp.yml → コンテナ再起動"
    echo "  tekken-update   tekken_bot プロジェクトから tekken.json をリポジトリにコピー"
    echo "  all             全サービス（tekken-update は含まない）"
    exit 1
    ;;
esac
