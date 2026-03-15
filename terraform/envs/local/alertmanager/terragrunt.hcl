# ==========================================
# Alertmanager Service Configuration
# ==========================================
# Prometheus アラートを Slack に通知する Alertmanager の設定

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

  # ボリューム不要（Alertmanager はステートレス動作）
  volumes = []

  # Alertmanager サービスの定義
  services = {
    alertmanager = {
      # Alertmanager 公式イメージ
      image = "prom/alertmanager:latest"

      # Alertmanager のデフォルト WebUI / API ポート
      internal_port = 9093
      external_port = 9093

      # コマンドライン引数設定
      command = [
        "--config.file=/etc/alertmanager/alertmanager.yml",
        "--storage.path=/alertmanager",
        "--web.external-url=http://YOUR_SERVER_IP:9093"
      ]

      # 環境変数設定
      env = []

      # Docker Volume 不要
      volumes = []

      # Bind マウント設定（リモートサーバーの設定ファイル）
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/alertmanager/alertmanager.yml"
          target    = "/etc/alertmanager/alertmanager.yml"
          read_only = true
        }
      ]
    }
  }
}
