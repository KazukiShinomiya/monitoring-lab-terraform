---
name: check-config
description: Terragrunt/Terraform設定ファイルの整合性チェック（依存関係・ポート重複・イメージ名の一貫性）
---

Exploreエージェントに以下のタスクを委譲してください:

**タスク**: Terragrunt設定ファイルの整合性チェック

thoroughness level: medium

**確認項目**:
1. `terraform/envs/local/` 配下のすべての `terragrunt.hcl` を読み込み
2. `dependency` ブロックの定義漏れチェック
3. 環境変数定義の整合性確認
4. Dockerイメージ名・バージョンの一貫性確認
5. ポート番号の重複チェック（8080, 9090, 3000, 8200, 5432, 8081, 9200等）

**報告形式**:
- 問題があれば詳細と修正提案
- 問題がなければ「✅ 整合性OK」と報告
