# ==========================================
# Vault Secret Management Module
# ==========================================
# このモジュールは、HashiCorp VaultのKV Secrets Engine v2を使用して
# 機密情報を安全に管理するためのモジュールです。

# ==========================================
# KV Secret Engine v2の有効化
# ==========================================
# Vault開発モードでは "secret/" マウントが自動で有効化されているが、
# 本番環境では明示的に有効化する必要がある
resource "vault_mount" "kv_v2" {
  path        = var.mount_path
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine for ${var.project_name}"

  # 既に存在する場合はインポートするため、エラーを無視
  lifecycle {
    ignore_changes = [options]
  }
}

# ==========================================
# Database Credentials (Zabbix PostgreSQL用)
# ==========================================
# ZabbixがPostgreSQLに接続する際の認証情報を保存
resource "vault_kv_secret_v2" "db_credentials" {
  mount = vault_mount.kv_v2.path
  name  = "${var.project_name}/postgres"

  data_json = jsonencode({
    username = var.db_username
    password = var.db_password
    database = var.db_name
    host     = var.db_host
  })

  # シークレットのバージョニング設定
  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      purpose    = "zabbix-database-credentials"
    }
  }
}

# ==========================================
# Grafana Admin Credentials
# ==========================================
# Grafanaの管理者アカウント情報を保存
resource "vault_kv_secret_v2" "grafana_admin" {
  mount = vault_mount.kv_v2.path
  name  = "${var.project_name}/grafana"

  data_json = jsonencode({
    admin_user     = var.grafana_admin_user
    admin_password = var.grafana_admin_password
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      purpose    = "grafana-admin-credentials"
    }
  }
}

# ==========================================
# Alertmanager Slack Webhook URL
# ==========================================
resource "vault_kv_secret_v2" "alertmanager_slack" {
  mount = vault_mount.kv_v2.path
  name  = "${var.project_name}/alertmanager"

  data_json = jsonencode({
    slack_webhook_url = var.alertmanager_slack_webhook_url
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      purpose    = "alertmanager-slack-notification"
    }
  }
}

# ==========================================
# Vault Policy for Applications
# ==========================================
# アプリケーションがシークレットを読み取るためのポリシー
resource "vault_policy" "app_read_policy" {
  name = "${var.project_name}-app-read"

  policy = <<EOT
# PostgreSQL認証情報の読み取り権限
path "${vault_mount.kv_v2.path}/data/${var.project_name}/postgres" {
  capabilities = ["read"]
}

# Grafana認証情報の読み取り権限
path "${vault_mount.kv_v2.path}/data/${var.project_name}/grafana" {
  capabilities = ["read"]
}

# Alertmanager Webhook URLの読み取り権限
path "${vault_mount.kv_v2.path}/data/${var.project_name}/alertmanager" {
  capabilities = ["read"]
}

# メタデータの読み取り権限
path "${vault_mount.kv_v2.path}/metadata/${var.project_name}/*" {
  capabilities = ["list", "read"]
}
EOT
}
