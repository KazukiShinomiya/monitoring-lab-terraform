# Feature Specification: GitOps Runner — GitHub Actions Self-hosted Runner

**Feature Branch**: `012-gitops-runner`
**Created**: 2026-03-29
**Status**: Draft
**Input**: GitHub Actions Self-hosted Runner をリモートサーバー (10.0.0.220) の Docker コンテナとして追加。Terragrunt (IaC) で管理。PR 時に terraform plan を自動実行、main マージ時に terraform apply を自動実行する GitOps 自動デプロイ基盤の構築。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — PR で自動 Plan チェック (Priority: P1)

開発者が IaC の変更を含む PR を作成・更新すると、GitHub Actions が自動的に `terragrunt plan` を実行し、その結果を PR コメントとして投稿する。開発者は GitHub の PR 画面だけで変更影響を確認できる。

**Why this priority**: インフラ変更の意図しない副作用を事前に検知できる。これがないと、変更を適用してから初めて問題に気づく。

**Independent Test**: IaC ファイルを変更した PR を作成するだけでテスト可能。PR コメントに plan 結果が届けば価値が確認できる。

**Acceptance Scenarios**:

1. **Given** IaC ファイル（`.tf` / `.hcl`）を変更した PR が作成された時、**When** GitHub Actions が起動し、**Then** 2分以内に plan 結果が PR コメントに投稿される
2. **Given** plan に変更あり（`+/-` リソース）の時、**When** コメントが投稿される、**Then** 追加・変更・削除のリソース数が明確に示される
3. **Given** IaC ファイルを含まない変更の PR の時、**When** PR が作成・更新される、**Then** plan ワークフローはスキップされる（不要なジョブを実行しない）
4. **Given** plan がエラーになった時、**When** コメントが投稿される、**Then** エラー内容が含まれ PR の Checks がブロック状態になる

---

### User Story 2 — main マージで自動 Apply (Priority: P2)

開発者が IaC 変更 PR を main にマージすると、GitHub Actions が自動的に `terragrunt apply` を実行し、リモートサーバーのインフラを更新する。

**Why this priority**: 手動 apply の手間を排除し、「コードが truth」のワークフローを確立する。

**Independent Test**: PR を main にマージして、リモートサーバーのコンテナ状態が spec 通りに更新されれば価値確認完了。

**Acceptance Scenarios**:

1. **Given** IaC 変更 PR が main にマージされた時、**When** GitHub Actions が起動し、**Then** 2分以内に apply が開始される
2. **Given** apply が成功した時、**When** ワークフローが完了し、**Then** GitHub Actions の実行結果に適用されたリソース変更のサマリーが表示される
3. **Given** apply が失敗した時、**When** エラーが発生し、**Then** ワークフローが失敗状態になり、担当者に通知が届く（GitHub の失敗通知）
4. **Given** 複数の PR が同時に main にマージされた時、**When** apply ジョブが競合しそうになる、**Then** 同時実行が防止され apply は順次実行される

---

### User Story 3 — Runner バージョン管理 (Priority: P3)

Runner のイメージバージョンを IaC で明示的に固定・管理する。バージョンアップは IaC の変更として PR → plan → apply のフローを経て適用される。

**Why this priority**: `latest` タグの使用は予期しない破壊的変更のリスクがある（過去に Tempo v2.10 で経験）。バージョンを固定し、アップデートを意図的な変更として扱うことでリグレッションを防ぐ。

**Independent Test**: `terragrunt.hcl` のイメージタグを変更して apply し、新バージョンのランナーが GitHub に登録されれば確認完了。

**Acceptance Scenarios**:

1. **Given** Runner の IaC 定義にバージョンが明示されている時、**When** `terragrunt apply` を実行し、**Then** 指定バージョンのコンテナが起動する（`latest` タグは使用しない）
2. **Given** Runner を新バージョンに更新したい時、**When** `terragrunt.hcl` のバージョンを変更して PR を作成し、**Then** plan で変更内容（旧→新バージョン）が確認でき、apply で無停止に近い形で更新される
3. **Given** 新バージョンで問題が発生した時、**When** バージョンを前のタグに戻して apply し、**Then** 旧バージョンのランナーが復元される

---

### User Story 4 — Runner 自体を IaC で管理 (Priority: P4)

Self-hosted Runner コンテナそのものを Terragrunt で定義・デプロイする。監視基盤の他のサービスと同じ手順でランナーを追加・更新・削除できる。

**Why this priority**: ランナー自体が手動管理になると「インフラをコードで管理する」原則に矛盾する。ただし P1/P2 の CI/CD 機能が動けば先に価値は出るため P4。

**Independent Test**: `terraform/envs/local/github-runner/` を apply するだけで 10.0.0.220 上にランナーコンテナが起動し、GitHub リポジトリの Settings > Actions > Runners にオンライン表示されれば確認完了。

**Acceptance Scenarios**:

1. **Given** `terraform/envs/local/github-runner/terragrunt.hcl` が定義された時、**When** `terragrunt apply` を実行し、**Then** リモートサーバーにランナーコンテナが起動し GitHub に登録される
2. **Given** ランナーコンテナが停止した時、**When** Docker の再起動ポリシーが働き、**Then** コンテナが自動再起動されランナーがオンラインに戻る
3. **Given** ランナーを削除したい時、**When** `terragrunt destroy` を実行し、**Then** コンテナが停止・削除され GitHub からも登録解除される

---

### Edge Cases

- ランナーがオフライン中に PR が作成・更新された場合、ジョブはキューに残り、ランナー復帰後に実行される
- apply 実行中に別の apply がトリガーされた場合、後発ジョブは前発の完了を待ってから実行される（同時実行数: 1）
- HCP Terraform State ロック中に apply を実行しようとした場合、エラーで失敗しワークフローが通知する
- GitHub Actions の Registration Token は有効期限（1時間）があるため、コンテナ起動時に毎回取得する仕組みが必要

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST automatically trigger a plan check on every PR that modifies IaC files (`.tf`, `.hcl`) targeting the main branch
- **FR-002**: System MUST post plan results (resource change summary + raw output) as a PR comment within 2 minutes of the triggering event
- **FR-003**: System MUST block PR merge when plan execution fails (Checks API)
- **FR-004**: System MUST automatically trigger apply on every push to main that modifies IaC files
- **FR-005**: System MUST prevent concurrent apply executions to avoid HCP Terraform state conflicts
- **FR-006**: System MUST deploy the runner itself as a Terragrunt-managed container on the remote server (10.0.0.220)
- **FR-007**: System MUST store all sensitive credentials (GitHub PAT, HCP Terraform token) as encrypted GitHub repository secrets
- **FR-008**: System MUST allow the runner to access the Docker daemon on the remote server to execute Terragrunt operations
- **FR-009**: System MUST automatically restart the runner container if it stops unexpectedly
- **FR-010**: Runner container image version MUST be explicitly pinned in the IaC definition (no `latest` tag)
- **FR-011**: Runner version updates MUST be performed as IaC changes going through the PR → plan → apply workflow
- **FR-012**: It MUST be possible to roll back to a previous runner version by reverting the IaC change and applying

### Key Entities

- **GitHub Actions Workflow**: CI/CD パイプライン定義（`.github/workflows/` に配置）。plan ワークフローと apply ワークフローの 2 ファイル
- **Self-hosted Runner**: 10.0.0.220 上で稼働する Docker コンテナ。GitHub Actions ジョブを受け取って実行する
- **Runner Registration Token**: GitHub から取得する短命トークン（有効期限1時間）。コンテナ起動時に API で取得して登録に使用
- **GitHub Repository Secrets**: ワークフローが参照する暗号化済み機密情報（`GH_PAT`, `TF_TOKEN_app_terraform_io` 等）

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: IaC ファイルを変更した PR 作成・更新から 2 分以内に plan 結果が PR コメントに投稿される
- **SC-002**: main へのマージから 2 分以内に apply が開始される
- **SC-003**: apply 成功時、変更されたリソースのサマリーが GitHub Actions のログで確認できる
- **SC-004**: Runner コンテナは他の監視基盤サービスと同一の `terragrunt apply` コマンドでデプロイ・更新できる
- **SC-005**: IaC ファイルを含まない PR では plan ワークフローが起動しない（不要な実行ゼロ）
- **SC-006**: ランナーコンテナが予期せず停止した場合、5分以内に自動再起動してオンライン状態に戻る
- **SC-007**: Runner のイメージバージョンが IaC に明示され、`latest` タグが使用されていないことがコードレビューで確認できる
- **SC-008**: Runner バージョンの変更は PR の plan 結果に旧バージョン→新バージョンの差分として表示される

---

## Assumptions

- HCP Terraform の実行モードはすべて `Local` のまま維持する（runner コンテナ内で terragrunt を実行し、HCP Terraform は State バックエンドとしてのみ使用）
- Runner イメージのバージョンは初期デプロイ時に安定版タグで固定する。定期的なバージョンアップは手動 PR で対応（Dependabot 等の自動化は scope 外）
- apply は `terragrunt run-all apply` で全ワークスペースを対象とする（変更差分のみを対象とした選択的 apply は scope 外）
- ランナーは GitHub リポジトリレベル（organization ではなく）で登録する
- plan / apply ともにリモートサーバー上のコンテナから SSH なしで直接 Docker を操作する（runner がリモートサーバー自身で動くため）
- GitHub Actions の `ubuntu-latest` ランナーではなく、自ホスト runner を必須とするジョブラベル（`self-hosted`）を使用する

