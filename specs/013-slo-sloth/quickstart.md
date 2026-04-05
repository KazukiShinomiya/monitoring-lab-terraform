# Quickstart: SLO + Error Budget 管理基盤 (Sloth)

**Feature**: 013-slo-sloth  
**Date**: 2026-04-05

---

## 前提条件

- WSL2 (Ubuntu-24.04) が起動済み
- リモートサーバー (10.0.0.220) の Docker Engine が稼働中
- Prometheus/Grafana/Alertmanager/Loki が稼働中

---

## 動作確認手順

### 1. SLO ルール生成

```bash
# SLO YAML から Prometheus ルールを生成
task slo:generate

# 生成されたルールファイルを確認
cat config/prometheus/slo-rules.yml | head -50

# ルールの文法チェック
task slo:validate
```

### 2. Prometheus への反映

```bash
# ルールファイルをリモートに同期 + ホットリロード
task sync:prometheus

# 反映確認（約15秒後）
# → ブラウザで http://10.0.0.220:9090/rules を開く
# → "slo:sli_error:ratio_rate*" の Recording Rules が表示されることを確認
```

### 3. Grafana ダッシュボード確認

```bash
# Sloth ダッシュボードを同期（初回のみ）
task sync:grafana

# → ブラウザで http://10.0.0.220:3000 を開く
# → "Sloth - SLO Overview" ダッシュボードを開く
# → 4つのサービス（Prometheus/Grafana/Alertmanager/Loki）の
#    Error Budget 残量が表示されることを確認
```

### 4. Error Budget 残量の確認（PromQL）

```promql
# Error Budget 残量（1.0 = 100%、0.0 = 0% = SLO違反）
slo:error_budget:ratio{sloth_service="monitoring-lab"}

# 現在の Burning Rate（1.0 = 正常ペース、14.4 = Fast Burn閾値）
slo:sli_error:ratio_rate1h / on(sloth_id) group_left()
  (1 - slo:objective:ratio{sloth_service="monitoring-lab"}) / (1/30)
```

---

## SLO 追加の手順

新しいサービスの SLO を追加する場合:

```bash
# 1. config/sloth/monitoring-lab.yml に SLO エントリを追記
vim config/sloth/monitoring-lab.yml

# 2. ルールを再生成
task slo:generate

# 3. 検証
task slo:validate

# 4. 反映
task sync:prometheus

# 5. ダッシュボードが自動更新されることを確認
#    → Grafana の Sloth ダッシュボードに新サービスが表示される
```

---

## アラートのテスト方法

Error Budget 枯渇アラートを手動でテストする方法（学習用）:

```bash
# 現在の Burning Rate を確認
# ブラウザで http://10.0.0.220:9090/graph を開いて以下を実行:
# slo:sli_error:ratio_rate1h{sloth_service="monitoring-lab"}

# Alertmanager の現在のアラートを確認
# → http://10.0.0.220:9093

# 注: 実際の Fast Burn（14.4倍）を再現するには
#     対象コンテナを短時間停止させる方法がある
#     例: docker stop monitoring-lab-prometheus (リモートで実行)
#     ただし本番では実施しないこと
```

---

## トラブルシューティング

| 症状 | 確認方法 | 対処 |
|---|---|---|
| `task slo:generate` が失敗 | WSL2 で Docker が起動しているか確認 | `sudo service docker start` |
| Prometheus に Rules が表示されない | `prometheus.yml` の `rule_files` に `slo-rules.yml` が含まれているか | `task sync:prometheus` を再実行 |
| Grafana ダッシュボードが表示されない | `sloth-overview.json` が provisioning ディレクトリにあるか | `task sync:grafana` を再実行 |
| Error Budget が 0% 表示 | Prometheus 起動直後は30日分のデータが不足 | 数時間後に再確認（過去データの蓄積が必要）|
