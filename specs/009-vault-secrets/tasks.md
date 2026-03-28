# Tasks: Vault シークレット管理 Step 1 — Alertmanager Webhook URL

**Input**: `specs/009-vault-secrets/`（spec.md / plan.md / data-model.md / contracts/ / research.md）
**Branch**: `009-vault-secrets`

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並行実行可能（異なるファイル・依存関係なし）
- **[Story]**: 対応する User Story（US1 / US2 / US3）

---

## Phase 1: Setup（Vault Workspace 準備）

**目的**: 新規 Terragrunt workspace の土台を作る

- [ ] T001 `terraform/envs/local/vault-secrets/` ディレクトリを作成する
- [ ] T002 HCP Terraform（`k1981-learning-lab`）に `vault-secrets` workspace を作成し、Execution Mode を Local に変更する

**Checkpoint**: `vault-secrets/` ディレクトリが存在し、HCP Terraform workspace が Local モードで準備完了

---

## Phase 2: Foundational（接続確認）

**目的**: Vault（10.0.0.220:8200）への疎通を確認する — 全 US の前提条件

**⚠️ CRITICAL**: この Phase が完了するまで US1 以降の作業を開始しない

- [ ] T003 Vault の稼働状態を確認する（`curl http://10.0.0.220:8200/v1/sys/health` で `initialized:true` / `sealed:false` を確認）

**Checkpoint**: Vault API への疎通確認完了

---

## Phase 3: User Story 1 — Vault に Webhook URL を格納する（Priority: P1）🎯 MVP

**Goal**: `terragrunt apply` を実行すると Vault KV v2 の `secret/monitoring-lab/alertmanager` に `slack_webhook_url` が格納される

**Independent Test**: `curl -H "X-Vault-Token: root" http://10.0.0.220:8200/v1/secret/data/monitoring-lab/alertmanager | jq '.data.data'` で `{"slack_webhook_url": "https://hooks.slack.com/..."}` が返ること

### Implementation for User Story 1

- [ ] T004 [P] [US1] `terraform/modules/vault_secret/variables.tf` に `alertmanager_slack_webhook_url` 変数（型: string、sensitive: true）を追加する
- [ ] T005 [P] [US1] `terraform/modules/vault_secret/main.tf` に `vault_kv_secret_v2.alertmanager_slack` リソースを追加する（パス: `monitoring-lab/alertmanager`、キー: `slack_webhook_url`、max_versions: 5）
- [ ] T006 [US1] `terraform/modules/vault_secret/main.tf` の `vault_policy.app_read_policy` に alertmanager パス（`<mount>/data/monitoring-lab/alertmanager`）への read 権限を追加する（T005 依存）
- [ ] T007 [P] [US1] `terraform/modules/vault_secret/outputs.tf` に `alertmanager_secret_path` 出力を追加する
- [ ] T008 [US1] `terraform/envs/local/vault-secrets/terragrunt.hcl` を作成する（vault_address: `http://10.0.0.220:8200`、vault_token: `get_env("VAULT_TOKEN", "root")`、alertmanager_slack_webhook_url: `get_env("SLACK_WEBHOOK_URL")`、T004-T007 依存）
- [ ] T009 [US1] `vault-secrets` workspace で `terragrunt init` を実行してプロバイダーをインストールする（T008 依存）
- [ ] T010 [US1] `terragrunt plan` で差分を確認し、3リソース（vault_mount / vault_kv_secret_v2 × 3 / vault_policy）が作成されることを確認する（T009 依存）
- [ ] T011 [US1] `terragrunt apply` を実行し、Vault API（`curl`）で `slack_webhook_url` が取得できることを確認する（T010 依存）

**Checkpoint**: Vault に Webhook URL が格納済み。`vault kv get` で取得可能

---

## Phase 4: User Story 2 — Vault から Webhook URL を読み取って Alertmanager を設定する（Priority: P2）

**Goal**: `.env` の `SLACK_WEBHOOK_URL` が未設定でも `sync-config.sh alertmanager` が Vault から URL を取得して正常完了する

**Independent Test**: `.env` の `SLACK_WEBHOOK_URL` をコメントアウトした状態で `./scripts/sync-config.sh alertmanager` を実行し、リモートの設定ファイルにプレースホルダーが残っていないこと、かつ `[OK] alertmanager 同期完了` が表示されること

### Implementation for User Story 2

- [ ] T012 [P] [US2] `.env.example` に `VAULT_ADDR`（デフォルト: `http://10.0.0.220:8200`）と `VAULT_TOKEN`（デフォルト: `root`）を追加し、`SLACK_WEBHOOK_URL` をオプション（コメント）としてマークする
- [ ] T013 [US2] `scripts/sync-config.sh` の `sync_alertmanager()` を更新する: Vault HTTP API（`curl` + `jq`）で `slack_webhook_url` を取得するロジックを追加し、取得失敗時は `.env` の `SLACK_WEBHOOK_URL` にフォールバックし、両方未設定の場合は Vault / `.env` の両方を案内するエラーメッセージを表示する（T011 依存）
- [ ] T014 [US2] `.env` の `SLACK_WEBHOOK_URL` をコメントアウトして `./scripts/sync-config.sh alertmanager` を実行し、Vault から URL を取得して同期が完了することを確認する（T013 依存）
- [ ] T015 [US2] Vault を停止した状態（またはトークン無効）で `sync-config.sh alertmanager` を実行し、`.env` フォールバックが機能すること、および両方未設定時のエラーメッセージが分かりやすいことを確認する（T014 依存）

**Checkpoint**: Vault 経由・`.env` フォールバック・両方未設定エラーの全3パターンが動作確認済み

---

## Phase 5: User Story 3 — Alertmanager が引き続き Slack に通知できることを確認する（Priority: P3）

**Goal**: Vault 経由の設定反映後も、既存のアラート通知が正常に機能している

**Independent Test**: `amtool check-config` 成功 + 手動でアラートを発火させて Slack 通知を受信

### Implementation for User Story 3

- [ ] T016 [US3] リモートサーバーで `amtool check-config /etc/alertmanager/alertmanager.yml` を実行し、SUCCESS が返ることを確認する（T014 依存）
- [ ] T017 [US3] cAdvisor コンテナを一時停止してアラートを発火させ、Slack `#monitoring-alerts` に FIRING 通知が届くことを確認する（T016 依存）
- [ ] T018 [US3] cAdvisor を再起動して RESOLVED 通知が届くことを確認する（T017 依存）

**Checkpoint**: 移行前後でアラート通知が正常に機能していることをエンドツーエンドで確認済み

---

## Phase 6: Polish & Cross-Cutting Concerns

**目的**: 運用性の向上とドキュメント整備

- [ ] T019 [P] `Taskfile.yml` に `vault:check` タスクを追加する（Vault API 疎通確認コマンドを1行で実行）
- [ ] T020 [P] `Taskfile.yml` に `vault:store` タスクを追加する（`vault-secrets` workspace で `terragrunt apply` を実行するショートカット）
- [ ] T021 `.claude/SESSION_STATE.md` を更新して今回の作業内容と次のアクションを記録する
- [ ] T022 変更ファイルをコミットして `009-vault-secrets` ブランチに push し、PR を作成する

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: 依存なし — 即開始可能
- **Phase 2 (Foundational)**: Phase 1 完了後 — **全 US をブロック**
- **Phase 3 (US1)**: Phase 2 完了後
- **Phase 4 (US2)**: Phase 3（T011）完了後（Vault にシークレットが存在する必要がある）
- **Phase 5 (US3)**: Phase 4（T014）完了後
- **Phase 6 (Polish)**: Phase 5 完了後

### User Story 内のタスク依存

```
T004 [P] ─┐
T005 [P] ──┤→ T006 → T008 → T009 → T010 → T011
T007 [P] ─┘

T012 [P] ─┐
           ├→ T013 → T014 → T015
(T011)  ──┘

T014 → T016 → T017 → T018

T019 [P] ─┐
           ├→ T021 → T022
T020 [P] ─┘
```

### 並行実行可能タスク

- **Phase 3 (US1)**: T004 / T005 / T007 を並行実行可能
- **Phase 4 (US2)**: T012 と T013 の準備は並行可能（T013 は T011 依存）
- **Phase 6 (Polish)**: T019 / T020 を並行実行可能

---

## Parallel Example: Phase 3 (US1)

```bash
# T004、T005、T007 は互いに独立したファイルを変更するため並行実行可能
Task: "variables.tf に alertmanager_slack_webhook_url 変数を追加"
Task: "main.tf に vault_kv_secret_v2.alertmanager_slack を追加"
Task: "outputs.tf に alertmanager_secret_path を追加"

# 上記3タスク完了後、順次実行
→ T006（ポリシー更新）→ T008（terragrunt.hcl）→ T009（init）→ T010（plan）→ T011（apply）
```

---

## Implementation Strategy

### MVP（US1 のみ）

1. Phase 1: Setup（T001-T002）
2. Phase 2: Foundational（T003）
3. Phase 3: US1（T004-T011）
4. **STOP & VALIDATE**: Vault API で Webhook URL が取得できることを確認
5. US2 に進む前に US1 の独立性を確認

### 完全実装（全 US）

1. Phase 1-2（Setup + Foundational）
2. Phase 3（US1）→ Vault 格納確認
3. Phase 4（US2）→ sync-config.sh 動作確認
4. Phase 5（US3）→ Slack 通知確認
5. Phase 6（Polish）→ PR 作成

---

## Notes

- Vault dev モード再起動後はシークレットが消えるため、T011 を再実行する
- `SLACK_WEBHOOK_URL` は T008 / T011 の `terragrunt apply` 実行時に `.env` に設定されている必要がある
- T010 の plan で `No changes` でなく3リソースが表示されることを確認してから T011 を実行すること
- `sensitive = true` の変数は `terraform plan` の出力に表示されない（仕様通り）
