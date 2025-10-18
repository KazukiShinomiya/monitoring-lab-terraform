# ==========================================
# Outputs for Vault Secret Module
# ==========================================

output "mount_path" {
  description = "KV Secrets Engineのマウントパス"
  value       = vault_mount.kv_v2.path
}

output "db_secret_path" {
  description = "Database認証情報のシークレットパス"
  value       = vault_kv_secret_v2.db_credentials.path
}

output "grafana_secret_path" {
  description = "Grafana認証情報のシークレットパス"
  value       = vault_kv_secret_v2.grafana_admin.path
}

output "app_policy_name" {
  description = "アプリケーション用ポリシー名"
  value       = vault_policy.app_read_policy.name
}

output "db_credentials_version" {
  description = "Database認証情報の現在のバージョン"
  value       = vault_kv_secret_v2.db_credentials.data["version"]
}
