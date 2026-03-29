# Implementation Plan: GitOps Runner

**Branch**: `012-gitops-runner` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-gitops-runner/spec.md`

---

## Summary

GitHub Actions Self-hosted Runner を リモートサーバー (YOUR_SERVER_IP) の Docker コンテナとして追加し、IaC 変更を自動検証・デプロイする GitOps 基盤を構築する。

Runner は `myoung34/github-runner:2.332.0-ubuntu-jammy` (バージョン固定) として Terragrunt 管理下に置く。PR 時に `terragrunt run --all plan` を実行して結果を PR コメントに投稿し、main マージ時に `run --all apply` を自動実行する。同時実行は GitHub Actions `concurrency` で防止。

---

## Technical Context

**Language/Version**: HCL (Terragrunt 0.68.0 / Terraform 1.10.5) + YAML (GitHub Actions)
**Primary Dependencies**:
- `myoung34/github-runner:2.332.0-ubuntu-jammy` (runner base image)
- `hashicorp/setup-terraform@v3` (workflow action)
- `peter-evans/create-or-update-comment@v4` (PR comment action)
- `peter-evans/find-comments@v3` (既存コメント検索)
**Storage**: N/A (runner はステートレス)
**Testing**: GitHub Actions ワークフロー実行ログ + runner オンライン確認
**Target Platform**: Docker Engine on Ubuntu (YOUR_SERVER_IP)
**Performance Goals**: plan/apply 開始まで 2 分以内 (SC-001/002)
**Constraints**: 同時実行数 1 (apply), HCP Terraform State ロック尊重

---

## Constitution Check

*GATE: Must pass before implementation*

### I. Infrastructure as Code (IaC)

✅ **PASS**: Runner コンテナは `docker_container` モジュール経由で Terragrunt 定義。HCP Terraform にて State 管理。

### II. セキュリティファースト

✅ **PASS**: GitHub PAT / HCP Terraform Token は GitHub Secrets に格納。コードへのハードコードなし。
⚠️ **NOTE**: `/var/run/docker.sock` マウントはホスト Docker への完全アクセスを許可する。学習環境では許容、本番化時は検討が必要（Constitution II の技術的負債として記録）。

### III. ドキュメント駆動開発

✅ **PASS**: Speckit ADLC フルサイクル (specify → plan) 実行済み。

### IV. モジュール化とDRY原則

✅ **PASS**: 既存 `docker_container` モジュールを使用。インライン定義なし。

### V. 自己監視の可観測性

✅ **PASS**: cAdvisor が runner コンテナを自動監視（全コンテナ対象）。runner は独自メトリクスを公開しないため追加 Job 不要。コンテナ停止は既存アラートフローで検知可能。

---

## Project Structure

### Documentation (this feature)

```text
specs/012-gitops-runner/
├── spec.md              ✅ 完了
├── research.md          ✅ 完了 (Phase 0)
├── data-model.md        ✅ 完了 (Phase 1)
├── quickstart.md        ✅ 完了 (Phase 1)
├── plan.md              ✅ このファイル
├── contracts/
│   ├── workflow-plan.yml              ✅ 完了
│   ├── workflow-apply.yml             ✅ 完了
│   └── github-runner-terragrunt.hcl  ✅ 完了
├── checklists/
│   └── requirements.md  ✅ 完了
└── tasks.md             📅 /speckit.tasks で生成
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── mcp-ci.yml                   # 既存 (変更なし)
    ├── terraform-plan.yml           # 新規作成 (Phase B)
    └── terraform-apply.yml          # 新規作成 (Phase C)

terraform/envs/local/
└── github-runner/
    └── terragrunt.hcl               # 新規作成 (Phase A)
```

**Structure Decision**: IaC + GitHub Actions ワークフローのみ。ソースコードなし。既存モジュール構造に従い `terraform/envs/local/github-runner/` に配置。

---

## Implementation Phases

### Phase A: Runner コンテナ (IaC) — US3/US4/FR-006/FR-009/FR-010

**目標**: YOUR_SERVER_IP 上に runner コンテナをデプロイし、GitHub にオンライン登録する

1. `.env` に `GH_RUNNER_PAT` を追加
2. `terraform/envs/local/github-runner/terragrunt.hcl` を作成
   - `contracts/github-runner-terragrunt.hcl` を参照
   - image: `myoung34/github-runner:2.332.0-ubuntu-jammy` (バージョン固定)
   - bind_mount: `/var/run/docker.sock`
   - env: `ACCESS_TOKEN`, `REPO_URL`, `RUNNER_NAME`, `LABELS`
3. HCP Terraform Workspace 作成 (`monitoring-lab-local-github-runner`, Local モード)
4. `terragrunt plan` → `terragrunt apply`
5. 動作確認: `docker ps` + GitHub Settings → Runners

**Acceptance**: runner が GitHub に `Idle` 状態で表示される

---

### Phase B: terraform-plan.yml ワークフロー — US1/FR-001/FR-002/FR-003

**目標**: PR 作成・更新時に plan を自動実行し結果をコメント投稿

1. GitHub Secrets に `TF_API_TOKEN` を登録
2. `.github/workflows/terraform-plan.yml` を作成
   - `contracts/workflow-plan.yml` を参照
   - trigger: `pull_request` + `paths: terraform/**, config/**`
   - steps: checkout → setup-terraform → install-terragrunt → plan → find-comment → post-comment → fail-on-error
3. テスト: 小変更 PR を作成して動作確認

**Acceptance**: PR コメントに plan 結果が 2 分以内に投稿される / plan 失敗時に Checks がブロック

---

### Phase C: terraform-apply.yml ワークフロー — US2/FR-004/FR-005

**目標**: main マージ時に apply を自動実行

1. `.github/workflows/terraform-apply.yml` を作成
   - `contracts/workflow-apply.yml` を参照
   - trigger: `push` to main + `paths: terraform/**, config/**`
   - concurrency: `group: terraform-apply, cancel-in-progress: false`
2. テスト: Phase B の PR を main にマージして動作確認

**Acceptance**: main マージから 2 分以内に apply が開始 / 同時実行時は 2 つ目がキュー待ち

---

### Phase D: バージョン管理検証 — US3/FR-010/FR-011/FR-012

**目標**: runner バージョン固定・更新フローが IaC を通じて機能することを確認

1. `data-model.md` のバージョン管理方針に従いドキュメント確認
2. runner image タグ変更 PR を作成し、plan コメントに旧→新バージョン差分が表示されることを確認
3. apply 後に新バージョンコンテナが起動することを確認
4. ロールバック: 旧タグに戻す PR → plan → apply でロールバック成功を確認

**Acceptance**: SC-007/SC-008 が満たされる

---

## 依存関係グラフ

```
Phase A (Runner デプロイ)
    ↓
Phase B (plan workflow)  ─→  Phase D (version管理検証)
    ↓
Phase C (apply workflow)
```

Phase A なしで B/C は動作しない（runner がいない）。

---

## Complexity Tracking

| 項目 | 学習環境での許容理由 |
|------|-------------------|
| `/var/run/docker.sock` マウント | runner がホスト自身で動くため必要。学習環境ではこれが最もシンプルな方式 |

