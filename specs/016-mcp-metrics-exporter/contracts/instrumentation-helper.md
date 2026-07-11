# Contract: 共通計装ヘルパー（`mcp/shared/telemetry.ts`）

**Feature**: 016-mcp-metrics-exporter

4つの MCP サーバーが共有する計装インターフェース。実装言語は TypeScript（ESM）。本契約は API 形状と振る舞いの約束を定義し、実装の詳細（SDK バージョン等）には踏み込まない。

---

## API

### `initTelemetry(serviceName: string): void`

MeterProvider を初期化し、OTLP/gRPC メトリクス exporter と `PeriodicExportingMetricReader` を接続する。Resource 属性 `service.name` を設定する。

- **冪等**: 二重呼び出しは2回目を no-op とする。
- **無効化（FR-012）**: 環境変数 `MCP_TELEMETRY_DISABLED=1` の場合、何も初期化せず後続の `instrumentTool` は素通し・`shutdownTelemetry` は即 resolve。
- **エンドポイント**: 既定 `http://10.0.0.220:4317`。環境変数 `OTEL_EXPORTER_OTLP_ENDPOINT` で上書き可能。
- **temporality**: cumulative（明示）。
- **失敗時**: exporter 接続不能でも例外を投げない（プロセス起動を妨げない）。stderr に警告のみ。

### `instrumentTool<T>(toolName: string, handler: (...args) => T | Promise<T>): (...args) => Promise<T>`

ツールハンドラをラップして計測を付加する。

- **戻り値の透過（FR-011）**: ラップ後も元ハンドラの戻り値をそのまま返す。
- **例外の透過**: 元ハンドラが throw した例外は `status=error` を記録した上で**再 throw** する。
- **計測内容**:
  - `mcp_tool_invocations_total{service, tool, status}` を +1
  - `mcp_tool_duration_seconds{service, tool}` に経過秒を記録
  - **`service`(bare 名)・`tool`・`status` はデータポイント属性として明示付与する**（Resource `service.name` のラベル化に依存しない。`service` vs `service_name` の名前不一致を避けるため。data-model.md 参照）
- **best-effort（FR-007）**: 計測処理自体が失敗しても握りつぶし、元の結果/例外に影響を与えない。計測の例外でツール応答を遅延・改変しない。
- **境界**: 計測区間はハンドラ呼び出しの直前〜完了（resolve/reject）まで。

### `shutdownTelemetry(timeoutMs = 2000): Promise<void>`

未送出メトリクスを flush し、MeterProvider を shutdown する。

- **flush 保証（FR-006）**: 戻る前に forceFlush 相当を完了させる。
- **タイムアウト**: `timeoutMs` 内に完了しなければ諦めて resolve（収集先到達不能時にプロセス終了を無限に待たせない）。
- **冪等**: 二重呼び出し安全。

---

## 各サーバー index.ts での利用契約

```text
1. import 後、最初に initTelemetry('<service>') を呼ぶ
2. server.tool(name, desc, schema, handler) の handler を instrumentTool(name, handler) でラップ
3. 終了経路すべてで shutdownTelemetry() を await してから process.exit():
   - SIGINT / SIGTERM
   - stdio transport の onclose（Claude 切断 / stdin EOF）
   - （uncaughtException/unhandledRejection は best-effort flush 後 exit(1)）
```

- イメージ名・`docker run` 起動方法・ツールの入出力契約は**変更しない**（`.mcp.json` 不変）。

---

## テスト契約（vitest）

- `instrumentTool` が成功時に `success`、throw 時に `error` を記録し、例外を再 throw することを検証。
- `MCP_TELEMETRY_DISABLED=1` で計測が素通しになることを検証。
- `shutdownTelemetry` が exporter 到達不能でも `timeoutMs` 内に resolve することを検証。
- 計測層の例外がツール戻り値/例外に波及しないことを検証（best-effort）。
