# 🔬 Monitoring Lab - 自宅オブザーバビリティ基盤

Terraform + Terragrunt + Vault を使用した、学習用の監視基盤IaC構成です。

## 📦 構成要素

### 監視基盤サービス

| コンポーネント | 用途 | アクセスURL |
|-------------|------|-----------|
| **Zabbix Server** | メトリクス収集・監視対象管理 | `http://YOUR_SERVER_IP:8080` |
| **Zabbix Agent2** | Zabbix Server自己監視 | `YOUR_SERVER_IP:10050` |
| **Prometheus** | 時系列メトリクス収集 | `http://YOUR_SERVER_IP:9090` |
| **Grafana** | 可視化ダッシュボード | `http://YOUR_SERVER_IP:3000` |
| **PostgreSQL** | Zabbixの永続ストレージ | `YOUR_SERVER_IP:5432` |
| **Vault** | 機密情報管理（開発モード） | `http://localhost:8200` |
| **New Relic** | 統合監視プラットフォーム | `https://one.newrelic.com/` |

### 監視対象

| 対象 | 監視方法 | 監視項目 |
|------|---------|---------|
| **SwitchBot温湿度計 × 4** | Zabbix External Check | 温度、湿度、バッテリー、照度、人感 |
| **Dockerコンテナ × 8** | New Relic Docker統合 | CPU、メモリ、ネットワーク、I/O |
| **ホストOS** | New Relic Infrastructure | CPU、メモリ、ディスク、ネットワーク |

---

## 🎯 このプロジェクトの目的

- **IaCの学習**: Terraform/Terragruntの実践的な理解
- **Vault連携**: シークレット管理のベストプラクティス習得
- **監視基盤の構築**: Zabbix + Prometheus + Grafana の統合環境構築

---

## 📁 ディレクトリ構成

```
monitoring-lab/
├── .claude/                         # Claude Code設定
│   ├── SESSION_STATE.md            # セッション状態管理
│   └── commands/                    # カスタムスラッシュコマンド
├── config/                          # サービス設定ファイル
│   ├── prometheus/
│   │   └── prometheus.yml          # Prometheusスクレイプ設定
│   ├── grafana/
│   │   └── provisioning/           # Grafanaプロビジョニング設定
│   └── zabbix/
│       └── scripts/
│           └── externalscripts/    # Zabbix外部スクリプト
│               └── check_switchbot.py
├── terraform/
│   ├── root.hcl                     # ルート設定（全環境共通）
│   ├── envs/
│   │   └── local/                   # ローカル環境設定
│   │       ├── terragrunt.hcl       # 環境固有設定
│   │       ├── network/             # Dockerネットワーク
│   │       ├── postgres/            # PostgreSQL
│   │       ├── vault/               # Vault
│   │       ├── zabbix/              # Zabbix Server/Web
│   │       ├── zabbix-agent/        # Zabbix Agent2
│   │       ├── prometheus/          # Prometheus
│   │       ├── grafana/             # Grafana
│   │       └── newrelic/            # New Relic Infrastructure
│   └── modules/
│       ├── docker_container/        # 共通Dockerコンテナモジュール
│       ├── network/                 # Dockerネットワークモジュール
│       └── vault_secret/            # Vaultシークレット管理モジュール
├── scripts/                         # ヘルパースクリプト
│   ├── setup-remote-config.sh      # リモートサーバー初期設定
│   ├── container-setup.sh          # 開発コンテナセットアップ
│   └── tg.sh / tg.bat              # Terragruntラッパー
├── docker-compose.yml               # 開発環境（Terragrunt/Vault）
├── .env.example                     # 環境変数テンプレート
├── CLAUDE.md                        # Claude Code用プロジェクト概要
└── README.md                        # このファイル
```

---

## 🚀 クイックスタート

### 前提条件

**最小要件（推奨）：**
- **Docker Desktop** for Windows がインストール済み

**オプション（ローカルインストール）：**
- **Terraform** >= 1.0
- **Terragrunt** >= 0.50

このプロジェクトでは、TerraformとTerragruntを**コンテナで実行**できるため、ローカルインストールは不要です。

#### インストール確認

```bash
# Docker確認（必須）
docker --version

# ローカルにTerraformをインストールしている場合
terraform --version
terragrunt --version
```

---

## 📋 実行方法（2つの選択肢）

### 🐳 方法A: コンテナで実行（推奨）

Terraform/Terragruntをローカルにインストールせずに、コンテナで実行する方法です。

#### A-1. コンテナ環境のセットアップ

**Windows:**
```bash
scripts\container-setup.bat
```

**Linux/Mac:**
```bash
bash scripts/container-setup.sh
```

**実行内容:**
- Terraform/Terragruntコンテナの起動
- Vault開発サーバーの起動
- 各種ヘルパースクリプトの準備

#### A-2. Terragrunt初期化（コンテナ経由）

**Windows:**
```bash
# terraform/envs/localに移動
cd terraform\envs\local

# Terragrunt初期化
..\..\..\scripts\tg.bat run-all init
```

**Linux/Mac:**
```bash
cd terraform/envs/local
../../../scripts/tg.sh run-all init
```

#### A-3. 全サービスデプロイ（コンテナ経由）

**Windows:**
```bash
..\..\..\scripts\tg.bat run-all apply
```

**Linux/Mac:**
```bash
../../../scripts/tg.sh run-all apply
```

---

### 💻 方法B: ローカルインストールで実行

Terraform/Terragruntをローカルにインストールしている場合の実行方法です。

#### B-1. 初期化

```bash
cd terraform/envs/local
terragrunt run-all init
```

**実行内容:**
- 各サービスのTerraformモジュールを初期化
- Dockerプロバイダーのダウンロード
- Stateファイルの準備

---

#### B-2. 全サービス構築

```bash
terragrunt run-all apply
```

**実行順序（依存関係を自動解決）:**
1. `postgres` → データベース起動
2. `vault` → シークレット管理サーバー起動
3. `zabbix` → 監視サーバー起動（PostgreSQL依存）
4. `prometheus` → メトリクス収集サーバー起動
5. `grafana` → 可視化ダッシュボード起動（Prometheus/Zabbix依存）

**確認コマンド:**
```bash
docker ps
```

---

---

## ✅ 動作確認

#### Zabbix
```
URL: http://localhost:8080
デフォルト認証情報:
  - ユーザー名: Admin
  - パスワード: zabbix
```

#### Grafana
```
URL: http://localhost:3000
デフォルト認証情報:
  - ユーザー名: admin
  - パスワード: admin
```

#### Prometheus
```
URL: http://localhost:9090
認証なし
```

#### Vault
```
URL: http://localhost:8200
Root Token: root（開発モード固定）
```

---

## 🔧 個別サービスの操作

### 特定サービスのみ再構築

**コンテナ使用時（Windows）:**
```bash
# Grafanaのみ更新
cd terraform\envs\local\grafana
..\..\..\scripts\tg.bat apply

# Zabbixのみ再起動
cd terraform\envs\local\zabbix
..\..\..\scripts\tg.bat destroy
..\..\..\scripts\tg.bat apply
```

**ローカルインストール時:**
```bash
# Grafanaのみ更新
cd terraform/envs/local/grafana
terragrunt apply

# Zabbixのみ再起動
cd terraform/envs/local/zabbix
terragrunt destroy
terragrunt apply
```

### 設定変更の反映

1. `terragrunt.hcl` を編集
2. `terragrunt plan` で変更内容確認（`scripts\tg.bat plan` または `terragrunt plan`）
3. `terragrunt apply` で反映（`scripts\tg.bat apply` または `terragrunt apply`）

---

## 🗑️ 環境の削除

### 全サービス削除

```bash
cd terraform/envs/local
terragrunt run-all destroy
```

**削除順序（依存関係の逆順）:**
1. `grafana`
2. `prometheus`
3. `zabbix`
4. `vault`
5. `postgres`

**注意:** Dockerボリュームも削除されるため、データは完全に消失します。

---

## 📚 学習ポイント

### 1. Terragruntの利点

#### DRY原則の実践
- 共通設定を `terraform/terragrunt.hcl` に集約
- 各サービスは差分のみ定義

#### 依存関係の自動解決
```hcl
dependency "postgres" {
  config_path = "../postgres"
}
```
→ Zabbixは自動的にPostgreSQLの起動を待機

#### 一括操作
```bash
terragrunt run-all apply  # 全サービスを正しい順序でデプロイ
terragrunt run-all destroy  # 依存関係を考慮して削除
```

---

### 2. Vaultとの連携（今後の拡張）

現在は環境変数に直接パスワードを記述していますが、本来は以下のように実装します:

#### ステップ1: Vaultにシークレットを保存

```bash
# Vault CLIでシークレットを保存
vault kv put secret/monitoring-lab/postgres \
  username=zabbix \
  password=super_secure_password
```

#### ステップ2: Terraformでシークレットを取得

```hcl
data "vault_kv_secret_v2" "postgres" {
  mount = "secret"
  name  = "monitoring-lab/postgres"
}

# 環境変数として注入
env = [
  "POSTGRES_USER=${data.vault_kv_secret_v2.postgres.data["username"]}",
  "POSTGRES_PASSWORD=${data.vault_kv_secret_v2.postgres.data["password"]}"
]
```

---

### 3. モジュールの再利用性

`docker_container` モジュールは汎用的に設計されているため、他のサービスも簡単に追加できます:

```hcl
# 例: Redisを追加する場合
services = {
  redis = {
    image         = "redis:alpine"
    internal_port = 6379
    external_port = 6379
    env           = []
    volumes       = [
      {
        source = "redis_data"
        target = "/data"
      }
    ]
  }
}
```

---

## 🛠️ トラブルシューティング

### コンテナが起動しない

```bash
# ログ確認
docker logs monitoring-lab-zbx_server

# ネットワーク確認
docker network inspect monitoring-lab-network

# ボリューム確認
docker volume ls | grep monitoring-lab
```

### Terraform/Terragruntコンテナに接続できない

```bash
# コンテナの状態確認
docker ps -a | grep monitoring-lab

# コンテナを再起動
docker-compose restart terraform terragrunt

# コンテナログ確認
docker logs monitoring-lab-terraform
docker logs monitoring-lab-terragrunt
```

### Terragruntがエラーで停止する

**コンテナ使用時:**
```bash
# Stateファイルのロック解除
scripts\tg.bat force-unlock <LOCK_ID>

# キャッシュクリア（コンテナ内）
docker exec -it monitoring-lab-terragrunt sh -c "rm -rf /workspace/terraform/envs/local/.terragrunt-cache"

# 再初期化
scripts\tg.bat init -reconfigure
```

**ローカルインストール時:**
```bash
# Stateファイルのロック解除
terragrunt force-unlock <LOCK_ID>

# キャッシュクリア
rm -rf .terragrunt-cache

# 再初期化
terragrunt init -reconfigure
```

### Prometheusがデータを収集しない

設定ファイルが未配置の可能性があります:

```bash
# 設定ファイルを手動配置
docker cp prometheus.yml monitoring-lab-prometheus:/etc/prometheus/

# 設定リロード
curl -X POST http://localhost:9090/-/reload
```

---

## 🔐 セキュリティに関する注意

このプロジェクトは **学習目的** のため、以下の設定は本番環境では使用しないでください:

- ❌ Vaultの開発モード（Root Token固定）
- ❌ パスワードのハードコーディング
- ❌ HTTPSなしの通信
- ❌ デフォルト認証情報の使用

### 本番環境への移行チェックリスト

- [ ] Vaultの開発モードを無効化
- [ ] TLS/SSL証明書の設定
- [ ] 強力なパスワードの設定
- [ ] ファイアウォールルールの設定
- [ ] Stateファイルのリモートバックエンド化（S3など）
- [ ] シークレットローテーションの実装

---

## 🐳 コンテナ使用の詳細

### コンテナ構成

このプロジェクトで起動されるコンテナ:

| コンテナ名 | イメージ | 用途 |
|-----------|---------|------|
| `monitoring-lab-terraform` | `hashicorp/terraform:latest` | Terraform CLI実行環境 |
| `monitoring-lab-terragrunt` | `alpine/terragrunt:latest` | Terragrunt CLI実行環境 |
| `monitoring-lab-vault-dev` | `hashicorp/vault:latest` | 開発用Vault（Root Token: root） |

### ヘルパースクリプト

#### Windows用

| スクリプト | 用途 |
|-----------|------|
| `scripts\container-setup.bat` | コンテナ環境の初期セットアップ |
| `scripts\tf.bat <command>` | Terraformコマンド実行 |
| `scripts\tg.bat <command>` | Terragruntコマンド実行 |

**使用例:**
```bash
# Terraformバージョン確認
scripts\tf.bat version

# Terragrunt初期化
cd terraform\envs\local
..\..\..\scripts\tg.bat run-all init

# デプロイ
..\..\..\scripts\tg.bat run-all apply
```

#### Linux/Mac用

| スクリプト | 用途 |
|-----------|------|
| `scripts/container-setup.sh` | コンテナ環境の初期セットアップ |
| `scripts/tf.sh <command>` | Terraformコマンド実行 |
| `scripts/tg.sh <command>` | Terragruntコマンド実行 |

**使用例:**
```bash
# Terraformバージョン確認
./scripts/tf.sh version

# Terragrunt初期化
cd terraform/envs/local
../../../scripts/tg.sh run-all init

# デプロイ
../../../scripts/tg.sh run-all apply
```

### コンテナシェルへのアクセス

デバッグやファイル操作が必要な場合、コンテナ内に直接入ることができます:

```bash
# コンテナが起動していない場合は、まず起動
docker-compose up -d

# または特定コンテナのみ起動
docker-compose up -d terraform

# コンテナの状態確認
docker-compose ps

# Terraformコンテナに接続
docker exec -it monitoring-lab-terraform sh

# Terragruntコンテナに接続
docker exec -it monitoring-lab-terragrunt sh

# Vaultコンテナに接続
docker exec -it monitoring-lab-vault-dev sh
```

### コンテナの管理

```bash
# コンテナ起動
docker-compose up -d

# 特定コンテナのみ起動
docker-compose up -d terraform

# コンテナ停止
docker-compose stop

# コンテナ削除（ボリュームは保持）
docker-compose down

# コンテナ＋ボリューム削除
docker-compose down -v

# ログ確認
docker-compose logs terraform
docker-compose logs -f terragrunt  # リアルタイム表示
```

---

## 📖 参考資料

- [Terraform公式ドキュメント](https://www.terraform.io/docs)
- [Terragrunt公式ドキュメント](https://terragrunt.gruntwork.io/docs/)
- [HashiCorp Vault公式ドキュメント](https://www.vaultproject.io/docs)
- [Zabbix公式ドキュメント](https://www.zabbix.com/documentation)
- [Prometheus公式ドキュメント](https://prometheus.io/docs)
- [Grafana公式ドキュメント](https://grafana.com/docs)
- [Docker Compose公式ドキュメント](https://docs.docker.com/compose/)

---

## 💡 今後の拡張案

1. **Vault連携の完全実装**
   - すべてのパスワードをVaultから取得
   - Dynamic Secretsの活用

2. **監視対象の追加**
   - Node Exporter（ホストメトリクス）
   - cAdvisor（コンテナメトリクス）

3. **アラート設定**
   - Prometheus Alertmanagerのデプロイ
   - Grafana Alertingの設定

4. **CI/CD統合**
   - GitHub ActionsでTerragruntを自動実行
   - Drift検出の自動化

5. **本番環境構成**
   - 複数環境対応（dev/staging/prod）
   - リモートStateバックエンド（S3 + DynamoDB）

---

## 🤝 コントリビューション

このプロジェクトは個人学習用ですが、改善提案は歓迎します！

---

## 📄 ライセンス

MIT License

---

## 📞 お問い合わせ

質問や提案がある場合は、Issueを作成してください。

---

**Happy Learning! 🎓**
