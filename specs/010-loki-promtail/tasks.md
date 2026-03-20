# Tasks: Loki + Promtail ログ収集基盤

**Input**: Design documents from `specs/010-loki-promtail/`
**Prerequisites**: plan.md ✅、spec.md ✅、research.md ✅、data-model.md ✅、contracts/ ✅

**Organization**: ユーザーストーリー単位でフェーズを構成。各フェーズが独立してテスト可能。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイル・依存関係なし）
- **[Story]**: 対応するユーザーストーリー（US1/US2/US3）
- ファイルパスは各タスクに明示

---

## Phase 1: Setup（ディレクトリ構造）

**Purpose**: 新規ファイル配置先のディレクトリを作成する

- [x] T001 `config/loki/` と `config/promtail/` ディレクトリを作成
- [x] T002 [P] `terraform/envs/local/loki/` と `terraform/envs/local/promtail/` ディレクトリを作成

---

## Phase 2: Foundational（設定ファイル・IaC定義の作成）

**Purpose**: US1〜US3 すべての前提となる設定ファイルと Terragrunt 定義を作成する

**⚠️ CRITICAL**: このフェーズが完了するまでデプロイ作業には進めない

- [x] T003 [P] HCP Terraform（app.terraform.io）に `loki` Workspace を作成し実行モードを Local に設定
- [x] T004 [P] HCP Terraform（app.terraform.io）に `promtail` Workspace を作成し実行モードを Local に設定
- [x] T005 `config/loki/loki.yml` を作成（auth_enabled: false、TSDB v13、retention_period: 168h、compactor.retention_enabled: true）
- [x] T006 `config/promtail/promtail.yml` を作成（docker_sd_configs: unix:///var/run/docker.sock、positions: /tmp/positions.yaml、push: http://loki:3100/loki/api/v1/push）
- [x] T007 [P] `terraform/envs/local/loki/terragrunt.hcl` を作成（grafana/loki:3.4.2、port 3100、volume: loki_data→/loki、bind: loki.yml、dependency: network）
- [x] T008 `terraform/envs/local/promtail/terragrunt.hcl` を作成（grafana/promtail:3.4.2、port 9080、volume: promtail_positions→/tmp、bind: promtail.yml + /var/run/docker.sock(read-only)、dependency: network + loki）

**Checkpoint**: 設定ファイルと IaC 定義が揃い、デプロイ作業を開始できる状態

---

## Phase 3: User Story 1 - ログ収集基盤のデプロイ (Priority: P1) 🎯 MVP

**Goal**: Loki + Promtail がリモート環境で起動し、監視基盤コンテナのログが自動収集される

**Independent Test**: `curl -G 'http://10.0.0.220:3100/loki/api/v1/query' --data-urlencode 'query={job="containers"}'` でログエントリが返ること（起動後 30 秒以内）

### Implementation for User Story 1

- [x] T009 [P] [US1] リモートサーバーに `loki.yml` 配置（`ssh ubuntu@10.0.0.220 mkdir -p ~/monitoring-lab/loki` → `scp config/loki/loki.yml ubuntu@10.0.0.220:~/monitoring-lab/loki/loki.yml`）
- [x] T010 [P] [US1] リモートサーバーに `promtail.yml` 配置（`ssh ubuntu@10.0.0.220 mkdir -p ~/monitoring-lab/promtail` → `scp config/promtail/promtail.yml ubuntu@10.0.0.220:~/monitoring-lab/promtail/promtail.yml`）
- [x] T011 [US1] loki をデプロイ（Terragruntコンテナ内: `cd terraform/envs/local/loki && terragrunt init && terragrunt apply`）
- [x] T012 [US1] promtail をデプロイ（Terragruntコンテナ内: `cd terraform/envs/local/promtail && terragrunt init && terragrunt apply`）
- [x] T013 [US1] Loki 起動確認（`curl http://10.0.0.220:3100/ready` が `"ready"` を返すこと）
- [x] T014 [US1] 30 秒待機後、Loki API でログ収集確認（`/loki/api/v1/query_range?query={container_name=~".+"}` で streams 配列にエントリが存在すること／SC-001）
- [x] T015 [P] [US1] `config/prometheus/prometheus.yml` に Job 8 として `loki` スクレイプ設定を追加（`targets: ['loki:3100']`）（FR-009）
- [x] T016 [US1] `scripts/sync-config.sh prometheus` で prometheus.yml をリモートに転送・リロードし、Prometheus Targets 画面（http://10.0.0.220:9090/targets）で `loki` が UP であることを確認

**Checkpoint**: Loki + Promtail が稼働し、ログ収集と Prometheus 自己監視が機能している

---

## Phase 4: User Story 2 - Grafana でのログ検索・閲覧 (Priority: P2)

**Goal**: Grafana Explore から LogQL でコンテナログを検索・閲覧できる

**Independent Test**: Grafana Explore（http://10.0.0.220:3000）で Loki データソースを選択し `{container_name=~".+"}` を実行してログ一覧が 5 秒以内に表示されること

### Implementation for User Story 2

- [x] T017 [US2] `config/grafana/provisioning/datasources/datasources.yml` に Loki データソースを追記（`deleteDatasources` に Loki エントリ追加、datasources に `type: loki / url: http://loki:3100` 追加）
- [x] T018 [US2] `scripts/sync-config.sh grafana` で datasources.yml をリモートに転送し Grafana を再起動
- [x] T019 [US2] Grafana UI → Connections → Data Sources で `Loki` が自動追加されていることを確認（FR-004）
- [x] T020 [US2] Grafana Explore で LogQL `{container_name=~".+"}` を実行し、5 秒以内にログ一覧が表示されることを確認（SC-002）※ `{job="containers"}` は docker_sd_configs では job ラベル未付与のため代替クエリ使用
- [x] T021 [US2] `{container_name=~".+"} |= "error"` でエラーキーワードフィルタリングが動作することを確認

**Checkpoint**: US1 + US2 が完了。Grafana からログを検索・閲覧できる状態

---

## Phase 5: User Story 3 - メトリクスとログの相関分析 (Priority: P3)

**Goal**: Grafana Explore の Split view でメトリクスとログを同一時間軸で確認できる

**Independent Test**: Grafana Explore の Split view（左: Prometheus、右: Loki）で同一時間範囲のデータが同期表示されること（SC-003）

### Implementation for User Story 3

- [ ] T022 [US3] Grafana Explore の Split view で左ペイン（Prometheus: 任意のメトリクス）と右ペイン（Loki: `{container_name="monitoring-lab-prometheus"}`）を同一時間範囲で表示し、両者の時系列が同期していることを確認 ※ブラウザ操作による目視確認
- [ ] T023 [US3] アラート発生時刻（Alertmanager または Prometheus Alerts から確認）の前後 5 分を指定した LogQL クエリで対象コンテナのエラーログを 1 分以内に特定（SC-003）※ブラウザ操作による目視確認

**Checkpoint**: US1〜US3 すべてが独立して機能している

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 運用性向上と全 Workspace の最終整合性確認

- [x] T024 `scripts/sync-config.sh` に `loki` オプション（loki.yml を scp → `docker restart monitoring-lab-loki`）と `promtail` オプション（promtail.yml を scp → `docker restart monitoring-lab-promtail`）を追加
- [x] T025 Promtail の positions ファイル永続化確認（`docker restart monitoring-lab-promtail` 後に重複ログが収集されないこと／FR-008）
- [x] T026 Terragruntコンテナ内で `cd terraform/envs/local && terragrunt run --all plan` を実行し、全 Workspace（loki/promtail を含む）で "No changes" を確認
- [x] T027 `.claude/SESSION_STATE.md` を更新し、010-loki-promtail の完了タスクと次回アクションを記録

---

## Dependencies & Execution Order

### フェーズ依存関係

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational) ← T003/T004: HCP Workspace 作成（並列可）
    │                    T005/T006: 設定ファイル作成（直列）
    │                    T007/T008: Terragrunt 定義作成（T007 並列可、T008 は T007 後）
    ↓
Phase 3 (US1) 🎯 ← T009/T010: scp（並列可）→ T011/T012: apply（直列）→ T013-T016: 確認
    ↓
Phase 4 (US2) ← T017: datasources.yml 変更 → T018: 反映 → T019-T021: 確認
    ↓
Phase 5 (US3) ← T022-T023: 相関分析確認
    ↓
Phase 6 (Polish) ← T024-T027: 運用性向上・最終確認
```

### ユーザーストーリー依存関係

- **US1 (P1)**: Phase 2 完了後に開始可能。他ストーリーに依存しない
- **US2 (P2)**: US1 完了後に開始（Loki が稼働していることが前提）
- **US3 (P3)**: US2 完了後に開始（Grafana Loki データソースが設定済みであることが前提）

### 並列実行可能タスク

| タイミング | 並列実行できるタスク |
|-----------|-------------------|
| Phase 2 開始時 | T003 + T004（HCP Workspace 作成） |
| Phase 2 中盤 | T005 + T006（設定ファイル作成） |
| Phase 2 終盤 | T007（loki terragrunt.hcl）→ T008 は T007 後 |
| Phase 3 開始時 | T009 + T010（scp）、T015（prometheus.yml）|

---

## Parallel Example: User Story 1

```bash
# Phase 2: 設定ファイルを並列作成
Task T005: config/loki/loki.yml を作成
Task T006: config/promtail/promtail.yml を作成

# Phase 3: リモートへの配置を並列実行
Task T009: loki.yml を scp
Task T010: promtail.yml を scp

# Phase 3: prometheus.yml 変更は apply と並列可
Task T011: loki terragrunt apply
Task T015: prometheus.yml に Job 8 追加（T011/T012 と独立）
```

---

## Implementation Strategy

### MVP First（User Story 1 のみ）

1. Phase 1: Setup（T001〜T002）
2. Phase 2: Foundational（T003〜T008）
3. Phase 3: US1 実装（T009〜T016）
4. **STOP & VALIDATE**: `curl http://10.0.0.220:3100/loki/api/v1/query` でログ収集確認
5. デモ可能な状態に到達

### Incremental Delivery

1. Setup + Foundational → IaC 定義完了
2. US1 完了 → ログ収集基盤稼働（MVP）
3. US2 完了 → Grafana からログ閲覧可能
4. US3 完了 → メトリクスとログの相関分析可能
5. Polish → 運用性向上・最終整合性確認

---

## Notes

- [P] タスク = 異なるファイル・依存関係なし、並列実行可能
- [Story] ラベルはユーザーストーリーへのトレーサビリティを示す
- T003/T004（HCP Workspace 作成）はブラウザ操作またはTerraform Cloud API経由
- T011 → T012 は順番必須（promtail が loki に依存）
- T015（prometheus.yml）は T011/T012 と独立して作業可能（scp 反映は T016 で実施）
- 各 Checkpoint でストーリー単位の動作確認を推奨
