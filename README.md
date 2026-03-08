# 🔬 Monitoring Lab - 自宅オブザーバビリティ基盤

Terraform + Terragrunt + Vault を使用した、学習用の監視基盤IaC構成です。
リモートDockerサーバー（10.0.0.220）上に監視スタック一式をデプロイします。

---

## 📐 アーキテクチャ構成図

> `docs/` 以下の `.drawio` ファイルを draw.io（[app.diagrams.net](https://app.diagrams.net) または VS Code の Draw.io 拡張機能）で開いてください。

| ファイル | 内容 |
|---------|------|
| `docs/network-topology.drawio` | **ネットワークトポロジー** — 物理構成・LAN/WAN・クラウド接続 |
| `docs/monitoring-stack.drawio` | **監視スタック** — コンポーネント間のデータフロー・ポート番号 |
| `docs/mcp-servers.md` | **MCP Servers** — Claude Code 連携の使い方・ツールリファレンス |

**概要:**

```
[監視対象]                         [データ収集層]          [監視スタック: 10.0.0.220]
  RTX830 (SNMP v1)   ──────────→  SNMP Exporter :9116 ─→ Prometheus :9090 ─→ Grafana :3000
  Synology (SNMP v2c)─────────→                          ↑                    ↑
  Docker Containers  ──────────→  cAdvisor :8081  ───────┘                    │
  SwitchBot × 4      ──────────→  Zabbix Server :10051 ─→ Zabbix Web :8080 ──┘
  Zabbix Agent       ──────────→  (Active check)
```

---

## 📦 構成要素

### 監視基盤サービス（リモートサーバー: 10.0.0.220）

| コンポーネント | イメージ | ポート | 用途 |
|-------------|---------|------|------|
| **PostgreSQL** | `postgres:15-alpine` | 5432 | Zabbix データ永続化 |
| **Vault** | `hashicorp/vault:latest` | 8200 | 機密情報管理（開発モード） |
| **Zabbix Server** | `zabbix/zabbix-server-pgsql` | 10051 | 監視サーバー |
| **Zabbix Agent2** | `zabbix/zabbix-agent2` | 10050 | Zabbix Server 自己監視 |
| **Zabbix Web** | `zabbix/zabbix-web-apache-pgsql` | 8080 | Web UI |
| **Prometheus** | `prom/prometheus:latest` | 9090 | 時系列メトリクス収集 + アラート |
| **cAdvisor** | `gcr.io/cadvisor/cadvisor` | 8081 | Docker コンテナメトリクス収集 |
| **SNMP Exporter** | `prom/snmp-exporter` | 9116 | 物理機器 SNMP → Prometheus 変換 |
| **Grafana** | `grafana/grafana:latest` | 3000 | 可視化ダッシュボード |
| **New Relic Infra** | `newrelic/infrastructure:latest` | - | 統合監視プラットフォーム連携 |

### 監視対象

| 対象 | 監視方法 | 監視項目 |
|------|---------|---------|
| **SwitchBot 温湿度計 × 4** | Zabbix External Check (SwitchBot API) | 温度、湿度、バッテリー、照度、人感 |
| **Yamaha RTX830** (10.0.0.1) | SNMP Exporter → Prometheus (SNMP v1) | インターフェーストラフィック、リンク状態 |
| **Synology NAS** (10.0.0.200) | SNMP Exporter → Prometheus (SNMP v2c) | CPU、ストレージ、ネットワーク、Uptime |
| **Docker コンテナ** | cAdvisor → Prometheus | CPU、メモリ、ネットワーク、ホストメトリクス |
| **ホスト OS** | New Relic Infrastructure Agent | CPU、メモリ、ディスク、ネットワーク |

### Grafana ダッシュボード

| ダッシュボード | データソース | 内容 |
|-------------|------------|------|
| **cAdvisor** | Prometheus | Docker コンテナ CPU / メモリ / ネットワーク |
| **Physical Devices** | Prometheus | RTX830 / Synology NAS のメトリクス |
| **Integrated Monitoring** | Prometheus + Zabbix | スクレイプ状態、アラート数、SwitchBot 温湿度 |

### アラートルール（Prometheus）

| ルール | 条件 |
|--------|------|
| `TargetDown` | スクレイプターゲットが応答なし |
| `ContainerHighCPU` | コンテナ CPU 使用率 > 80% (5分継続) |
| `ContainerHighMemory` | コンテナメモリ使用率 > 85% (5分継続) |
| `RTX830LANInterfaceDown` | LAN インターフェースがダウン (2分継続) |
| `SynologyHighCPU` | NAS CPU > 80% (5分継続) |
| `SynologyDiskHighUsage` | Volume 使用率 > 85% (10分継続) |

---

## 🎯 このプロジェクトの目的

- **IaC の学習**: Terraform / Terragrunt の実践的な理解
- **Vault 連携**: シークレット管理のベストプラクティス習得（将来の完全移行に向けて準備中）
- **監視基盤の構築**: Zabbix + Prometheus + Grafana の統合環境構築
- **MCP Server 開発**: AI を活用した自律的インフラ改善基盤（Docker / Prometheus / Terragrunt MCP 稼働中）

---

## 📁 ディレクトリ構成

```
E:\work\labo/
├── docs/
│   ├── network-topology.drawio     # ネットワークトポロジー図（物理構成・LAN/WAN）
│   └── monitoring-stack.drawio     # 監視スタック構成図（コンポーネント・データフロー）
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml          # スクレイプ設定（SNMP / cAdvisor / Prometheus self）
│   │   └── alerts.yml              # アラートルール（6ルール）
│   ├── snmp/
│   │   └── snmp.yml                # SNMP Exporter 設定（RTX830 / Synology）
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── datasources.yml # Prometheus + Zabbix データソース定義
│           └── dashboards/
│               ├── dashboards.yml
│               ├── cadvisor.json
│               ├── physical-devices.json
│               └── integrated-monitoring.json
├── terraform/
│   ├── root.hcl                     # ルート設定（HCP Terraform backend、Docker Provider）
│   ├── modules/
│   │   ├── docker_container/        # 共通 Docker コンテナモジュール
│   │   ├── network/                 # Docker ネットワークモジュール
│   │   └── vault_secret/            # Vault シークレット管理モジュール（将来用）
│   └── envs/
│       └── local/
│           ├── terragrunt.hcl       # 環境固有設定
│           ├── network/             # Docker ネットワーク
│           ├── postgres/            # PostgreSQL
│           ├── vault/               # Vault（開発モード）
│           ├── zabbix/              # Zabbix Server / Web
│           ├── zabbix-agent/        # Zabbix Agent2
│           ├── prometheus/          # Prometheus + Alert Rules
│           ├── cadvisor/            # cAdvisor（コンテナメトリクス）
│           ├── snmp-exporter/       # SNMP Exporter（物理機器監視）
│           ├── grafana/             # Grafana
│           └── newrelic/            # New Relic Infrastructure
├── scripts/
│   ├── setup-remote-config.sh      # リモートサーバー初期設定
│   ├── container-setup.sh / .bat   # 開発コンテナセットアップ
│   └── tg.sh / tg.bat              # Terragrunt ラッパー
├── mcp/
│   ├── prometheus-server/          # Prometheus MCP Server（メトリクス取得・提案生成）
│   ├── docker-server/              # Docker MCP Server（コンテナ操作・ログ取得）
│   └── terragrunt-server/          # Terragrunt MCP Server（承認フロー・apply実行）
├── .specify/
│   └── memory/                     # Speckit ADLC 成果物（仕様書、計画書、タスクリスト）
├── .claude/
│   ├── SESSION_STATE.md            # セッション状態管理
│   └── commands/                   # Speckit スラッシュコマンド
├── docker-compose.yml               # 開発環境（Terragrunt / Vault）
├── .env.example                     # 環境変数テンプレート
├── CLAUDE.md                        # Claude Code 用プロジェクト概要
└── README.md                        # このファイル
```

---

## 🚀 クイックスタート

### 前提条件

| 要件 | 詳細 |
|------|------|
| **WSL2** | Ubuntu-24.04（Docker Engine 29.x がインストール済み） |
| **Docker Engine** | WSL2 上で動作（Docker Desktop ではない） |
| **SSH 鍵** | `~/.ssh/id_rsa`（WSL2 内、リモートサーバー 10.0.0.220 に接続可能） |
| **HCP Terraform トークン** | `.env` に `TF_TOKEN_app_terraform_io` として設定 |

> ⚠️ このプロジェクトは **WSL2 上の Docker Engine** を使用します。Docker Desktop は使用しません。

### 初回セットアップ

```bash
# 1. WSL2 の Docker を起動
wsl -d Ubuntu-24.04 -e bash -c "sudo service docker start"

# 2. 環境変数ファイルを作成
cp .env.example .env
# .env を編集して TF_TOKEN_app_terraform_io などを設定

# 3. 開発コンテナを起動（WSL2 経由）
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d"

# 4. Terragrunt コンテナに接続
wsl -d Ubuntu-24.04 -e bash -c "docker exec -it monitoring-lab-terragrunt sh"

# コンテナ内で実行:
cd /workspace/terraform/envs/local
terragrunt run --all init
terragrunt run --all plan
terragrunt run --all apply
```

### アクセス URL

| サービス | URL | 認証情報 |
|---------|-----|---------|
| **Grafana** | `http://10.0.0.220:3000` | admin / admin |
| **Zabbix Web** | `http://10.0.0.220:8080` | Admin / zabbix |
| **Prometheus** | `http://10.0.0.220:9090` | 認証なし |
| **cAdvisor** | `http://10.0.0.220:8081` | 認証なし |
| **SNMP Exporter** | `http://10.0.0.220:9116` | 認証なし |
| **Vault** (開発用) | `http://localhost:8200` | Token: `root` |
| **New Relic** | `https://one.newrelic.com/` | ライセンスキーで認証 |
| **HCP Terraform** | `https://app.terraform.io/app/k1981-learning-lab` | API Token |

---

## 🔧 個別サービスの操作

### 特定サービスのみ更新

```bash
# コンテナ内で実行
cd /workspace/terraform/envs/local/grafana
terragrunt apply

cd /workspace/terraform/envs/local/prometheus
terragrunt apply
```

### Prometheus 設定のホットリロード

```bash
wsl -d Ubuntu-24.04 -e bash -c \
  "ssh ubuntu@10.0.0.220 'curl -s -X POST http://localhost:9090/-/reload'"
```

### リモートサーバーのコンテナ確認

```bash
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@10.0.0.220 'docker ps'"
```

---

## 🗑️ 環境の削除

```bash
# コンテナ内で実行
cd /workspace/terraform/envs/local
TG_NON_INTERACTIVE=true terragrunt run --all destroy

# 削除順序（依存関係の逆順）
# grafana → cadvisor → snmp-exporter → prometheus → zabbix-agent → zabbix → vault → postgres → network
```

> ⚠️ Docker ボリュームも削除されるため、Zabbix / Grafana のデータは完全に消失します。

---

## 📚 学習ポイント

### 1. Terragrunt の利点

#### DRY 原則の実践

共通設定（Docker Provider、HCP Terraform backend）を `root.hcl` に集約し、各サービスは差分のみ定義。

#### 依存関係の自動解決

```hcl
dependency "postgres" {
  config_path = "../postgres"
}
```
→ Zabbix は PostgreSQL の起動を自動的に待機してからデプロイされる。

#### 一括操作

```bash
terragrunt run --all apply   # 全サービスを正しい順序でデプロイ
terragrunt run --all destroy # 依存関係を考慮して削除
```

### 2. HCP Terraform によるState管理

ローカルの `terraform.tfstate` ではなく、[HCP Terraform](https://app.terraform.io) の Remote Backend を使用。

- **Organization**: `k1981-learning-lab`
- **Workspace 数**: 10（サービスごとに分離）
- **Execution Mode**: Local（Terraform 実行はコンテナ内で行い、State のみ HCP 管理）

```hcl
# root.hcl
remote_state {
  backend = "cloud"
  config = {
    organization = "k1981-learning-lab"
    workspaces {
      name = "${local.project_name}-${local.environment}-${path_relative_to_include()}"
    }
  }
}
```

### 3. Vault との連携（将来の完全移行に向けて準備中）

現在は環境変数に直接パスワードを記述していますが、将来は以下のように実装予定:

```hcl
data "vault_kv_secret_v2" "postgres" {
  mount = "secret"
  name  = "monitoring-lab/postgres"
}

env = [
  "POSTGRES_PASSWORD=${data.vault_kv_secret_v2.postgres.data["password"]}"
]
```

### 4. Pull 型 vs Push 型監視の使い分け

| 方式 | ツール | 用途 |
|------|--------|------|
| **Pull 型** | Prometheus | Docker コンテナ、物理機器（SNMP Exporter 経由） |
| **Push 型** | Zabbix | SwitchBot 温湿度計（External Check API 呼び出し） |
| **エージェント型** | New Relic Infra | ホスト OS / コンテナ統合監視 |

### 5. SNMP Exporter の活用

ルーターや NAS などの SNMP 対応機器を Prometheus で監視する変換レイヤー。

```yaml
# prometheus.yml
- job_name: 'snmp_rtx830'
  static_configs:
    - targets: ['10.0.0.1']
  metrics_path: /snmp
  params:
    module: [if_mib]
    auth: [monlab_v1]    # v0.30.1以降: URLパラメータで認証指定
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - target_label: __address__
      replacement: localhost:9116
```

---

## 🛠️ トラブルシューティング

### WSL2 の Docker が停止している

```bash
wsl -d Ubuntu-24.04 -e bash -c "sudo service docker start"
```

### Terragrunt コンテナが起動しない（Vault 依存）

```bash
# Vault を先に起動してから Terragrunt を起動
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d vault"
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d terragrunt"

# または one-shot で実行（Vault 依存を回避）
wsl -d Ubuntu-24.04 -e bash -c "docker compose run --rm terragrunt sh -c \
  'cp /tmp/ssh-keys/id_rsa /root/.ssh/id_rsa && chmod 600 /root/.ssh/id_rsa && \
   cd /workspace/terraform/envs/local/<service> && terragrunt apply -auto-approve'"
```

### HCP Terraform の新規 Workspace が Remote モードになる

新規 Workspace はデフォルトで Remote 実行モードになります。Local モードへの変更が必要です:

```bash
curl -X PATCH "https://app.terraform.io/api/v2/organizations/k1981-learning-lab/workspaces/<workspace-name>" \
  -H "Authorization: Bearer $TF_TOKEN_app_terraform_io" \
  -H "Content-Type: application/vnd.api+json" \
  --data '{"data":{"type":"workspaces","attributes":{"execution-mode":"local"}}}'
```

### Prometheus がデータを収集しない

```bash
# ターゲット状態確認
# ブラウザ: http://10.0.0.220:9090/targets

# 設定リロード
wsl -d Ubuntu-24.04 -e bash -c \
  "ssh ubuntu@10.0.0.220 'curl -s -X POST http://localhost:9090/-/reload'"
```

### SNMP Exporter がターゲットを取得できない

```bash
# RTX830 疎通確認
wsl -d Ubuntu-24.04 -e bash -c \
  "ssh ubuntu@10.0.0.220 'snmpwalk -v1 -c monlab 10.0.0.1 sysDescr.0'"

# Synology 疎通確認
wsl -d Ubuntu-24.04 -e bash -c \
  "ssh ubuntu@10.0.0.220 'snmpwalk -v2c -c monlab 10.0.0.200 sysDescr.0'"
```

> ⚠️ RTX830 は SNMP **v1 のみ**対応（v2c はタイムアウト）。

### コンテナが起動しない（リモートサーバー）

```bash
# ログ確認
wsl -d Ubuntu-24.04 -e bash -c \
  "ssh ubuntu@10.0.0.220 'docker logs monitoring-lab-zbx_server'"

# ネットワーク確認
wsl -d Ubuntu-24.04 -e bash -c \
  "ssh ubuntu@10.0.0.220 'docker network inspect monitoring-lab-network'"
```

---

## 🔐 セキュリティに関する注意

このプロジェクトは **学習目的** のため、以下の設定は本番環境では使用しないでください:

- ❌ Vault の開発モード（Root Token 固定）
- ❌ パスワードのハードコーディング（`.env` ファイル）
- ❌ HTTP 通信（HTTPS 未設定）
- ❌ デフォルト認証情報の使用

### 本番環境への移行チェックリスト

- [ ] Vault の本番モード化（`config.hcl` 作成、Unseal 設定）
- [ ] すべてのパスワードを Vault から動的取得
- [ ] TLS / SSL 証明書の設定
- [ ] 強力なパスワードへの変更
- [ ] HCP Terraform の Remote State（すでに設定済み ✅）
- [ ] ネットワークファイアウォールルールの設定
- [ ] シークレットローテーションの実装

---

## 💡 今後の拡張予定

| ステータス | 項目 |
|-----------|------|
| ✅ 完了 | cAdvisor によるコンテナメトリクス収集 |
| ✅ 完了 | Prometheus アラートルール（6ルール） |
| ✅ 完了 | SNMP Exporter による物理機器監視（RTX830 / Synology） |
| ✅ 完了 | Grafana ダッシュボード（cAdvisor / Physical Devices / Integrated） |
| ✅ 完了 | HCP Terraform による State 管理（10 Workspaces） |
| ✅ 完了 | Docker MCP Server（コンテナ操作・ログ・リソース監視） |
| ✅ 完了 | Prometheus MCP Server（メトリクス取得・アラート確認・改善提案生成） |
| ✅ 完了 | Terragrunt MCP Server（承認フロー・plan/apply・ロールバック） |
| ✅ 完了 | Linux Node Exporter 設定（10.0.0.250 / 10.0.0.254） |
| 📅 計画中 | Vault の完全活用（Dynamic Secrets） |
| 📅 計画中 | CI/CD 統合（GitHub Actions + Terragrunt） |

---

## 📖 参考資料

- [Terraform 公式ドキュメント](https://www.terraform.io/docs)
- [Terragrunt 公式ドキュメント](https://terragrunt.gruntwork.io/docs/)
- [HCP Terraform ドキュメント](https://developer.hashicorp.com/terraform/cloud-docs)
- [HashiCorp Vault 公式ドキュメント](https://www.vaultproject.io/docs)
- [Zabbix 公式ドキュメント](https://www.zabbix.com/documentation)
- [Prometheus 公式ドキュメント](https://prometheus.io/docs)
- [SNMP Exporter ドキュメント](https://github.com/prometheus/snmp_exporter)
- [Grafana 公式ドキュメント](https://grafana.com/docs)
- [cAdvisor ドキュメント](https://github.com/google/cadvisor)

---

## 🤝 コントリビューション

このプロジェクトは個人学習用ですが、改善提案は歓迎します！

## 📄 ライセンス

MIT License

---

**Happy Learning! 🎓**
