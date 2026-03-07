# ==========================================
# SNMP Exporter Service Configuration
# ==========================================
# Yamaha RTX830 (10.0.0.1) および Synology NAS (10.0.0.200) の
# SNMPメトリクスをPrometheus形式に変換するエクスポーター
#
# アクセス情報:
#   Metrics: http://10.0.0.220:9116/snmp?target=<IP>&module=<module>&auth=monlab_v2
#   RTX830 例: http://10.0.0.220:9116/snmp?target=10.0.0.1&module=if_mib&auth=monlab_v2
#   Synology例: http://10.0.0.220:9116/snmp?target=10.0.0.200&module=synology&auth=monlab_v2
#
# HCP Terraform Workspace: monitoring-lab-local-snmp-exporter (自動作成)

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
    snmp-exporter = {
      # SNMP Exporter 公式イメージ
      image = "prom/snmp-exporter:latest"

      # SNMP Exporterのデフォルトポート
      internal_port = 9116
      external_port = 9116

      env = []

      # 特権モード不要（空文字列でデフォルト動作）
      cgroupns_mode = ""

      # Docker Volume 不要
      volumes = []

      # snmp.yml をリモートホストからコンテナへbind mount
      # リモートサーバー側のパス: /home/ubuntu/monitoring-lab/snmp/snmp.yml
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/snmp/snmp.yml"
          target    = "/etc/snmp_exporter/snmp.yml"
          read_only = true
        }
      ]
    }
  }
}
