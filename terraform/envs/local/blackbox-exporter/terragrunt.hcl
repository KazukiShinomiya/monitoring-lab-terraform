# ==========================================
# Blackbox Exporter Service Configuration
# ==========================================
# HTTP の外形監視をPrometheus形式に変換するエクスポーター
# 現在の監視対象: Vault の開封状態（/v1/sys/health）
#
# アクセス情報:
#   Metrics: http://YOUR_SERVER_IP:9115/probe?target=<URL>&module=<module>
#   Vault 例: http://YOUR_SERVER_IP:9115/probe?target=https://vault:8200/v1/sys/health&module=vault_health
#
# HCP Terraform Workspace: monitoring-lab-local-blackbox-exporter (自動作成)

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

  # 永続ボリューム不要（ステートレス）
  volumes = []

  services = {
    blackbox-exporter = {
      # Blackbox Exporter 公式イメージ（バージョン固定で再現性を確保）
      image = "prom/blackbox-exporter:v0.28.0"

      # Blackbox Exporterのデフォルトポート
      internal_port = 9115
      external_port = 9115

      env = []

      # 特権モード不要（空文字列でデフォルト動作）
      cgroupns_mode = ""

      # Docker Volume 不要
      volumes = []

      # blackbox.yml をリモートホストからコンテナへbind mount
      # リモートサーバー側のパス: /home/ubuntu/monitoring-lab/blackbox/blackbox.yml
      # 注: apply より先に sync-config.sh blackbox で配備すること
      #     （ファイルが無いと Docker がディレクトリを作ってしまい起動に失敗する）
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/blackbox/blackbox.yml"
          target    = "/etc/blackbox_exporter/config.yml"
          read_only = true
        }
      ]
    }
  }
}
