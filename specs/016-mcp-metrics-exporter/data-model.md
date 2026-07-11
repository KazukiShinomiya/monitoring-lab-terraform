# Data Model: MCP メトリクスエクスポータ

**Feature**: 016-mcp-metrics-exporter | **Date**: 2026-06-17

本機能が生成・流通させる「データ」はメトリクス（時系列）である。永続エンティティ（DB レコード等）は持たない。以下にメトリクス定義・属性スキーマ・リソース属性・ライフサイクルを定義する。

---

## エンティティ概観

| エンティティ | 表現 | 由来 spec |
|---|---|---|
| ツール呼び出しイベント | Counter のインクリメント + Histogram の記録（1呼び出し=1記録） | Key Entities |
| 呼び出しカウンタ | Counter `mcp_tool_invocations_total` | FR-001/002 |
| レイテンシ分布 | Histogram `mcp_tool_duration_seconds` | FR-003 |
| MCP サービス識別子 | Resource 属性 `service.name` | FR-004 |

---

## メトリクス定義

### M1. `mcp_tool_invocations_total`（Counter / cumulative）

ツール呼び出しの累積回数。

| 属性 | 型 | 値の例 | 説明 |
|---|---|---|---|
| `service` | string | `prometheus`, `docker`, `terragrunt`, `alertmanager`（**bare 名固定**） | どの MCP サーバーか。**メトリクスのデータポイント属性として明示付与する**（Resource `service.name` には依存しない。理由は下記「リソース属性」節） |
| `tool` | string | `query_metrics`, `docker_get_logs` | ツール名（`server.tool` 登録名） |
| `status` | enum | `success` / `error` | ツールハンドラが正常完了したか例外/エラーを返したか |

- 単調増加。`rate()` / `increase()` での集計を想定。
- カーディナリティ: service(4) × tool(約22総計) × status(2) ≒ 数十系列。低い。

### M2. `mcp_tool_duration_seconds`（Histogram / cumulative）

ツールハンドラの入口〜出口の実行時間（秒）。

| 属性 | 型 | 説明 |
|---|---|---|
| `service` | string | M1 と同じ |
| `tool` | string | M1 と同じ |

- `service` / `tool` も M1 と同じく**明示データポイント属性**として付与（bare 名）。
- `status` は付与しない（成功・失敗を区別せずレイテンシ全体を見る。失敗の所要時間も分布に含める）。必要なら将来 status 分離を検討。
- **明示バケット境界（秒）**: `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30`
  - 根拠: PromQL クエリ系（数十ms）から docker/ssh 越しの操作（秒オーダー）、terragrunt plan（十秒オーダー）までを1つの分布でカバー。
  - **登録箇所**: OpenTelemetry JS ではバケット境界は計装時ではなく **MeterProvider 初期化時の View（`ExplicitBucketHistogramAggregation`）で登録**する。よって `initTelemetry()`（tasks T004）の責務とする。
- 派生: `histogram_quantile(0.95, ...)` で p95、`_count`/`_sum` で平均。

---

## リソース属性（全メトリクス共通）

OpenTelemetry Resource として付与。**識別用クエリには使わない**（理由は下記）。

| 属性 | 値 | 説明 |
|---|---|---|
| `service.name` | `mcp-<name>`（例 `mcp-prometheus`） | OpenTelemetry 慣例の識別。`target_info` 等に展開される。**M1/M2 のクエリラベル `service` の源ではない** |
| `service.version` | 各 `package.json` の version（例 `2.0.0`） | バージョン別の挙動差を観測可能に |
| `service.instance.id` | プロセスごとの UUID（起動時に生成） | **プロセスごとに独立系列を作る**（T014 で追加）。短命プロセスが同一系列へ同値の cumulative を書くと `increase()` がリセットを検出できず合算が 0 に潰れるため。`resource_to_telemetry_conversion` でラベル `service_instance_id` に展開される |

> ⚠️ **`service` ラベルは Resource ではなくデータポイント属性で付与する（設計上の確定事項）**:
> Resource 属性 `service.name` は `prometheusremotewrite` exporter で Prometheus 形式へ落ちる際、慣例で **`service_name`**（または `target_info` 経由）というラベル名に変換され、**`service` という名前のラベルにはならない**。
> 一方 contracts/metrics-contract.md のクエリ・ダッシュは `{service="..."}` を前提とする。両者の名前の不一致（`service` vs `service_name`）はメトリクスが届いていてもクエリが空振りする分かりにくい不具合を生む。
> これを避けるため、`instrumentTool` は **`service`（bare 名）を Counter/Histogram のデータポイント属性として直接付与**し、exporter の Resource ラベル化挙動に依存しない。これによりクエリ側の前提と確実に一致する。
> なお Resource の `service.name`（`mcp-<name>`）と明示属性 `service`（bare 名）は別物として共存する（前者は OTel 慣例の識別、後者がクエリの正）。

---

## エラー分類（status の決定規則）

`instrumentTool` ラッパーが以下で `status` を決める:

| ハンドラの結果 | status |
|---|---|
| 正常に値を返す | `success` |
| 例外を throw する | `error`（例外は再 throw し、本来の振る舞いを透過） |
| MCP のエラー応答（`isError: true` 等のツールレベルエラー）を返す | `error`（戻り値は透過。判定は best-effort） |

- ツールレベルエラー（throw せず error 応答）の判定は MCP SDK の戻り値形に依存するため、Phase A で実際の戻り値型を確認して確定する。最低限「例外 = error」は保証する。

---

## ライフサイクルと一貫性

- **プロセス起動ごとに新しいカウンタ**: 短命コンテナのため、各起動でカウンタは 0 から始まる（cumulative はプロセス内累積）。`service.instance.id` でプロセスごとに独立系列とし、利用者視点の合算は `sum by (service, tool) (max_over_time(...[w]))` で成立させる（**`increase()` は同値書き込みでリセット検出不能のため使わない**。詳細は contracts/metrics-contract.md）。
- **取りこぼし防止**: 記録〜送出の間にプロセスが死ぬと失われるため、終了時 flush（D4）で担保。SC-002 の検証対象。
- **best-effort**: 計測の記録・送出失敗はツール本来の応答に影響しない（FR-007）。例外は計装層で握る。

---

## 計測しないもの（再掲・data の境界）

- ツール呼び出しの**引数値・戻り値の中身**（機密混入防止、spec Out of Scope）。属性は識別子と status のみ。
- ツール内部のサブ処理（外部コマンド個別の docker/ssh/curl 呼び出し時間）。計測境界はハンドラ入口〜出口。
