# Implementation Plan: Vault シークレット管理 Step 1

**Branch**: `009-vault-secrets` | **Date**: 2026-03-16 | **Spec**: [spec.md](./spec.md)

## Summary

Vault dev モードで稼働中の HashiCorp Vault に Alertmanager の Slack Webhook URL を格納し、`sync-config.sh` が `.env` ではなく Vault HTTP API から URL を取得するよう変更する。既存の `vault_secret` モジュールを拡張し、新規 Terragrunt workspace `vault-secrets/` から呼び出す。

## Technical Context

**Language/Version**: HCL (Terraform ≥ 1.0) + Bash
**Primary Dependencies**: hashicorp/vault provider ~> 4.0、curl、jq
**Storage**: Vault KV v2 (`secret/monitoring-lab/alertmanager`)
**Testing**: 手動検証（amtool check-config + Slack 通知確認）
**Target Platform**: WSL2 Ubuntu-24.04 + リモートホスト 10.0.0.220
**Project Type**: Infrastructure (IaC)
**Performance Goals**: sync-config.sh の実行時間 +5 秒以内（Vault API 呼び出し追加分）
**Constraints**: Vault dev モード（再起動でシークレット消失）、HTTP 通信（TLS なし）
**Scale/Scope**: 1 シークレット（slack_webhook_url）、1 新規 Terragrunt workspace

## Constitution Check

### I. Infrastructure as Code ✅

- vault_secret モジュール拡張 + 新規 Terragrunt workspace で IaC 管理
- Vault への手動書き込みは行わない（`terragrunt apply` のみ）
- HCP Terraform に State 保存（新規 workspace: `vault-secrets`）

### II. セキュリティファースト ✅

- Webhook URL を `.env` から Vault に移動することでセキュリティ向上
- Vault dev モード継続は学習段階での許容（Constitutionに明記済み）
- `vault_token` は sensitive 変数として扱い State には残らない（`sensitive = true`）

### III. ドキュメント駆動開発 ✅

- spec.md → plan.md → tasks.md の順序に従っている
- 設計上の意思決定は research.md に記録済み

### IV. モジュール化と DRY 原則 ✅

- 既存 `vault_secret` モジュールを拡張（新規モジュール不要）
- `docker_container` モジュールは使用しない（コンテナ追加なし）

### V. 自己監視の可観測性 ✅ (N/A)

- 新規コンテナを追加しないため監視設定追加は不要

## Project Structure

### Documentation (this feature)

```text
specs/009-vault-secrets/
├── plan.md              ← このファイル
├── spec.md              ← 機能仕様書
├── research.md          ← Phase 0 調査・意思決定
├── data-model.md        ← データ構造・変更対象
├── quickstart.md        ← 動作確認手順
├── contracts/
│   └── vault-alertmanager-secret.md  ← API/インターフェース定義
├── checklists/
│   └── requirements.md  ← 品質チェックリスト
└── tasks.md             ← Phase 2 出力（/speckit.tasks で生成）
```

### Source Code (変更対象)

```text
terraform/
├── modules/
│   └── vault_secret/
│       ├── main.tf          # alertmanager_slack リソース追加 + ポリシー更新
│       ├── variables.tf     # alertmanager_slack_webhook_url 変数追加
│       └── outputs.tf       # alertmanager_secret_path 出力追加
└── envs/
    └── local/
        └── vault-secrets/   # 新規 Workspace
            └── terragrunt.hcl

scripts/
└── sync-config.sh           # sync_alertmanager() に Vault 読み取り追加

.env.example                 # VAULT_ADDR / VAULT_TOKEN 追加
Taskfile.yml                 # vault:store / vault:check タスク追加（オプション）
```

## Implementation Phases

### Phase A: Terraform モジュール拡張

1. `variables.tf` に `alertmanager_slack_webhook_url` 変数を追加（sensitive）
2. `main.tf` に `vault_kv_secret_v2.alertmanager_slack` リソースを追加
3. `main.tf` の `vault_policy.app_read_policy` に alertmanager パスを追加
4. `outputs.tf` に `alertmanager_secret_path` を追加

### Phase B: Terragrunt Workspace 作成

1. `terraform/envs/local/vault-secrets/terragrunt.hcl` を作成
2. HCP Terraform に `vault-secrets` workspace を作成（手動）
3. `terragrunt init` → `plan` → `apply` を実行

### Phase C: sync-config.sh 更新

1. `sync_alertmanager()` に Vault HTTP API 呼び出しを追加
2. `.env` へのフォールバックロジックを実装
3. エラーハンドリング（Vault 停止時・シークレット未設定時）を追加

### Phase D: 設定ファイルと動作確認

1. `.env.example` を更新（`VAULT_ADDR` / `VAULT_TOKEN` 追加）
2. `Taskfile.yml` に Vault 関連タスクを追加（任意）
3. エンドツーエンド動作確認（amtool + Slack 通知）

## Complexity Tracking

違反なし。既存モジュールの拡張のみで対応可能。
