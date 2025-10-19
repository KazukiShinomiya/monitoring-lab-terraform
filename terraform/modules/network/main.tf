# ==========================================
# Network Module
# ==========================================
# 監視基盤の共通ネットワークを作成・管理

resource "docker_network" "monitoring" {
  name   = var.network_name
  driver = "bridge"

  # IPアドレス範囲を明示的に指定
  ipam_config {
    subnet  = var.subnet
    gateway = var.gateway
  }
}
