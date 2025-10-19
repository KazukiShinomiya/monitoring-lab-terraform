# ==========================================
# Outputs for Docker Container Module
# ==========================================

output "container_ids" {
  description = "作成されたコンテナIDのマップ（サービス名 -> コンテナID）"
  value       = { for k, v in docker_container.service : k => v.id }
}

output "container_names" {
  description = "作成されたコンテナ名のマップ（サービス名 -> コンテナ名）"
  value       = { for k, v in docker_container.service : k => v.name }
}

output "volume_names" {
  description = "作成されたボリューム名のマップ（論理名 -> 実際のボリューム名）"
  value       = { for k, v in docker_volume.data : k => v.name }
}
