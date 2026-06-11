# Quickstart: Pyroscope 継続的プロファイリング基盤

**Feature**: 015-pyroscope
**Date**: 2026-05-07（バックフィル: 2026-06-08）

---

## 前提条件

- WSL2 (Ubuntu-24.04) が起動済み
- リモートサーバー (YOUR_SERVER_IP) の Docker Engine が稼働中
- Prometheus / Grafana が稼働中
- HCP Terraform の `monitoring-lab-local-pyroscope` Workspace が Local モードで作成済み

---

## 動作確認手順

### 1. コンテナ稼働確認

```bash
# リモートで Pyroscope コンテナの状態を確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker ps --filter name=pyroscope'"

# /ready ヘルスチェック（起動直後の 503「Segment Writer waiting 30s」は正常猶予）
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'curl -s -o /dev/null -w \"%{http_code}\" http://localhost:4040/ready'"
# → 200 が返れば稼働中
```

### 2. Prometheus メトリクス統合確認（SC-002）

```bash
# ブラウザで http://YOUR_SERVER_IP:9090/targets を開く
# → "pyroscope" ジョブが UP 状態であることを確認

# PromQL で死活確認
# up{job="pyroscope"}        → 1 が返れば UP

# プロファイル受信メトリクス
# pyroscope_distributor_received_profiles_total
```

### 3. Grafana datasource 確認（FR-004）

```bash
# ブラウザで http://YOUR_SERVER_IP:3000 を開く
# → Connections → Data sources → "Pyroscope" を選択
# → "Save & test" で接続成功（Data source is working）を確認
```

### 4. データ永続化確認（SC-003）

```bash
# コンテナを再起動
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker restart monitoring-lab-pyroscope'"

# 再起動後も pyroscope_data ボリュームが維持されていることを確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker volume ls | grep pyroscope_data'"
```

---

## バージョン更新の手順

```bash
# 1. terraform/envs/local/pyroscope/terragrunt.hcl の image を編集
#    image = "grafana/pyroscope:2.0.2"  →  新バージョンに変更
#    （:latest は使わない — Tempo/OTel の破壊的変更の教訓）

# 2. plan で forces replacement と影響範囲を確認
task tg:plan:svc -- pyroscope

# 3. apply（名前付きボリューム pyroscope_data は保持される / 瞬断数秒）
#    MCP terragrunt-server の apply_service、または Terragrunt CLI で実行

# 4. /ready 200 と Restarts 0 を確認
```

---

## トラブルシューティング

| 症状 | 確認方法 | 対処 |
|---|---|---|
| `/ready` が 503 | 起動からの経過時間 | 起動直後30秒は正常猶予（Segment Writer waiting）。30秒待って再確認 |
| `pyroscope` ジョブが DOWN | `prometheus.yml` の job 定義 | `task sync:prometheus` を再実行 |
| Grafana datasource 接続失敗 | コンテナ稼働と `url: http://pyroscope:4040` | コンテナ再起動、ネットワーク同居を確認 |
| プロファイルデータが空 | — | v2.x は pull スクレイプ非対応。実プロファイル収集は Alloy/SDK 配線が必要（research.md 決定事項 2 参照）|
| apply 後に Restarts 増加 | `docker logs monitoring-lab-pyroscope` | 設定ファイルの構文、bind mount パスを確認 |

---

## 既知の制約

- **セルフプロファイルのフレームグラフ（SC-001）は部分達成**。Pyroscope v2.x は pull-based pprof スクレイプを `config.yml` で設定できないため、実プロファイル収集には Grafana Alloy（push）または Pyroscope SDK の組み込みが必要。本フェーズはサーバー稼働・メトリクス統合・datasource 接続・永続化までを達成範囲とする。
