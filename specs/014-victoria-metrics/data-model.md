# Data Model: VictoriaMetrics 長期メトリクス保存基盤

**Branch**: `014-victoria-metrics` | **Date**: 2026-04-19

---

## エンティティ定義

### Entity 1: VictoriaMetrics コンテナ

| 属性 | 値 |
|---|---|
| コンテナ名 | `monitoring-lab-victoriametrics` |
| Docker イメージ | `victoriametrics/victoria-metrics:stable` |
| 内部ポート | `8428` (HTTP API / remote_write / metrics) |
| 外部ポート | `8428` |
| ネットワーク | `monitoring-lab-network` (既存) |
| 再起動ポリシー | `unless-stopped` (docker_container モジュール デフォルト) |
| コマンド引数 | `-retentionPeriod=12`, `-storageDataPath=/victoria-metrics-data` |

**IaC パス**: `terraform/envs/local/victoriametrics/terragrunt.hcl`  
**依存関係**: `network` のみ（Terragrunt dependency）

---

### Entity 2: vm_data ボリューム

| 属性 | 値 |
|---|---|
| ボリューム名 | `vm_data` |
| ドライバー | `local` |
| コンテナ内マウントパス | `/victoria-metrics-data` |
| 読み取り専用 | `false` |
| 推定容量 | 5〜10 GB / 年（スクレイプ対象 ~10 サービス） |

**IaC 定義場所**: `terraform/envs/local/victoriametrics/terragrunt.hcl` の `volumes` ブロック

---

### Entity 3: Prometheus remote_write 設定

| 属性 | 値 |
|---|---|
| エンドポイント | `http://victoriametrics:8428/api/v1/write` |
| min_backoff | `30ms` |
| max_backoff | `60s` |
| max_shards | `4` |

**設定ファイル**: `config/prometheus/prometheus.yml`  
**反映方法**: `task sync:prometheus`（ホットリロード / コンテナ再起動不要）

---

### Entity 4: Prometheus スクレイプジョブ（自己監視 Job 11）

| 属性 | 値 |
|---|---|
| job_name | `victoriametrics` |
| ターゲット | `victoriametrics:8428` |
| scrape_interval | グローバルデフォルト (15s) |

**設定ファイル**: `config/prometheus/prometheus.yml`  
**目的**: Constitution 原則 V 遵守。既存 TargetDown アラートで VM ダウンを自動検知。

---

### Entity 5: Grafana データソース（VictoriaMetrics）

| 属性 | 値 |
|---|---|
| name | `VictoriaMetrics` |
| type | `prometheus` (Prometheus 互換 API を利用) |
| uid | `victoriametrics` |
| url | `http://victoriametrics:8428` |
| isDefault | `false` (Prometheus がデフォルトを維持) |
| deleteDatasources エントリ | 追加要 (冪等性のため) |

**設定ファイル**: `config/grafana/provisioning/datasources/datasources.yml`  
**反映方法**: `task sync:grafana`（Grafana コンテナ再起動）

---

## 状態遷移

```
[Terragrunt apply]
       ↓
VictoriaMetrics コンテナ起動 + vm_data ボリューム作成
       ↓
[sync:prometheus]
       ↓
prometheus.yml に remote_write + Job 11 追加 → ホットリロード
       ↓
Prometheus が victoriametrics:8428/api/v1/write へのメトリクス転送開始
       ↓
[sync:grafana]
       ↓
datasources.yml に VictoriaMetrics 追加 → Grafana 再起動
       ↓
Grafana から http://victoriametrics:8428 でクエリ可能（US2 達成）
```

---

## 既存エンティティへの影響

| エンティティ | 変更 | 影響 |
|---|---|---|
| Prometheus コンテナ | `remote_write` 追加のみ | スクレイプ・アラート評価は継続（FR-007 準拠） |
| Grafana データソース一覧 | VictoriaMetrics を追加 | 既存 Prometheus/Loki/Tempo/Zabbix に変更なし（SC-003 準拠） |
| HCP Terraform | 新 Workspace `monitoring-lab-local-victoriametrics` | 既存 Workspace に影響なし |
| Docker Network | 既存 `monitoring-lab-network` に VM コンテナが参加 | 変更なし |

---

## 検証ポイント（contracts 参照）

| SC | 検証方法 |
|---|---|
| SC-001 (1分以内転送) | `curl http://YOUR_SERVER_IP:8428/api/v1/query?query=up` でメトリクス確認 |
| SC-002 (365日保持) | `-retentionPeriod=12` 設定の確認（稼働直後は将来確認） |
| SC-003 (既存変更なし) | `terragrunt plan` が全 Workspace で "No changes" を維持 |
| SC-004 (5秒以内応答) | Grafana Explore で 90日クエリの実行時間確認 |
