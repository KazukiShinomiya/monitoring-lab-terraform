# Tasks: Alertmanager導入 — アラート通知基盤

**Input**: Design documents from `/specs/004-alertmanager-slack/`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅

**Tests**: 本フィーチャーはIaC（HCL/YAML）のため自動テストは対象外。`amtool check-config` による設定検証と手動発火テストで代替する。

**Organization**: フェーズ1→2は直列必須。フェーズ3〜5はUS1完了後に順次、またはUS2/US3は並行実施可能。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並行実施可能（別ファイル・他タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（US1/US2/US3）

---

## Phase 1: Setup（ディレクトリ・環境変数の整備）

**Purpose**: ローカルリポジトリのディレクトリ構造と環境変数テンプレートを準備する

- [ ] T001 `config/alertmanager/` ディレクトリを作成する（`mkdir config/alertmanager/`）
- [ ] T002 `.env.example` に `SLACK_WEBHOOK_URL=<YOUR_SLACK_WEBHOOK_URL>` エントリを追加する

---

## Phase 2: Foundational（Alertmanagerコンテナのデプロイ）

**Purpose**: Alertmanagerコンテナ自体の起動確認まで完了させる。Prometheus連携の前提条件。

**⚠️ CRITICAL**: このフェーズ完了前はUS実装を開始しないこと

- [ ] T003 [P] `config/alertmanager/alertmanager.yml` を `contracts/alertmanager.yml.example` を基に作成する（Webhook URLはプレースホルダー `<YOUR_SLACK_WEBHOOK_URL>` のまま）
- [ ] T004 [P] `terraform/envs/local/alertmanager/terragrunt.hcl` を作成する（イメージ: `prom/alertmanager:latest`、ポート: 9093、bind_mount: `alertmanager.yml`、ネットワーク: `monitoring-lab-network`、依存: `network`）
- [ ] T005 リモートサーバーにディレクトリを作成し、alertmanager.yml をコピーして Webhook URL を実際の値に置換する（`ssh ubuntu@YOUR_SERVER_IP 'mkdir -p /home/ubuntu/monitoring-lab/alertmanager'` → scp → sed で URL 書き換え）
- [ ] T006 HCP Terraform Workspace `monitoring-lab-local-alertmanager` を作成し、API で Local 実行モードに変更する（既知の手順: `curl -X PATCH https://app.terraform.io/api/v2/...`）
- [ ] T007 `terraform/envs/local/alertmanager/` で `terragrunt init` を実行する（HCP Workspace への接続確認）
- [ ] T008 `terragrunt apply` を実行して Alertmanager コンテナをデプロイする
- [ ] T009 Alertmanager の起動を確認する（`docker ps` で `monitoring-lab-alertmanager` が Up 状態 + `http://YOUR_SERVER_IP:9093` の WebUI アクセス確認）

**Checkpoint**: Alertmanager が起動している状態。Prometheus との連携は未設定。

---

## Phase 3: User Story 1 — アラート発生時にSlackで即座に気づく (Priority: P1) 🎯 MVP

**Goal**: Prometheus のアラートが Alertmanager 経由で Slack に届くことを確認する

**Independent Test**: cAdvisor コンテナを停止 → 60秒以内に Slack 通知を受信 → cAdvisor 再起動 → Slack に resolved 通知を受信

### Implementation for User Story 1

- [ ] T010 [US1] `config/prometheus/prometheus.yml` に `alerting:` セクション（`alertmanager:9093` へのルーティング）と `alertmanager` スクレイプジョブ（`targets: ['alertmanager:9093']`）を追加する（SC-004準拠）
- [ ] T011 [US1] 更新した `config/prometheus/prometheus.yml` を scp でリモートサーバーに転送する（`scp config/prometheus/prometheus.yml ubuntu@YOUR_SERVER_IP:/home/ubuntu/monitoring-lab/prometheus/`）
- [ ] T012 [US1] Prometheus をホットリロードする（`curl -X POST http://YOUR_SERVER_IP:9090/-/reload`）
- [ ] T013 [US1] Prometheus が Alertmanager を認識していることを確認する（`http://YOUR_SERVER_IP:9090/status` の "Alertmanagers" セクションに `alertmanager:9093` が表示されること）
- [ ] T014 [US1] cAdvisor コンテナを停止して TargetDown アラートを発火させる（`ssh ubuntu@YOUR_SERVER_IP 'docker stop monitoring-lab-cadvisor'`）
- [ ] T015 [US1] 60秒以内（SC-001）に Slack チャンネルへ通知が届くことを確認する（アラート名・重要度・発生時刻・説明が読み取れること SC-003）
- [ ] T016 [US1] cAdvisor を再起動して resolved 通知が Slack に届くことを確認する（`docker start monitoring-lab-cadvisor`）

**Checkpoint**: US1 完了。基本的な通知フローが動作している。

---

## Phase 4: User Story 2 — 重要度別にアラートをルーティングする (Priority: P2)

**Goal**: `critical` と `warning` で通知の見た目（色・ラベル）が異なることを確認する

**Independent Test**: TargetDown（critical）と ContainerHighCPU（warning）をそれぞれ発火させ、Slack メッセージの色が異なることを目視確認する

### Implementation for User Story 2

- [ ] T017 [US2] `config/alertmanager/alertmanager.yml` に2つのレシーバーが正しく定義されていることを確認する（`slack-notifications`: `color: warning/good`（黄色）、`slack-critical`: `color: danger/good`（赤色））
- [ ] T018 [US2] ルーティングルールで `severity: critical` が `slack-critical` レシーバーに振り分けられていることを確認する（`match: {severity: critical}` → `receiver: 'slack-critical'`）
- [ ] T019 [US2] ContainerHighCPU（warning）を発火させ Slack 通知の色が黄色（`warning`）であることを確認する（cAdvisor に高負荷をかけるか、`config/prometheus/alerts.yml` の閾値を一時的に下げる）
- [ ] T020 [US2] TargetDown（critical）を発火させ Slack 通知の色が赤（`danger`）であることを確認し、warning との視覚的な差異を確認する

**Checkpoint**: US1 + US2 完了。severity による色分けが機能している。

---

## Phase 5: User Story 3 — アラートの重複通知を抑制する (Priority: P3)

**Goal**: 同一アラートの再発時に `repeat_interval` が適切に機能し、inhibit_rules が動作していることを確認する

**Independent Test**: 設定値の確認（`repeat_interval: 4h`、`inhibit_rules` の定義）と `amtool` による設定検証で代替

### Implementation for User Story 3

- [ ] T021 [US3] `config/alertmanager/alertmanager.yml` の `repeat_interval` 設定を確認する（デフォルトルート: `4h`（FR-005）、critical ルート: `1h`）
- [ ] T022 [US3] `inhibit_rules` が定義されていることを確認する（`severity: critical` 発火時に同一 `job` の `severity: warning` を抑制する設定）
- [ ] T023 [US3] コンテナ内で `amtool check-config /etc/alertmanager/alertmanager.yml` を実行して設定を検証する（`ssh ubuntu@YOUR_SERVER_IP 'docker exec monitoring-lab-alertmanager amtool check-config /etc/alertmanager/alertmanager.yml'`）

**Checkpoint**: US1 + US2 + US3 完了。全3ユーザーストーリーが機能している。

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 品質保証・IaC整合性確認・コミット

- [ ] T024 `terragrunt plan` を実行して "No changes" を確認する（IaC Constitution I 準拠）
- [ ] T025 [P] `config/prometheus/prometheus.yml` がリモートサーバーのファイルと同期されていることを確認する（diff で比較）
- [ ] T026 [P] `config/alertmanager/alertmanager.yml`（プレースホルダー版）がリポジトリに正しくコミットされていることを確認する（Webhook URL が含まれていないことを確認）
- [ ] T027 SESSION_STATE.md を更新する（今日の戦果・次回アクション）
- [ ] T028 変更ファイルをコミットしてプッシュする（`config/alertmanager/alertmanager.yml`、`terraform/envs/local/alertmanager/terragrunt.hcl`、`config/prometheus/prometheus.yml`、`.env.example`）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし。即開始可能
- **Foundational (Phase 2)**: Phase 1 完了後。**US実装をブロック**
- **US1 (Phase 3)**: Phase 2 完了後 — 他のUSに依存しない
- **US2 (Phase 4)**: Phase 2 完了後 — US1 の動作確認後が望ましい（same config file）
- **US3 (Phase 5)**: Phase 2 完了後 — US1/US2 完了後が望ましい（same config file）
- **Polish (Phase 6)**: 全US完了後

### User Story Dependencies

- **US1 (P1)**: Foundational完了後に開始可能。他USへの依存なし
- **US2 (P2)**: Foundational完了後に開始可能。US1の設定ファイル（alertmanager.yml）が前提
- **US3 (P3)**: Foundational完了後に開始可能。設定の確認が主体のため US1/US2 後が自然

### Parallel Opportunities

- T003 と T004: 別ファイル作成のため並行可能（`alertmanager.yml` と `terragrunt.hcl`）
- T024 と T025 と T026: Polish フェーズの確認作業は並行可能
- T014〜T016（US1動作確認）と T017〜T018（US2設定確認）: 設定確認は並行可能（動作テストは順次が望ましい）

---

## Parallel Example: Phase 2 Setup

```bash
# T003 と T004 を並行作成:
Task A: config/alertmanager/alertmanager.yml を contracts/alertmanager.yml.example から作成
Task B: terraform/envs/local/alertmanager/terragrunt.hcl を作成
```

---

## Implementation Strategy

### MVP First (User Story 1 のみ)

1. Phase 1: Setup（T001-T002）
2. Phase 2: Foundational（T003-T009）— **ここで Alertmanager が起動**
3. Phase 3: US1（T010-T016）— **Slack 通知が届けば MVP 達成**
4. **STOP and VALIDATE**: cAdvisor テストで通知フローを確認
5. PR作成・レビューでもよし

### Incremental Delivery

1. Setup + Foundational → Alertmanager コンテナが起動
2. US1 → Slack 通知が届く（MVP！）
3. US2 → 重要度別の色分けが機能する
4. US3 → 重複抑制の設定を確認する
5. Polish → IaC整合性確認・コミット

---

## Summary

| フェーズ | タスク数 | 内容 |
|---------|---------|------|
| Phase 1: Setup | 2 | ディレクトリ・環境変数 |
| Phase 2: Foundational | 7 | コンテナデプロイ |
| Phase 3: US1 (P1) | 7 | Prometheus連携・Slack通知確認 |
| Phase 4: US2 (P2) | 4 | severity別色分け確認 |
| Phase 5: US3 (P3) | 3 | 重複抑制・設定検証 |
| Phase 6: Polish | 5 | IaC整合性・コミット |
| **合計** | **28** | |

**MVP スコープ**: Phase 1-3（T001〜T016）の16タスク完了でSlack通知が機能する状態になる。
