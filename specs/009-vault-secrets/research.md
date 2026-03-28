# Research: Vault シークレット管理 Step 1

**Branch**: `009-vault-secrets`
**Date**: 2026-03-16

---

## Decision 1: Vault への書き込み方法

**Decision**: 既存の `vault_secret` モジュールを拡張し、新しい Terragrunt workspace `vault-secrets/` から呼び出す。

**Rationale**:
- `terraform/modules/vault_secret/` が既に `vault_kv_secret_v2` リソースパターンを確立している
- Constitution IV（モジュール化/DRY）: 既存モジュールで合理的に対応可能
- 新規 workspace を作ることで HCP Terraform に独立した State が作られ、vault コンテナ定義と分離できる

**Alternatives considered**:
- Vault CLI (`vault kv put`) を手動実行 → IaC 管理外になるため棄却（Constitution I 違反）
- 既存 `vault/` workspace に vault_secret モジュールを追加 → コンテナ定義とシークレット管理が混在し単一責任の原則に反するため棄却

---

## Decision 2: Vault アドレス（Terragrunt コンテナ視点）

**Decision**: `vault_address = "http://10.0.0.220:8200"` を使用する。

**Rationale**:
- Terragrunt はWSL2上のDockerコンテナ内で実行される
- Vault は 10.0.0.220 のリモートサーバー上のDockerコンテナで動作
- コンテナ内からの `localhost:8200` は Terragrunt コンテナ自身を指すため無効
- 現在の `terraform/envs/local/terragrunt.hcl` の `vault_address = "http://localhost:8200"` は未使用（vault_secret モジュールを呼ぶ workspace が存在しない）ため、今回は `vault-secrets/terragrunt.hcl` で正しいアドレスを設定する

**Alternatives considered**:
- Docker ネットワーク DNS で解決 → Terragrunt コンテナと Vault コンテナは異なる Docker host にあるため不可

---

## Decision 3: sync-config.sh での Vault 読み取り方法

**Decision**: Vault HTTP API を `curl` + `jq` で呼び出す。`.env` の `SLACK_WEBHOOK_URL` はフォールバックとして残す。

**Vault HTTP API エンドポイント（KV v2）**:
```
GET /v1/secret/data/monitoring-lab/alertmanager
Header: X-Vault-Token: root
Response: {"data": {"data": {"slack_webhook_url": "https://hooks.slack.com/..."}}}
```

**実装パターン**:
```bash
VAULT_ADDR="${VAULT_ADDR:-http://10.0.0.220:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
SLACK_WEBHOOK_URL=$(curl -sf \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/monitoring-lab/alertmanager" \
  | jq -r '.data.data.slack_webhook_url' 2>/dev/null)
```

**フォールバック戦略**:
1. Vault から取得を試みる
2. 取得失敗（Vault 停止・キー未設定）の場合、`.env` の `SLACK_WEBHOOK_URL` を使用
3. 両方とも未設定の場合はエラーで終了

**Rationale**: `jq` は WSL2 Ubuntu-24.04 に標準インストール済み。curl も標準利用可能。

**Alternatives considered**:
- Vault CLI (`vault kv get`) → Vault CLI の別途インストールが必要なため棄却
- Terraform data source での読み取り → apply 時にしか実行されず、設定ファイルを Terraform で管理することになり責務が混在するため棄却
- envoy/consul-template → オーバーエンジニアリングのため棄却

---

## Decision 4: vault_secret モジュールの拡張方法

**Decision**: `alertmanager_slack_webhook_url` 変数と `vault_kv_secret_v2.alertmanager_slack` リソースを追加する。ポリシーも更新して alertmanager パスへの読み取り権限を追加する。

**格納パス**: `secret/monitoring-lab/alertmanager`
**キー**: `slack_webhook_url`

**Rationale**:
- 既存の `db_credentials`、`grafana_admin` と同じパターンを踏襲
- `monitoring-lab/` プレフィックスはプロジェクト全体で統一されている

---

## Decision 5: vault_token の管理方法

**Decision**: `.env` の `VAULT_TOKEN` 環境変数から取得し、デフォルト値を `root`（dev モード固定値）とする。

**Rationale**:
- Vault dev モードでは Root Token が `root` に固定されている（`VAULT_DEV_ROOT_TOKEN_ID=root`）
- `.env.example` に `VAULT_TOKEN=root` をドキュメント化する
- 本番モード移行時（Step 2）には適切な AppRole 認証に置き換える予定

**Alternatives considered**:
- トークンをハードコード → `.env` ファイルを使うことで Gitには残らないが、コードにハードコードは避けるべき

---

## 未解決事項

なし。すべての設計上の疑問点は上記で解決済み。

---

## 変更対象ファイルのまとめ

| ファイル | 変更種別 | 内容 |
|---------|---------|------|
| `terraform/modules/vault_secret/main.tf` | 拡張 | alertmanager_slack リソース追加 + ポリシー更新 |
| `terraform/modules/vault_secret/variables.tf` | 拡張 | alertmanager_slack_webhook_url 変数追加 |
| `terraform/modules/vault_secret/outputs.tf` | 拡張 | alertmanager_secret_path 出力追加 |
| `terraform/envs/local/vault-secrets/terragrunt.hcl` | 新規 | vault_secret モジュールを呼び出す Workspace |
| `scripts/sync-config.sh` | 更新 | sync_alertmanager() に Vault API 読み取り追加 |
| `.env.example` | 更新 | VAULT_ADDR / VAULT_TOKEN 追加、SLACK_WEBHOOK_URL をオプション化 |
| `Taskfile.yml` | 更新 | vault:store / vault:check タスク追加（任意） |
