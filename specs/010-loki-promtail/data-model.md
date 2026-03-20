# Data Model: Loki + Promtail ログ収集基盤

**Branch**: `010-loki-promtail` | **Date**: 2026-03-20

---

## エンティティ定義

### 1. Log Stream

Loki における最小管理単位。同一ラベルセットを持つログエントリの集合。

| フィールド | 型 | 説明 | 例 |
|-----------|-----|------|-----|
| `container_name` | string | Dockerコンテナ名 | `monitoring-lab-prometheus` |
| `image` | string | Dockerイメージ名 | `prom/prometheus:latest` |
| `logstream` | string | ログストリーム種別 | `stdout` / `stderr` |
| `compose_service` | string | Docker Composeサービス名（存在する場合） | `prometheus` |
| `job` | string | Promtailジョブ名（固定） | `containers` |

**制約**:
- ラベルセットの組み合わせで一意に識別される
- ラベルのカーディナリティを低く保つこと（高カーディナリティはLoki性能劣化を招く）
- コンテナ名に特殊文字が含まれる場合、`relabel_configs` の regex で処理する

---

### 2. Log Entry

Loki に保存される最小単位。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `timestamp` | int64 (nanoseconds) | ログ出力時刻（Unix ナノ秒） |
| `labels` | map[string]string | Log Stream のラベルセット |
| `line` | string | ログ行テキスト |

**制約**:
- タイムスタンプは単調増加でなければならない（同一ストリーム内）
- 保持期間: 168時間（7日）。`compactor` により自動削除される

---

### 3. Loki Config

| フィールド | 値 | 説明 |
|-----------|-----|------|
| `http_listen_port` | 3100 | HTTP API ポート |
| `grpc_listen_port` | 9096 | gRPC ポート（内部通信） |
| `path_prefix` | `/loki` | データディレクトリのベースパス |
| `schema` | v13 | TSDBスキーマバージョン |
| `retention_period` | 168h | ログ保持期間（7日） |
| `storage_type` | filesystem | ストレージバックエンド |

**コンテナ内パス**:
- データ: `/loki/chunks/`
- インデックス: `/loki/index/`
- ルール: `/loki/rules/`
- コンパクタ: `/loki/compactor/`

**リモートサーバー配置**:
- 設定ファイル: `/home/ubuntu/monitoring-lab/loki/loki.yml`
- Docker Volume: `monitoring-lab-loki_data`（`/loki` にマウント）

---

### 4. Promtail Config

| フィールド | 値 | 説明 |
|-----------|-----|------|
| `http_listen_port` | 9080 | Prometheus メトリクスポート |
| `positions_file` | `/tmp/positions.yaml` | 読み取り位置記録ファイル |
| `loki_push_url` | `http://loki:3100/loki/api/v1/push` | Loki へのプッシュエンドポイント |
| `scrape_method` | docker_sd_configs | Docker Socket 経由のサービスディスカバリ |
| `docker_host` | `unix:///var/run/docker.sock` | Docker Socket パス |
| `refresh_interval` | 5s | コンテナ一覧の更新間隔 |

**リモートサーバー配置**:
- 設定ファイル: `/home/ubuntu/monitoring-lab/promtail/promtail.yml`
- Docker Volume: `monitoring-lab-promtail_positions`（`/tmp` にマウント）
- Bind Mount: `/var/run/docker.sock` → `/var/run/docker.sock`（read-only）

---

### 5. Grafana Loki Datasource

| フィールド | 値 | 説明 |
|-----------|-----|------|
| `name` | `Loki` | Grafana上の表示名 |
| `type` | `loki` | データソースタイプ（Grafana組み込み） |
| `access` | `proxy` | Grafanaサーバー経由でアクセス |
| `url` | `http://loki:3100` | Docker Network内のエンドポイント |
| `isDefault` | false | Prometheusがデフォルトを維持 |
| `editable` | true | UI上で編集可能 |

---

## 変更対象ファイル一覧

### 新規作成

| ファイル | 説明 |
|---------|------|
| `config/loki/loki.yml` | Loki 設定ファイル |
| `config/promtail/promtail.yml` | Promtail 設定ファイル |
| `terraform/envs/local/loki/terragrunt.hcl` | Loki Terragrunt サービス定義 |
| `terraform/envs/local/promtail/terragrunt.hcl` | Promtail Terragrunt サービス定義 |

### 既存ファイル変更

| ファイル | 変更内容 |
|---------|---------|
| `config/prometheus/prometheus.yml` | Job 8: `loki` スクレイプ設定を追加 |
| `config/grafana/provisioning/datasources/datasources.yml` | Loki データソース追記 |
| `scripts/sync-config.sh` | `loki` / `promtail` 設定同期オプション追加 |

---

## 依存関係

```
network
  └─→ loki
        └─→ promtail
              └─→ (Grafana は network 依存のみ、Loki データソースは設定ファイルで対応)
```

**Terragrunt dependency 関係**:
- `loki`: `network` に依存
- `promtail`: `network` + `loki` に依存
- `grafana`: 既存の依存関係は変更しない（Loki データソースは設定ファイル変更で対応）
