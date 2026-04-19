# Quickstart: VictoriaMetrics 長期メトリクス保存基盤

**Branch**: `014-victoria-metrics` | **Date**: 2026-04-19

---

## 前提条件

- WSL2 (Ubuntu-24.04) + Docker が起動済み
- リモートサーバー (`YOUR_SERVER_IP`) が SSH 接続可能
- 既存の Prometheus / Grafana が稼働中

---

## デプロイ手順

### Step 1: VictoriaMetrics コンテナのデプロイ

```bash
# Terragrunt init + apply
cd terraform/envs/local/victoriametrics
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo/terraform/envs/local/victoriametrics && terragrunt init && terragrunt apply -auto-approve"

# コンテナ起動確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker ps | grep victoriametrics'"
```

### Step 2: ヘルスチェック

```bash
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'curl -sf http://localhost:8428/health'"
# → "OK" が返ることを確認
```

### Step 3: Prometheus remote_write の有効化

```bash
# prometheus.yml に remote_write + Job 11 を追加後:
task sync:prometheus
```

期待結果: `prometheus 同期完了`

### Step 4: データ転送の確認（1分待機後）

```bash
# VictoriaMetrics にメトリクスが届いているか確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'curl -s \"http://localhost:8428/api/v1/query?query=up\" | python3 -m json.tool | head -20'"
```

`"status": "success"` で `result` にデータがあれば転送成功（SC-001 達成）。

### Step 5: Grafana データソースの追加

```bash
# datasources.yml に VictoriaMetrics を追加後:
task sync:grafana
```

### Step 6: Grafana Explore で動作確認

1. Grafana (`http://YOUR_SERVER_IP:3000`) にアクセス
2. Explore → データソースで「VictoriaMetrics」を選択
3. クエリ: `up`、時間範囲: Last 1 hour → データが表示されることを確認（US2 達成）

---

## 動作確認コマンド集

```bash
# VictoriaMetrics ヘルスチェック
curl -sf http://YOUR_SERVER_IP:8428/health

# 取り込みメトリクス数確認
curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=vm_rows_inserted_total"

# 保持期間の確認
curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=vm_retention_months"

# Prometheus → VictoriaMetrics 転送キュー状態
curl -s "http://YOUR_SERVER_IP:9090/api/v1/query?query=prometheus_remote_storage_queue_highest_sent_timestamp_seconds"
```

---

## 最終検証（全 SC）

| SC | コマンド / 操作 | 期待結果 |
|---|---|---|
| SC-001 | `curl "http://YOUR_SERVER_IP:8428/api/v1/query?query=up"` | `status: success`, 結果あり |
| SC-002 | `curl "http://YOUR_SERVER_IP:8428/metrics" \| grep retention` | `vm_retention_months 12` |
| SC-003 | `task tg:plan` | 全 Workspace "No changes" |
| SC-004 | Grafana Explore: Last 90 days クエリ | 5秒以内に結果表示 |

---

## トラブルシューティング

### VictoriaMetrics が起動しない

```bash
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker logs monitoring-lab-victoriametrics'"
```

### Prometheus の remote_write が失敗している

```bash
# Prometheus の remote_write エラーカウントを確認
curl -s "http://YOUR_SERVER_IP:9090/api/v1/query?query=prometheus_remote_storage_failed_samples_total"
```

### Grafana で VictoriaMetrics データソースに接続できない

```bash
# Grafana コンテナから VM への疎通確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker exec monitoring-lab-grafana wget -qO- http://victoriametrics:8428/health'"
```
