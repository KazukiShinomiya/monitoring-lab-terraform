# ==========================================
# Variables for Docker Container Module
# ==========================================

variable "project_name" {
  type        = string
  description = "プロジェクト名（すべてのリソース名のプレフィックスになる）"

  validation {
    condition     = length(var.project_name) > 0
    error_message = "プロジェクト名は必須です"
  }
}

variable "network_name" {
  type        = string
  description = "接続するDockerネットワークの名前"
}

variable "volumes" {
  type        = list(string)
  description = "作成する永続ボリュームの名前リスト（例: ['zbx_server_data', 'grafana_data']）"
  default     = []
}

variable "services" {
  type = map(object({
    image          = string           # Dockerイメージ名（例: "zabbix/zabbix-server-pgsql:alpine-latest"）
    internal_port  = number           # コンテナ内部ポート（例: 10051）
    external_port  = number           # ホスト側公開ポート（例: 10051）
    env            = list(string)     # 環境変数リスト（"KEY=VALUE"形式）
    command        = optional(list(string), []) # コンテナ起動コマンド（オプション）
    volumes = list(object({
      source = string                 # ボリューム名（var.volumesで定義したもの）
      target = string                 # コンテナ内マウントパス（例: "/var/lib/zabbix"）
    }))
    bind_mounts = optional(list(object({
      source = string                 # ホスト側のパス（例: "/opt/monitoring-lab/prometheus/prometheus.yml"）
      target = string                 # コンテナ内マウントパス（例: "/etc/prometheus/prometheus.yml"）
      read_only = optional(bool, false) # 読み取り専用マウント（デフォルト: false）
    })), [])
  }))
  description = "デプロイするサービスの定義マップ"
  default     = {}
}
