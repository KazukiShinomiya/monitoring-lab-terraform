# Implementation Plan: MCP メトリクスエクスポータ（MCP サーバー可観測性）

**Branch**: `016-mcp-metrics-exporter` | **Date**: 2026-06-17 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/016-mcp-metrics-exporter/spec.md`

## Summary

4つの MCP サーバー（docker / prometheus / terragrunt / alertmanager、TypeScript・stdio・WSL2 ローカル Docker 上の短命コンテナ）にツール計装を施し、呼び出し回数・レイテンシ・成否を計測する。pull スクレイプが構成上不可能なため、各サーバーは OpenTelemetry SDK で計測値を OTLP/gRPC により稼働中の otel-collector（10.0.0.220:4317、外部公開・到達性実証済み）へ push する。otel-collector に metrics パイプライン + `prometheusremotewrite` exporter を増設し、既存 VictoriaMetrics（`victoriametrics:8428/api/v1/write`）へ転送する。Grafana の既存 VictoriaMetrics データソースから可視化する。短命コンテナでは定期エクスポートが発火しないため、**プロセス終了時の forceFlush/shutdown が唯一かつ最優先の送出経路**となる。

## Technical Context

**Language/Version**: TypeScript（Node.js 22+、ESM）／ otel-collector 設定は YAML ／ インフラは HCL（Terragrunt）
**Primary Dependencies**: `@opentelemetry/api`, `@opentelemetry/sdk-metrics`, `@opentelemetry/exporter-metrics-otlp-grpc`, `@opentelemetry/resources`, `@opentelemetry/semantic-conventions`（新規）／ `@modelcontextprotocol/sdk@^1.29.0`（既存）
**Storage**: VictoriaMetrics（既存、`prometheusremotewrite` 経由で受信。新規ストレージ追加なし）
**Testing**: vitest（各サーバーに既存）。計装ヘルパーの単体テスト + flush 挙動の検証
**Target Platform**: MCP = WSL2 ローカル Docker Engine 上の ephemeral コンテナ（`docker run --rm -i`）／ otel-collector・VictoriaMetrics = リモート 10.0.0.220 の Docker Engine
**Project Type**: single（`mcp/` 配下の独立した4 TS パッケージ + 共通計装ヘルパー）
**Performance Goals**: 計装によるツール応答オーバーヘッドは無視可能（1呼び出しあたり数 ms 未満）。終了時 flush は shutdown 猶予内（数百 ms）に完了
**Constraints**: 計測は best-effort（ツール応答を遅延・失敗させない）／ **cumulative temporality 必須**（Prometheus カウンタ互換）／ 新規 publish ポートを増やさない／ 新規常駐サービスを追加しない／ ツール引数・戻り値は記録しない（機密混入防止）
**Scale/Scope**: 4 サーバー × 各約6ツール（計約22ツール）。対話起点の低頻度呼び出し。低カーディナリティ（service × tool × status）

## Constitution Check

*GATE: Phase 0 前に通過必須。Phase 1 設計後に再評価。*

| 原則 | 評価 | 根拠 |
|---|---|---|
| **I. IaC（絶対）** | ✅ PASS | インフラ変更は otel-collector.yml（bind mount・scp 後 apply/restart）と Grafana プロビジョニングのみ。既存コンテナの再作成も含め Terragrunt 管理下。apply 後 全 workspace "No changes" を確認する。MCP の TS コードはアプリケーションコードでありインフラ State 対象外。 |
| **II. セキュリティファースト** | ✅ PASS | 新規シークレットなし。OTLP は学習環境のため insecure gRPC（既存 Tempo 経路と同方針）。**ツール引数・戻り値を計測値に含めない**（spec Out of Scope）ため機密混入リスクを排除。属性は service/tool/status のみ。 |
| **III. ドキュメント駆動** | ✅ PASS | 本サイクル（specify→plan→tasks→implement）に準拠。設計判断と却下案を research.md に記録。 |
| **IV. モジュール化とDRY** | ✅ PASS | 4サーバー共通の計装ヘルパーを単一実装し再利用（重複禁止）。コンテナ定義変更時は `docker_container` モジュールを使用（ただし本機能はotel-collector の設定追加のみで新規コンテナなし）。 |
| **V. 自己監視の可観測性** | ✅ PASS（本機能が原則Vを直接前進させる） | MCP サーバーは唯一 Prometheus/Zabbix の監視盲点だった。本機能でその盲点を解消。新メトリクスには Grafana ダッシュボードを同一サイクルで用意（US3）。 |

**MCP/AI 自己成長基盤セクションとの整合**: 本機能は読み取り専用の計測であり書き込み操作を伴わない。AI 自動適用も無い。承認フローに抵触しない。

**ゲート結果**: 違反なし。Complexity Tracking 不要。

## Project Structure

### Documentation (this feature)

```text
specs/016-mcp-metrics-exporter/
├── plan.md              # 本ファイル
├── spec.md              # 機能仕様
├── research.md          # Phase 0 出力（設計判断の根拠）
├── data-model.md        # Phase 1 出力（メトリクス・属性スキーマ）
├── quickstart.md        # Phase 1 出力（デプロイ・検証手順）
├── contracts/           # Phase 1 出力（計装ヘルパーIF・メトリクス契約・collector契約）
│   ├── instrumentation-helper.md
│   ├── metrics-contract.md
│   └── otel-collector-pipeline.md
├── checklists/
│   └── requirements.md  # specify フェーズで生成済み（全PASS）
└── tasks.md             # Phase 2 出力（/speckit.tasks で生成・本コマンドでは作らない）
```

### Source Code (repository root)

```text
mcp/
├── shared/                          # 【新規】共通計装ヘルパー（DRY、原則IV）
│   └── telemetry.ts                 # MeterProvider 初期化 / instrumentTool ラッパー / shutdown flush
├── docker-server/
│   ├── src/
│   │   ├── index.ts                 # 【変更】telemetry 初期化 + 各 server.tool を instrument でラップ + 終了時 flush
│   │   └── ...                      # 既存ツール（不変）
│   ├── Dockerfile                   # 【変更】shared/telemetry.ts をビルドコンテキストに含める
│   └── package.json                 # 【変更】@opentelemetry/* 依存追加
├── prometheus-server/               # 同上の変更
├── terragrunt-server/               # 同上の変更
└── alertmanager-server/             # 同上の変更

config/
├── otel-collector/
│   └── otel-collector.yml           # 【変更】metrics パイプライン + prometheusremotewrite exporter 増設
└── grafana/provisioning/dashboards/
    └── mcp-observability.json       # 【新規】ツール別 呼び出し回数/レイテンシ/エラー率（VictoriaMetrics DS）

# インフラ（変更が必要なら）
terraform/envs/local/otel-collector/terragrunt.hcl  # 設定ファイル再読込のための再起動・apply（command/bind は不変想定）
```

**Structure Decision**: `mcp/` 配下の既存4パッケージ構成を維持しつつ、共通計装を `mcp/shared/telemetry.ts` に単一実装する（原則IV のDRY）。各サーバーは自身の Dockerfile ビルドコンテキストに shared を取り込む。インフラ側は otel-collector の設定追加と Grafana ダッシュボード追加のみで、新規コンテナ・新規 publish ポート・新規常駐サービスを伴わない。

## 実装フェーズ（概要・詳細タスクは /speckit.tasks）

- **Phase A（US1+US2, P1）**: 共通計装ヘルパー実装（MeterProvider/OTLP exporter/instrumentTool/shutdown flush）→ 1サーバー（prometheus-server）に適用 → otel-collector に metrics パイプライン増設 → VictoriaMetrics 反映を実証（ephemeral flush 含む）
- **Phase B（US1+US2, P1）**: 残り3サーバー（docker/terragrunt/alertmanager）へ計装を横展開・4イメージ再ビルド
- **Phase C（US3, P2）**: Grafana ダッシュボード追加（サーバー別・ツール別の回数/レイテンシ/エラー率）

## Complexity Tracking

> Constitution Check に違反なし。記載不要。
