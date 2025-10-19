# ==========================================
# Network Module - Outputs
# ==========================================

output "network_id" {
  description = "作成されたネットワークのID"
  value       = docker_network.monitoring.id
}

output "network_name" {
  description = "作成されたネットワークの名前"
  value       = docker_network.monitoring.name
}

output "subnet" {
  description = "ネットワークのサブネット"
  value       = var.subnet
}

output "gateway" {
  description = "ネットワークのゲートウェイ"
  value       = var.gateway
}
