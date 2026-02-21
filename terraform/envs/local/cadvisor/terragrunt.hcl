# ==========================================
# cAdvisor Service Configuration
# ==========================================
# コンテナリソースメトリクスを収集するcAdvisorの設定
# Prometheusからスクレイプされ、Grafanaで可視化される

# ----- 親設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- Terraformモジュールの指定 -----
terraform {
  source = "../../../modules/docker_container"
}

# ----- 依存関係 -----
dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}

# ----- サービス固有の変数 -----
inputs = {
  network_name = dependency.network.outputs.network_name

  # cAdvisorは永続ボリューム不要（ステートレス）
  volumes = []

  # cAdvisorサービスの定義
  services = {
    cadvisor = {
      # cAdvisor公式イメージ（Google Container Registry）
      image = "gcr.io/cadvisor/cadvisor:latest"

      # cAdvisorのデフォルトWebポート
      internal_port = 8080
      external_port = 8081  # 8080はZabbix Webが使用中

      # 環境変数設定（空）
      env = []

      # Cgroup Namespaceモード（cgroupメトリクス取得に必要）
      cgroupns_mode = "host"

      # ボリュームマウント設定（Docker Volume）- 不要
      volumes = []

      # Bind マウント設定（ホストのシステムファイル）
      bind_mounts = [
        {
          # Docker API ソケット（コンテナ情報取得に必須）
          source    = "/var/run/docker.sock"
          target    = "/var/run/docker.sock"
          read_only = true
        },
        {
          # システムメトリクス（CPU、メモリ等）
          source    = "/sys"
          target    = "/sys"
          read_only = true
        },
        {
          # Dockerデータディレクトリ（コンテナファイルシステム情報）
          source    = "/var/lib/docker"
          target    = "/var/lib/docker"
          read_only = true
        },
        {
          # ディスクI/O情報
          source    = "/dev/disk"
          target    = "/dev/disk"
          read_only = true
        }
      ]
    }
  }
}

# ----- cAdvisor メトリクス情報 -----
#
# アクセス情報:
#   Web UI: http://10.0.0.220:8081
#   Metrics: http://10.0.0.220:8081/metrics
#
# 主要なメトリクス:
#   - container_cpu_usage_seconds_total: CPU使用量
#   - container_memory_usage_bytes: メモリ使用量
#   - container_network_receive_bytes_total: ネットワーク受信
#   - container_network_transmit_bytes_total: ネットワーク送信
#   - container_fs_usage_bytes: ファイルシステム使用量
#
# Prometheus scrape_config 例:
#   - job_name: 'cadvisor'
#     static_configs:
#       - targets: ['cadvisor:8080']
#
