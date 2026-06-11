# Tasks: Pyroscope 継続的プロファイリング基盤

**Input**: Design documents from `/specs/015-pyroscope/`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅
**Tests**: 仕様書に明示的なテスト要求なし。検証は `/ready` ヘルスチェック + Prometheus `up` + Grafana datasource 接続確認で行う。

> **注**: 本 tasks.md は実装・デプロイ完了後のバックフィル。全タスクは既に完了済み（`[x]`）であり、稼働中の実装に対応する記録である。

**Organization**: US1（サーバー稼働 + 可視化基盤）→ US2（Prometheus 統合）→ US3（永続化）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイル・依存関係なし）
- **[Story]**: 対応するユーザーストーリー（US1/US2/US3）

---

## Phase 1: Setup（共有基盤準備）

- [x] T001 [P] `config/pyroscope/` ディレクトリを作成する
- [x] T002 [P] WSL2 で `docker pull grafana/pyroscope:2.0.2` を実行し、イメージが取得できることを確認する

---

## Phase 2: Foundational（全ユーザーストーリーの前提条件）

**⚠️ CRITICAL**: このフェーズが完了するまでユーザーストーリーの実装を開始しないこと

- [x] T003 `config/pyroscope/config.yml` を作成する（`pyroscopedb.data_path: /data`）。pull スクレイプは v2.x の config.yml では非対応のため記載せず、設計意図をコメントで明記する
- [x] T004 `terraform/envs/local/pyroscope/terragrunt.hcl` を作成する（`image = "grafana/pyroscope:2.0.2"`、port 4040、`pyroscope_data` ボリューム、`/home/ubuntu/monitoring-lab/pyroscope` bind mount、network 依存）
- [x] T005 リモートサーバーに `config/pyroscope/config.yml` を scp する（`/home/ubuntu/monitoring-lab/pyroscope/`）

**Checkpoint**: 設定ファイルとコンテナ定義が揃った → ユーザーストーリー実装開始可能

---

## Phase 3: User Story 1 - Pyroscope サーバー稼働と可視化基盤（Priority: P1）🎯 MVP

**Goal**: Pyroscope が稼働し、Grafana datasource として接続される

**Independent Test**: `/ready` が 200 を返し、Grafana の Data sources で Pyroscope の接続テストが成功する

- [x] T006 [US1] HCP Workspace（`monitoring-lab-local-pyroscope`）を作成し、実行モードを Local に変更する
- [x] T007 [US1] `terragrunt apply` で Pyroscope コンテナを起動する
- [x] T008 [US1] `/ready` を確認する（起動直後の 503「Segment Writer waiting 30s」は正常猶予と判断）
- [x] T009 [US1] `config/grafana/provisioning/datasources/datasources.yml` に Pyroscope datasource を追記する（`type: grafana-pyroscope-datasource`、`uid: pyroscope`、`url: http://pyroscope:4040`）
- [x] T010 [US1] `task sync:grafana` でリモート反映し、Grafana を再起動する
- [x] T011 [US1] Grafana UI の Data sources 一覧で Pyroscope の接続テストが成功することを確認する

**Checkpoint**: User Story 1 完了 → サーバー稼働 + datasource 接続を独立して確認済み

---

## Phase 4: User Story 2 - Prometheus スクレイプ統合（Priority: P2）

**Goal**: Pyroscope メトリクスが既存 Prometheus で収集される

**Independent Test**: Prometheus UI `/targets` で `pyroscope` ジョブが UP 状態になる

- [x] T012 [US2] `config/prometheus/prometheus.yml` に `pyroscope` ジョブを追加する（`static_configs.targets: ['pyroscope:4040']`）
- [x] T013 [US2] `task sync:prometheus` でリモート反映 + ホットリロードする
- [x] T014 [P] [US2] Prometheus UI `/targets` で `pyroscope` ジョブが UP であることを確認する（SC-002）
- [x] T015 [P] [US2] Prometheus で `pyroscope_distributor_received_profiles_total` 等の `pyroscope_*` メトリクスが取得できることを確認する

**Checkpoint**: User Story 2 完了 → Prometheus 統合を独立して確認済み

---

## Phase 5: User Story 3 - データ永続化（Priority: P3）

**Goal**: コンテナ再起動後もプロファイルデータが保持される

**Independent Test**: コンテナ再起動の前後で `pyroscope_data` ボリュームのデータが保持される

- [x] T016 [US3] `pyroscope_data` ボリュームが `/data` にマウントされていることを確認する
- [x] T017 [US3] コンテナを再起動し、`pyroscope_data` のデータが保持されることを確認する（SC-003）

**Checkpoint**: User Story 3 完了 → 永続化を独立して確認済み

---

## Phase 6: Polish & 運用確認

- [x] T018 イメージタグを `:latest` → `grafana/pyroscope:2.0.2` に固定する（Tempo/OTel の教訓適用、2026-05-30）
- [x] T019 `terragrunt apply` でタグ変更が `forces replacement`（1 add/1 destroy）となること、名前付きボリュームが保持されること（瞬断4秒）を確認する
- [x] T020 `task tg:plan` を実行し、全 HCP Terraform ワークスペースで "No changes" を確認する（Constitution I, SC-005）
- [x] T021 `.claude/SESSION_STATE.md` を更新し、作業内容・完了タスク・次のアクションを記録する

---

## Dependencies & Execution Order

### Phase 依存関係

- **Phase 1 (Setup)**: 依存なし — 即座に開始可能
- **Phase 2 (Foundational)**: Phase 1 完了後 — US1〜US3 を全てブロック
- **Phase 3 (US1)**: Phase 2 完了後に開始可能（MVP）
- **Phase 4 (US2)**: Phase 3 完了後（コンテナ稼働が前提）
- **Phase 5 (US3)**: Phase 3 完了後（US2 とは並列実行可能）
- **Phase 6 (Polish)**: Phase 3〜5 完了後

### ユーザーストーリー間の依存関係

- **US1 (P1)**: Phase 2 完了後 → 独立（MVP）
- **US2 (P2)**: US1 完了後（コンテナ `:4040` が稼働していること）
- **US3 (P3)**: US1 完了後、US2 とは並列実行可能

### 並列実行機会

- T001 / T002（Phase 1）: 完全並列
- T014 / T015（Phase 4）: 完全並列（UI / クエリ確認）
- US2（T012〜T015）と US3（T016〜T017）: US1 完了後に並列実行可能

---

## Implementation Strategy

### MVP First（US1 のみ）

1. Phase 1: Setup 完了
2. Phase 2: Foundational 完了（CRITICAL）
3. Phase 3: US1 完了 → Pyroscope 稼働 + Grafana datasource 接続
4. **STOP & VALIDATE**: `/ready` 200 + Grafana 接続テスト成功

### Incremental Delivery

1. Phase 1 + 2 → 基盤完成
2. Phase 3 (US1) → サーバー稼働 + 可視化基盤（MVP）
3. Phase 4 (US2) → Prometheus 統合
4. Phase 5 (US3) → 永続化で完結
5. Phase 6 → バージョン固定で運用堅牢化

---

## Notes

- 全タスクは実装・デプロイ済み（バックフィル記録）
- SC-001（セルフプロファイルのフレームグラフ表示）は v2.x の pull スクレイプ非対応のため**部分達成** → Alloy/SDK 配線が次フェーズ課題（research.md 決定事項 2 参照）
- `image` は固定タグ必須。更新時は `terragrunt.hcl` の値を明示的に上げること
- Pyroscope v2.x の `/ready`: 内部 ready 後も約30秒の猶予 → 起動直後の 503 は正常
