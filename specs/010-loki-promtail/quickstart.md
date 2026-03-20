# Quickstart: Loki + Promtail ログ収集基盤

**前提条件**: monitoring-lab の基本スタック（network, prometheus, grafana）が稼働中であること

---

## Step 1: 設定ファイルをリモートサーバーに配置

```bash
# ローカルからリモートへ設定ファイルをコピー
scp config/loki/loki.yml ubuntu@YOUR_SERVER_IP:/home/ubuntu/monitoring-lab/loki/loki.yml
scp config/promtail/promtail.yml ubuntu@YOUR_SERVER_IP:/home/ubuntu/monitoring-lab/promtail/promtail.yml

# または sync-config.sh を使用（実装後）
./scripts/sync-config.sh loki
./scripts/sync-config.sh promtail
```

---

## Step 2: HCP Terraform Workspace を作成

```bash
# HCP Terraform API で Workspace 作成（実行モード: Local）
# ブラウザ: https://app.terraform.io → Organizations → YOUR_TF_ORG
# → New Workspace → API-driven workflow
# Workspace名: loki / promtail
# 実行モードを Local に変更（Settings → General → Execution Mode）
```

---

## Step 3: Terragrunt でデプロイ

```bash
# Terragruntコンテナに接続
docker compose exec terragrunt sh

cd terraform/envs/local

# loki のみ初期化・デプロイ
cd loki
terragrunt init
terragrunt apply

# promtail のみ初期化・デプロイ
cd ../promtail
terragrunt init
terragrunt apply

# または全サービス一括
cd ..
terragrunt run-all apply
```

---

## Step 4: 動作確認

### Loki 起動確認

```bash
# リモートサーバーから
ssh ubuntu@YOUR_SERVER_IP 'curl -s http://localhost:3100/ready'
# 期待値: "ready"

# コンテナ状態確認
ssh ubuntu@YOUR_SERVER_IP 'docker ps | grep loki'
# 期待値: monitoring-lab-loki が Up
```

### Promtail 動作確認

```bash
# コンテナ状態確認
ssh ubuntu@YOUR_SERVER_IP 'docker ps | grep promtail'
# 期待値: monitoring-lab-promtail が Up

# Promtail のログ確認（Docker Socket 接続成功を確認）
ssh ubuntu@YOUR_SERVER_IP 'docker logs monitoring-lab-promtail 2>&1 | head -20'
# 期待値: "Starting Promtail" + "Watching for pod changes" が表示
```

### ログ収集確認（FR-001/FR-002/SC-001）

```bash
# 30秒待ってから実行（収集ラグのため）
curl -G 'http://YOUR_SERVER_IP:3100/loki/api/v1/query' \
  --data-urlencode 'query={job="containers"}' \
  --data-urlencode 'limit=5'
# 期待値: streams 配列にログエントリが含まれる

# Prometheusコンテナのログを指定して取得
curl -G 'http://YOUR_SERVER_IP:3100/loki/api/v1/query' \
  --data-urlencode 'query={container_name="monitoring-lab-prometheus"}'
```

---

## Step 5: Grafana データソース確認（US2）

1. `http://YOUR_SERVER_IP:3000` にアクセス
2. Connections → Data Sources → Loki が自動追加されていることを確認
3. Explore → Loki データソースを選択
4. Label filters: `container_name` を選択 → コンテナ名を選択 → Run query
5. ログ一覧が表示されることを確認（SC-002: 5秒以内）

---

## Step 6: Prometheus スクレイプ確認（FR-009）

```bash
# prometheus.yml をリロード
./scripts/sync-config.sh prometheus

# Prometheus Targets 確認
# ブラウザ: http://YOUR_SERVER_IP:9090/targets
# 期待値: loki (http://loki:3100/metrics) が UP
```

---

## トラブルシューティング

### Promtail が Docker Socket に接続できない

```bash
# Docker Socket 権限確認
ssh ubuntu@YOUR_SERVER_IP 'ls -la /var/run/docker.sock'
# 期待値: srw-rw---- ... docker グループ

# Promtail コンテナ内から確認
ssh ubuntu@YOUR_SERVER_IP 'docker exec monitoring-lab-promtail ls /var/run/docker.sock'
```

### Loki にログが届かない

```bash
# Promtail のエラーログを確認
ssh ubuntu@YOUR_SERVER_IP 'docker logs monitoring-lab-promtail 2>&1 | grep -i error'

# Loki への疎通確認（Promtailコンテナ内から）
ssh ubuntu@YOUR_SERVER_IP 'docker exec monitoring-lab-promtail wget -qO- http://loki:3100/ready'
```

### Grafana に Loki データソースが表示されない

```bash
# datasources.yml をリモートに同期して Grafana を再起動
./scripts/sync-config.sh grafana

# Grafana のプロビジョニングログ確認
ssh ubuntu@YOUR_SERVER_IP 'docker logs monitoring-lab-grafana 2>&1 | grep -i loki'
```
