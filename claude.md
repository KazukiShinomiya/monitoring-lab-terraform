# 🔬 Monitoring Lab - プロジェクト概要 (Claude Code用)

---

## 🚀 セッション開始時の自動指示

**重要**: Claude Codeでこのプロジェクトを開いたら、必ず最初に以下を実行してください:

### ステップ1: 前回の作業状況を確認
`.claude/SESSION_STATE.md` を読み込み、以下を表示してください:
- ✅ 前回セッションで完了した作業
- 🚧 未完了のタスク（優先度別）
- 🎯 次に推奨するアクション

### ステップ2: 現在の状態を確認
ユーザーに以下を簡潔に伝えてください:
```
前回のセッションでは[XXX]を完了しました。
次にやるべきことは[YYY]です。
何から始めますか？
```

**注意**: この指示はセッション開始時に自動的に実行され、ユーザーがスラッシュコマンドを入力する必要はありません。

---

## ⚠️ 実行方式 - 必読

**実行環境**: WSL2 (Ubuntu-24.04) 上のDocker Engine
- **Docker Desktop は使用しない**
- WSL2でdocker composeを実行
- Terragruntコンテナ内から当プロジェクトのTerraformを実行
- TerragruntコンテナはWSL2のDocker Engine上で動作

**SSH鍵の配置**:
- WSL2: `~/.ssh/id_rsa` (ubuntuユーザーのホームディレクトリ)
- コンテナ起動時に自動的に `/root/.ssh/` にコピー (docker-compose.ymlのentrypointで実行)
- コンテナ内から `/root/.ssh/id_rsa` を使用してリモートサーバー(10.0.0.220)にSSH接続

**重要な注意点**:
- Dockerコマンドは必ずWSL2経由で実行: `wsl -d Ubuntu-24.04 -e bash -c "..."`
- Terragrunt/TerraformはコンテナからSSH経由でリモートDockerを操作
- SSH鍵はWSL2ホスト側とコンテナ内の両方に必要

---

## 📌 プロジェクト概要

**目的**: Terraform + Terragrunt + Vault を使用した学習用オブザーバビリティ基盤の構築

**構成**: リモートDocker環境でのコンテナベース監視基盤
- Zabbix Server/Web (サーバー監視)
- Prometheus (メトリクス収集)
- Grafana (可視化)
- PostgreSQL (永続ストレージ)
- Vault (機密情報管理 - 開発モード)

**環境**: WSL2 (Ubuntu-24.04) + リモートDocker Engine (10.0.0.220)

---

## 🗂️ ディレクトリ構成

```
E:\work\labo/
├── docker-compose.yml              # Terraform/Terragrunt開発環境
├── .env.example                    # 環境変数テンプレート
├── .env                           # 環境変数 (要作成、Gitignore済み)
├── README.md                       # プロジェクトドキュメント
├── QUICKSTART.md                   # クイックスタートガイド
├── claude.md                       # このファイル
│
├── config/                         # サービス設定ファイル
│   ├── prometheus/
│   │   ├── prometheus.yml         # スクレイプ設定（Job 1-7）
│   │   └── alerts.yml             # アラートルール（7種類）
│   ├── alertmanager/
│   │   └── alertmanager.yml       # Slack通知設定（URLはプレースホルダー）
│   ├── snmp/
│   │   └── snmp.yml               # SNMP Exporter設定（RTX830/Synology）
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── datasources.yml # Prometheus/Zabbixデータソース
│           └── dashboards/
│               ├── dashboards.yml  # ダッシュボードプロビジョニング設定
│               ├── cadvisor.json   # cAdvisorダッシュボード
│               ├── physical-devices.json # RTX830/Synologyダッシュボード
│               ├── integrated-monitoring.json # 統合ダッシュボード
│               └── tekken.json    # Tekken Botバトル統計
│
├── mcp/                            # MCP Servers（Claude Code連携）
│   ├── docker-server/             # Dockerコンテナ操作（6ツール）
│   ├── prometheus-server/         # Prometheusメトリクス・アラート（6ツール）
│   └── terragrunt-server/         # Terragrunt plan/apply（6ツール）
│
├── terraform/                      # IaC定義
│   ├── root.hcl                   # ルート設定 (全環境共通)
│   ├── modules/                   # 再利用可能モジュール
│   │   ├── docker_container/     # Docker汎用モジュール
│   │   ├── network/               # Dockerネットワークモジュール
│   │   └── vault_secret/         # Vault統合モジュール
│   └── envs/
│       └── local/                 # ローカル環境（HCP Terraform管理）
│           ├── network/           # Dockerネットワーク
│           ├── postgres/          # PostgreSQL
│           ├── vault/             # Vault（開発モード）
│           ├── zabbix/            # Zabbix Server/Web
│           ├── zabbix-agent/      # Zabbix Agent2
│           ├── prometheus/        # Prometheus
│           ├── grafana/           # Grafana
│           ├── newrelic/          # New Relic Infra
│           ├── cadvisor/          # cAdvisor（コンテナメトリクス）
│           ├── snmp-exporter/     # SNMP Exporter（物理機器監視）
│           └── alertmanager/      # Alertmanager（Slack通知）
│
├── specs/                          # Speckit ADLCドキュメント
│   ├── 001-mcp-self-growth/       # MCP自己成長基盤
│   └── 004-alertmanager-slack/    # Alertmanager Slack通知
│
├── docs/                           # アーキテクチャドキュメント
│   ├── monitoring-stack.drawio    # 監視スタック構成図
│   ├── network-topology.drawio    # ネットワークトポロジー図
│   ├── mcp-servers.md             # MCP Serverリファレンス
│   ├── node-exporter-setup.md     # Node Exporterセットアップ手順
│   └── windows-exporter-setup.md  # Windows Exporterセットアップ手順
│
└── scripts/                       # ヘルパースクリプト
    ├── sync-config.sh             # 設定ファイル同期（scp + reload）
    ├── container-setup.sh / .bat # 開発コンテナセットアップ
    ├── tg.sh / .bat              # Terragruntコマンドラッパー
    └── setup-remote-config.sh    # リモートサーバー初回セットアップ
```

---

## 🎯 主要コンポーネント

### 監視基盤サービス

| サービス | イメージ | ポート | 用途 | 依存関係 |
|---------|---------|--------|------|---------|
| **PostgreSQL** | `postgres:15-alpine` | 5432 | Zabbixデータ永続化 | なし |
| **Vault** | `hashicorp/vault:latest` | 8200 | 機密情報管理 (開発モード) | なし |
| **Zabbix Server** | `zabbix/zabbix-server-pgsql:alpine-latest` | 10051 | 監視サーバー | PostgreSQL |
| **Zabbix Agent2** | `zabbix/zabbix-agent2:alpine-latest` | 10050 | Zabbix Server自己監視 | Zabbix Server |
| **Zabbix Web** | `zabbix/zabbix-web-apache-pgsql:alpine-latest` | 8080 | WebUI | PostgreSQL, Zabbix Server |
| **Prometheus** | `prom/prometheus:latest` | 9090 | メトリクス収集・アラート評価 | なし |
| **Alertmanager** | `prom/alertmanager:latest` | 9093 | アラート通知（Slack） | Prometheus |
| **cAdvisor** | `gcr.io/cadvisor/cadvisor:latest` | 8081 | Dockerコンテナメトリクス | なし |
| **SNMP Exporter** | `prom/snmp-exporter:latest` | 9116 | 物理機器監視（RTX830/NAS） | なし |
| **Grafana** | `grafana/grafana:latest` | 3000 | ダッシュボード | Prometheus, Zabbix |
| **New Relic Infra** | `newrelic/infrastructure:latest` | - | 統合監視プラットフォーム | なし |

### 監視対象

| 対象 | 監視方法 | 項目 |
|------|---------|------|
| **SwitchBot温湿度計** | Zabbix External Check | 温度、湿度、バッテリー、照度、人感（4台） |
| **Dockerコンテナ群** | cAdvisor → Prometheus | CPU、メモリ、ネットワーク（全コンテナ） |
| **Yamaha RTX830** | SNMP Exporter（v1） | インターフェーストラフィック、リンク状態 |
| **Synology NAS** | SNMP Exporter（v2c） | CPU、ストレージ使用量、ネットワーク |
| **Linuxホスト** | Node Exporter（:9100） | CPU、メモリ、ディスク（10.0.0.250, .254） |
| **Tekken Bot** | カスタムExporter（:9877） | レーティング推移、勝率、対面別成績 |
| **ホストOS** | New Relic Infrastructure Agent | CPU、メモリ、ディスク、ネットワーク |

### MCP Servers（Claude Code連携）

| MCP Server | ツール数 | 主な機能 |
|-----------|---------|---------|
| **docker-server** | 6 | コンテナ一覧・ログ取得・起動/停止/再起動・stats |
| **prometheus-server** | 6 | PromQLクエリ・アラート確認・AI改善提案・提案管理 |
| **terragrunt-server** | 6 | plan/apply・設定確認・ワークスペース一覧・承認フロー・ロールバック |

### 開発環境コンテナ

| コンテナ | イメージ | 用途 |
|---------|---------|------|
| **Terraform CLI** | `hashicorp/terraform:latest` | Terraform実行環境 |
| **Terragrunt CLI** | `alpine/terragrunt:latest` | Terragrunt実行環境 |

---

## 🚀 クイックスタート

### 前提条件
- Docker Desktop (Windows) または Docker Engine (Linux) がインストール済み
- Git Bash / WSL2 / Linux Terminal

### 初回セットアップ

```bash
# 1. 環境変数ファイルの作成
cp .env.example .env

# 2. 開発コンテナの起動
docker compose up -d

# 3. コンテナ状態確認
docker compose ps

# 4. Terragruntコンテナに接続
docker compose exec terragrunt sh

# 5. 作業ディレクトリに移動
cd terraform/envs/local

# 6. Terragrunt初期化
terragrunt run-all init

# 7. 実行計画確認
terragrunt run-all plan

# 8. 監視基盤のデプロイ
terragrunt run-all apply
```

### アクセスURL

| サービス | URL | 認証情報 |
|---------|-----|---------|
| Vault | http://localhost:8200 | Token: `root` (開発用ローカル) |
| Zabbix | http://10.0.0.220:8080 | User: `Admin`, Pass: `zabbix` |
| Prometheus | http://10.0.0.220:9090 | 認証なし |
| Grafana | http://10.0.0.220:3000 | User: `admin`, Pass: `admin` |
| New Relic | https://one.newrelic.com/ | ライセンスキーで認証 |

---

## 🔧 よくある操作

### コンテナ管理

```bash
# 開発コンテナ起動
docker compose up -d

# 特定コンテナのみ起動
docker compose up -d terragrunt

# コンテナに接続
docker compose exec terragrunt sh

# コンテナ停止
docker compose stop

# コンテナ削除
docker compose down

# ボリュームも含めて削除
docker compose down -v

# ログ確認
docker compose logs -f terragrunt
```

### 監視基盤の管理

```bash
# コンテナ内で実行
cd terraform/envs/local

# 全サービスの状態確認
terragrunt run-all plan

# 全サービスのデプロイ
terragrunt run-all apply

# 特定サービスのみ更新
cd grafana
terragrunt apply

# 全サービスの削除
cd ..
terragrunt run-all destroy
```

### ヘルパースクリプト使用 (ホストから実行)

**Windows:**
```bash
# 初期化
cd terraform\envs\local
..\..\..\scripts\tg.bat run-all init

# デプロイ
..\..\..\scripts\tg.bat run-all apply
```

**Linux/Mac:**
```bash
# 初期化
cd terraform/envs/local
../../../scripts/tg.sh run-all init

# デプロイ
../../../scripts/tg.sh run-all apply
```

---

## 📁 重要なファイル

### Terragrunt設定

| ファイル | 役割 | 主要設定 |
|---------|------|---------|
| `terraform/terragrunt.hcl` | ルート設定 | Backend: local, Docker Provider, 共通変数 |
| `terraform/envs/local/terragrunt.hcl` | 環境設定 | Vault接続URL |
| `terraform/envs/local/*/terragrunt.hcl` | サービス定義 | コンテナ設定、依存関係 |

### サービス設定

| ファイル | 用途 | 状態 |
|---------|------|------|
| `config/prometheus/prometheus.yml` | Prometheusスクレイプ設定 | 基本設定のみ有効 |
| `config/grafana/provisioning/datasources/datasources.yml` | Grafanaデータソース | Prometheus/Zabbix定義済み |

### 環境変数

| ファイル | 用途 | Gitコミット |
|---------|------|-----------|
| `.env.example` | テンプレート | ✅ コミット対象 |
| `.env` | 実際の設定値 | ❌ Gitignore (要作成) |

---

## 🛠️ トラブルシューティング

### コンテナが起動しない

```bash
# ステータス確認
docker compose ps -a

# ログ確認
docker compose logs terragrunt
docker compose logs terraform

# 再起動
docker compose restart terragrunt

# 完全再作成
docker compose down
docker compose up -d
```

### Terragrunt実行時のエラー

```bash
# キャッシュクリア
rm -rf terraform/envs/local/.terragrunt-cache

# State再初期化
cd terraform/envs/local
terragrunt run-all init -reconfigure

# 依存関係の確認
terragrunt graph-dependencies
```

### 監視サービスが起動しない

```bash
# ホストから確認
docker ps -a | grep monitoring-lab

# ログ確認
docker logs monitoring-lab-postgres
docker logs monitoring-lab-vault-dev
docker logs monitoring-lab-zbx_server
docker logs monitoring-lab-prometheus
docker logs monitoring-lab-grafana

# ネットワーク確認
docker network inspect monitoring-lab-network

# ボリューム確認
docker volume ls | grep monitoring-lab
```

### Prometheusがターゲットを収集しない

```bash
# 設定ファイルの確認
docker exec monitoring-lab-prometheus cat /etc/prometheus/prometheus.yml

# 設定リロード
curl -X POST http://localhost:9090/-/reload

# Targetsの状態確認
# ブラウザで http://localhost:9090/targets を開く
```

### GrafanaでZabbixデータソースが接続できない

```bash
# Zabbixコンテナの起動確認
docker ps | grep zbx

# ネットワーク疎通確認
docker exec monitoring-lab-grafana ping zbx_web

# Zabbix API URL確認 (正しい形式)
# http://zbx_web:8080/api_jsonrpc.php
```

---

## 🔐 セキュリティに関する注意

### 現在の構成 (学習用)
- ❌ Vaultは開発モード (Root Token固定)
- ❌ パスワードがハードコード
- ❌ HTTP通信 (HTTPS未設定)
- ❌ デフォルト認証情報使用

### 本番環境への移行時の必須対応
- [ ] Vaultの本番モード化 (config.hcl作成)
- [ ] すべてのパスワードをVault管理に移行
- [ ] TLS/SSL証明書の設定
- [ ] 強力なパスワードへの変更
- [ ] Stateファイルのリモートバックエンド化 (S3等)
- [ ] ネットワークセキュリティ設定

---

## 🧩 依存関係グラフ

```
PostgreSQL ─┬─→ Zabbix Server ─→ Zabbix Web
            │
            └─→ (将来) Grafana PostgreSQLデータソース

Vault ─→ (将来) 全サービス (シークレット取得)

Prometheus ─→ Grafana

Zabbix ─→ Grafana
```

---

## 📚 学習ポイント

### 1. Terragruntの活用
- **DRY原則**: 共通設定をルートに集約、差分のみ各環境で定義
- **依存関係管理**: `dependency` ブロックで起動順序を制御
- **一括操作**: `run-all` で複数サービスを一括管理

### 2. Dockerプロバイダーの理解
- ネットワーク、ボリューム、コンテナの宣言的管理
- `for_each` による動的リソース作成
- ヘルスチェック、再起動ポリシーの設定

### 3. 監視基盤の統合
- Zabbix (エージェントベース監視) + Prometheus (Pull型監視)
- Grafanaでの統合可視化
- PostgreSQLによるメタデータ永続化

### 4. Vault統合の準備
- `vault_secret` モジュールの実装
- 開発モードから本番モードへの移行パス
- シークレットローテーションの考慮

---

## 🚧 今後の拡張予定

### Phase 1: 基本動作確認 (現在)
- [x] Terragrunt/Terraform基盤構築
- [x] 各サービスのコンテナ定義
- [ ] 全サービスの起動確認
- [ ] Web UIへのアクセス確認

### Phase 2: 監視機能の拡充
- [ ] Zabbix Agentの追加 (自己監視)
- [ ] Prometheusスクレイプ設定の有効化
- [ ] Grafanaダッシュボードの作成
- [ ] PostgreSQLデータソースの有効化

### Phase 3: セキュリティ強化
- [ ] Vaultへのシークレット移行
- [ ] パスワードの動的取得実装
- [ ] TLS証明書設定

### Phase 4: 運用改善
- [ ] アラートルールの実装
- [ ] メトリクス長期保存設定
- [ ] バックアップ自動化

### Phase 5: 本番化準備
- [ ] リモートStateバックエンド (S3等)
- [ ] マルチ環境対応 (dev/staging/prod)
- [ ] CI/CD統合

---

## 🔍 デバッグ Tips

### Terraformの動作確認

```bash
# コンテナ内で実行
cd terraform/envs/local/postgres

# プラン詳細表示
TF_LOG=DEBUG terragrunt plan

# State確認
terragrunt state list
terragrunt state show docker_container.service[\"postgres\"]

# 依存関係グラフ出力
terragrunt graph-dependencies | dot -Tpng > deps.png
```

### Dockerリソースの確認

```bash
# すべての監視基盤コンテナを表示
docker ps -a --filter "label=project=monitoring-lab"

# ネットワーク詳細
docker network inspect monitoring-lab-network

# ボリューム使用状況
docker system df -v | grep monitoring-lab

# コンテナ内のファイル確認
docker exec monitoring-lab-postgres ls -la /var/lib/postgresql/data
```

### 設定ファイルの検証

```bash
# Prometheus設定チェック
docker exec monitoring-lab-prometheus promtool check config /etc/prometheus/prometheus.yml

# Grafanaプロビジョニング確認
docker exec monitoring-lab-grafana cat /etc/grafana/provisioning/datasources/datasources.yml
```

---

## 📖 参考コマンド集

### 開発フロー

```bash
# 1. 設定変更
vim terraform/envs/local/grafana/terragrunt.hcl

# 2. 差分確認
cd terraform/envs/local/grafana
terragrunt plan

# 3. 適用
terragrunt apply

# 4. 動作確認
docker logs monitoring-lab-grafana

# 5. ブラウザでアクセス
# http://localhost:3000
```

### 緊急時の対応

```bash
# すべてのコンテナを停止
docker stop $(docker ps -q --filter "label=project=monitoring-lab")

# 特定コンテナの強制再作成
cd terraform/envs/local/prometheus
terragrunt destroy -auto-approve
terragrunt apply -auto-approve

# Stateロックの強制解除
terragrunt force-unlock <LOCK_ID>
```

---

## 🤝 貢献・質問

このプロジェクトは学習用です。
- 質問や提案は Issue で受け付けています
- 改善提案は Pull Request 歓迎

---

## 📄 ライセンス

MIT License

---

**Happy Learning! 🎓**

*最終更新: 2025-10-18*

## Active Technologies
- TypeScript 5.x + Node.js v22.20.0（Windows Git Bash環境で利用可能） (001-mcp-self-growth)
- ローカルJSON/Markdownファイル（`.specify/memory/proposals/`、`.specify/memory/approvals/`） (001-mcp-self-growth)
- TypeScript 5.x + Node.js v22.20.0 (LTS) + `@modelcontextprotocol/sdk` (MCP通信), `zod` (スキーマバリデーション) (002-docker-mcp-server)
- N/A（ステートレス設計） (002-docker-mcp-server)
- HCL (Terraform/Terragrunt)、YAML (Alertmanager config) + `prom/alertmanager:latest`、既存 `docker_container` Terragruntモジュール (004-alertmanager-slack)
- N/A（Alertmanagerはステートレス動作。silencesは再起動時にリセット許容） (004-alertmanager-slack)
- HCL (Terraform/Terragrunt), YAML (設定ファイル), Bash (sync スクリプト) + grafana/tempo:latest, otel/opentelemetry-collector-contrib:latest, 既存 docker_container モジュール (011-tempo)
- Docker Volume (tempo_data) — local filesystem バックエンド (011-tempo)
- HCL (Terragrunt), YAML (Sloth v0.11.0 `prometheus/v1` スキーマ) + `ghcr.io/slok/sloth:v0.11.0`, Prometheus, Grafana, Alertmanager (013-slo-sloth)
- N/A（Sloth はステートレス・ファイル生成のみ） (013-slo-sloth)
- HCL (Terragrunt/Terraform), YAML + `victoriametrics/victoria-metrics:v1.140.0`, 既存 `docker_container` モジュール (`terraform/modules/docker_container/`) (014-victoria-metrics)
- Docker Volume `vm_data` — local filesystem backend (`/victoria-metrics-data`) (014-victoria-metrics)

## Recent Changes
- 001-mcp-self-growth: Added TypeScript 5.x + Node.js v22.20.0（Windows Git Bash環境で利用可能）
