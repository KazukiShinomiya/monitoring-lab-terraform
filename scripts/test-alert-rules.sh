#!/bin/bash
# ==========================================
# アラートルールのユニットテスト実行スクリプト
# ==========================================
# config/prometheus/tests/ 配下のテストを promtool で実行する。
#
# 使い方:
#   ./scripts/test-alert-rules.sh
#
# なぜ必要か:
#   Prometheus の /api/v1/rules が health=ok / state=inactive を返しても、
#   ルールが正しいことにはならない。式が常に空を返していても inactive になるためだ。
#   合成データを与えて「鳴るべきときに鳴り、鳴るべきでないときに鳴らない」ことを確かめる。
#
# 実行方法について:
#   promtool はリモートの prometheus コンテナ内のものを使う（ローカルに Prometheus を
#   入れずに済ませるため）。ルールとテストを一時ディレクトリへ流し込んで評価するだけで、
#   稼働中の設定には触れない。配備は sync-config.sh prometheus が行う。
#
# 前提条件:
#   - .env に TARGET_HOST が設定済み
#   - リモートへ SSH 接続可能、monitoring-lab-prometheus が稼働中

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC}  $1"; }
error() { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }
step()  { echo -e "${BLUE}[>>]${NC}  $1"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.env"
  set +a
fi

TARGET_HOST="${TARGET_HOST:-YOUR_SERVER_IP}"
TARGET_USER="${TARGET_USER:-ubuntu}"
CONTAINER="monitoring-lab-prometheus"
REMOTE_DIR="/tmp/ruletest"

[ "${TARGET_HOST}" = "YOUR_SERVER_IP" ] && error "TARGET_HOST が未設定です（.env を確認してください）"

RULES="${REPO_ROOT}/config/prometheus/alerts.yml"
TEST_DIR="${REPO_ROOT}/config/prometheus/tests"

[ -f "${RULES}" ] || error "ルールファイルが見つかりません: ${RULES}"
[ -d "${TEST_DIR}" ] || error "テストディレクトリが見つかりません: ${TEST_DIR}"

SSH="ssh -o BatchMode=yes ${TARGET_USER}@${TARGET_HOST}"

step "テスト環境を準備中..."
# テストファイルは rule_files: ../alerts.yml を参照するため、同じ相対配置を再現する
$SSH "docker exec ${CONTAINER} rm -rf ${REMOTE_DIR} && docker exec ${CONTAINER} mkdir -p ${REMOTE_DIR}/tests" \
  || error "テスト環境の準備に失敗しました（${CONTAINER} は稼働していますか）"

# shellcheck disable=SC2002
cat "${RULES}" | $SSH "docker exec -i ${CONTAINER} sh -c 'cat > ${REMOTE_DIR}/alerts.yml'"

step "ルールの構文チェック..."
$SSH "docker exec ${CONTAINER} promtool check rules ${REMOTE_DIR}/alerts.yml" \
  || error "ルールの構文チェックに失敗しました"

FAILED=0
for test_file in "${TEST_DIR}"/*.yml; do
  name="$(basename "${test_file}")"
  step "テスト実行: ${name}"

  # shellcheck disable=SC2002
  cat "${test_file}" | $SSH "docker exec -i ${CONTAINER} sh -c 'cat > ${REMOTE_DIR}/tests/${name}'"

  if $SSH "docker exec ${CONTAINER} sh -c 'cd ${REMOTE_DIR}/tests && promtool test rules ${name}'"; then
    info "${name} 通過"
  else
    FAILED=1
  fi
done

# 後始末（失敗時も消す。残しても次回冒頭で rm -rf される）
$SSH "docker exec ${CONTAINER} rm -rf ${REMOTE_DIR}" >/dev/null 2>&1 || true

[ "${FAILED}" -ne 0 ] && error "テストに失敗しました"
info "アラートルールのテストは全て通過しました"
