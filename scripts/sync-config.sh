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

TARGET_HOST="${TARGET_HOST:-YOUR_SERVER_IP}"
TARGET_USER="${TARGET_USER:-ubuntu}"
REMOTE_BASE="${REMOTE_BASE_DIR:-/home/ubuntu/monitoring-lab}"
TEKKEN_SOURCE="${TEKKEN_SOURCE_DIR:-/mnt/e/work/tekken_bot}/grafana/tekken.json"

# ========== プレースホルダ置換 ==========
# リポジトリの config/ は公開用にホスト名をプレースホルダ化している。
# デプロイ時に .env の実値へ置換し、置換しきれなかったファイルは配備を拒否する。
# （2026-06: プレースホルダ入り prometheus.yml が配備され監視が1ヶ月停止した事故の再発防止）

PLACEHOLDER_MAP=(
  "YOUR_SERVER_IP=${TARGET_HOST}"
  "YOUR_ROUTER_IP=${PROM_ROUTER_IP:-}"
  "YOUR_NAS_IP=${PROM_NAS_IP:-}"
  "YOUR_LINUX_HOST_1=${PROM_LINUX_HOST_1:-}"
  "YOUR_LINUX_HOST_2=${PROM_LINUX_HOST_2:-}"
  "YOUR_CRAWLER_HOST=${PROM_CRAWLER_HOST:-}"
)

# コメント行以外にプレースホルダが残っていたら中断する
assert_no_placeholder() {
  local f="$1" src="$2"
  if grep -nE '^[^#]*\bYOUR_[A-Z0-9_]+' "$f" > /dev/null 2>&1; then
    grep -nE '^[^#]*\bYOUR_[A-Z0-9_]+' "$f" | head -5 >&2
    rm -f "$f"
    error "${src}: 未置換のプレースホルダが残っています。.env の PROM_* / TARGET_HOST を設定してください（配備を中断）"
  fi
}

# プレースホルダを実値に置換した一時ファイルのパスを標準出力に返す
render_config() {
  local src="$1" tmp pair name value
  tmp=$(mktemp "/tmp/$(basename "$src").render.XXXXXX")
  cp "$src" "$tmp"
  for pair in "${PLACEHOLDER_MAP[@]}"; do
    name="${pair%%=*}"
    value="${pair#*=}"
    if [ -n "$value" ]; then
      sed -i "s|${name}|${value}|g" "$tmp"
    fi
  done
  assert_no_placeholder "$tmp" "$src"
  echo "$tmp"
}

# render_config → scp → 一時ファイル削除
deploy_file() {
  local src="$1" dest="$2" tmp
  tmp=$(render_config "$src")
  scp "$tmp" "${TARGET_USER}@${TARGET_HOST}:${dest}"
  rm -f "$tmp"
}

# ========== サービス別同期関数 ==========

sync_prometheus() {
  step "prometheus: 設定ファイルを転送中（プレースホルダ置換あり）..."
  deploy_file "${REPO_ROOT}/config/prometheus/prometheus.yml" \
      "${REMOTE_BASE}/prometheus/prometheus.yml"
  deploy_file "${REPO_ROOT}/config/prometheus/alerts.yml" \
      "${REMOTE_BASE}/prometheus/alerts.yml"
  if [ -f "${REPO_ROOT}/config/prometheus/slo-rules.yml" ]; then
    deploy_file "${REPO_ROOT}/config/prometheus/slo-rules.yml" \
        "${REMOTE_BASE}/prometheus/slo-rules.yml"
  fi
  step "prometheus: ホットリロード中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "curl -sf -X POST http://localhost:9090/-/reload"
  info "prometheus 同期完了"
}

sync_alertmanager() {
  step "alertmanager: Webhook URL を解決中..."

  local WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
  local VAULT_API="${VAULT_ADDR:-http://YOUR_SERVER_IP:8200}"
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
  assert_no_placeholder "${TMPFILE}" "${REPO_ROOT}/config/alertmanager/alertmanager.yml"
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
  deploy_file "${REPO_ROOT}/config/grafana/provisioning/dashboards/dashboards.yml" \
      "${REMOTE_BASE}/grafana/provisioning/dashboards/dashboards.yml"
  step "grafana: ダッシュボード JSON を転送中（プレースホルダ置換あり）..."
  # 素の scp だと render/assert を通らず YOUR_* 入りのまま配備される
  # （2026-07-12: linux-hosts.json が YOUR_LINUX_HOST_* のまま配備され12パネル死亡していた）
  local json_found=0
  for json in "${REPO_ROOT}/config/grafana/provisioning/dashboards/"*.json; do
    [ -f "$json" ] || continue
    json_found=1
    deploy_file "$json" \
        "${REMOTE_BASE}/grafana/provisioning/dashboards/$(basename "$json")"
  done
  [ "$json_found" -eq 1 ] || warn "ダッシュボード JSON が見つかりません（スキップ）"
  step "grafana: datasources.yml を転送中..."
  deploy_file "${REPO_ROOT}/config/grafana/provisioning/datasources/datasources.yml" \
      "${REMOTE_BASE}/grafana/provisioning/datasources/datasources.yml"
  step "grafana: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-grafana"
  info "grafana 同期完了"
}

sync_snmp() {
  step "snmp: snmp.yml を転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/snmp"
  deploy_file "${REPO_ROOT}/config/snmp/snmp.yml" "${REMOTE_BASE}/snmp/snmp.yml"
  step "snmp-exporter: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-snmp-exporter"
  info "snmp 同期完了"
}

sync_loki() {
  step "loki: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/loki"
  deploy_file "${REPO_ROOT}/config/loki/loki.yml" "${REMOTE_BASE}/loki/loki.yml"
  step "loki: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-loki"
  info "loki 同期完了"
}

sync_promtail() {
  step "promtail: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/promtail"
  deploy_file "${REPO_ROOT}/config/promtail/promtail.yml" "${REMOTE_BASE}/promtail/promtail.yml"
  step "promtail: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-promtail"
  info "promtail 同期完了"
}

sync_tempo() {
  step "tempo: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/tempo"
  deploy_file "${REPO_ROOT}/config/tempo/tempo.yml" "${REMOTE_BASE}/tempo/tempo.yml"
  step "tempo: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-tempo"
  info "tempo 同期完了"
}

sync_otel_collector() {
  step "otel-collector: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/otel-collector"
  deploy_file "${REPO_ROOT}/config/otel-collector/otel-collector.yml" \
      "${REMOTE_BASE}/otel-collector/otel-collector.yml"
  step "otel-collector: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-otel-collector"
  info "otel-collector 同期完了"
}

sync_pyroscope() {
  step "pyroscope: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/pyroscope"
  deploy_file "${REPO_ROOT}/config/pyroscope/config.yml" "${REMOTE_BASE}/pyroscope/config.yml"
  step "pyroscope: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-pyroscope"
  info "pyroscope 同期完了"
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
  pyroscope)       sync_pyroscope ;;
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
    sync_pyroscope
    info "全サービス同期完了"
    ;;
  *)
    echo "使い方: $0 {prometheus|alertmanager|grafana|snmp|loki|promtail|tempo|otel-collector|pyroscope|tekken-update|all}"
    echo ""
    echo "  prometheus      prometheus.yml + alerts.yml → ホットリロード"
    echo "  alertmanager    alertmanager.yml (URL置換) → ホットリロード"
    echo "  grafana         dashboards/ + datasources.yml → コンテナ再起動"
    echo "  snmp            snmp.yml → コンテナ再起動"
    echo "  loki            loki.yml → コンテナ再起動"
    echo "  promtail        promtail.yml → コンテナ再起動"
    echo "  tempo           tempo.yml → コンテナ再起動"
    echo "  otel-collector  otel-collector.yml → コンテナ再起動"
    echo "  pyroscope       config.yml → コンテナ再起動"
    echo "  tekken-update   tekken_bot プロジェクトから tekken.json をリポジトリにコピー"
    echo "  all             全サービス（tekken-update は含まない）"
    exit 1
    ;;
esac
