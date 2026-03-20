# Research: Loki + Promtail ログ収集基盤

**Branch**: `010-loki-promtail` | **Date**: 2026-03-20

---

## 決定事項一覧

### Decision 1: Dockerイメージバージョン

- **Decision**: `grafana/loki:3.4.2` / `grafana/promtail:3.4.2`（タグ固定）
- **Rationale**: latest タグは再デプロイ時に意図しないアップグレードが発生するリスクがある。Loki と Promtail は同一バージョンで揃えることでプロトコル互換性を確保する。
- **Alternatives considered**: `latest` タグ（シンプルだが再現性なし）、`3.3.2`（より枯れているが3.4.xが現時点の安定版）

---

### Decision 2: Promtailのログ収集方式

- **Decision**: Docker Socket（`/var/run/docker.sock`）経由の `docker_sd_configs` を使用
- **Rationale**: spec.mdのClarificationsで確定済み。Docker SDはコンテナのメタデータ（名前・イメージ・ラベル）を自動取得できる。ファイルシステムパス方式（`/var/lib/docker/containers/`）と比べてラベル付与が容易。
- **Alternatives considered**: ファイルシステムパス方式（手動ラベル付与が煩雑）、Fluentd/Fluent Bit（追加コンポーネント不要のため却下）

---

### Decision 3: Loki設定 - ストレージとスキーマ

- **Decision**: ローカルファイルシステムストレージ + TSDB スキーマ v13
- **Rationale**: 学習環境であるため S3 等のオブジェクトストレージは不要。TSDB は Loki 3.x 推奨スキーマで、旧 BoltDB-Shipper より効率的。
- **Alternatives considered**: BoltDB-Shipper（旧来方式、非推奨）、MinIO（シングルバイナリで使えるがコンポーネント増加）

---

### Decision 4: ログ保持期間の設定方法

- **Decision**: `limits_config.retention_period: 744h`（31日） + `compactor.retention_enabled: true`
- **Rationale**: Loki 3.x では `retention_period` は hours/minutes/seconds 形式で指定。`7d` のような日数表記はサポートされているが、実績ある時間表記（`744h` = 31日）を使用する。ただし学習用として 168h（7日）を採用する。
- **Alternatives considered**: TTL不設定（ストレージ枯渇リスク）

**採用値**: `retention_period: 168h`（7日）

---

### Decision 5: Promtail positions ファイルの永続化

- **Decision**: Docker Volume `promtail_positions` を `/tmp` にマウント
- **Rationale**: positions.yaml（Promtailが読み込み済みのログ位置を記録するファイル）をコンテナ再起動をまたいで保持することで重複収集を防ぐ（FR-008）。`/tmp/positions.yaml` がデフォルトパスのため、`/tmp` ディレクトリ全体をボリューム化する。
- **Alternatives considered**: bind mount（リモートサーバーにディレクトリ作成が必要）、ボリューム不使用（重複収集が発生）

---

### Decision 6: 設定ファイルのリモート配置パス

- **Decision**: 既存パターンに準拠
  - Loki: `/home/ubuntu/monitoring-lab/loki/loki.yml`
  - Promtail: `/home/ubuntu/monitoring-lab/promtail/promtail.yml`
- **Rationale**: Prometheus（`/home/ubuntu/monitoring-lab/prometheus/`）、Grafana（`/home/ubuntu/monitoring-lab/grafana/`）と同一パターン。sync-config.sh への追加が容易。
- **Alternatives considered**: なし（既存パターン一択）

---

### Decision 7: ポート割り当て

| サービス | 内部ポート | 外部ポート | 用途 |
|---------|----------|----------|------|
| Loki | 3100 | 3100 | HTTP API（ログ受信・クエリ） |
| Promtail | 9080 | 9080 | Prometheus メトリクス（自己監視） |

- **Rationale**: Loki デフォルトポートは 3100。既存サービスとの競合なし（確認済み）。Promtail の 9080 は Prometheus スクレイプ用。
- **Alternatives considered**: ポート変更（理由なし）

---

### Decision 8: Grafana データソース追加戦略

- **Decision**: 既存 `config/grafana/provisioning/datasources/datasources.yml` に Loki エントリを追記する
- **Rationale**: 既存の Prometheus・Zabbix データソースと同一ファイルで管理。`deleteDatasources` セクションに Loki を追加して再プロビジョニング時の重複を防ぐ。Grafana 再起動で反映（sync-config.sh 経由）。
- **Alternatives considered**: 別ファイル分割（管理が分散する）

---

### Decision 9: Prometheus による Loki 自己監視

- **Decision**: `prometheus.yml` に Job 8 として `loki` を追加（`loki:3100/metrics`）
- **Rationale**: Constitution 原則 V（自己監視の可観測性）への準拠。Loki の取り込みレート・クエリレイテンシ・ストレージ使用量が Grafana で確認可能になる。既存の `TargetDown` アラートルールが Loki ダウンを自動検知する。
- **Alternatives considered**: 監視対象外（Constitution 違反のため却下）

---

### Decision 10: Terragrunt ワークスペース構成

- **Decision**: `loki` と `promtail` を独立したワークスペースとして作成
- **Rationale**: 既存パターン（prometheus, grafana, alertmanager など各サービス独立）に準拠。HCP Terraform に新規 Workspace を2つ作成し、実行モードを Local に設定。
- **Alternatives considered**: 単一ワークスペース（依存関係管理が複雑になる）

---

## 設定ファイル設計

### loki.yml（最小構成）

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 168h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
```

### promtail.yml（Docker Socket方式）

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container_name'
      - source_labels: ['__meta_docker_container_image']
        target_label: 'image'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'logstream'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'compose_service'
```

---

## 既存システムへの影響範囲

| ファイル | 変更内容 | 影響 |
|---------|---------|------|
| `config/prometheus/prometheus.yml` | Job 8 (loki) 追加 | Prometheus 設定リロード必要 |
| `config/grafana/provisioning/datasources/datasources.yml` | Loki データソース追記 | Grafana 再起動必要 |
| `scripts/sync-config.sh` | `loki` / `promtail` 同期オプション追加 | 後方互換性あり |

**新規ファイル**:
- `config/loki/loki.yml`
- `config/promtail/promtail.yml`
- `terraform/envs/local/loki/terragrunt.hcl`
- `terraform/envs/local/promtail/terragrunt.hcl`
