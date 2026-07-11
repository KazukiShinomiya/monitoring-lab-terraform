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
| サーバー別 総呼び出し数（1時間） | `sum by (service) (max_over_time(mcp_tool_invocations_total[1h]))` |
| ツール別 呼び出し数 | `sum by (service, tool) (max_over_time(mcp_tool_invocations_total[1h]))` |
| ツール別 エラー率 | `sum by (service, tool) (max_over_time(mcp_tool_invocations_total{status="error"}[1h])) / sum by (service, tool) (max_over_time(mcp_tool_invocations_total[1h]))` |
| ツール別 p95 レイテンシ | `histogram_quantile(0.95, sum by (service, tool, le) (max_over_time(mcp_tool_duration_seconds_bucket[1h])))` |
| ツール別 平均レイテンシ | `sum by (service, tool)(max_over_time(mcp_tool_duration_seconds_sum[1h])) / sum by (service, tool)(max_over_time(mcp_tool_duration_seconds_count[1h]))` |

> **⚠️ `increase()`/`rate()` はこのメトリクスに使えない（T014 実装時に確定した設計修正）**:
> 短命プロセスは各起動でカウンタが 0 から始まる。当初案の「同一系列 + カウンタリセット検出」は、連続する
> プロセスが**同値**（例: 各1回呼び出し → 1→1→1）を書くとリセットとして検出されず、合算が 0 に潰れる。
> このため Resource に `service.instance.id`（プロセスごと UUID、`resource_to_telemetry_conversion` で
> ラベル `service_instance_id` に展開）を付与して**プロセスごとに独立系列**とし、集計は
> `sum(max_over_time(...[w]))`（各プロセスの最終累積値を合算）で行う。
> 窓 `w` はダッシュボードの粒度（1h 推奨）。カーディナリティはプロセス起動数に比例するが、
> 値は小さく VM の保持期間で自然に減衰するため学習環境では許容。

---

## 受け入れ基準との対応

| SC | 検証クエリ/観点 |
|---|---|
| SC-001（取りこぼし0） | あるツールを N 回呼んだ後 `sum(max_over_time(mcp_tool_invocations_total{...}[t]))` が N に一致 |
| SC-002（ephemeral flush 100%） | ツール1回→即終了 を繰り返し、`sum(max_over_time(...))` の合算が回数と一致 |
| SC-003（4/4 サーバー観測可能） | `count(count by (service)(mcp_tool_invocations_total)) == 4` |
| SC-004（ダッシュボード） | 上記代表クエリがパネルとして描画される |

---

## 安定性の約束

- メトリクス名・ラベル名は対外契約。変更時はダッシュボード・将来アラートへの下流影響をレビューする（憲法ガバナンス）。
- `service` ラベル値は `docker` / `prometheus` / `terragrunt` / `alertmanager` の4値で固定。
