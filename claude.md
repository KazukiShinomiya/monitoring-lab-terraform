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

## 💬 コミュニケーションガイドライン

**必須**: 作業を実行する際は、以下のルールを厳守してください:

### 作業前の説明
すべてのツール実行（Bash、Edit、Read等）の**前に**、必ず以下を説明してください:
1. **何をしようとしているのか** - 目的を明確に
2. **なぜそれが必要なのか** - 理由を簡潔に
3. **何を確認するのか** - 期待する結果

**悪い例**:
```
（説明なしにいきなりBashコマンドを実行）
```

**良い例**:
```
SSH鍵がWSL2のホームディレクトリに正しく配置されているか確認します。
これはTerragruntコンテナがリモートサーバーに接続するために必要です。
id_rsaとid_rsa.pubの2つのファイルが存在し、適切な権限(600/644)が設定されていることを確認します。

（その後Bashコマンドを実行）
```

### コマンド実行後の報告
ツール実行後は、結果を解釈して報告してください:
- ✅ **成功した場合**: 何が確認できたか
- ❌ **失敗した場合**: 何が問題か、次にどうするか

### 段階的な説明
複数のステップがある場合:
1. 全体の流れを最初に説明
2. 各ステップの前に個別に説明
3. 各ステップ完了後に進捗を報告

**例**:
```
これから以下の3ステップでSSH接続を確認します:
1. WSL2側のSSH鍵の存在確認
2. コンテナ内へのSSH鍵コピー確認
3. リモートサーバーへの接続テスト

【ステップ1】WSL2側のSSH鍵を確認します...
（コマンド実行）
✅ SSH鍵が正しく配置されています。

【ステップ2】コンテナ内のSSH鍵を確認します...
（以下続く）
```

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
│   │   └── prometheus.yml         # Prometheusスクレイプ設定
│   └── grafana/
│       └── provisioning/
│           └── datasources/
│               └── datasources.yml # Grafanaデータソース自動設定
│
├── terraform/                      # IaC定義
│   ├── terragrunt.hcl             # ルート設定 (全環境共通)
│   ├── modules/                   # 再利用可能モジュール
│   │   ├── docker_container/     # Docker汎用モジュール
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── vault_secret/         # Vault統合モジュール
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── envs/                      # 環境別設定
│       └── local/                 # ローカル環境
│           ├── terragrunt.hcl    # 環境固有設定
│           ├── postgres/          # PostgreSQLコンテナ定義
│           ├── vault/             # Vaultコンテナ定義
│           ├── zabbix/            # Zabbix Server/Webコンテナ定義
│           ├── prometheus/        # Prometheusコンテナ定義
│           └── grafana/           # Grafanaコンテナ定義
│
└── scripts/                       # ヘルパースクリプト
    ├── container-setup.sh / .bat # 開発コンテナセットアップ
    ├── tf.sh / .bat              # Terraformコマンドラッパー
    └── tg.sh / .bat              # Terragruntコマンドラッパー
```

---

## 🎯 主要コンポーネント

### 監視基盤サービス

| サービス | イメージ | ポート | 用途 | 依存関係 |
|---------|---------|--------|------|---------|
| **PostgreSQL** | `postgres:15-alpine` | 5432 | Zabbixデータ永続化 | なし |
| **Vault** | `hashicorp/vault:latest` | 8200 | 機密情報管理 (開発モード) | なし |
| **Zabbix Server** | `zabbix/zabbix-server-pgsql:alpine-latest` | 10051 | 監視サーバー | PostgreSQL |
| **Zabbix Web** | `zabbix/zabbix-web-apache-pgsql:alpine-latest` | 8080 | WebUI | PostgreSQL, Zabbix Server |
| **Prometheus** | `prom/prometheus:latest` | 9090 | メトリクス収集 | なし |
| **Grafana** | `grafana/grafana:latest` | 3000 | ダッシュボード | Prometheus, Zabbix |

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
| Vault | http://localhost:8200 | Token: `root` |
| Zabbix | http://localhost:8080 | User: `Admin`, Pass: `zabbix` |
| Prometheus | http://localhost:9090 | 認証なし |
| Grafana | http://localhost:3000 | User: `admin`, Pass: `admin` |

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
