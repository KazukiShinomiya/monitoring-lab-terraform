# Tasks: GitOps Runner — GitHub Actions Self-hosted Runner

**Input**: Design documents from `/specs/012-gitops-runner/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: テストは spec に明示されていないため省略。quickstart.md の手順で動作確認を代替。

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1=PR Plan, US2=Auto Apply, US3=Version管理, US4=IaC Runner)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 認証情報の準備とディレクトリ構造の作成

- [x] T001 `.env.example` に `GH_RUNNER_PAT=` エントリを追加 in `.env.example`
- [ ] T002 [P] `.env` に `GH_RUNNER_PAT=<実際のPAT>` を設定（GitHub PAT, `repo` scope）
- [ ] T003 [P] GitHub リポジトリ Secrets に `TF_API_TOKEN` を登録（HCP Terraform token）
- [ ] T004 [P] GitHub リポジトリ Secrets に `GH_RUNNER_PAT` を登録（runner 登録用 PAT）
- [x] T005 `terraform/envs/local/github-runner/` ディレクトリを作成

**Checkpoint**: 認証情報が揃い、ディレクトリが作成された状態

---

## Phase 2: Foundational — Runner コンテナ (US4: IaC Runner管理)

**Purpose**: Self-hosted Runner コンテナを YOUR_SERVER_IP にデプロイし GitHub にオンライン登録する。US1/US2/US3 すべての前提条件。

**⚠️ CRITICAL**: このフェーズが完了するまで US1/US2/US3 のワークフローは動作しない

- [x] T006 [US4] `terraform/envs/local/github-runner/terragrunt.hcl` を作成（`specs/012-gitops-runner/contracts/github-runner-terragrunt.hcl` を参照）
  - image: `myoung34/github-runner:2.332.0-ubuntu-jammy`（バージョン固定、`latest` 禁止）
  - bind_mount: `/var/run/docker.sock:/var/run/docker.sock`
  - env: `ACCESS_TOKEN`, `REPO_URL`, `RUNNER_NAME=monitoring-lab-runner-01`, `LABELS=self-hosted,linux,monitoring-lab`
- [x] T007 [US4] HCP Terraform Workspace `monitoring-lab-local-github-runner` を作成し実行モードを Local に設定（API PATCH または UI）
- [x] T008 [US4] Terragrunt コンテナ内で `terraform/envs/local/github-runner/` に移動し `terragrunt plan` を実行して変更内容を確認
- [x] T009 [US4] `terragrunt apply` を実行してリモートサーバー (YOUR_SERVER_IP) にコンテナをデプロイ
- [x] T010 [US4] 動作確認: `wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker ps | grep github-runner'"` で `monitoring-lab-github-runner` が Up を確認
- [x] T011 [US4] GitHub → Settings → Actions → Runners → `monitoring-lab-runner-01` が `Idle` 状態で表示されることを確認

**Checkpoint**: Runner が GitHub にオンライン登録された — ワークフロー実装を開始できる

---

## Phase 3: User Story 1 — PR で自動 Plan チェック (Priority: P1) 🎯 MVP

**Goal**: IaC ファイルを含む PR 作成・更新時に `terragrunt run --all plan` が自動実行され、結果が PR コメントに投稿される

**Independent Test**: テスト用 PR を作成し、2 分以内に plan 結果コメントが投稿されれば US1 確認完了

- [x] T012 [US1] `.github/workflows/terraform-plan.yml` を新規作成（`specs/012-gitops-runner/contracts/workflow-plan.yml` を参照）
  - trigger: `pull_request` (types: opened, synchronize, reopened) + paths: `terraform/**`, `config/**`
  - concurrency: `group: terraform-plan-${{ github.event.pull_request.number }}`, `cancel-in-progress: true`
  - permissions: `contents: read`, `pull-requests: write`
  - env: `TF_TOKEN_app_terraform_io: ${{ secrets.TF_API_TOKEN }}`
  - steps: checkout@v4 → setup-terraform@v3(1.10.5) → install-terragrunt(0.68.0) → plan(working-dir: terraform/envs/local) → find-comments → create-or-update-comment → fail-on-error
- [x] T013 [US1] テスト用ブランチ `test/plan-workflow-check` を作成し `terraform/envs/local/prometheus/terragrunt.hcl` にコメント行を追加して PR を作成
- [x] T014 [US1] GitHub Actions の `Terraform Plan` ワークフローが起動し 2 分以内に PR コメントに `Terragrunt Plan Results` が投稿されることを確認
- [x] T015 [US1] plan 結果が `No changes` または変更サマリーを含む形式で表示されていることを確認
- [x] T016 [US1] plan 失敗シナリオ確認: `terragrunt.hcl` に意図的な構文エラーを追加してコミット → plan ワークフローが ❌ になり PR の Checks がブロック状態になることを確認
- [ ] T017 [US1] IaC ファイル以外の変更（例: `README.md`）だけの PR では plan ワークフローが起動しないことを確認（paths フィルタ動作）

**Checkpoint**: US1 完了 — IaC 変更のある PR で plan 結果が自動コメントされる

---

## Phase 4: User Story 2 — main マージで自動 Apply (Priority: P2)

**Goal**: IaC 変更を含む PR を main にマージすると `terragrunt run --all apply` が自動実行される

**Independent Test**: Phase 3 のテスト PR を main にマージし、2 分以内に apply ワークフローが起動すれば US2 確認完了

- [x] T018 [US2] `.github/workflows/terraform-apply.yml` を新規作成（`specs/012-gitops-runner/contracts/workflow-apply.yml` を参照）
  - trigger: `push` (branches: main) + paths: `terraform/**`, `config/**`
  - concurrency: `group: terraform-apply`, **`cancel-in-progress: false`**（CRITICAL）
  - env: `TF_TOKEN_app_terraform_io: ${{ secrets.TF_API_TOKEN }}`
  - steps: checkout@v4 → setup-terraform@v3(1.10.5) → install-terragrunt(0.68.0) → apply(working-dir: terraform/envs/local) + GITHUB_STEP_SUMMARY 出力
- [ ] T019 [US2] T013 で作成したテスト PR（plan チェック通過済み）を main にマージして apply ワークフローが起動することを確認
- [ ] T020 [US2] GitHub Actions の `Terraform Apply` ワークフローが ✅ で完了し、Job Summary に apply 結果サマリーが表示されることを確認
- [ ] T021 [US2] 同時実行防止確認: 連続して 2 つの変更を main にマージし、2 つ目のジョブが `Queued` になり 1 つ目の完了後に実行されることを確認

**Checkpoint**: US2 完了 — main マージで apply が自動実行される

---

## Phase 5: User Story 3 — Runner バージョン管理 (Priority: P3)

**Goal**: Runner image バージョンが IaC で明示固定され、アップデートが PR を通じて管理される

**Independent Test**: T006 の `terragrunt.hcl` に `latest` タグが使われておらず、バージョン変更 PR で plan に差分が表示されれば US3 確認完了

- [ ] T022 [US3] T006 で作成した `terraform/envs/local/github-runner/terragrunt.hcl` を確認し、image フィールドが `myoung34/github-runner:2.332.0-ubuntu-jammy` 形式でバージョン固定されていることを確認（`latest` 不使用）
- [ ] T023 [US3] バージョンアップ確認用ブランチ `test/runner-version-bump` を作成し `terraform/envs/local/github-runner/terragrunt.hcl` の image タグを別バージョンに変更して PR を作成
- [ ] T024 [US3] plan PR コメントに `~ image = "...OLD..." -> "...NEW..."` の差分が表示されることを確認（SC-008 達成）
- [ ] T025 [US3] T023 の PR をマージして apply 後に新バージョンのコンテナが起動していることを確認
- [ ] T026 [US3] ロールバック確認: 元のバージョンタグに戻した PR → plan → apply で旧バージョンのランナーが復元されることを確認

**Checkpoint**: US3 完了 — runner バージョンが IaC で管理され、更新/ロールバックが diff として可視化される

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 全ストーリーの統合確認と最終整理

- [ ] T027 [P] `quickstart.md` の Step 5「ランナー自動再起動確認」を実行: `docker stop` 後 5 分以内に自動再起動することを確認
- [ ] T028 [P] `run-all plan` / `run-all apply` がすべてのワークスペースで `No changes` になることを確認（既存サービスへの影響なし）
- [ ] T029 `.claude/SESSION_STATE.md` を更新（012-gitops-runner 完了状態を記録）
- [ ] T030 `git add`, `git commit -m "feat: 012-gitops-runner GitHub Actions GitOps基盤"`, `git push origin 012-gitops-runner` を実行して PR を作成

**Checkpoint**: 全 US が完了し、PR が作成された状態

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1: Setup (T001-T005)
    ↓
Phase 2: Foundational / US4 (T006-T011)  ← BLOCKS all workflows
    ↓
Phase 3: US1 - Plan Workflow (T012-T017)
    ↓
Phase 4: US2 - Apply Workflow (T018-T021)  ← depends on US1 runner being live
    ↓ (can overlap with Phase 4)
Phase 5: US3 - Version Management (T022-T026)
    ↓
Phase 6: Polish (T027-T030)
```

### User Story Dependencies

- **US4 (P4)**: Setup 完了後すぐ開始可能。他の US の前提条件
- **US1 (P1)**: US4 完了後に開始可能
- **US2 (P2)**: US1 完了後に開始（apply テストに plan 済み PR が必要）
- **US3 (P3)**: US4 完了後すぐ開始可能（US1/US2 と並列可能）

### Parallel Opportunities

- T002, T003, T004 は並列実行可（Phase 1 内）
- T022-T026（US3）は T011 完了後、T018 と並列実行可
- T027, T028（Phase 6）は並列実行可

---

## Parallel Example: Phase 2 後の並列実行

```bash
# US4 (T006-T011) 完了後:

# Stream A: US1 → US2 の順で実行
T012: terraform-plan.yml 作成
T013-T017: plan ワークフロー動作確認
T018: terraform-apply.yml 作成
T019-T021: apply ワークフロー動作確認

# Stream B: US3 を並列で進める（同じファイルに競合なし）
T022: バージョン固定確認
T023-T026: バージョンアップ・ロールバックフロー確認
```

---

## Implementation Strategy

### MVP First (US1 のみ)

1. Phase 1: Setup 完了
2. Phase 2: Runner デプロイ完了 (US4)
3. Phase 3: `terraform-plan.yml` 作成・動作確認 (US1)
4. **STOP and VALIDATE**: PR 作成 → plan コメント投稿を確認
5. この時点で「PR レビュー時に plan 結果が見える」という最大の価値が実現

### Incremental Delivery

1. Setup + Foundational → Runner オンライン
2. US1: plan コメント機能 → MVP デリバリー
3. US2: apply 自動化 → フル GitOps 実現
4. US3: バージョン管理 → 運用品質向上

---

## Notes

- T003/T004 は GitHub Web UI での手動操作（CLI での設定も可: `gh secret set`）
- T007 の HCP Workspace 作成は API PATCH が必要な場合あり（初回 `terragrunt init` で自動作成後 Local モードへ変更）
- T016 のエラーテストは確認後に必ず構文エラーを元に戻してから次のコミットを作成すること
- T021 の同時実行テストはタイミングが難しい場合あり — GitHub Actions の `workflow_dispatch` で手動トリガーを使った検証も可
- Terragrunt コマンド: v0.67+ は `terragrunt run --all plan` / `run --all apply`。ワークフロー内バージョン (0.68.0) と合わせること
