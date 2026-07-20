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
    extra_ports = optional(list(object({ # 追加のポート公開（オプション。例: otel-collector の 4318/OTLP-HTTP）
      internal = number
      external = number
    })), [])
    env            = list(string)     # 環境変数リスト（"KEY=VALUE"形式）
    command        = optional(list(string), []) # コンテナ起動コマンド（オプション）
    entrypoint     = optional(list(string), []) # エントリーポイント上書き（オプション）
    user           = optional(string, "")       # 実行ユーザー（オプション）
    privileged     = optional(bool, false)      # 特権モード（ホストアクセスが必要な場合、デフォルト: false）
    network_mode   = optional(string, "")       # ネットワークモード（host/bridge/none、デフォルト: bridge）
    stop_timeout   = optional(number, 0)        # 停止時に SIGKILL するまでの猶予秒数（0 = 未指定＝Docker既定の10秒）
    cgroupns_mode  = optional(string, "")       # Cgroup Namespaceモード（host/private、デフォルト: private）
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
