# ==========================================
# Variables for Vault Secret Module
# ==========================================

# ----- マウント設定 -----

variable "mount_path" {
  type        = string
  description = "KV Secrets Engineのマウントパス"
  default     = "secret"
}

variable "project_name" {
  type        = string
  description = "プロジェクト名（シークレットパスのプレフィックスになる）"
}

# ----- Database認証情報 -----

variable "db_username" {
  type        = string
  description = "PostgreSQLのユーザー名"
  default     = "zabbix"
}

variable "db_password" {
  type        = string
  description = "PostgreSQLのパスワード"
  sensitive   = true
}

variable "db_name" {
  type        = string
  description = "PostgreSQLのデータベース名"
  default     = "zabbix"
}

variable "db_host" {
  type        = string
  description = "PostgreSQLのホスト名（Dockerネットワーク内）"
  default     = "postgres"
}

# ----- Alertmanager設定 -----

variable "alertmanager_slack_webhook_url" {
  type        = string
  description = "AlertmanagerのSlack Webhook URL"
  sensitive   = true
}

# ----- Grafana認証情報 -----

variable "grafana_admin_user" {
  type        = string
  description = "Grafanaの管理者ユーザー名"
  default     = "admin"
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafanaの管理者パスワード"
  sensitive   = true
}
