# Quickstart: GitOps Runner 動作確認手順

**Feature**: 012-gitops-runner
**Date**: 2026-03-29

---

## 前提条件

- [ ] `GH_RUNNER_PAT` を `.env` に設定済み（GitHub PAT, `repo` scope）
- [ ] `TF_API_TOKEN` を GitHub リポジトリ Secrets に設定済み（HCP Terraform token）
- [ ] `GH_RUNNER_PAT` を GitHub リポジトリ Secrets に設定済み（runner 登録用）

---

## Step 1: Runner コンテナのデプロイ確認 (US4)

```bash
# Terragrunt コンテナに入る
docker compose exec terragrunt sh

# github-runner サービスをデプロイ
cd terraform/envs/local/github-runner
terragrunt plan     # 変更内容の確認
terragrunt apply    # デプロイ実行
```

**確認ポイント**:
- `docker ps | grep github-runner` → `monitoring-lab-github-runner` が Up
- GitHub → Settings → Actions → Runners → `monitoring-lab-runner-01` が `Idle` 表示

---

## Step 2: バージョン固定確認 (US3)

```bash
# コンテナのイメージタグを確認
docker inspect monitoring-lab-github-runner | grep -i image
# 期待値: "myoung34/github-runner:2.332.0-ubuntu-jammy" (latest でないこと)
```

---

## Step 3: PR で自動 Plan チェック (US1)

```bash
# テスト用ブランチで IaC ファイルを小変更
git checkout -b test/plan-check
# terraform/envs/local/prometheus/terragrunt.hcl にコメント追加など
echo "# test" >> terraform/envs/local/prometheus/terragrunt.hcl
git add . && git commit -m "test: trigger plan workflow"
git push origin test/plan-check
```

**確認ポイント**:
- GitHub Actions → `Terraform Plan` ワークフローが起動（2分以内）
- PR コメントに `Terragrunt Plan Results` が投稿される
- plan が成功 → PR の Checks が ✅
- plan が失敗 → PR の Checks が ❌（マージブロック）

---

## Step 4: main マージで自動 Apply (US2)

```bash
# テスト用 PR をマージ（plan チェックが通った後）
# GitHub UI から PR を Merge
```

**確認ポイント**:
- GitHub Actions → `Terraform Apply` ワークフローが起動（2分以内）
- apply 成功 → ワークフロー ✅ + Job Summary にリソース変更サマリー
- apply 失敗 → ワークフロー ❌ + Slack/GitHub 通知

---

## Step 5: 同時実行防止確認 (US2 Edge Case)

```bash
# 2つの PR を立て続けに main にマージする
# 2つ目のワークフローは concurrency グループで待機状態になることを確認
```

**確認ポイント**:
- GitHub Actions で 2 つ目のジョブが `Queued` 表示
- 1 つ目の完了後に自動で実行開始

---

## Step 6: ランナー自動再起動確認 (US4 Edge Case)

```bash
# Runner コンテナを手動停止
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@10.0.0.220 'docker stop monitoring-lab-github-runner'"

# 5分以内に自動再起動することを確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@10.0.0.220 'docker ps | grep github-runner'"
```

**確認ポイント**:
- 停止後 5 分以内にコンテナが再起動
- GitHub → Settings → Actions → Runners → `monitoring-lab-runner-01` が再び `Idle`

---

## Step 7: バージョンアップ確認 (US3)

```bash
# バージョンタグを変更する PR を作成
# contracts/github-runner-terragrunt.hcl を参考に image タグを変更
git checkout -b test/runner-version-bump
# terragrunt.hcl の image タグを変更
git add . && git commit -m "chore: bump github-runner to X.X.X"
git push origin test/runner-version-bump
```

**確認ポイント**:
- Plan コメントに `~ image = "myoung34/github-runner:OLD" -> "myoung34/github-runner:NEW"` の差分
- apply 後に新バージョンのコンテナが起動

---

## トラブルシューティング

### Runner が GitHub に表示されない

```bash
# コンテナログを確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@10.0.0.220 'docker logs monitoring-lab-github-runner'"
# ACCESS_TOKEN が無効 or 期限切れの場合はエラーログ確認
# GH_RUNNER_PAT の scope (repo) が正しいか確認
```

### plan ワークフローが起動しない

- `.github/workflows/terraform-plan.yml` の `paths:` フィルタを確認
- 変更ファイルが `terraform/**` または `config/**` に含まれているか確認
- runner が GitHub にオンライン登録されているか確認

### apply で HCP Terraform 認証エラー

```bash
# GitHub Secrets の TF_API_TOKEN が最新か確認
# HCP Terraform → User Settings → Tokens で有効期限確認
```

