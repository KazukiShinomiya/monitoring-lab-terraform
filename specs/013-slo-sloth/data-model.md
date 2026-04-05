# Data Model: SLO + Error Budget 管理基盤 (Sloth)

**Feature**: 013-slo-sloth  
**Date**: 2026-04-05

---

## 設定ファイル構造

### SLO 定義ファイル（`config/sloth/monitoring-lab.yml`）

```
SloDefinitionFile
└── version: "prometheus/v1"
└── service: string              # サービスグループ識別子（"monitoring-lab"）
└── labels: map<string, string>  # 全SLO共通ラベル（省略可）
└── slos: []SloEntry
```

```
SloEntry
├── name: string                 # SLO識別子（例: "prometheus-availability"）
├── objective: float64           # SLO目標値（例: 99.5）
├── description: string          # SLO説明
├── sli: SliDefinition
│   └── raw:
│       └── error_ratio_query: string  # PromQL式（{{.window}} 変数使用）
└── alerting: AlertingConfig
    ├── name: string             # アラートルール名プレフィックス
    ├── labels: map              # 全アラート共通ラベル
    ├── annotations: map         # アラートアノテーション
    ├── page_alert:              # Fast Burn アラート（即時対応）
    │   └── labels: {severity: "page"}
    └── ticket_alert:            # Slow Burn アラート（翌業務日対応）
        └── labels: {severity: "ticket"}
```

### 初期 SLO 定義（4件）

| SLO名 | ジョブ名 | 目標値 | error_ratio_query |
|---|---|---|---|
| prometheus-availability | `job="prometheus"` | 99.5% | `1 - avg_over_time(up{job="prometheus"}[{{.window}}])` |
| grafana-availability | `job="grafana"` | 99.5% | `1 - avg_over_time(up{job="grafana"}[{{.window}}])` |
| alertmanager-availability | `job="alertmanager"` | 99.5% | `1 - avg_over_time(up{job="alertmanager"}[{{.window}}])` |
| loki-availability | `job="loki"` | 99.0% | `1 - avg_over_time(up{job="loki"}[{{.window}}])` |

> Loki は他の3サービスより目標値を99.0%に設定（ログ収集サービスとして若干の許容度あり）

---

## Prometheus 生成メトリクス

Sloth が `slo-rules.yml` として生成する Recording Rules が出力するメトリクス一覧。

### Recording Rules（各 SLO × 各ウィンドウ）

| メトリクス名 | ラベル | 説明 |
|---|---|---|
| `slo:sli_error:ratio_rate1h` | `sloth_id`, `sloth_service`, `sloth_slo` | 1時間ウィンドウのエラー率 |
| `slo:sli_error:ratio_rate6h` | 同上 | 6時間ウィンドウのエラー率 |
| `slo:sli_error:ratio_rate3d` | 同上 | 3日ウィンドウのエラー率 |
| `slo:sli_error:ratio_rate30d` | 同上 | 30日ウィンドウのエラー率（主要指標）|
| `slo:error_budget:ratio` | 同上 | Error Budget 残量（1.0 = 100%残）|
| `slo:time_period:days` | 同上 | SLO 計算期間（30.0）|
| `slo:objective:ratio` | 同上 | SLO 目標値（例: 0.995）|

### Alerting Rules（各 SLO × 2種類）

| アラート名 | 条件 | severity |
|---|---|---|
| `{name}PageQuickBurn` | Burning Rate > 14.4（1h窓）かつ > 6（6h窓）| page |
| `{name}PageSlowBurn` | Burning Rate > 3（6h窓）かつ > 1（3d窓）| page |
| `{name}TicketQuickBurn` | Burning Rate > 6（6h窓）かつ > 3（3d窓）| ticket |
| `{name}TicketSlowBurn` | Burning Rate > 1（3d窓）かつ > 1（30d窓）| ticket |

---

## ファイル依存関係

```
config/sloth/monitoring-lab.yml   ← 手動編集（SLO定義）
        ↓ task slo:generate
config/prometheus/slo-rules.yml   ← Sloth 自動生成（Git管理対象）
        ↓ task sync:prometheus
リモートサーバー /etc/prometheus/slo-rules.yml
        ↓ curl /-/reload
Prometheus Recording Rules 評価開始
        ↓
config/grafana/provisioning/dashboards/sloth-overview.json
        ↓ task sync:grafana（初回のみ）
Grafana ダッシュボード自動表示
```

---

## 既存ファイルへの変更

| ファイル | 変更内容 |
|---|---|
| `config/prometheus/prometheus.yml` | `rule_files` に `'/etc/prometheus/slo-rules.yml'` を追記 |
| `Taskfile.yml` | `slo:generate`, `slo:validate` タスクを追加 |
| `scripts/sync-config.sh` | 変更なし（既存 `prometheus` オプションで slo-rules.yml も同期される）|
