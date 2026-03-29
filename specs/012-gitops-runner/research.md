# Research: GitOps Runner

**Phase**: 0 (Pre-design)
**Date**: 2026-03-29
**Branch**: 012-gitops-runner

---

## 決定事項一覧

### D-001: Runner Docker イメージ

**Decision**: `myoung34/github-runner:2.332.0-ubuntu-jammy`

**Rationale**:
- 最もメンテナンスが活発な self-hosted runner イメージ（2026-03-29 時点で最新 2.332.0）
- PAT ベースの自動登録/解除に対応（`ACCESS_TOKEN` 環境変数）
- Ubuntu Jammy (22.04) ベースで apt による追加パッケージインストールが容易
- バージョンを `2.332.0-ubuntu-jammy` 形式でピンすることで `latest` タグの破壊的変更を回避

**Alternatives considered**:
- `actions-runner-controller (ARC)`: Kubernetes ベース — 過剰
- `tcardonne/docker-github-runner`: メンテナンス停止
- GitHub 公式ランナー: Docker 化が複雑

**Version pinning pattern**:
```
myoung34/github-runner:2.332.0-ubuntu-jammy
```
次回アップデート時は `terragrunt.hcl` のタグを PR で変更して plan → apply。

---

### D-002: Docker デーモンアクセス方式

**Decision**: `/var/run/docker.sock` のバインドマウント

**Rationale**:
- runner がリモートサーバー (YOUR_SERVER_IP) 自身で動くため、ソケットマウントで直接 Docker 操作が可能
- Docker-in-Docker (DinD) より軽量で設定が単純
- 既存モジュールの `bind_mounts` 機能で実現できる

**Security note**:
- docker.sock マウントはホスト Docker への完全アクセスを許可する
- 学習環境では許容。本番化する場合は rootless Docker または専用ネットワーク分離を検討

**Configuration**:
```hcl
bind_mounts = [
  {
    source    = "/var/run/docker.sock"
    target    = "/var/run/docker.sock"
    read_only = false
  }
]
```

---

### D-003: Terraform / Terragrunt のインストール方法

**Decision**: ワークフロー内でステップとしてインストール

**Rationale**:
- `hashicorp/setup-terraform@v3` で Terraform をバージョン固定インストール
- Terragrunt はバイナリを直接ダウンロード（GitHub Releases）
- カスタムイメージ作成不要でシンプル。バージョン変更も workflow YAML の変更のみ

**Version pins** (初期値):
- Terraform: `1.10.5` (HCP Terraform との互換性確認済みバージョン系)
- Terragrunt: `0.68.0` (run-all コマンド構文が安定しているバージョン)

**Rationale for Terragrunt version**:
- Terragrunt v0.67 以降: `run-all` コマンドは `run --all` に変更された
- 既存 docker-compose では `alpine/terragrunt:latest` を使用しているが、CI では安定版を固定
- v0.68.0 を初期値とし、既存環境で使用中のバージョンと一致させること

**Install steps**:
```yaml
- uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: "1.10.5"
    terraform_wrapper: false  # plan出力をキャプチャするため false

- name: Install Terragrunt
  run: |
    TG_VERSION="0.68.0"
    wget -q -O /tmp/terragrunt \
      "https://github.com/gruntwork-io/terragrunt/releases/download/v${TG_VERSION}/terragrunt_linux_amd64"
    chmod +x /tmp/terragrunt
    sudo mv /tmp/terragrunt /usr/local/bin/terragrunt
```

---

### D-004: Plan 結果の PR コメント方式

**Decision**: `terragrunt run --all plan` 出力をキャプチャ → `peter-evans/create-or-update-comment` でコメント投稿

**Rationale**:
- `dflook/terraform-plan` は Terraform 直接実行前提で Terragrunt の `run-all` に非対応
- `gruntwork-io/terragrunt-action` は実行は可能だが出力キャプチャが限定的
- 手動キャプチャ + `peter-evans/create-or-update-comment` が最も柔軟

**Pattern**:
```yaml
- name: Terragrunt Plan
  id: plan
  run: |
    cd terraform/envs/local
    terragrunt run --all plan --terragrunt-non-interactive 2>&1 | tee /tmp/plan_output.txt
    echo "PLAN_EXIT_CODE=${PIPESTATUS[0]}" >> $GITHUB_OUTPUT
  continue-on-error: true

- name: Post Plan Comment
  uses: peter-evans/create-or-update-comment@v4
  with:
    issue-number: ${{ github.event.pull_request.number }}
    comment-id: ${{ steps.find_comment.outputs.comment-id }}
    edit-mode: replace
    body: |
      ## Terragrunt Plan Results
      <details><summary>Click to expand</summary>

      ```
      ${{ steps.plan.outputs.stdout }}
      ```
      </details>
```

---

### D-005: 同時実行防止

**Decision**: GitHub Actions `concurrency` 機能 + `cancel-in-progress: false`

**Rationale**:
- `cancel-in-progress: false` により、実行中の apply はキャンセルされず新しいジョブはキューに入る
- apply 中断は HCP Terraform State ロックで問題を起こす可能性がある
- plan は `cancel-in-progress: true` でも問題なし（読み取り専用）

**Configuration**:
```yaml
# apply ワークフロー
concurrency:
  group: terraform-apply
  cancel-in-progress: false  # 絶対 false にすること

# plan ワークフロー
concurrency:
  group: terraform-plan-${{ github.event.pull_request.number }}
  cancel-in-progress: true  # 同一PR の古い plan はキャンセル可
```

---

### D-006: Runner 登録方式

**Decision**: `ACCESS_TOKEN` (PAT) 環境変数による自動登録・解除

**Rationale**:
- `myoung34/github-runner` は `ACCESS_TOKEN` (GitHub PAT) を使い、起動時に Registration Token を API で自動取得
- Registration Token（有効期限1時間）の手動管理が不要
- コンテナ停止時に GitHub から自動デレジスタ

**Required PAT scopes**: `repo` (full) のみ

**Container env vars**:
```
ACCESS_TOKEN  = <GitHub PAT>
REPO_URL      = https://github.com/KazukiShinomiya/monitoring-lab-terraform
RUNNER_NAME   = monitoring-lab-runner-01
LABELS        = self-hosted,linux,monitoring-lab
RUNNER_WORKDIR = /tmp/runner-work
```

---

### D-007: GitHub Secrets 構成

**Decision**: GitHub リポジトリレベルの Secrets に集約

| Secret 名 | 内容 | 用途 |
|----------|------|------|
| `GH_PAT` | GitHub PAT (repo scope) | Runner 自動登録 |
| `TF_API_TOKEN` | HCP Terraform Token | `TF_TOKEN_app_terraform_io` として Terragrunt が参照 |

**Note**: `TF_TOKEN_app_terraform_io` は HCP Terraform の自動認証環境変数名。Workflow で `TF_TOKEN_app_terraform_io: ${{ secrets.TF_API_TOKEN }}` のようにマッピング。

---

### D-008: Terragrunt 実行ディレクトリとコマンド

**Decision**: `terraform/envs/local` から `terragrunt run --all plan/apply`

**Rationale**: 全ワークスペース（15+）を一括対象とする（spec の Assumptions に従い、変更差分の選択的実行はスコープ外）

**Command syntax** (Terragrunt v0.67+):
```bash
# Plan
terragrunt run --all plan --terragrunt-non-interactive

# Apply
terragrunt run --all apply --terragrunt-non-interactive
```

**Note**: Terragrunt v0.67 以前は `run-all plan` / `run-all apply`。バージョン固定により互換性を保証する。

---

### D-009: Observability (Constitution V 準拠)

**Decision**: cAdvisor による自動カバレッジを活用、追加 Prometheus Job は不要

**Rationale**:
- cAdvisor は全 Docker コンテナを自動監視（runner コンテナも含まれる）
- runner は独自のメトリクスエンドポイントを公開しない
- runner の状態は GitHub API / GitHub Actions UI で確認可能

**Additions**:
- `alerts.yml` に `GithubRunnerDown` アラートルールを追加（オプション・別 PR）
- cAdvisor でコンテナが消えたら Prometheus アラート → Alertmanager → Slack 通知の既存フローで検知可能

