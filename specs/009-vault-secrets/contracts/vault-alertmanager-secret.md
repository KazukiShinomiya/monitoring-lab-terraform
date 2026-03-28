# Contract: Vault Alertmanager シークレット

**Branch**: `009-vault-secrets`
**Date**: 2026-03-16

---

## Vault KV v2 API

### シークレット書き込み（Terraform が実施）

```
PUT /v1/secret/data/monitoring-lab/alertmanager

Headers:
  X-Vault-Token: <VAULT_TOKEN>

Body:
  {
    "data": {
      "slack_webhook_url": "<SLACK_WEBHOOK_URL>"
    },
    "options": {
      "max_versions": 5
    }
  }

Response 200:
  {
    "data": {
      "created_time": "...",
      "version": 1
    }
  }
```

### シークレット読み取り（sync-config.sh が実施）

```
GET /v1/secret/data/monitoring-lab/alertmanager

Headers:
  X-Vault-Token: <VAULT_TOKEN>

Response 200:
  {
    "data": {
      "data": {
        "slack_webhook_url": "https://hooks.slack.com/services/xxx/yyy/zzz"
      },
      "metadata": {
        "version": 1
      }
    }
  }

Response 404:
  シークレットが存在しない → フォールバック処理へ

Response 403:
  トークン無効 → エラーで終了
```

---

## Terraform Module Interface

### vault_secret モジュール入力（拡張後）

| 変数 | 型 | 必須 | 説明 |
|------|-----|------|------|
| `vault_address` | string | ✅ | Vault API アドレス |
| `vault_token` | string (sensitive) | ✅ | 認証トークン |
| `skip_tls_verify` | bool | - | TLS スキップ（デフォルト: true） |
| `mount_path` | string | - | KV マウントパス（デフォルト: secret） |
| `project_name` | string | ✅ | プロジェクト名 |
| `db_password` | string (sensitive) | ✅ | DB パスワード |
| `grafana_admin_password` | string (sensitive) | ✅ | Grafana パスワード |
| `alertmanager_slack_webhook_url` | string (sensitive) | ✅ | Slack Webhook URL (**新規**) |

### vault_secret モジュール出力（拡張後）

| 出力 | 値 | 説明 |
|------|-----|------|
| `mount_path` | `secret` | KV マウントパス |
| `db_secret_path` | `monitoring-lab/postgres` | DB シークレットパス |
| `grafana_secret_path` | `monitoring-lab/grafana` | Grafana シークレットパス |
| `alertmanager_secret_path` | `monitoring-lab/alertmanager` | Alertmanager シークレットパス (**新規**) |
| `app_policy_name` | `monitoring-lab-app-read` | アプリ読み取りポリシー名 |

---

## sync-config.sh インターフェース変更

### 環境変数（追加）

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `VAULT_ADDR` | `http://YOUR_SERVER_IP:8200` | Vault API エンドポイント |
| `VAULT_TOKEN` | `root` | Vault 認証トークン |

### `sync_alertmanager()` の動作変更

**Before**:
- `SLACK_WEBHOOK_URL` が未設定 → エラー終了

**After**:
1. `VAULT_ADDR` の Vault から `slack_webhook_url` を取得
2. 取得失敗 → `SLACK_WEBHOOK_URL`（.env）にフォールバック
3. 両方未設定 → エラー終了（メッセージに Vault と .env の両方を案内）
