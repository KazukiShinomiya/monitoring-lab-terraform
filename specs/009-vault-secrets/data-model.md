# Data Model: Vault シークレット管理 Step 1

**Branch**: `009-vault-secrets`
**Date**: 2026-03-16

---

## Vault KV v2 シークレット構造

### マウントポイント
```
secret/  (KV v2 エンジン - dev モードでデフォルト有効)
└── monitoring-lab/
    ├── postgres          (既存: DB認証情報)
    ├── grafana           (既存: Grafana管理者認証情報)
    └── alertmanager      (新規: Alertmanager 通知設定)
```

### alertmanager シークレット

| フィールド | キー | 型 | 説明 |
|-----------|-----|-----|------|
| Slack Webhook URL | `slack_webhook_url` | string | Slack Incoming Webhook URL |

**Vault パス**: `secret/data/monitoring-lab/alertmanager`
**読み取りポリシー**: `monitoring-lab-app-read`
**最大バージョン**: 5

---

## Terraform リソースモデル

### vault_secret モジュールの拡張

```
vault_mount.kv_v2
  └── vault_kv_secret_v2.db_credentials      (既存)
  └── vault_kv_secret_v2.grafana_admin       (既存)
  └── vault_kv_secret_v2.alertmanager_slack  (新規)

vault_policy.app_read_policy                  (既存 → 更新: alertmanager パスを追加)
```

### 新規変数

| 変数名 | 型 | sensitive | デフォルト | 説明 |
|--------|-----|-----------|-----------|------|
| `alertmanager_slack_webhook_url` | string | true | (なし) | Slack Incoming Webhook URL |

### 新規出力

| 出力名 | 値 | 説明 |
|--------|-----|------|
| `alertmanager_secret_path` | `vault_kv_secret_v2.alertmanager_slack.path` | Alertmanager シークレットのパス |

---

## vault-secrets Workspace 構成

```
terraform/envs/local/vault-secrets/
└── terragrunt.hcl          (新規)
    ├── include "root"       ← root.hcl 継承
    ├── source: vault_secret module
    └── inputs:
        ├── vault_address     = "http://10.0.0.220:8200"
        ├── vault_token       = get_env("VAULT_TOKEN", "root")
        ├── skip_tls_verify   = true
        ├── project_name      = "monitoring-lab"
        ├── mount_path        = "secret"
        ├── db_password       = get_env("POSTGRES_PASSWORD")
        ├── grafana_admin_password = get_env("GRAFANA_ADMIN_PASSWORD")
        └── alertmanager_slack_webhook_url = get_env("SLACK_WEBHOOK_URL")
```

**依存関係**: vault コンテナが稼働していること（network は不要: vault provider は HTTP API 経由）

---

## sync-config.sh データフロー

```
sync_alertmanager() の処理フロー:

1. VAULT_ADDR (デフォルト: http://10.0.0.220:8200) を設定
2. VAULT_TOKEN (デフォルト: root) を設定
3. Vault HTTP API を curl で呼び出す
   GET /v1/secret/data/monitoring-lab/alertmanager
4. jq で .data.data.slack_webhook_url を抽出
5. 取得失敗時: .env の SLACK_WEBHOOK_URL にフォールバック
6. 両方未設定: エラーで終了
7. 取得成功: sed で alertmanager.yml を置換 → scp → curl reload
```

---

## .env.example 変更

```bash
# Vault 接続設定（Step 1 から使用）
VAULT_ADDR=http://10.0.0.220:8200
VAULT_TOKEN=root  # dev モード固定値、本番化時は変更すること

# Slack Webhook URL（Vault 未使用時のフォールバック。Vault 設定後は不要）
# SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx/yyy/zzz
```
