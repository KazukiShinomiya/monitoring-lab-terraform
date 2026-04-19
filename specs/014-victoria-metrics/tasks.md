# Tasks: VictoriaMetrics 長期メトリクス保存基盤

**Input**: Design documents from `/specs/014-victoria-metrics/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Organization**: インフラ専用フィーチャー。アプリケーションコードなし。テストは curl/API による E2E 検証のみ。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（別ファイル、依存関係なし）
- **[Story]**: 対応するユーザーストーリー（US1/US2/US3）

---

## Phase 1: Setup（ディレクトリ準備）

**Purpose**: IaC ファイル配置先の準備

- [x] T001 `terraform/envs/local/victoriametrics/` ディレクトリを作成する

---

## Phase 2: Foundational（IaC 定義）

**Purpose**: VictoriaMetrics コンテナの IaC 定義 — US1 デプロイのブロッキング前提条件

**⚠️ CRITICAL**: このフェーズが完了しないと US1 のコンテナデプロイを開始できない

- [x] T002 `terraform/envs/local/victoriametrics/terragrunt.hcl` を作成する（イメージ: `victoriametrics/victoria-metrics:stable`、ポート: 8428、`-retentionPeriod=12`、`-storageDataPath=/victoria-metrics-data`、Volume: `vm_data`、依存: `network` のみ）

**Checkpoint**: terragrunt.hcl 定義完了 — デプロイ作業開始可能

---

## Phase 3: User Story 1 - 長期メトリクスの自動保存（Priority: P1）🎯 MVP

**Goal**: VictoriaMetrics が稼働し、Prometheus から全メトリクスが自動転送されること

**Independent Test**: `curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=up"` で `status: success` かつ結果が返ること

### Implementation for User Story 1

- [x] T003 [US1] `terraform/envs/local/victoriametrics/` で `terragrunt init` を実行し、HCP Workspace `monitoring-lab-local-victoriametrics` を作成する
- [x] T004 [US1] HCP Terraform API で `monitoring-lab-local-victoriametrics` Workspace の実行モードを "Remote" → "Local" に変更する（既知の手順: API PATCH）
- [x] T005 [US1] `terragrunt apply` を実行し、VictoriaMetrics コンテナ（`monitoring-lab-victoriametrics`）と `vm_data` ボリュームを起動する
- [x] T006 [US1] ヘルスチェックで起動を確認する（`curl -sf http://YOUR_SERVER_IP:8428/health` → "OK"）
- [x] T007 [US1] `config/prometheus/prometheus.yml` に `remote_write` セクションを追加する（URL: `http://victoriametrics:8428/api/v1/write`、queue_config: `min_backoff: 30ms`, `max_backoff: 60s`, `max_shards: 4`）
- [x] T008 [US1] `config/prometheus/prometheus.yml` に Job 11 を追加する（`job_name: victoriametrics`、ターゲット: `victoriametrics:8428`、Constitution 原則 V 対応）
- [x] T009 [US1] `task sync:prometheus` を実行し、`prometheus.yml` の変更をリモートへ反映・ホットリロードする
- [x] T010 [US1] SC-001 を検証する（1分待機後、`curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=up"` で `status: success` かつデータが返ることを確認）

**Checkpoint**: US1 完了 — VictoriaMetrics が稼働し Prometheus からのメトリクス転送が自動継続している

---

## Phase 4: User Story 2 - Grafana から長期データを可視化（Priority: P2）

**Goal**: Grafana から VictoriaMetrics をデータソースとして選択し、任意の時間範囲でクエリできること

**Independent Test**: Grafana Explore → "VictoriaMetrics" データソース → `up` クエリ → グラフ表示。時間範囲 "Last 90 days" でも結果が返ること

### Implementation for User Story 2

- [x] T011 [US2] `config/grafana/provisioning/datasources/datasources.yml` に VictoriaMetrics エントリを追加する（`deleteDatasources` への `VictoriaMetrics` エントリ追加 + `datasources` への `name: VictoriaMetrics`, `type: prometheus`, `uid: victoriametrics`, `url: http://victoriametrics:8428`, `isDefault: false` を追加）
- [x] T012 [US2] `task sync:grafana` を実行し、`datasources.yml` をリモートへ反映・Grafana コンテナを再起動する
- [x] T013 [US2] Grafana Explore（`http://YOUR_SERVER_IP:3000`）で VictoriaMetrics データソースを選択し、`up` クエリを実行してグラフが表示されることを確認する（SC-004: 5秒以内に返ることも確認）

**Checkpoint**: US2 完了 — Grafana から既存 Prometheus と同じ操作感で長期データを参照可能

---

## Phase 5: User Story 3 - SLO Error Budget の長期トレンド分析（Priority: P3）

**Goal**: SLO メトリクス（`slo:error_budget:ratio` 等）が VictoriaMetrics に蓄積され、SLO ダッシュボードから参照できること

**Independent Test**: `curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=slo:error_budget:ratio"` で結果が返ること。Grafana "SLO Overview" ダッシュボードで VictoriaMetrics データソースを使用してグラフが表示されること

**Note**: SLO メトリクスは Prometheus の recording rules（`slo-rules.yml`）で生成され、`remote_write` で自動的に VM に転送される。追加の設定変更は不要。

### Implementation for User Story 3

- [x] T014 [US3] SLO メトリクスが VM に蓄積されていることを確認する（`curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=slo:error_budget:ratio"` で `status: success` かつ結果が返ること）
- [x] T015 [US3] Grafana の "SLO Overview — monitoring-lab" ダッシュボード（`http://YOUR_SERVER_IP:3000`）でデータソースを "VictoriaMetrics" に切り替え、Error Budget パネルにデータが表示されることを確認する

**Checkpoint**: US3 完了 — SLO 長期トレンド分析の基盤が整った（データ蓄積期間に応じて精度が向上）

---

## Phase 6: Polish & E2E 検証

**Purpose**: 全 Success Criteria の確認と IaC クリーンアップ

- [x] T016 [P] SC-001〜SC-004 の最終検証を実施する（`specs/014-victoria-metrics/quickstart.md` の「最終検証」セクション参照）
- [x] T017 `task tg:plan` を実行し、全 HCP Workspace で "No changes" を確認する（Constitution 原則 I）
- [x] T018 `.claude/SESSION_STATE.md` を更新する（014-victoria-metrics 完了、次のアクション候補を記録）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即時開始可能
- **Foundational (Phase 2)**: Phase 1 完了後 — **全 US をブロック**
- **US1 (Phase 3)**: Phase 2 完了後に開始
- **US2 (Phase 4)**: US1 完了後に開始（Grafana が VM に接続するには VM が稼働している必要がある）
- **US3 (Phase 5)**: US1 完了後に開始（SLO メトリクスの蓄積には VM + remote_write が必要）
- **Polish (Phase 6)**: 全 US 完了後

### User Story Dependencies

- **US1 (P1)**: Phase 2 完了後に独立して開始可能 — **MVP スコープ**
- **US2 (P2)**: US1 完了後（VM 稼働が前提）— US3 とは独立
- **US3 (P3)**: US1 完了後（remote_write で SLO メトリクスが VM に届いている必要がある）— US2 とは独立

### US1 内の依存関係

```
T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010
```

T007, T008 は同一ファイル（prometheus.yml）への変更のため逐次実行

### Parallel Opportunities

- T016（最終検証）は T017 と並列実行可能

---

## Parallel Example: User Story 1

```bash
# VM デプロイ完了後、Prometheus 設定を逐次追加:
T007: prometheus.yml に remote_write セクションを追加
T008: prometheus.yml に Job 11 を追加（同じファイルのため逐次）
T009: task sync:prometheus で反映
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 完了: ディレクトリ作成
2. Phase 2 完了: terragrunt.hcl 作成（CRITICAL）
3. Phase 3 完了: VM デプロイ + remote_write 設定
4. **STOP and VALIDATE**: `curl http://YOUR_SERVER_IP:8428/api/v1/query?query=up` でデータ確認
5. 長期保存基盤の稼働確認 → US2/US3 へ進む

### Incremental Delivery

1. Setup + Foundational → IaC 定義完成
2. US1 → VM 稼働 + メトリクス転送開始（MVP！）
3. US2 → Grafana からの可視化が可能に
4. US3 → SLO 長期トレンド分析の確認
5. 各 US はそれぞれ独立して検証可能

---

## Notes

- インフラ専用フィーチャーのため、全タスクは設定ファイル作成・コマンド実行・動作確認で構成される
- アプリケーションコードの変更なし
- テストは curl/API 呼び出しによる E2E 検証のみ（ユニットテスト不要）
- T004（Workspace Local 化）は既知の手順: SESSION_STATE.md または過去セッションの手順を参照
- T015（SLO ダッシュボード確認）はブラウザ目視確認。recording rules のデータが VM に届くまで数分待機が必要な場合がある
