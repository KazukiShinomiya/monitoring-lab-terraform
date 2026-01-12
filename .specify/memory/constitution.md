# Monitoring Lab Constitution

## Core Principles

### I. Infrastructure as Code (IaC) - NON-NEGOTIABLE
すべてのインフラリソースはコードで管理する。手動での変更は禁止。
- Terraform/Terragruntによる宣言的な定義
- Git管理によるバージョン管理と変更履歴の追跡
- State管理はHCP Terraform（リモートバックエンド）を使用
- 変更は必ず`plan` → レビュー → `apply`のフローを経る

### II. セキュリティファースト（段階的アプローチ）
学習用プロジェクトだが、本番移行を見据えたセキュリティ設計を段階的に導入。
- Phase 1-2: 基本構築（開発モード、平文パスワード許容）
- Phase 3-4: セキュリティ強化（Vault本番モード、TLS/SSL）
- Phase 5: 本番化準備（強力な認証、ネットワーク分離）
- `.env`ファイルは絶対にGitコミットしない（`.gitignore`で保護）
- 機密情報はVaultで管理（将来的に100%移行）

### III. ドキュメント駆動開発
仕様とドキュメントを実装と同等に重視する。
- `.specify/memory/`に仕様・計画・タスクを記録
- `CLAUDE.md`にプロジェクト概要とガイドラインを維持
- `SESSION_STATE.md`でセッション状態を追跡
- すべての変更は目的と理由を明記

### IV. モジュール化とDRY原則
再利用可能なモジュールを作成し、重複を排除する。
- 共通設定は`terraform/root.hcl`に集約
- サービス固有設定のみ`terraform/envs/local/*/terragrunt.hcl`に記述
- `terraform/modules/`に再利用可能なモジュールを配置
- 依存関係は明示的に`dependency`ブロックで定義

### V. 監視の可観測性（Self-Monitoring）
監視基盤自体も監視対象とする。
- Zabbix Agent2でZabbix Server自身を監視
- Prometheusでコンテナメトリクスを収集
- Grafanaで統合ダッシュボードを構築
- ログとメトリクスの永続化を考慮

## Technology Stack Constraints

### 必須技術スタック
- **IaC**: Terraform 1.x + Terragrunt 0.x
- **Container Runtime**: Docker Engine（WSL2経由）
- **State Backend**: HCP Terraform (app.terraform.io)
- **Secrets Management**: HashiCorp Vault
- **監視**: Zabbix + Prometheus + Grafana + New Relic

### 環境構成
- **開発環境**: WSL2 (Ubuntu) + Docker Compose
- **実行環境**: リモートDockerホスト (10.0.0.220)
- **SSH接続**: Ed25519鍵認証（パスワード認証禁止）

### 禁止事項
- Docker Desktopの使用（WSL2のDocker Engineを使用）
- Stateファイルのローカル管理（HCP Terraform必須）
- 手動でのコンテナ起動・停止（すべてTerraform経由）

## Development Workflow

### Spec-Driven Development Process
1. **Specify** - `.specify/memory/specs/`に仕様を作成
2. **Plan** - `.specify/memory/plans/`に実装計画を作成
3. **Tasks** - `.specify/memory/tasks/`にタスクを分解
4. **Implement** - コードを実装
5. **Validate** - `terragrunt plan`で差分なしを確認

### Phase-Based Progression
- **Phase 0**: 環境準備（完了）
- **Phase 1**: 基本インフラ構築（完了）
- **Phase 2**: HCP Terraform移行（完了）
- **Phase 2.5**: Spec Kit導入（進行中）
- **Phase 3**: 監視機能拡充（次回）
- **Phase 4**: 運用改善
- **Phase 5**: 本番化準備

### Quality Gates
- すべての変更は`terragrunt plan`で差分を確認
- HCP Terraformで全Workspaceの状態を追跡
- セッション記録を`SESSION_STATE.md`に残す
- 重要なマイルストーンはGitコミット

## Observability & Monitoring Standards

### 監視対象
- **SwitchBot温湿度計**: Zabbix External Check（4台）
- **Dockerコンテナ**: New Relic Docker統合（8台）
- **ホストOS**: New Relic Infrastructure Agent
- **Zabbix自身**: Zabbix Agent2による自己監視

### メトリクス収集
- Prometheusで15秒間隔でスクレイプ
- データ保持期間: 15日間（初期設定）
- Grafanaで統合ダッシュボード提供

### ログ管理
- コンテナログは`docker logs`で確認可能
- 重要なイベントはセッション記録に記載

## Governance

### 憲法の優先順位
この憲法はすべてのコーディング規約・慣習に優先する。
- 原則に反する変更は拒否される
- 例外が必要な場合は憲法の改訂を検討

### 改訂プロセス
1. 変更の必要性を`.specify/memory/`に文書化
2. 影響範囲を分析
3. 移行計画を作成
4. 改訂を実施し、バージョンアップ

### コンプライアンス
- すべての変更はこの憲法への準拠を確認
- Spec-Driven Developmentのプロセスを遵守
- セッション間の継続性を`SESSION_STATE.md`で維持

---

**Version**: 1.0.0
**Ratified**: 2026-01-01
**Last Amended**: 2026-01-01
**Project**: Monitoring Lab - オブザーバビリティ基盤学習プロジェクト
