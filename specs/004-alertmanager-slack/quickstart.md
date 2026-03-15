# Quickstart: Alertmanager導入

**前提条件**: 監視基盤（Prometheus + alerts.yml）が稼働中であること

## 1. Slack Incoming Webhook URL の取得

1. Slack ワークスペースの [App 管理画面](https://api.slack.com/apps) へアクセス
2. "Incoming Webhooks" を追加し、通知先チャンネル（例: `#monitoring-alerts`）を選択
3. 生成された Webhook URL を控える（例: `https://hooks.slack.com/services/T.../B.../xxx...`）
4. `.env` ファイルに `SLACK_WEBHOOK_URL=<取得したURL>` を追加

## 2. ファイル配置（ローカル）

```bash
# Alertmanager 設定ファイルを作成
cp specs/004-alertmanager-slack/contracts/alertmanager.yml.example config/alertmanager/alertmanager.yml

# .env の SLACK_WEBHOOK_URL を実際のURLに書き換える
# config/alertmanager/alertmanager.yml 内の <YOUR_SLACK_WEBHOOK_URL> も実際のURLに書き換える
```

## 3. リモートサーバーにファイルを配置

```bash
wsl -d Ubuntu-24.04 -e bash -c "
  ssh ubuntu@10.0.0.220 'mkdir -p /home/ubuntu/monitoring-lab/alertmanager'
  scp /mnt/e/work/labo/config/alertmanager/alertmanager.yml ubuntu@10.0.0.220:/home/ubuntu/monitoring-lab/alertmanager/alertmanager.yml
"
```

## 4. Alertmanager コンテナをデプロイ

```bash
# HCP Terraform Workspace を Local モードで作成後...
wsl -d Ubuntu-24.04 -e bash -c "
  docker exec monitoring-lab-terragrunt sh -c '
    cd /workspace/terraform/envs/local/alertmanager
    terragrunt init
    terragrunt apply -auto-approve
  '
"
```

## 5. prometheus.yml の更新 + リロード

```bash
# prometheus.yml をリモートに反映
wsl -d Ubuntu-24.04 -e bash -c "
  scp /mnt/e/work/labo/config/prometheus/prometheus.yml ubuntu@10.0.0.220:/home/ubuntu/monitoring-lab/prometheus/prometheus.yml
  ssh ubuntu@10.0.0.220 'curl -X POST http://localhost:9090/-/reload'
"
```

## 6. 動作確認

```bash
# Alertmanager UI 確認
# http://10.0.0.220:9093

# テスト: cAdvisor を一時停止して TargetDown を発火させる
wsl -d Ubuntu-24.04 -e bash -c "
  ssh ubuntu@10.0.0.220 'docker stop monitoring-lab-cadvisor'
"
# 約1分後にSlack通知が届くことを確認
# その後コンテナを再起動して resolved 通知を確認
wsl -d Ubuntu-24.04 -e bash -c "
  ssh ubuntu@10.0.0.220 'docker start monitoring-lab-cadvisor'
"
```
