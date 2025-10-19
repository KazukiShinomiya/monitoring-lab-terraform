# ==========================================
# Network Module - Variables
# ==========================================

variable "project_name" {
  description = "プロジェクト名"
  type        = string
}

variable "network_name" {
  description = "作成するDockerネットワークの名前"
  type        = string
}

variable "subnet" {
  description = "ネットワークのサブネット（CIDR形式）"
  type        = string
  default     = "172.28.0.0/16"
}

variable "gateway" {
  description = "ネットワークのゲートウェイIPアドレス"
  type        = string
  default     = "172.28.0.1"
}
