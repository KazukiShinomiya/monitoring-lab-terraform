# ==========================================
# Variables for Vault Secret Module
# ==========================================

# ----- Vault接続設定 -----

variable "vault_address" {
  type        = string
  description = "Vaultサーバーのアドレス（例: http://localhost:8200）"
  default     = "http://localhost:8200"
}

variable "vault_token" {
  type        = string
  description = "Vaultの認証トークン（開発モードでは初期化時に表示される）"
  sensitive   = true
}

variable "skip_tls_verify" {
  type        = bool
  description = "TLS証明書の検証をスキップするか（開発環境のみtrue）"
  default     = true
}

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
