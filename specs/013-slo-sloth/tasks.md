# Tasks: SLO + Error Budget 管理基盤 (Sloth)

**Input**: Design documents from `/specs/013-slo-sloth/`  
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅  
**Tests**: 仕様書に明示的なテスト要求なし。検証は `sloth validate` + `promtool check rules` + UI確認で行う。

**Organization**: US1（ルール生成）→ US2（ダッシュボード）→ US3（Slack通知）の順で独立して動作確認可能。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイル・依存関係なし）
- **[Story]**: 対応するユーザーストーリー（US1/US2/US3）

---

## Phase 1: Setup（共有基盤準備）

**Purpose**: ディレクトリ作成と Sloth Docker イメージの確認

- [x] T001 [P] `config/sloth/` ディレクトリを作成する
- [x] T002 [P] WSL2 で `docker pull ghcr.io/slok/sloth:v0.11.0` を実行し、イメージが取得できることを確認する

---

## Phase 2: Foundational（全ユーザーストーリーの前提条件）

**Purpose**: SLO 定義ファイルと Taskfile タスクを整備する。これらが揃って初めて US1〜US3 が実装可能になる。

**⚠️ CRITICAL**: このフェーズが完了するまでユーザーストーリーの実装を開始しないこと

- [x] T003 `config/sloth/monitoring-lab.yml` を新規作成する。`contracts/sloth-slo-schema.yml` のスキーマに従い、4件の SLO を定義する（Prometheus/Grafana/Alertmanager = 目標値99.5%、Loki = 99.0%、SLI は `raw` タイプで `1 - avg_over_time(up{job="..."}[{{.window}}])`）
- [x] T004 [P] `Taskfile.yml` に `slo:generate` タスクを追加する。WSL2 経由で `ghcr.io/slok/sloth:v0.11.0` コンテナをワンショット実行し、`config/sloth/monitoring-lab.yml` を入力、`config/prometheus/slo-rules.yml` を出力とする
- [x] T005 [P] `Taskfile.yml` に `slo:validate` タスクを追加する。WSL2 経由で `prom/prometheus:latest` コンテナを使い `promtool check rules /etc/prometheus/slo-rules.yml` を実行する

**Checkpoint**: T003〜T005 完了 → ユーザーストーリー実装開始可能

---

## Phase 3: User Story 1 - SLO定義からアラートルール自動生成（Priority: P1）🎯 MVP

**Goal**: `task slo:generate` 実行で Prometheus に SLO Recording Rules と Alerting Rules が反映される

**Independent Test**: Prometheus UI `http://YOUR_SERVER_IP:9090/rules` で `slo:sli_error:ratio_rate*` の Recording Rules と `SLOBudgetBurn` 形式の Alerting Rules が表示されることを確認する

- [x] T006 [US1] `task slo:generate` を実行し、`config/prometheus/slo-rules.yml` が生成されることを確認する（4サービス分のルールが含まれていること）
- [x] T007 [US1] `task slo:validate` を実行し、生成されたルールが `promtool check rules` をパスすることを確認する
- [x] T008 [US1] `config/prometheus/prometheus.yml` の `rule_files:` セクションに `- '/etc/prometheus/slo-rules.yml'` を追記する
- [x] T009 [US1] `task sync:prometheus` を実行してリモートサーバーに `prometheus.yml` と `slo-rules.yml` を転送し、Prometheus をホットリロードする
- [x] T010 [P] [US1] Prometheus UI `http://YOUR_SERVER_IP:9090/rules` を開き、`slo:sli_error:ratio_rate1h`、`slo:error_budget:ratio`、`slo:objective:ratio` 等の Recording Rules が4サービス分表示されることを確認する
- [x] T011 [P] [US1] Prometheus UI `/rules` で `MonitoringLab*Availability*Burn` 形式の Alerting Rules が各サービスに4件（PageQuickBurn / PageSlowBurn / TicketQuickBurn / TicketSlowBurn）表示されることを確認する

**Checkpoint**: User Story 1 完了 → Prometheus に SLO ルールが反映されていることを独立して確認済み

---

## Phase 4: User Story 2 - Error Budgetダッシュボードで消費状況を可視化（Priority: P2）

**Goal**: Grafana で全4サービスの Error Budget 残量と Burning Rate グラフが手動設定なしで表示される

**Independent Test**: Grafana `http://YOUR_SERVER_IP:3000` で "Sloth - SLO Overview" ダッシュボードを開き、4サービスの Error Budget 残量（%）と Burning Rate グラフが表示されることを確認する

- [x] T012 [US2] WSL2 で以下を実行して Sloth 公式ダッシュボード JSON を取得する: `docker run --rm --entrypoint cat ghcr.io/slok/sloth:v0.11.0 /dist/grafana-dashboard.json > config/grafana/provisioning/dashboards/sloth-overview.json`
- [x] T013 [US2] 取得した `config/grafana/provisioning/dashboards/sloth-overview.json` を開き、ファイルが有効な JSON であり Grafana ダッシュボード形式（`"panels"` キーを含む）であることを確認する
- [x] T014 [US2] `task sync:grafana` を実行して `sloth-overview.json` をリモートの Grafana プロビジョニングディレクトリに転送し、Grafana を再起動する
- [x] T015 [US2] Grafana UI `http://YOUR_SERVER_IP:3000` を開き、"Sloth" または "SLO" という名称のダッシュボードが存在することを確認する
- [x] T016 [US2] ダッシュボード上で4サービス（prometheus / grafana / alertmanager / loki）の Error Budget 残量（%）パネルが表示されることを確認する（Prometheus 起動直後は1.0 = 100%残が正常）
- [x] T017 [US2] ダッシュボード上で Fast Burn（1h/6h 窓）と Slow Burn（3d/30d 窓）の Burning Rate グラフが表示されることを確認する

**Checkpoint**: User Story 2 完了 → US1 のルールと US2 のダッシュボードが独立して機能確認済み

---

## Phase 5: User Story 3 - Error Budget枯渇時のSlack通知（Priority: P3）

**Goal**: Burning Rate 閾値超過時に Alertmanager 経由で Slack 通知が届く

**Independent Test**: 対象コンテナを一時停止して Fast Burn アラートを FIRING 状態にし、Slack `#alerts` に通知が届くことを確認する

- [x] T018 [US3] `config/alertmanager/alertmanager.yml` を開き、`severity: page` と `severity: ticket` ラベルに対応した routes が定義されているか確認する
- [x] T019 [US3] routes に `severity` ベースのルーティングが不足している場合、`config/alertmanager/alertmanager.yml` に `matchers: [{name: severity, value: page}]` の route を追加し、`task sync:alertmanager` を実行する
- [x] T020 [US3] リモートサーバーで対象コンテナ（例: `monitoring-lab-loki`）を一時的に停止して Fast Burn 状態を再現する: `ssh ubuntu@YOUR_SERVER_IP "docker stop monitoring-lab-loki"`
- [x] T021 [US3] 停止から数分後、Alertmanager UI `http://YOUR_SERVER_IP:9093` を開き `SLOBudgetBurn` 形式のアラートが FIRING 状態になっていることを確認する
- [x] T022 [US3] Slack の `#alerts` チャンネルに FIRING 通知が届いていることを確認する（severity と sloth_service ラベルが含まれていること）
- [x] T023 [US3] 停止したコンテナを再起動する: `ssh ubuntu@YOUR_SERVER_IP "docker start monitoring-lab-loki"`
- [x] T024 [US3] Slack に RESOLVED 通知が届いていることを確認する

**Checkpoint**: User Story 3 完了 → US1〜US3 の全ユーザーストーリーが独立して機能確認済み

---

## Phase 6: Polish & 運用確認

**Purpose**: 運用フロー全体の確認・整合性検証・セッション記録

- [x] T025 `scripts/sync-config.sh` の `prometheus` ケースを確認し、`config/prometheus/` 以下の全ファイル（`slo-rules.yml` を含む）が scp 対象になっていることを確認する（変更不要であれば確認のみ）
- [x] T026 新規 SLO 追加のエンドツーエンドフロー確認: `config/sloth/monitoring-lab.yml` に5件目の SLO エントリを追記 → `task slo:generate` → `task slo:validate` → `task sync:prometheus` → Prometheus UI で新ルール確認 → エントリを元に戻して再生成（SC-004 の検証）
- [x] T027 `task tg:plan` を実行し、全 HCP Terraform ワークスペースで "No changes" が出力されることを確認する（Constitution I 準拠確認）
- [x] T028 `.claude/SESSION_STATE.md` を更新し、今回の作業内容・完了タスク・次のアクションを記録する

---

## Dependencies & Execution Order

### Phase 依存関係

- **Phase 1 (Setup)**: 依存なし — 即座に開始可能
- **Phase 2 (Foundational)**: Phase 1 完了後 — US1〜US3 を全てブロック
- **Phase 3 (US1)**: Phase 2 完了後に開始可能
- **Phase 4 (US2)**: Phase 3 完了後に開始（Recording Rules が必要）
- **Phase 5 (US3)**: Phase 3 完了後に開始可能（US2 とは独立）
- **Phase 6 (Polish)**: Phase 3〜5 完了後

### ユーザーストーリー間の依存関係

- **US1 (P1)**: Phase 2 完了後 → 独立
- **US2 (P2)**: US1 完了後（Recording Rules がないとダッシュボードに値が出ない）
- **US3 (P3)**: US1 完了後（Alerting Rules が必要）、US2 とは並列実行可能

### 各ストーリー内の順序

- T006 → T007（validate は generate 後）
- T008 → T009（sync は設定変更後）
- T010 / T011 は並列確認可能
- T015 → T016 → T017（UI確認は順次）

### 並列実行機会

- T001 / T002（Phase 1）: 完全並列
- T004 / T005（Phase 2）: 完全並列（Taskfile の異なるセクション）
- T010 / T011（Phase 3）: 完全並列（UI確認）
- US2（T012〜T017）と US3（T018〜T024）: US1 完了後に並列実行可能

---

## Parallel Example: User Story 1

```bash
# Phase 2 の並列タスク（Taskfile.yml の異なる箇所を同時編集）
Task T004: slo:generate タスクを Taskfile.yml に追加
Task T005: slo:validate タスクを Taskfile.yml に追加

# Phase 3 の終盤確認（並列）
Task T010: Prometheus UI で Recording Rules を確認
Task T011: Prometheus UI で Alerting Rules を確認
```

---

## Implementation Strategy

### MVP First（US1 のみ）

1. Phase 1: Setup 完了
2. Phase 2: Foundational 完了（CRITICAL）
3. Phase 3: US1 完了
4. **STOP & VALIDATE**: Prometheus UI で SLO ルール確認
5. この時点で SC-001 達成 → デモ可能

### Incremental Delivery

1. Phase 1 + 2 → 基盤完成
2. Phase 3 (US1) → Prometheus に SLO ルール反映済み（MVP）
3. Phase 4 (US2) → Grafana ダッシュボードで可視化
4. Phase 5 (US3) → Slack 通知で完結
5. 各フェーズで独立したビジネス価値を提供

---

## Notes

- [P] タスク = 異なるファイル・依存関係なし → 並列実行可
- US1 が MVP: Prometheus UI での確認のみで独立してデモ可能
- `slo-rules.yml` は自動生成ファイルだが Git 管理対象（生成コマンド再現性の担保）
- Prometheus 起動直後は Recording Rules の計算結果（30日分）が不足するため、Error Budget = 1.0（100%残）が正常表示
- Fast Burn アラート（14.4倍）は実際の障害を短時間再現して確認する
