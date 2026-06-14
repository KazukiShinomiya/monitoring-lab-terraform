# ==========================================
# Loki Service Configuration
# ==========================================
# ログ集約サービス Loki の Terragrunt 定義

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

  # 永続ボリュームの定義
  volumes = [
    "loki_data"  # ログデータ・インデックス・コンパクタ用
  ]

  # Loki サービスの定義
  services = {
    loki = {
      # Loki 公式イメージ（バージョン固定で再現性を確保）
      image = "grafana/loki:3.7.1"

      # Loki デフォルト HTTP ポート
      internal_port = 3100
      external_port = 3100  # API・Grafana データソース用

      # 設定ファイルを引数で指定
      command = ["-config.file=/etc/loki/loki.yml"]

      # 環境変数設定（不要）
      env = []

      # ボリュームマウント設定（Docker Volume）
      volumes = [
        {
          source = "loki_data"
          target = "/loki"  # データ・インデックス・コンパクタの保存先
        }
      ]

      # Bind マウント設定（リモートサーバーのファイル）
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/loki/loki.yml"
          target    = "/etc/loki/loki.yml"
          read_only = true
        }
      ]
    }
  }
}
