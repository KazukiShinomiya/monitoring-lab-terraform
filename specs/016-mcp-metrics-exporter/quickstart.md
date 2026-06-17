# Quickstart: MCP メトリクスエクスポータ

**Feature**: 016-mcp-metrics-exporter | **Date**: 2026-06-17

デプロイと動作検証の手順。前提・検証コマンド・受け入れ基準への対応を示す。

---

## 前提

- WSL2 (Ubuntu-24.04) で Docker 稼働（`sudo service docker start`）
- リモート 10.0.0.220 で監視スタック稼働中（otel-collector / victoriametrics / grafana）
- 到達性確認済み: WSL2 docker → `10.0.0.220:4317` OPEN（2026-06-17 実証）

---

## 手順

### 1. otel-collector に metrics パイプライン増設

```bash
# config/otel-collector/otel-collector.yml を編集（contracts/otel-collector-pipeline.md 参照）
# prometheusremotewrite exporter + metrics パイプラインを追加

# リモートへ転送
scp -i ~/.ssh/monitoring_lab_key config/otel-collector/otel-collector.yml \
  ubuntu@10.0.0.220:/home/ubuntu/monitoring-lab/otel-collector/otel-collector.yml

# 再起動（ステートレス）
ssh -i ~/.ssh/monitoring_lab_key ubuntu@10.0.0.220 'docker restart otel-collector'

# 検証: ログにエラーなし
ssh -i ~/.ssh/monitoring_lab_key ubuntu@10.0.0.220 'docker logs --tail 30 otel-collector'
```

### 2. 共通計装ヘルパー実装 + 1サーバー適用（Phase A）

```bash
# mcp/shared/telemetry.ts を実装（contracts/instrumentation-helper.md 準拠）
# mcp/prometheus-server に適用:
#   - package.json に @opentelemetry/* 追加
#   - index.ts で initTelemetry / instrumentTool ラップ / 終了時 shutdownTelemetry
#   - Dockerfile で shared/ をビルドコンテキストに含める

cd mcp/prometheus-server
npm install
npm run build
npm test   # vitest: instrumentTool / disabled / flush timeout / best-effort

# イメージ再ビルド（shared を含むコンテキストで）
# 例: docker build -f mcp/prometheus-server/Dockerfile -t monitoring-lab-prometheus-mcp mcp/
```

### 3. ephemeral flush の実証（最重要・SC-002）

```bash
# MCP を1回起動 → ツール1回呼び出し → 即終了 を再現
# （Claude Code 経由、または手動で stdio に1リクエスト投げて EOF）

# VictoriaMetrics に反映されたか確認
curl -s 'http://10.0.0.220:8428/api/v1/query?query=mcp_tool_invocations_total' | python3 -m json.tool
```

### 4. 残り3サーバーへ横展開（Phase B）

```bash
# docker-server / terragrunt-server / alertmanager-server に同様の計装を適用
# 4イメージすべて再ビルド
```

### 5. Grafana ダッシュボード追加（Phase C / US3）

```bash
# config/grafana/provisioning/dashboards/mcp-observability.json を作成（VictoriaMetrics DS）
# 同期して Grafana 再起動
./scripts/sync-config.sh grafana   # or task sync:grafana
```

---

## 受け入れ検証（Success Criteria 対応）

| SC | 検証 |
|---|---|
| SC-001 取りこぼし0 | ツールを N 回呼び `increase(mcp_tool_invocations_total{service="prometheus"}[10m])` が N に一致 |
| SC-002 flush 100% | 「1回呼ぶ→即終了」を5回繰り返し、合算カウントが 5 |
| SC-003 4/4 観測 | `count(count by (service)(mcp_tool_invocations_total))` == 4 |
| SC-004 ダッシュボード | MCP Observability ダッシュボードで サーバー別/ツール別 回数・p95・エラー率が描画 |
| SC-005 無劣化 | otel-collector 停止中にツール呼び出し → 正常応答（best-effort）を確認 |
| SC-006 新規常駐なし | `docker ps`（remote）に新コンテナが増えていない |

---

## ロールバック

- **otel-collector**: metrics パイプライン除去 → scp → `docker restart`（ステートレス、損失なし）
- **MCP サーバー**: 計装前のイメージへ戻す or `MCP_TELEMETRY_DISABLED=1` で計測無効化（ツール機能は不変）

---

## トラブルシューティング

| 症状 | 確認 |
|---|---|
| VM に `mcp_tool_*` が出ない | collector ログ、`otelcol_exporter_sent_metric_points{exporter="prometheusremotewrite"}`、MCP の OTLP エンドポイント設定 |
| カウントが想定より少ない | 終了時 flush 未実装/未 await の疑い（D4）。shutdownTelemetry の呼び出し経路を確認 |
| ツール応答が遅い/失敗 | best-effort 違反。instrumentTool が計測例外を握っているか、flush を同期 await していないか確認 |
| collector 再起動後に traces が止まった | traces パイプラインを誤って変更した疑い。otel-collector.yml の traces セクション不変を確認 |
