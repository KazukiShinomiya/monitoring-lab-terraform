---
name: validate
description: デプロイ前の事前検証（環境変数・Docker起動状態・ポート・コンテナ・ディスク容量）
---

general-purposeエージェントに以下のタスクを委譲してください:

**タスク**: デプロイ前の環境検証

**検証項目**:
1. `.env` ファイルが存在するか確認（なければ `.env.example` からコピーを提案）
2. WSL2のDockerが起動しているか確認
3. リモートサーバー（YOUR_SERVER_IP）への疎通確認
4. 主要ポートの使用状況確認（8080, 9090, 3000, 8200, 5432, 8081, 9200）
5. ディスク容量の確認

**実行コマンド（WSL2経由）**:
```bash
wsl -d Ubuntu -- bash -c "docker ps 2>&1 | head -5"
wsl -d Ubuntu -- bash -c "ssh -o ConnectTimeout=5 ubuntu@YOUR_SERVER_IP 'echo OK' 2>&1"
wsl -d Ubuntu -- bash -c "ssh ubuntu@YOUR_SERVER_IP 'df -h /var/lib/docker | tail -1'"
```

**実行後のアクション**:
- 問題があれば修正手順を提示
- すべてOKなら「✅ デプロイ可能」と報告
- 次に実行すべきコマンドを提示
