---
name: debug
description: デプロイ失敗・コンテナ異常時のトラブルシューティング（Terragrunt State・Dockerログ・ネットワーク診断）
---

general-purposeエージェントに以下のタスクを委譲してください:

**タスク**: 監視基盤のデプロイ失敗の診断と修正提案

**調査内容**:
1. Terragrunt Stateファイルの確認
2. Dockerコンテナのログ確認（直近50行）
3. ネットワーク設定の検証
4. ボリューム状態の確認
5. エラーログの解析と根本原因の特定

**実行コマンド（WSL2経由）**:
```bash
wsl -d Ubuntu -- bash -c "ssh ubuntu@10.0.0.220 'docker ps -a --format \"table {{.Names}}\t{{.Status}}\"'"
wsl -d Ubuntu -- bash -c "ssh ubuntu@10.0.0.220 'docker logs <container> --tail 50'"
wsl -d Ubuntu -- bash -c "ssh ubuntu@10.0.0.220 'docker network ls'"
```

**報告形式**:
- 検出された問題のリスト
- 推奨される修正手順
- 実行すべきコマンド
