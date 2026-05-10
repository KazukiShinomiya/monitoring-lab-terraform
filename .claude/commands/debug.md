---
description: デプロイ失敗時のトラブルシューティング
---

以下のタスクをgeneral-purposeエージェントに委譲してください:

**タスク**: 監視基盤のデプロイ失敗の診断と修正提案

**調査内容**:
1. Terragrunt State ファイルの確認
2. Docker コンテナのログ確認
3. ネットワーク設定の検証
4. ボリュームの状態確認
5. エラーログの解析

**実行コマンド**:
- `docker compose ps -a`
- `docker compose logs --tail=50`
- `docker network ls`
- terraform/envs/local 配下の .terragrunt-cache 確認

**報告形式**:
- 検出された問題のリスト
- 推奨される修正手順
- 実行すべきコマンド
