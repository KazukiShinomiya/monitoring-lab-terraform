# ==========================================
# VictoriaMetrics Service Configuration
# ==========================================
# Prometheus メトリクスの長期保存バックエンド
# remote_write で全メトリクスを受信・12ヶ月保持

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

  # 永続ボリュームの定義（メトリクスデータ長期保存用）
  volumes = [
    "vm_data"
  ]

  # VictoriaMetrics サービスの定義
  services = {
    victoriametrics = {
      # VictoriaMetrics シングルノード バージョン固定
      # stable タグは存在しないため、latest 回避で特定バージョンにピン
      image = "victoriametrics/victoria-metrics:v1.140.0"

      # HTTP API / remote_write 受信 / Prometheus 互換クエリ / /metrics
      internal_port = 8428
      external_port = 8428

      # CLI 引数で保持期間とストレージパスを設定（設定ファイル不要）
      command = [
        "-retentionPeriod=12",                       # 12ヶ月保持 (FR-002: 365日以上)
        "-storageDataPath=/victoria-metrics-data"    # ボリュームマウント先と一致
      ]

      # 環境変数設定（不要）
      env = []

      # ボリュームマウント設定（メトリクスデータ永続化）
      volumes = [
        {
          source = "vm_data"
          target = "/victoria-metrics-data"
        }
      ]

      # Bind マウント不要（設定ファイルなし、CLI 引数で完結）
      bind_mounts = []
    }
  }
}
