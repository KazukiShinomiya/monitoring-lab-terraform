# Contract: メトリクス（時系列の対外契約）

**Feature**: 016-mcp-metrics-exporter

VictoriaMetrics に格納され、Grafana（VictoriaMetrics データソース）から照会される時系列の契約。ダッシュボード（US3）とアラート将来拡張はこの契約に依存する。

---

## メトリクス一覧

### `mcp_tool_invocations_total`

- **型**: Counter（cumulative, monotonic）
- **ラベル**: `service`, `tool`, `status`(`success`|`error`)
- **意味**: 当該 MCP サーバーの当該ツールが呼ばれた累積回数

### `mcp_tool_duration_seconds`（Histogram）

VictoriaMetrics 上では以下の系列に展開される:
- `mcp_tool_duration_seconds_bucket{service, tool, le}`
- `mcp_tool_duration_seconds_sum{service, tool}`
- `mcp_tool_duration_seconds_count{service, tool}`

- **バケット境界（秒）**: `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30`

---

## 代表クエリ（ダッシュボード/受け入れ検証で使用）

| 目的 | PromQL |
|---|---|
| サーバー別 総呼び出し数（5分） | `sum by (service) (increase(mcp_tool_invocations_total[5m]))` |
| ツール別 呼び出し数 | `sum by (service, tool) (increase(mcp_tool_invocations_total[5m]))` |
| ツール別 エラー率 | `sum by (service, tool) (increase(mcp_tool_invocations_total{status="error"}[5m])) / sum by (service, tool) (increase(mcp_tool_invocations_total[5m]))` |
| ツール別 p95 レイテンシ | `histogram_quantile(0.95, sum by (service, tool, le) (increase(mcp_tool_duration_seconds_bucket[5m])))` |
| ツール別 平均レイテンシ | `sum by (service, tool)(increase(mcp_tool_duration_seconds_sum[5m])) / sum by (service, tool)(increase(mcp_tool_duration_seconds_count[5m]))` |

> 短命プロセスはカウンタが起動ごとにリセットされるため、`rate`/`increase` は VictoriaMetrics のカウンタリセット検出に依存する。`sum by` で複数プロセス起動分を合算し、利用者視点の連続性を成立させる（spec Edge Case）。

---

## 受け入れ基準との対応

| SC | 検証クエリ/観点 |
|---|---|
| SC-001（取りこぼし0） | あるツールを N 回呼んだ後 `increase(mcp_tool_invocations_total{...}[t])` が N に一致 |
| SC-002（ephemeral flush 100%） | ツール1回→即終了 を繰り返し、各回が VM に反映（カウント合算が回数と一致） |
| SC-003（4/4 サーバー観測可能） | `count(count by (service)(mcp_tool_invocations_total)) == 4` |
| SC-004（ダッシュボード） | 上記代表クエリがパネルとして描画される |

---

## 安定性の約束

- メトリクス名・ラベル名は対外契約。変更時はダッシュボード・将来アラートへの下流影響をレビューする（憲法ガバナンス）。
- `service` ラベル値は `docker` / `prometheus` / `terragrunt` / `alertmanager` の4値で固定。
