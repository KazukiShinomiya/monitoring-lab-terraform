# ==========================================
# Promtail Service Configuration
# ==========================================
# ログ収集エージェント Promtail の Terragrunt 定義
# Docker Socket 経由で全監視基盤コンテナのログを収集し Loki に転送する

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

# Loki が先に起動している必要がある
dependency "loki" {
  config_path = "../loki"
  mock_outputs = {
    container_ids = {}
  }
}

# ----- サービス固有の変数 -----
inputs = {
  network_name = dependency.network.outputs.network_name

  # 永続ボリュームの定義
  volumes = [
    "promtail_positions"  # positions.yaml（読み取り済みログ位置）を永続化
  ]

  # Promtail サービスの定義
  services = {
    promtail = {
      # Promtail 公式イメージ（バージョン固定で再現性を確保）
      # 注: Promtail は Loki の版番号に追従しない（メンテナンスモード／後継は Grafana Alloy）。
      #     現行リモート実態の 3.6.8 を固定（Loki は 3.7.1）。
      image = "grafana/promtail:3.6.8"

      # Promtail メトリクスポート（Prometheus スクレイプ用）
      internal_port = 9080
      external_port = 9080

      # 設定ファイルを引数で指定
      command = ["-config.file=/etc/promtail/promtail.yml"]

      # 環境変数設定（不要）
      env = []

      # ボリュームマウント設定（Docker Volume）
      # positions.yaml を永続化して重複収集を防ぐ（FR-008）
      volumes = [
        {
          source = "promtail_positions"
          target = "/tmp"
        }
      ]

      # Bind マウント設定（リモートサーバーのファイル）
      bind_mounts = [
        # Promtail 設定ファイル
        {
          source    = "/home/ubuntu/monitoring-lab/promtail/promtail.yml"
          target    = "/etc/promtail/promtail.yml"
          read_only = true
        },
        # Docker Socket（コンテナログの読み取りに必要）
        {
          source    = "/var/run/docker.sock"
          target    = "/var/run/docker.sock"
          read_only = true
        }
      ]
    }
  }
}
