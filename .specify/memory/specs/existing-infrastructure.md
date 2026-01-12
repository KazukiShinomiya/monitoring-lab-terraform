# Specification: Existing Monitoring Infrastructure

**Created**: 2026-01-01
**Status**: Baseline (Phase 0-2 完了時点)
**Version**: 1.0.0

## 目的

Terraform + Terragrunt + HCP Terraformによる、学習用オブザーバビリティ基盤の現在の構成を文書化する。
この仕様は、Phase 3以降の拡張の基準となる。

---

## アーキテクチャ概要

### システム構成

```
┌─────────────────────────────────────────────────────────────┐
│ Development Environment (WSL2 Ubuntu)                        │
│  - Docker Engine 29.1.3                                      │
│  - Docker Compose v5.0.0                                     │
│  - Terragrunt Container (alpine/terragrunt:latest)           │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ SSH (Ed25519 Key Auth)
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Remote Docker Host (10.0.0.220)                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Docker Network: monitoring-lab-network                │  │
│  │                                                        │  │
│  │  [PostgreSQL:5432] ───→ [Zabbix Server:10051]        │  │
│  │         │                      │                      │  │
│  │         │                      ├─→ [Zabbix Web:8080]  │  │
│  │         │                      └─→ [Zabbix Agent2]    │  │
│  │         │                                              │  │
│  │  [Vault:8200]   (開発モード、将来的に統合)            │  │
│  │                                                        │  │
│  │  [Prometheus:9090] ─→ [Grafana:3000]                  │  │
│  │         │                      │                      │  │
│  │         │                      └─→ Zabbix Plugin      │  │
│  │         │                                              │  │
│  │  [New Relic Infrastructure Agent]                     │  │
│  │                                                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ State Management
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ HCP Terraform (app.terraform.io)                             │
│  - Organization: k1981-learning-lab                          │
│  - Workspaces: 8個 (service-per-workspace)                   │
│  - Execution Mode: Local                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## コンポーネント仕様

### 1. Network

**Purpose**: すべてのコンテナが通信するDockerブリッジネットワーク

**Terraform Resource**: `docker_network.network`

**Specification**:
- Name: `monitoring-lab-network`
- Driver: `bridge`
- HCP Workspace: `monitoring-lab-local-network`

**Dependencies**: なし（最初に作成）

---

### 2. PostgreSQL

**Purpose**: Zabbixのメタデータ・監視データの永続化

**Terraform Resource**: `docker_container.service["postgres"]`

**Specification**:
- Image: `postgres:15-alpine`
- Port: `5432` (内部のみ、外部公開なし)
- Environment:
  - `POSTGRES_DB`: `zabbix`
  - `POSTGRES_USER`: `zabbix`
  - `POSTGRES_PASSWORD`: `zabbix_password` (学習用、将来Vault管理)
- Volume: `monitoring-lab-postgres-data` → `/var/lib/postgresql/data`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-postgres`

**Dependencies**: Network

**Health Check**: PostgreSQL内蔵のヘルスチェック

---

### 3. Vault

**Purpose**: 機密情報管理（現在は開発モード、将来的に本番化）

**Terraform Resource**: `docker_container.service["vault"]`

**Specification**:
- Image: `hashicorp/vault:latest`
- Port: `8200:8200`
- Environment:
  - `VAULT_DEV_ROOT_TOKEN_ID`: `root` (開発モード)
  - `VAULT_DEV_LISTEN_ADDRESS`: `0.0.0.0:8200`
- Capabilities: `IPC_LOCK`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-vault`

**Dependencies**: Network

**Status**: 開発モード（Phase 3-4で本番モード化予定）

---

### 4. Zabbix Server

**Purpose**: エージェントベース監視サーバー

**Terraform Resource**: `docker_container.service["zbx_server"]`

**Specification**:
- Image: `zabbix/zabbix-server-pgsql:alpine-latest`
- Port: `10051` (Zabbix Agentから接続受付)
- Environment:
  - `DB_SERVER_HOST`: `postgres`
  - `POSTGRES_DB`: `zabbix`
  - `POSTGRES_USER`: `zabbix`
  - `POSTGRES_PASSWORD`: `zabbix_password`
- Volumes:
  - `monitoring-lab-zabbix-alertscripts` → `/usr/lib/zabbix/alertscripts`
  - `monitoring-lab-zabbix-externalscripts` → `/usr/lib/zabbix/externalscripts`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-zabbix`

**Dependencies**: PostgreSQL, Network

**Health Check**: Zabbix Server内蔵のヘルスチェック

---

### 5. Zabbix Agent2

**Purpose**: Zabbix Server自身の自己監視

**Terraform Resource**: `docker_container.service["zbx_agent2"]`

**Specification**:
- Image: `zabbix/zabbix-agent2:alpine-latest`
- Port: `10050` (Zabbix Serverから接続)
- Environment:
  - `ZBX_HOSTNAME`: `Zabbix server`
  - `ZBX_SERVER_HOST`: `zbx_server`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-zabbix-agent`

**Dependencies**: Zabbix Server, Network

**Monitoring Target**: Zabbix Server自身のCPU、メモリ、プロセス

---

### 6. Zabbix Web UI

**Purpose**: Zabbix管理WebインターフェースNote: Zabbix Serverと同じHCP Workspaceで管理

**Terraform Resource**: `docker_container.service["zbx_web"]`

**Specification**:
- Image: `zabbix/zabbix-web-apache-pgsql:alpine-latest`
- Port: `8080:8080`
- Environment:
  - `DB_SERVER_HOST`: `postgres`
  - `POSTGRES_DB`: `zabbix`
  - `POSTGRES_USER`: `zabbix`
  - `POSTGRES_PASSWORD`: `zabbix_password`
  - `ZBX_SERVER_HOST`: `zbx_server`
  - `PHP_TZ`: `Asia/Tokyo`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-zabbix` (Zabbix Serverと共通)

**Dependencies**: PostgreSQL, Zabbix Server, Network

**Access URL**: `http://10.0.0.220:8080`

**Default Credentials**:
- Username: `Admin`
- Password: `zabbix`

---

### 7. Prometheus

**Purpose**: Pull型メトリクス収集

**Terraform Resource**: `docker_container.service["prometheus"]`

**Specification**:
- Image: `prom/prometheus:latest`
- Port: `9090:9090`
- Volumes:
  - `monitoring-lab-prometheus-data` → `/prometheus`
  - `${path.module}/../../../../config/prometheus/prometheus.yml` → `/etc/prometheus/prometheus.yml`
- Command: `--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=15d`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-prometheus`

**Dependencies**: Network

**Scrape Configuration**: 基本設定のみ（Phase 3で拡充予定）

**Access URL**: `http://10.0.0.220:9090`

---

### 8. Grafana

**Purpose**: 統合ダッシュボードとデータ可視化

**Terraform Resource**: `docker_container.service["grafana"]`

**Specification**:
- Image: `grafana/grafana:latest`
- Port: `3000:3000`
- Environment:
  - `GF_SECURITY_ADMIN_PASSWORD`: `admin`
  - `GF_INSTALL_PLUGINS`: `alexanderzobnin-zabbix-app`
- Volumes:
  - `monitoring-lab-grafana-data` → `/var/lib/grafana`
  - `${path.module}/../../../../config/grafana/provisioning` → `/etc/grafana/provisioning`
- Network: `monitoring-lab-network`
- HCP Workspace: `monitoring-lab-local-grafana`

**Dependencies**: Prometheus, Network

**Datasources**:
1. Prometheus: `http://prometheus:9090`
2. Zabbix: `http://zbx_web:8080/api_jsonrpc.php`

**Access URL**: `http://10.0.0.220:3000`

**Default Credentials**:
- Username: `admin`
- Password: `admin`

---

### 9. New Relic Infrastructure Agent

**Purpose**: 統合監視プラットフォームによるDockerコンテナ・ホストOS監視

**Terraform Resource**: `docker_container.service["newrelic"]`

**Specification**:
- Image: `newrelic/infrastructure:latest`
- Environment:
  - `NRIA_LICENSE_KEY`: `${var.newrelic_license_key}` (環境変数から取得)
- Volumes:
  - `/:/host:ro`
  - `/var/run/docker.sock:/var/run/docker.sock`
- Network: `host`
- Privileged: `true`
- HCP Workspace: `monitoring-lab-local-newrelic`

**Dependencies**: Network

**Monitoring Targets**:
- ホストOS（CPU、メモリ、ディスク、ネットワーク）
- Dockerコンテナ（8台すべて）

**Access URL**: `https://one.newrelic.com/`

---

## データフロー

### メトリクスフロー

```
[SwitchBot温湿度計 x4]
         │
         │ (External Check Script)
         ▼
   [Zabbix Server] ────→ [Zabbix Web UI]
         │                      │
         │                      │
         └──────────────────────┴───→ [Grafana]
                                       ▲
                                       │
                                       │
[Dockerコンテナ x8] ───→ [Prometheus] ─┘
         │
         ├───→ [New Relic] ───→ [New Relic One]
         │
   [ホストOS]
```

### State管理フロー

```
[WSL2: Terragrunt] ──→ [terraform plan/apply]
         │
         ├─→ [SSH] ───→ [Remote Docker Engine] ───→ [Containers]
         │
         └─→ [HCP Terraform] ───→ [State Storage (8 Workspaces)]
```

---

## HCP Terraform構成

### Organization

- **Name**: `k1981-learning-lab`
- **Plan**: Free Tier
- **API Token**: `.env`ファイルで管理（変数名: `TF_TOKEN_app_terraform_io`）

### Workspaces（Service-per-Workspace Pattern）

| Workspace Name | Service | State Resources |
|----------------|---------|-----------------|
| `monitoring-lab-local-network` | Network | `docker_network.network` |
| `monitoring-lab-local-postgres` | PostgreSQL | `docker_container.service["postgres"]`, `docker_volume.volumes["postgres-data"]` |
| `monitoring-lab-local-vault` | Vault | `docker_container.service["vault"]` |
| `monitoring-lab-local-prometheus` | Prometheus | `docker_container.service["prometheus"]`, `docker_volume.volumes["prometheus-data"]` |
| `monitoring-lab-local-newrelic` | New Relic | `docker_container.service["newrelic"]` |
| `monitoring-lab-local-zabbix` | Zabbix Server + Web + Agent2 | `docker_container.service["zbx_server"]`, `docker_container.service["zbx_web"]`, `docker_volume.volumes["zabbix-*"]` |
| `monitoring-lab-local-zabbix-agent` | Zabbix Agent2 | `docker_container.service["zbx_agent2"]` |
| `monitoring-lab-local-grafana` | Grafana | `docker_container.service["grafana"]`, `docker_volume.volumes["grafana-data"]` |

### Execution Mode

すべてのWorkspaceで**Local**モードを使用。
- Terraform実行はWSL2のTerragruntコンテナから実施
- HCP TerraformはStateストレージのみに使用

---

## セキュリティ設定（現状）

### 認証情報管理

**現在の方式**: 環境変数とハードコード（学習用）
- PostgreSQLパスワード: `zabbix_password` (ハードコード)
- Vaultルートトークン: `root` (開発モード)
- Grafana adminパスワード: `admin` (デフォルト)
- New Relicライセンスキー: 環境変数（`.env`ファイル）

**将来計画（Phase 3-4）**: Vault本番モード化
- すべてのパスワードをVaultで管理
- Terraformから動的に取得
- TLS/SSL証明書の導入

### ネットワークセキュリティ

**現状**:
- HTTP通信（HTTPS未設定）
- Dockerブリッジネットワーク（内部通信のみ）
- リモートホスト（10.0.0.220）へのSSH接続はEd25519鍵認証

**将来計画（Phase 5）**:
- TLS/SSL証明書導入
- ネットワーク分離（管理ネットワーク/監視ネットワーク）
- ファイアウォールルール設定

---

## 成功基準（現状の達成状況）

### ✅ Phase 0-2 完了基準

- [x] **SC-001**: すべてのインフラがTerraform/Terragruntで管理されている
- [x] **SC-002**: StateがHCP Terraformで管理されている（8 Workspaces、すべて差分なし）
- [x] **SC-003**: WSL2からリモートDockerホストへSSH接続可能
- [x] **SC-004**: 全8サービスが正常に起動している
- [x] **SC-005**: ZabbixでSwitchBot温湿度計4台を監視中
- [x] **SC-006**: New RelicでDockerコンテナとホストOSを監視中
- [x] **SC-007**: Grafanaでデータソース（Prometheus、Zabbix）を統合
- [x] **SC-008**: Git管理と`.gitignore`でセキュリティ保護

### 🚧 Phase 3以降の計画

- [ ] **SC-009**: Prometheusスクレイプ設定の有効化
- [ ] **SC-010**: Grafanaダッシュボードの作成
- [ ] **SC-011**: Vault本番モード化
- [ ] **SC-012**: TLS/SSL証明書導入
- [ ] **SC-013**: アラートルール実装

---

## 技術的負債

### 優先度: 高

1. **パスワードのハードコード**
   - 影響: セキュリティリスク
   - 解決策: Vault本番モード化（Phase 3-4）

2. **HTTP通信（HTTPS未設定）**
   - 影響: 通信の暗号化なし
   - 解決策: TLS/SSL証明書導入（Phase 4-5）

### 優先度: 中

3. **Prometheusスクレイプ設定が基本設定のみ**
   - 影響: メトリクス収集が限定的
   - 解決策: Phase 3で拡充

4. **Grafanaダッシュボードが未作成**
   - 影響: 可視化が不十分
   - 解決策: Phase 3で作成

### 優先度: 低

5. **WSL2再起動時にDockerサービスが停止**
   - 影響: 手動で`sudo service docker start`が必要
   - 解決策: 自動起動設定（運用改善）

---

## 次のステップ（Phase 3へ）

この仕様を基準として、Phase 3「監視機能拡充」で以下を実施：

1. **Prometheusスクレイプ設定の拡充**
2. **Grafanaダッシュボードの作成**
3. **Zabbix監視項目の追加**
4. **アラートルールの実装**

---

**Specification Version**: 1.0.0
**Based on**: Phase 0-2 完了時点（2026-01-01）
**Constitutional Compliance**: ✅ すべての原則に準拠
