---
description: "Task list for 016-mcp-metrics-exporter"
---

# Tasks: MCP メトリクスエクスポータ（MCP サーバー可観測性）

**Input**: Design documents from `/specs/016-mcp-metrics-exporter/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: 計装ヘルパーの単体テストのみ含める（`contracts/instrumentation-helper.md` のテスト契約に基づく）。サーバー統合・メトリクス到達は検証タスク（手動/integration）で確認する。

**Organization**: ユーザーストーリー単位でフェーズ化。US1/US2 は共に P1 で flush により結合するため、計装ヘルパーと collector パイプラインを Foundational に置く。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並行実行可（異なるファイル・依存なし）
- **[Story]**: US1 / US2 / US3
- 各タスクに具体的なファイルパスを記載

## Path Conventions

- MCP サーバー: `mcp/<server>/`（独立 TS パッケージ）／ 共通: `mcp/shared/`
- インフラ設定: `config/otel-collector/`, `config/grafana/provisioning/dashboards/`
- リモート: 10.0.0.220（otel-collector / victoriametrics / grafana）

---

## Phase 1: Setup（共通基盤の足場）

**Purpose**: 共通計装の置き場と依存・ビルド方式を確定する

- [X] T001 `mcp/shared/` ディレクトリを新設（自己完結パッケージ: `package.json`/`tsconfig.json`/`telemetry.ts`/`__tests__/`）。`telemetry.ts` は T004-T006 で正本実装
- [X] T002 [P] `mcp/prometheus-server/package.json` に `@opentelemetry/api` / `@opentelemetry/sdk-metrics` / `@opentelemetry/exporter-metrics-otlp-grpc` / `@opentelemetry/resources` / `@opentelemetry/semantic-conventions` を追加（T010 配線用の prep。`npm install` は T011 のイメージ再ビルド時）
- [X] T003 ビルドコンテキスト方針を確定（research.md D6）: 各サーバーは context=`mcp/`、Dockerfile が `shared/telemetry.ts` を `./src/` へ COPY し `import './telemetry.js'`。**実際の Dockerfile/import 改変は T010/T011 の領分**（本Phaseでは方針確定のみ）

---

## Phase 2: Foundational（全ストーリーの前提・ブロッキング）

**Purpose**: 計測の核（共通ヘルパー）とメトリクスの出口（collector→VM）。これが無いとどのストーリーも実証不能

**⚠️ CRITICAL**: このフェーズ完了まで US 実装は開始不可

- [X] T004 `mcp/shared/telemetry.ts` に `initTelemetry(serviceName)` を実装（Resource `service.name`=`mcp-<name>`、OTLP/gRPC exporter、`PeriodicExportingMetricReader`、**cumulative temporality 明示**、`mcp_tool_duration_seconds` の**明示バケット境界を View（`ExplicitBucketHistogramAggregation`）で登録**[境界値は data-model.md]、既定エンドポイント `http://10.0.0.220:4317`／`OTEL_EXPORTER_OTLP_ENDPOINT` 上書き、`MCP_TELEMETRY_DISABLED=1` で no-op、冪等、接続失敗で例外を投げない）— contracts/instrumentation-helper.md 準拠
- [X] T005 `mcp/shared/telemetry.ts` に `instrumentTool(toolName, handler)` を実装（`mcp_tool_invocations_total{service,tool,status}` Counter +1、`mcp_tool_duration_seconds{service,tool}` Histogram 記録、**`service`(bare 名)・`tool`・`status` は Resource 任せにせずデータポイント属性として明示付与**[I1 回避・data-model.md 参照]、戻り値/例外を透過、計測例外は握る best-effort）
- [X] T006 `mcp/shared/telemetry.ts` に `shutdownTelemetry(timeoutMs=2000)` を実装（forceFlush + MeterProvider shutdown、timeout 超過で resolve、冪等）
- [X] T007 [P] 計装ヘルパーの vitest テストを `mcp/shared/__tests__/telemetry.test.ts` に作成（7件 green）（成功=success/throw=error かつ再throw、`MCP_TELEMETRY_DISABLED=1` で素通し、到達不能でも `shutdownTelemetry` が timeout 内に resolve、計測例外がツール結果/例外に波及しない）— contracts/instrumentation-helper.md テスト契約
- [X] T008 `config/otel-collector/otel-collector.yml` に `prometheusremotewrite` exporter（`http://victoriametrics:8428/api/v1/write`, `tls.insecure: true`, `resource_to_telemetry_conversion.enabled: true`）と `metrics` パイプライン（receivers:[otlp], processors:[batch], exporters:[prometheusremotewrite]）を増設（traces パイプラインと `:8888` テレメトリは不変）— contracts/otel-collector-pipeline.md
- [X] T009 otel-collector 設定をリモートへ反映し検証（使い捨てコンテナで `validate`=EXIT0 → 実パス差し替え → `docker restart monitoring-lab-otel-collector` → ログ: prometheusremotewrite exporter / metrics signal 起動・traces 継続・エラーなし）

**Checkpoint**: 計装ヘルパー（テスト green）とメトリクス出口が準備完了

---

## Phase 3: User Story 1 - MCP ツール利用が観測可能になる (Priority: P1) 🎯 MVP

**Goal**: 1つの MCP サーバー（prometheus-server）のツール利用が VictoriaMetrics に届き、回数・成否・レイテンシをクエリできる

**Independent Test**: prometheus-server のツールを数回（成功+意図的失敗）呼び、`mcp_tool_invocations_total{service="prometheus"}` の増加と status 区別、`mcp_tool_duration_seconds` の分布を VM で確認

- [X] T010 [US1] `mcp/prometheus-server/src/index.ts` を計装（先頭で `initTelemetry('prometheus')`、6ツールを `instrumentTool` でラップ、SIGINT/SIGTERM/`transport.onclose`/例外で `await shutdownTelemetry()`→`process.exit`）。⚠️発見: **stdin EOF では onclose が発火しない**（pipe close で flush せず）。**本番は Claude Code が `docker stop`=SIGTERM で止めるため SIGTERM 経路が機能すれば良い**。stdin EOF 経路の硬化は T013 で詰める
- [X] T011 [US1] `monitoring-lab-prometheus-mcp` を context=`mcp/`（Dockerfile が `shared/telemetry.ts` を `./src/` へ COPY）で再ビルド成功。tsc green（計装込み）
- [X] T012 [US1] 検証（SC-001）: SIGTERM 経路で `mcp_tool_invocations_total{service="prometheus",tool="get_active_alerts",status="success"}=1`、`histogram_quantile(0.95,...)`=0.049s を VM で確認。**I1 修正が奏功**（`service` ラベル存在・Resource 由来は `service_name` で併存）。collector: accepted=2/sent=2/PRW batch=1。注: status=success は handler が例外を throw せず error 応答を返したため（A2 既知・T013で isError 判定検討）

**Checkpoint**: prometheus-server が単独で完全に観測可能（MVP 成立）

---

## Phase 4: User Story 2 - 短命プロセスでも計測値が失われない (Priority: P1)

**Goal**: ツール1回呼び出し→即終了でも計測値が確実に VM へ届く（取りこぼし 0）。collector 到達不能でもツールは正常応答

**Independent Test**: 「1呼び出し→即終了」を繰り返し、合算カウントが回数と一致（SC-002）。otel-collector 停止下でツールが正常応答（SC-005）

- [X] T013 [US2] 全終了経路を硬化。**実装が大きく発展**（research.md D8）: stdin `end`/`close` 経路追加・**gracefulExit の冪等ガード**（連続発火で2発目が exit を先に踏む相討ちを実測→修正）・`isError:true` 応答の status=error 判定（A2）・flush は forceFlush→ref付きsettle(500ms)→shutdown の順・予算8s
- [X] T014 [US2] 検証（SC-002）**green: 5回中5回・取りこぼし0**。ただし到達には D8 の転換一式が必要だった: OTLP/HTTP(4318)化・`service.instance.id` 独立系列化・集計は `sum(max_over_time(...))`（increase は同値書き込みでリセット検出不能）・バージョン完全固定（otel 5pkg + node:22.20.0-alpine）。VM の検索遅延（~30s）にも注意
- [X] T015 [US2] 検証（SC-005）green: collector 停止下でツール正常応答・総所要 3.9s で自力終了・collector 復旧確認

**Checkpoint**: ephemeral flush の信頼性が実証され、US1 の数値が信頼できる

---

## Phase 5: 全4サーバーへ横展開（US1+US2 を全サーバーで成立 — SC-003）

**Goal**: docker / terragrunt / alertmanager にも計装を適用し、4/4 サーバーが観測可能になる

**Independent Test**: `count(count by (service)(mcp_tool_invocations_total)) == 4`

- [X] T016 [P] [US1] `mcp/docker-server` に計装適用（6ツール instrumentTool・冪等 gracefulExit・Dockerfile context=mcp/ 化 + node 22.20.0 固定 + otel 5pkg exact pin。lock は Linux コンテナで再生成——Windows 生成 lock は @emnapi/* 欠落で npm ci が落ちる）
- [X] T017 [P] [US1] `mcp/terragrunt-server` に計装適用（同上・6ツール・`initTelemetry('terragrunt')`）
- [X] T018 [P] [US1] `mcp/alertmanager-server` に計装適用（同上・4ツール・`initTelemetry('alertmanager')`。build スクリプトに shared→src の条件付き同期を追加し、`mcp/*/src/telemetry.ts` は .gitignore（正本は shared）——全4サーバー共通）
- [X] T019 [US1] 3イメージ再ビルド完了・ローカル tsc 4/4 green・shared vitest 8/8 green。`mcp/.dockerignore` 新設（node_modules 同梱で 9p 経由の context 転送が激遅になる罠を制圧）
- [X] T020 [US2] 検証（SC-003）**green: count=4**（prometheus/docker/alertmanager=success、terragrunt=error——A2 の isError 判定が実弾で機能している証左）

**Checkpoint**: 全 MCP サーバーが観測可能（監視盲点を完全に解消・憲法 原則V）

---

## Phase 6: User Story 3 - ツール利用ダッシュボード (Priority: P2)

**Goal**: サーバー別・ツール別の 呼び出し回数 / レイテンシ(p95) / エラー率 を1枚で俯瞰

**Independent Test**: MCP Observability ダッシュボードを開き、各パネルが実データで描画される

- [X] T021 [US3] `mcp-observability.json` 作成（VM データソース uid=victoriametrics、7パネル: SC-003 stat / 総呼び出し / 全体エラー率 / サーバー別 rolling 1h / ツール別 status 別 / p95 / ツール別エラー率。**すべて max_over_time 型**——改訂済み contract 準拠）
- [X] T022 [US3] 同期・Grafana 再起動・`/api/search` でロード確認（uid=mcp-observability）。パネルクエリは SC-003 検証で実データ返答を確認済み（SC-004）

**Checkpoint**: 全ストーリー完了。日常的に MCP 利用を一望できる

---

## Phase 7: Polish & Cross-Cutting

**Purpose**: 仕上げと憲法準拠の最終確認

- [X] T023 検証（SC-006）green: リモート常駐 19 コンテナ（増加なし・otel-collector は置換のみ）、mcp コンテナ 0（ローカル ephemeral）
- [X] T024 憲法 原則I green: `run --all plan` 全20 workspace "No changes"（otel-collector の extra_ports=4318 は apply 済みでコード=State=実態一致。注: 当初計画から変更あり——D8 により terragrunt.hcl とモジュールに extra_ports を追加した）
- [ ] T025 [P] `.claude/SESSION_STATE.md` と `MEMORY.md` を更新（016 完了・OTLP→VM 経路・ephemeral flush の知見を記録）
- [ ] T026 [P] `specs/016-mcp-metrics-exporter/quickstart.md` の受け入れ検証表（SC-001〜006）を実走し結果を追記
- [ ] T027 ブランチ `016-mcp-metrics-exporter` をフェーズ単位でコミットし、PR を作成（master へ）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (P1)**: 即開始可
- **Foundational (P2)**: Setup 完了に依存。全 US をブロック
- **US1 (P3)**: Foundational 完了後。MVP
- **US2 (P4)**: US1 のサーバー統合（T010）に依存（同一 index.ts の終了経路を硬化するため）
- **横展開 (P5)**: US1+US2 のパターン確立後（T010/T013 が雛形）
- **US3 (P6)**: メトリクスが VM に存在すること（最低 US1、理想は P5 完了後で全サーバー描画）
- **Polish (P7)**: 全 US 完了後

### Within Each Story

- ヘルパー実装（T004-T006）→ テスト（T007）→ サーバー統合（T010）→ 再ビルド（T011）→ 検証（T012）
- T008/T009（collector）は T010 と独立に進められるが、T012 の検証前に完了必須

### Parallel Opportunities

- T002（依存追加）と T007（ヘルパーテスト作成）は他と異なるファイルで [P]
- T016/T017/T018（3サーバーの計装適用）は異なるパッケージで [P]（ただし共通の `mcp/shared/telemetry.ts` は変更しない前提）
- T025/T026（ドキュメント）は [P]

---

## Parallel Example: Phase 5 横展開

```bash
# 3サーバーへの計装適用を並行実施（異なるパッケージ）:
Task: "mcp/docker-server に計装適用 (T016)"
Task: "mcp/terragrunt-server に計装適用 (T017)"
Task: "mcp/alertmanager-server に計装適用 (T018)"
```

---

## Implementation Strategy

### MVP First（US1 のみ）

1. Phase 1 Setup
2. Phase 2 Foundational（ヘルパー + collector パイプライン）← 全ストーリーをブロック
3. Phase 3 US1（prometheus-server）
4. **STOP & VALIDATE**: prometheus-server のメトリクスが VM に出ることを確認
5. ここまでで「MCP が観測可能」という積年の空白が埋まる（最小の価値）

### Incremental Delivery

1. Setup + Foundational → 基盤完成
2. US1（1サーバー）→ 検証 → MVP
3. US2（flush 信頼性）→ 検証（SC-002）
4. 横展開（全4サーバー）→ 検証（SC-003）
5. US3（ダッシュボード）→ 検証（SC-004）
6. Polish（No changes 確認・記録・PR）

---

## Notes

- [P] = 異なるファイル・依存なし
- 短命コンテナでは定期エクスポートが発火しない → **shutdown flush が唯一の送出経路**（T006/T010/T013 が本機能の生命線）
- 計測値にツール引数・戻り値を**含めない**（機密混入防止）
- 各フェーズ/論理単位でコミット。チェックポイントでストーリー独立性を検証
- 検証タスク（T012/T014/T015/T020/T022）は VM クエリ・Grafana 目視・実機操作を伴う（手動 integration）
