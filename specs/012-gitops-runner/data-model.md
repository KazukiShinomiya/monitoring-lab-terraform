# Data Model: GitOps Runner

**Feature**: 012-gitops-runner
**Date**: 2026-03-29

---

## エンティティ一覧

### 1. GitHub Actions Workflow (Plan)

**場所**: `.github/workflows/terraform-plan.yml`

| フィールド | 値 | 説明 |
|----------|---|------|
| trigger | `pull_request` (types: opened, synchronize, reopened) | PR 作成・更新時 |
| paths filter | `terraform/**`, `config/**` | IaC ファイル変更時のみ |
| runs-on | `self-hosted` | 監視サーバー上の runner |
| concurrency group | `terraform-plan-${{ github.event.pull_request.number }}` | 同一PR の重複防止 |
| cancel-in-progress | `true` | 古い plan はキャンセル可 |
| permissions | `pull-requests: write`, `contents: read` | PR コメント投稿 |

**Steps**:
1. `actions/checkout@v4`
2. `hashicorp/setup-terraform@v3` (version: 1.10.5, wrapper: false)
3. Install Terragrunt binary (v0.68.0)
4. `terragrunt run --all plan --terragrunt-non-interactive` (出力キャプチャ)
5. `peter-evans/find-comments@v3` (既存コメント検索)
6. `peter-evans/create-or-update-comment@v4` (plan 結果を PR コメントに投稿/更新)
7. plan 失敗時にワークフローを失敗状態にする

---

### 2. GitHub Actions Workflow (Apply)

**場所**: `.github/workflows/terraform-apply.yml`

| フィールド | 値 | 説明 |
|----------|---|------|
| trigger | `push` (branches: main) | main へのマージ時 |
| paths filter | `terraform/**`, `config/**` | IaC ファイル変更時のみ |
| runs-on | `self-hosted` | 監視サーバー上の runner |
| concurrency group | `terraform-apply` | apply の同時実行防止 |
| cancel-in-progress | `false` | 実行中の apply は絶対キャンセル禁止 |
| environment | `production` | 将来の手動承認ゲート用 |

**Steps**:
1. `actions/checkout@v4`
2. `hashicorp/setup-terraform@v3` (version: 1.10.5, wrapper: false)
3. Install Terragrunt binary (v0.68.0)
4. `terragrunt run --all apply --terragrunt-non-interactive`
5. apply 結果をサマリーに出力

---

### 3. Self-hosted Runner Container

**Terragrunt 定義**: `terraform/envs/local/github-runner/terragrunt.hcl`
**HCP Workspace**: `monitoring-lab-local-github-runner`

| フィールド | 値 |
|----------|---|
| image | `myoung34/github-runner:2.332.0-ubuntu-jammy` |
| container name | `monitoring-lab-github-runner` |
| network | `monitoring-lab-network` |
| internal_port | `0` (未使用) |
| external_port | `0` (未使用) |
| restart policy | `unless-stopped` |

**Environment Variables**:

| 変数名 | 値 | 機密 | 説明 |
|-------|---|------|------|
| `ACCESS_TOKEN` | `get_env("GH_RUNNER_PAT")` | ✅ | GitHub PAT (runner 登録用) |
| `REPO_URL` | `https://github.com/KazukiShinomiya/monitoring-lab-terraform` | ❌ | 登録先リポジトリ |
| `RUNNER_NAME` | `monitoring-lab-runner-01` | ❌ | GitHub 上の表示名 |
| `LABELS` | `self-hosted,linux,monitoring-lab` | ❌ | ジョブルーティング用ラベル |
| `RUNNER_WORKDIR` | `/tmp/runner-work` | ❌ | 作業ディレクトリ |
| `RUNNER_ALLOW_RUNASROOT` | `true` | ❌ | root ユーザーでの実行許可 |

**Bind Mounts**:

| source (host) | target (container) | read_only | 目的 |
|--------------|-------------------|-----------|------|
| `/var/run/docker.sock` | `/var/run/docker.sock` | false | Docker デーモンアクセス |

**Volumes**: なし（runner は stateless）

---

### 4. GitHub Repository Secrets

**設定場所**: GitHub → Settings → Secrets and variables → Actions

| Secret 名 | マッピング先 | 用途 |
|----------|------------|------|
| `GH_RUNNER_PAT` | runner container の `ACCESS_TOKEN` 環境変数 | Runner 自動登録・解除 |
| `TF_API_TOKEN` | workflow の `TF_TOKEN_app_terraform_io` 環境変数 | HCP Terraform 認証 |

**Note**: `TF_TOKEN_app_terraform_io` は Terraform が HCP Terraform に自動認証するための予約環境変数名。

---

### 5. Runner Registration Token (Runtime Entity)

**概念上のエンティティ**（永続化されない）

| フィールド | 値 |
|----------|---|
| 取得方法 | GitHub API (POST /repos/{owner}/{repo}/actions/runners/registration-token) |
| 有効期限 | 1 時間 |
| 管理 | `myoung34/github-runner` が `ACCESS_TOKEN` を使って自動取得・更新 |
| 保存場所 | コンテナ内メモリのみ（永続化なし） |

---

## 設定値のバージョン管理方針

IaC で管理するバージョン番号一覧:

| コンポーネント | 管理場所 | 初期バージョン | 更新方法 |
|-------------|---------|-------------|---------|
| Runner image | `terraform/envs/local/github-runner/terragrunt.hcl` | `2.332.0-ubuntu-jammy` | IaC PR → plan → apply |
| Terraform | `.github/workflows/terraform-plan.yml` / `terraform-apply.yml` | `1.10.5` | workflow PR → apply |
| Terragrunt | 同上 | `0.68.0` | workflow PR → apply |

**原則**: いずれも `latest` タグ / 省略を禁止。変更は PR を通じて diff として可視化する。

