<!--
  同期影響レポート
  ================
  バージョン変更: 0.0.0 (テンプレート) → 1.1.0
  バンプ理由: MINOR - 初期5原則の正式化(1.0.0) +
    MCP/AI自己成長基盤セクションの追加(1.1.0)

  変更された原則:
    - [PRINCIPLE_1_NAME] → I. Infrastructure as Code (IaC)
    - [PRINCIPLE_2_NAME] → II. セキュリティファースト
    - [PRINCIPLE_3_NAME] → III. ドキュメント駆動開発
    - [PRINCIPLE_4_NAME] → IV. モジュール化とDRY原則
    - [PRINCIPLE_5_NAME] → V. 自己監視の可観測性

  追加セクション:
    - 技術的制約（技術スタック、環境、State管理）
    - 開発ワークフロー（Speckit ADLCプロセス）
    - MCP/AI自己成長基盤（新構想、承認フロー）
    - ガバナンス（改訂手順、バージョニング、コンプライアンス）

  削除セクション: なし

  テンプレート影響:
    - .specify/templates/plan-template.md        ✅ 更新不要
      (Constitution Checkは動的プレースホルダー)
    - .specify/templates/spec-template.md         ✅ 更新不要
      (Constitution参照なし)
    - .specify/templates/tasks-template.md        ✅ 更新不要
      (Constitution参照なし)
    - .specify/templates/checklist-template.md    ✅ 更新不要
      (Constitution参照なし)
    - .specify/templates/agent-file-template.md   ✅ 更新不要
      (Constitution参照なし)

  保留事項: なし
-->

# Monitoring Lab Constitution

## 核心原則

### I. Infrastructure as Code (IaC) - 絶対原則

すべてのインフラ変更はTerraform/Terragruntで管理しなければならない。
リモートDocker環境（YOUR_SERVER_IP）への手動変更は禁止とする。
緊急復旧時のみ例外を認めるが、同一セッション内にIaCへ反映すること。

- すべてのリソースは `terraform/envs/local/` にTerragruntサービス定義
  として記述し、再利用可能モジュールを参照すること。
- apply作業の完了後、`terragrunt plan` が全ワークスペースで
  "No changes" を示すこと。
- StateはHCP Terraform（Organization: `YOUR_TF_ORG`）に保存
  すること。ローカルStateファイルの使用は禁止とする。
- すべての変更はバージョン管理上のdiffとして表現可能であること。

### II. セキュリティファースト（段階的アプローチ）

学習環境であっても、基本的なセキュリティ衛生を維持すること。
セキュリティ強化は一度にすべてではなく、計画的な段階で進める。

- シークレット（APIトークン、パスワード、ライセンスキー）は `.env` に
  格納し、Gitにコミットしてはならない。`.gitignore` に `.env` を
  含めること。
- Vault統合は段階的に進める。現在はdev-mode、将来的にproduction-mode
  へ移行する。各段階は実装前に文書化すること。
- デフォルト認証情報（例: Zabbix `Admin/zabbix`）は現在の学習段階
  では許容するが、技術的負債として追跡すること。
- AIが提案した変更の自動適用は禁止とする。すべての変更に人間の
  明示的な承認を要する（下記MCP/AIセクション参照）。

### III. ドキュメント駆動開発

実装は「仕様策定 → 計画 → タスク分解 → 実装」の順序に従うこと。
事前の仕様なしにコード変更を行ってはならない。

- Speckit ADLCプロセスを正式なワークフローとする:
  `specify → clarify → plan → tasks → analyze → checklist → implement`
- 機能実装の開始前に、仕様書を作成すること。
- 設計上の意思決定は、根拠と検討した代替案とともに
  該当するplanドキュメントに記録すること。
- セッション終了時に `.claude/SESSION_STATE.md` へ進捗を記録すること。

### IV. モジュール化とDRY原則

Terraformモジュールは再利用すること。共有モジュールで対応可能な
場合、コードの重複は禁止とする。

- すべてのコンテナ定義には `docker_container` モジュール
  （`terraform/modules/docker_container/`）を使用すること。
  インラインでの `docker_container` リソース定義は禁止とする。
- 新規モジュールの作成は、既存モジュールでは合理的に対応できない
  場合のみ許可する。その判断は文書化すること。
- 環境ごとに異なる設定は `terraform/envs/<env>/terragrunt.hcl` に、
  共通の設定は `terraform/root.hcl` に配置すること。

### V. 自己監視の可観測性（Self-Monitoring）

監視基盤自体を監視すること。監視スタックの盲点は許容しない。

- 本プロジェクトがデプロイするすべてのコンテナは、Prometheusの
  スクレイプ対象またはZabbixの監視対象（もしくは両方）とすること。
- すべての重要なサービスメトリクスに対してGrafanaダッシュボードを
  用意すること。
- サービスダウンおよびリソース逼迫に対するアラートルールを
  定義すること（Phase 3スコープ）。
- スタックに新しいサービスを追加する際は、同一タスク内で
  監視設定も含めること。

## 技術的制約

| 制約 | 値 |
|------|-----|
| IaCツール | Terraform + Terragrunt |
| コンテナランタイム | リモートホスト（YOUR_SERVER_IP）上のDocker Engine |
| 開発環境 | WSL2 (Ubuntu-24.04) on Windows 11 |
| Stateバックエンド | HCP Terraform (`YOUR_TF_ORG`) |
| 監視スタック | Prometheus, Zabbix, Grafana, cAdvisor |
| シークレット管理 | HashiCorp Vault（dev-mode、段階的にproductionへ移行） |
| データベース | PostgreSQL 15 (Alpine) |
| CI/CD | 未構築（Phase 4スコープ） |

## 開発ワークフロー

本プロジェクトは **Speckit ADLC**（Application Development Life Cycle）に従う:

```
/speckit.constitution  →  プロジェクト原則（本ファイル）
        ↓
/speckit.specify       →  機能仕様書（spec.md）
        ↓
/speckit.clarify       →  曖昧点の解消（Q&Aをspecに反映）
        ↓
/speckit.plan          →  実装計画（plan.md）
        ↓
/speckit.tasks         →  タスク分解（tasks.md）
        ↓
/speckit.analyze       →  成果物間の整合性チェック
        ↓
/speckit.checklist     →  実装前チェックリスト
        ↓
/speckit.implement     →  実行
```

- すべての非自明な機能は、少なくとも specify → plan → tasks を
  経由すること。
- 軽微な修正（タイポ、1行の設定変更等）はフルサイクルを省略して
  よいが、SESSION_STATE.mdへの記録は必須とする。

## MCP/AI自己成長基盤

本セクションは、AIを活用したインフラの自律的進化を可能にする
MCP（Model Context Protocol）統合の方針を定める。

### ビジョン

```
観測 → AI分析 → 改善提案 → 人間の承認 → 適用 → 効果測定
```

### 承認フロー（絶対原則）

AIが生成した変更の自動適用は一切禁止する。承認フローは緊急度に
応じて以下のように分岐する:

| 緊急度 | 例 | フロー |
|--------|-----|--------|
| 低 | リソース最適化、設定チューニング | PR作成 → レビュー → マージ → apply |
| 中 | メモリ逼迫の予兆 | PR作成 + 通知で注意喚起 |
| 高 | サービスダウン | 通知 + AI診断レポート（自動applyはしない） |

### MCP Serverスコープ（計画）

| 優先度 | MCP Server | 機能 |
|--------|-----------|------|
| 1 | Docker MCP | コンテナ操作、ログ取得、状態監視 |
| 2 | Prometheus MCP | PromQLクエリ、AIによる傾向分析 |
| 3 | Terragrunt MCP | plan/apply実行、設定の読み取り |

### 制約条件

- MCP Serverは読み取り中心・書き込み慎重の設計とすること。
  書き込み操作には人間の明示的な確認を必須とする。
- AI分析結果にはエビデンス（メトリクス、ログ、タイムスタンプ）を
  含めること。根拠のない提案は却下すること。
- AIが提案したすべての変更と、その承認/却下の結果を
  監査可能な形でログに記録すること。

## ガバナンス

- 本Constitutionはすべてのアドホックな慣行に優先する。
  ここに記載された原則と矛盾する慣行がある場合、
  Constitutionが優先される。
- 改訂には以下を要する:
  (1) 文書化された根拠
  (2) 仕様書/計画書/タスクへの下流影響のレビュー
  (3) セマンティックバージョニングに基づくバージョンバンプ
- バージョニングポリシー:
  - MAJOR: 原則の削除または後方互換性のない再定義
  - MINOR: 新しい原則やセクションの追加、または大幅な拡充
  - PATCH: 表現の明確化、タイポ修正、非意味的な改善
- すべての実装計画に「Constitution Check」ゲートを設け、
  作業開始前にすべての原則への準拠を検証すること。
- コンプライアンスレビュー: 新しい機能サイクルの開始時に
  本文書を再読し、原則が暗黙のうちに違反されていないか確認すること。

**Version**: 1.1.0 | **策定日**: 2026-01-01 | **最終改訂日**: 2026-02-21
