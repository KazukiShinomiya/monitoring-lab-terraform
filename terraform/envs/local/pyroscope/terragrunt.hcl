# ==========================================
# Grafana Pyroscope Service Configuration
# ==========================================
# 継続的プロファイリングバックエンド (LGTM+P スタックの P)
# Go サービスの pprof エンドポイントを pull スクレイプ → フレームグラフで可視化

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

  # プロファイルデータ永続化ボリューム（FR-004）
  volumes = [
    "pyroscope_data"
  ]

  services = {
    pyroscope = {
      # Grafana Pyroscope — シングルノードモード
      # 注意: latest 回避のためバージョン固定を推奨。必要に応じて更新すること
      image = "grafana/pyroscope:latest"

      # HTTP API / pprof 受信 / Prometheus 互換 /metrics (FR-001)
      internal_port = 4040
      external_port = 4040

      # config.yml で pull スクレイプ設定を読み込む
      command = [
        "--config.file=/etc/pyroscope/config.yml",
      ]

      env = []

      # プロファイルデータ永続化（FR-004）
      volumes = [
        {
          source = "pyroscope_data"
          target = "/data"
        }
      ]

      # スクレイプ設定をリモートサーバーのファイルから bind mount
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/pyroscope"
          target    = "/etc/pyroscope"
          read_only = true
        }
      ]
    }
  }
}
