# Tasks: Grafana Tempo + OpenTelemetry Collector トレーシング基盤

**Input**: Design documents from `/specs/011-tempo/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: テスト自動化は本フィーチャーのスコープ外。動作確認は `quickstart.md` の手順で目視確認。

**Organization**: タスクはユーザーストーリー単位でフェーズ化されており、US1 (P1) から独立してデプロイ・テスト可能。

**Changelog (speckit.analyze 修正適用)**:
- C1: OTel Collector Prometheus スクレイプジョブ追加 (T016, Constitution 原則 V 対応)
- H1: T009/T010 順序入れ替え — 設定ファイルを apply 前にリモート転送
- H3: T015/T016 順序入れ替え — 同上
- H2: T019/T020/T021 の [P] 除去 — 同一ファイル (prometheus.yml) への競合防止
- M1: T013 (永続化確認) を Phase 3 に追加

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能 (別ファイル、未完了タスクへの依存なし)
- **[Story]**: どのユーザーストーリーに属するか (US1〜US4)
- ファイルパスはすべてリポジトリルートからの相対パス

---

## Phase 1: Setup (ディレクトリ構造の作成)

**Purpose**: 新規ファイルの配置先となるディレクトリを作成する

- [x] T001 [P] `config/tempo/` ディレクトリを作成する
- [x] T002 [P] `config/otel-collector/` ディレクトリを作成する
- [x] T003 [P] `terraform/envs/local/tempo/` ディレクトリを作成する
- [x] T004 [P] `terraform/envs/local/otel-collector/` ディレクトリを作成する

---

## Phase 2: Foundational (ブロッキング前提条件)

**Purpose**: HCP Terraform の新規 Workspace を Local 実行モードに変更する。この作業が完了するまでユーザーストーリーの実装は進められない。

**⚠️ CRITICAL**: HCP Terraform UI または API で手動実施。デフォルトは Remote モードのため、terragrunt apply が失敗する。

- [x] T005 HCP Terraform UI (app.terraform.io) で workspace `monitoring-lab-local-tempo` の Execution Mode を **Local** に変更する
- [x] T006 HCP Terraform UI (app.terraform.io) で workspace `monitoring-lab-local-otel-collector` の Execution Mode を **Local** に変更する

**Checkpoint**: 2つの Workspace が Local モードになったことを HCP UI で確認してから次フェーズへ

---

## Phase 3: User Story 1 - トレースデータの収集と保存 (Priority: P1) 🎯 MVP

**Goal**: Grafana Tempo が OTLP でトレースを受信・永続化できる状態にする

**Independent Test**: `curl -s http://10.0.0.220:3200/ready` が `"ready"` を返す。telemetrygen → OTel Collector (4317) → Tempo → HTTP API (3200) でトレースを確認できる。なお Tempo への直接 OTLP (4317/4318) はモジュール制約により外部非公開。

### Implementation for User Story 1

- [x] T007 [US1] `config/tempo/tempo.yml` を作成する。内容: single binary モード、http_listen_port: 3200、OTLP gRPC (4317) + HTTP (4318) レシーバー、local backend (`/var/tempo`)、WAL (`/var/tempo/wal`)、metrics_generator (service-graphs, span-metrics)、block_retention: 336h
- [x] T008 [US1] `terraform/envs/local/tempo/terragrunt.hcl` を作成する。内容: `docker_container` モジュール参照、dependency: network、volume: `tempo_data` → `/var/tempo`、bind_mount: `~/monitoring-lab/tempo/tempo.yml` → `/etc/tempo/tempo.yml`、port: 3200→3200、command: `["-config.file=/etc/tempo/tempo.yml"]`
- [x] T009 [US1] リモートサーバーにディレクトリを作成し設定ファイルを **apply 前に** 転送する (bind_mount のファイルが存在しないと起動失敗するため必須): `ssh ubuntu@10.0.0.220 'mkdir -p ~/monitoring-lab/tempo'` → `scp config/tempo/tempo.yml ubuntu@10.0.0.220:~/monitoring-lab/tempo/tempo.yml` (T007, T005 完了後)
- [x] T010 [US1] `task tg:apply:svc -- tempo` を実行して Tempo コンテナをリモートサーバーにデプロイする (T008, T009 完了後)
- [x] T011 [US1] Tempo ヘルスチェックを実行して動作を確認する: `curl -s http://10.0.0.220:3200/ready` が `"ready"` を返すことを確認する (T010 完了後)
- [x] T012 [US1] データ永続化を検証する (FR-007, SC-006): `task logs -- otel-collector` でトレースが記録されていることを確認後、`ssh ubuntu@10.0.0.220 'docker restart monitoring-lab-tempo'` を実行し、再起動後も Tempo HTTP API でトレースが参照可能であることを確認する (T011 完了後、T016 完了後が望ましい)

**Checkpoint**: Tempo コンテナが UP かつ `/ready` が通る。US1 は独立してテスト可能。

---

## Phase 4: User Story 3 - OTel Collector によるトレースルーティング (Priority: P2)

**Goal**: OTel Collector が OTLP を受信して Tempo に転送し、エンドツーエンドでトレースが保存される。かつ OTel Collector 自身が Prometheus にスクレイプされる (Constitution 原則 V)。

**Independent Test**: `task logs -- otel-collector` に `"Everything is ready."` が表示される。telemetrygen でトレースを送信後、Grafana Tempo Explore でトレースが確認できる。

**Depends on**: Phase 3 (Tempo が稼働中であること)

### Implementation for User Story 3

- [x] T013 [US3] `config/otel-collector/otel-collector.yml` を作成する。内容: receivers: otlp (gRPC 0.0.0.0:4317, HTTP 0.0.0.0:4318)、processors: batch (timeout: 1s, send_batch_size: 1024)、exporters: otlp/tempo (endpoint: tempo:4317, tls.insecure: true)、pipeline: traces (otlp → batch → otlp/tempo)
- [x] T014 [US3] `terraform/envs/local/otel-collector/terragrunt.hcl` を作成する。内容: `docker_container` モジュール参照、dependency: network と tempo、volumes: []（ステートレス）、bind_mount: `~/monitoring-lab/otel-collector/otel-collector.yml` → `/etc/otel-collector/otel-collector.yml`、port: 4317→4317、image: `otel/opentelemetry-collector-contrib:latest`
- [x] T015 [US3] リモートサーバーにディレクトリを作成し設定ファイルを **apply 前に** 転送する (H3 修正): `ssh ubuntu@10.0.0.220 'mkdir -p ~/monitoring-lab/otel-collector'` → `scp config/otel-collector/otel-collector.yml ubuntu@10.0.0.220:~/monitoring-lab/otel-collector/otel-collector.yml` (T013, T006 完了後)
- [x] T016 [US3] `task tg:apply:svc -- otel-collector` を実行して OTel Collector コンテナをデプロイする (T014, T015 完了後)
- [x] T017 [US3] `config/prometheus/prometheus.yml` に Job 10 (OTel Collector 自己監視) を追加する: `job_name: 'otel-collector'`、`targets: ['otel-collector:8888']` — **Constitution 原則 V 対応** (T016 完了後)
- [x] T018 [US3] telemetrygen でサンプルトレースを送信し、OTel Collector 経由で Tempo に到達することを確認する: `docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest traces --otlp-endpoint localhost:4317 --otlp-insecure --traces 5` (T016 完了後)
- [x] T019 [US3] `task logs -- otel-collector` でログを確認し `"Everything is ready."` と転送成功ログを確認する (T018 完了後)

**Checkpoint**: OTel Collector → Tempo のパイプラインが動作。OTel Collector が prometheus.yml のスクレイプ対象に追加済み。US3 は独立してテスト可能。

---

## Phase 5: User Story 2 - Grafana 可視化 + Exemplar 連携 (Priority: P2)

**Goal**: Grafana Explore からトレースを可視化し、Prometheus Exemplar マーカー経由でトレースにジャンプできる

**Independent Test**: Grafana Explore → Tempo データソース → Search → トレース一覧表示 → ウォーターフォールビュー確認。Prometheus Targets で tempo と otel-collector ジョブが UP。

**Depends on**: Phase 3 (Tempo 稼働中)

### Implementation for User Story 2

- [x] T020 [US2] `config/prometheus/prometheus.yml` の `global:` セクションに `scrape_protocols` を追加する: `[OpenMetricsText1.0.0, OpenMetricsText0.0.1, PrometheusText0.0.4]`
- [x] T021 [US2] `config/prometheus/prometheus.yml` に `storage.exemplar_storage` セクションを追加する: `enable_exemplar_storage: true`、`max_exemplars: 100000` **(T020 完了後 — 同一ファイル、順次実行)** ※Prometheus 3.x では不要のため削除済み
- [x] T022 [US2] `config/prometheus/prometheus.yml` に Job 9 (Tempo スクレイプ) を追加する: `job_name: 'tempo'`、`targets: ['tempo:3200']` **(T021 完了後 — 同一ファイル、順次実行)**
- [x] T023 [P] [US2] `config/grafana/provisioning/datasources/datasources.yml` の `deleteDatasources:` リストに `{name: Tempo, orgId: 1}` を追加する
- [x] T024 [US2] `config/grafana/provisioning/datasources/datasources.yml` に Tempo データソースを追加する (T023 後): name: Tempo、type: tempo、uid: tempo、url: http://tempo:3200、jsonData: serviceMap (datasourceUid: prometheus)、nodeGraph.enabled: true、tracesToLogs (datasourceUid: loki)、tracesToMetrics (datasourceUid: prometheus)
- [x] T025 [US2] `config/grafana/provisioning/datasources/datasources.yml` の Prometheus データソースの `jsonData:` に `exemplarTraceIdDestinations` を追加する (T024 後): `[{name: traceID, datasourceUid: tempo}]`
- [x] T026 [US2] `task sync:prometheus` を実行して Prometheus 設定を同期・ホットリロードする (T017, T020, T021, T022 完了後)
- [x] T027 [US2] `task sync:grafana` を実行して Grafana 設定を同期・再起動する (T025 完了後)
- [x] T028 [US2] Grafana (http://10.0.0.220:3000) の Explore → Tempo データソース → Search → Run query でトレース一覧が表示されることを確認する (T027 完了後)
- [x] T029 [US2] Prometheus (http://10.0.0.220:9090/targets) で `tempo` と `otel-collector` ジョブが **UP** 状態であることを確認する (T026 完了後)

**Checkpoint**: Grafana からトレースが可視化され、Prometheus が Tempo と OTel Collector をスクレイプしている。US2 独立テスト完了。

---

## Phase 6: User Story 4 - IaC run-all 確認 (Priority: P3)

**Goal**: `terragrunt run --all plan` が tempo / otel-collector を含む全ワークスペースで No changes を示す

**Independent Test**: `task tg:plan` が全ワークスペースで exit 0 で完了。

**Depends on**: Phase 3, Phase 4 (両コンテナが apply 済み)

### Implementation for User Story 4

- [x] T030 [US4] `task tg:plan` を実行し、`monitoring-lab-local-tempo` と `monitoring-lab-local-otel-collector` を含む全ワークスペースで **No changes** になることを確認する

**Checkpoint**: IaC 状態が収束している。全 US が独立してテスト完了。

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 運用フローへの統合 (sync-config.sh, Taskfile) と最終確認

- [x] T031 [P] `scripts/sync-config.sh` に `sync_tempo()` 関数を追加する: step/scp/restart パターンで `config/tempo/tempo.yml` → `${REMOTE_BASE}/tempo/tempo.yml` → `docker restart monitoring-lab-tempo`
- [x] T032 [P] `scripts/sync-config.sh` に `sync_otel_collector()` 関数を追加する: step/scp/restart パターンで `config/otel-collector/otel-collector.yml` → `${REMOTE_BASE}/otel-collector/otel-collector.yml` → `docker restart monitoring-lab-otel-collector`
- [x] T033 `scripts/sync-config.sh` の `all)` ケースに `sync_tempo` と `sync_otel_collector` の呼び出しを追加する (T031, T032 完了後)
- [x] T034 `scripts/sync-config.sh` のヘルプテキスト (usage 部分) に `tempo` と `otel-collector` の説明行を追加する (T033 完了後)
- [x] T035 [P] `Taskfile.yml` に `sync:tempo` タスクを追加する: desc + wsl コマンドパターンで `sync-config.sh tempo` を実行
- [x] T036 [P] `Taskfile.yml` に `sync:otel-collector` タスクを追加する: desc + wsl コマンドパターンで `sync-config.sh otel-collector` を実行
- [x] T037 `quickstart.md` の全ステップを通して最終動作確認を行い、`sync-config.sh tempo` と `sync-config.sh otel-collector` の動作も確認する (US3 Acceptance Scenario 3 対応)
- [x] T038 `.claude/SESSION_STATE.md` を 011-tempo の完了状態に更新し、次フェーズ (012-gitops) を次推奨アクションとして記録する

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)          → 依存なし、即座に開始可能
Phase 2 (Foundational)   → Phase 1 完了後、HCP UI 操作が必要
Phase 3 (US1 Tempo)      → Phase 2 完了後 (T005 が前提)
Phase 4 (US3 OTel)       → Phase 3 完了後 (Tempo が稼働中であること)
Phase 5 (US2 Grafana)    → Phase 3 完了後 (Phase 4 と並列実行可能、T026 は T017 も必要)
Phase 6 (US4 IaC確認)    → Phase 3 + Phase 4 完了後
Phase 7 (Polish)         → Phase 3 完了後に開始可能 (T031/T032/T035/T036 は並列)
```

### User Story Dependencies

- **US1 (P1)**: Phase 2 完了後に開始 — 他ストーリーへの依存なし
- **US3 (P2)**: US1 完了後に開始 (Tempo が動作中であること)
- **US2 (P2)**: US1 完了後に開始 (US3 と並列実行可能、ただし T026 は T017 も待つ)
- **US4 (P3)**: US1 + US3 完了後に開始 (両コンテナが apply 済み)

### Within Phase 3 (US1) — 逐次実行

```
T007 (tempo.yml作成)
  → T008 (terragrunt.hcl作成)
  → T009 (リモート転送 ← apply 前に必須)
  → T010 (terragrunt apply)
  → T011 (ヘルスチェック)
  → T012 (永続化確認 ← T018完了後が望ましい)
```

### Within Phase 4 (US3) — 逐次実行

```
T013 (otel-collector.yml作成)
  → T014 (terragrunt.hcl作成)
  → T015 (リモート転送 ← apply 前に必須)
  → T016 (terragrunt apply)
  → T017 (prometheus.yml Job 10 追加)
  → T018 (telemetrygen テスト)
  → T019 (ログ確認)
```

### Within Phase 5 (US2) — 部分的並列

```
T020 prometheus scrape_protocols
  → T021 exemplar_storage  ← 同一ファイル、順次
  → T022 Job 9 tempo       ← 同一ファイル、順次
  → T026 sync:prometheus   ← T017 も完了していること

T023 [P] deleteDatasources
  → T024 Tempo DS
  → T025 Prometheus Exemplar
  → T027 sync:grafana

T026, T027 完了後 → T028 (Grafana確認) + T029 (Prometheus確認)
```

### Within Phase 7 (Polish) — 部分的並列

```
T031 [P] sync_tempo()
T032 [P] sync_otel_collector()
  → T033 (all) → T034 (help)
T035 [P] Taskfile sync:tempo
T036 [P] Taskfile sync:otel-collector
T037 → T038 (順次)
```

---

## Parallel Example: Phase 5 (US2)

```bash
# Prometheus 設定変更は順次 (同一ファイル):
T020 → T021 → T022 → T026 (sync)

# Grafana 設定変更は部分的に並列:
T023 [P] (deleteDatasources)
  └→ T024 (Tempo DS) → T025 (Exemplar) → T027 (sync)

# 確認は T026 + T027 完了後:
T028 (Grafana Explore) + T029 (Prometheus Targets)
```

---

## Implementation Strategy

### MVP First (User Story 1 のみ: T001〜T012)

1. Phase 1 (T001〜T004): ディレクトリ作成
2. Phase 2 (T005〜T006): HCP Workspace Local 化
3. Phase 3 (T007〜T012): Tempo デプロイ + ヘルスチェック + 永続化確認
4. **STOP & VALIDATE**: `curl http://10.0.0.220:3200/ready` が `"ready"` を返し、再起動後もデータが保持されることを確認
5. この時点で US1 が独立して動作している

### Incremental Delivery

1. T001〜T012 → US1 完了 → Tempo 稼働
2. T013〜T019 → US3 完了 → OTel Collector 経由でトレース送信可能 + 自己監視
3. T020〜T029 → US2 完了 → Grafana 可視化 + Exemplar 連携
4. T030 → US4 完了 → IaC 収束確認
5. T031〜T038 → Polish 完了 → 運用フロー統合

### 総タスク数: 38

| フェーズ | タスク数 | 内容 |
|---------|---------|------|
| Phase 1 (Setup) | 4 | ディレクトリ作成 |
| Phase 2 (Foundational) | 2 | HCP Workspace Local 化 |
| Phase 3 (US1) | 6 | Tempo 設定・デプロイ・永続化確認 (+1 M1修正) |
| Phase 4 (US3) | 7 | OTel Collector 設定・デプロイ・自己監視追加 (+1 C1修正) |
| Phase 5 (US2) | 10 | Grafana + Prometheus 統合 |
| Phase 6 (US4) | 1 | IaC run-all 確認 |
| Phase 7 (Polish) | 8 | sync-config.sh + Taskfile + 最終確認 |

### 並列実行機会

- Phase 1: T001〜T004 全て並列
- Phase 5: T023 は T020〜T022 と並列実行可能
- Phase 7: T031/T032/T035/T036 並列

---

## Notes

- [P] タスクは別ファイルへの変更で依存関係なし — 並列実行可能
- [Story] ラベルは spec.md のユーザーストーリーとの対応を示す
- **⚠️ T009/T015 は必ず T010/T016 (apply) より前に実行すること** — bind_mount 対象ファイルが存在しない状態で apply するとコンテナ起動失敗
- **T020/T021/T022 は同一ファイル (prometheus.yml) への変更のため順次実行** — 並列不可
- `docker_container` モジュールの単一ポート制約により、Tempo の外部公開は 3200 のみ (research.md §3 参照)
- Exemplar 収集はアプリ側の Exemplar 生成実装が必要。本フィーチャーは受け入れ側の準備のみ
- 各フェーズ完了後にコミットを推奨
