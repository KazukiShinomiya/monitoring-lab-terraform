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
#   ./scripts/sync-config.sh loki           # loki.yml → Loki 再起動
#   ./scripts/sync-config.sh promtail       # promtail.yml → Promtail 再起動
#   ./scripts/sync-config.sh tempo          # tempo.yml → Tempo 再起動
#   ./scripts/sync-config.sh otel-collector # otel-collector.yml → OTel Collector 再起動
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
  step "alertmanager: Webhook URL を解決中..."

  local WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
  local VAULT_API="${VAULT_ADDR:-http://10.0.0.220:8200}"
  local VAULT_TK="${VAULT_TOKEN:-root}"

  # Vault から取得を試みる
  if [ -z "${WEBHOOK_URL}" ]; then
    step "alertmanager: Vault から Webhook URL を取得中 (${VAULT_API})..."
    WEBHOOK_URL=$(curl -sf \
      -H "X-Vault-Token: ${VAULT_TK}" \
      "${VAULT_API}/v1/secret/data/monitoring-lab/alertmanager" \
      2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["data"]["slack_webhook_url"])' 2>/dev/null || true)

    if [ -n "${WEBHOOK_URL}" ]; then
      info "alertmanager: Vault から Webhook URL を取得しました"
    else
      warn "alertmanager: Vault からの取得に失敗しました"
    fi
  fi

  # 両方未設定の場合はエラー
  if [ -z "${WEBHOOK_URL}" ]; then
    error "Webhook URL を解決できませんでした。\n  方法1: .env に SLACK_WEBHOOK_URL を設定する\n  方法2: VAULT_ADDR + VAULT_TOKEN を設定して Vault から取得する"
  fi

  step "alertmanager: 設定ファイルを転送中（Webhook URL を置換）..."
  # ローカルで URL 置換 → /tmp に一時ファイル → scp → 削除
  TMPFILE=$(mktemp /tmp/alertmanager_deploy.XXXXXX.yml)
  sed "s|<YOUR_SLACK_WEBHOOK_URL>|${WEBHOOK_URL}|g" \
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

sync_loki() {
  step "loki: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/loki"
  scp "${REPO_ROOT}/config/loki/loki.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/loki/loki.yml"
  step "loki: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-loki"
  info "loki 同期完了"
}

sync_promtail() {
  step "promtail: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/promtail"
  scp "${REPO_ROOT}/config/promtail/promtail.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/promtail/promtail.yml"
  step "promtail: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-promtail"
  info "promtail 同期完了"
}

sync_tempo() {
  step "tempo: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/tempo"
  scp "${REPO_ROOT}/config/tempo/tempo.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/tempo/tempo.yml"
  step "tempo: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-tempo"
  info "tempo 同期完了"
}

sync_otel_collector() {
  step "otel-collector: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/otel-collector"
  scp "${REPO_ROOT}/config/otel-collector/otel-collector.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/otel-collector/otel-collector.yml"
  step "otel-collector: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-otel-collector"
  info "otel-collector 同期完了"
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
  loki)            sync_loki ;;
  promtail)        sync_promtail ;;
  tempo)           sync_tempo ;;
  otel-collector)  sync_otel_collector ;;
  tekken-update)   sync_tekken_update ;;
  all)
    sync_prometheus
    sync_alertmanager
    sync_grafana
    sync_snmp
    sync_loki
    sync_promtail
    sync_tempo
    sync_otel_collector
    info "全サービス同期完了"
    ;;
  *)
    echo "使い方: $0 {prometheus|alertmanager|grafana|snmp|loki|promtail|tempo|otel-collector|tekken-update|all}"
    echo ""
    echo "  prometheus      prometheus.yml + alerts.yml → ホットリロード"
    echo "  alertmanager    alertmanager.yml (URL置換) → ホットリロード"
    echo "  grafana         dashboards/ + datasources.yml → コンテナ再起動"
    echo "  snmp            snmp.yml → コンテナ再起動"
    echo "  loki            loki.yml → コンテナ再起動"
    echo "  promtail        promtail.yml → コンテナ再起動"
    echo "  tempo           tempo.yml → コンテナ再起動"
    echo "  otel-collector  otel-collector.yml → コンテナ再起動"
    echo "  tekken-update   tekken_bot プロジェクトから tekken.json をリポジトリにコピー"
    echo "  all             全サービス（tekken-update は含まない）"
    exit 1
    ;;
esac
