# ==========================================
# Prometheus Service Configuration
# ==========================================
# 時系列メトリクス収集・保存を行うPrometheusの設定

# ----- 親設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- Terraformモジュールの指定 -----
terraform {
  source = "../../../modules/docker_container"
}

# ----- サービス固有の変数 -----
inputs = {
  # 永続ボリュームの定義
  volumes = [
    "prometheus_data"   # 時系列データベース
  ]

  # Prometheusサービスの定義
  services = {
    prometheus = {
      # Prometheus公式イメージ
      image = "prom/prometheus:latest"

      # PrometheusのデフォルトWebポート
      internal_port = 9090
      external_port = 9090  # Web UI / APIアクセス用

      # コマンドライン引数設定
      command = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=30d",
        "--web.enable-lifecycle",
        "--web.enable-admin-api",
        "--web.external-url=http://localhost:9090"
      ]

      # 環境変数設定（空）
      env = []

      # ボリュームマウント設定（Docker Volume）
      volumes = [
        {
          source = "prometheus_data"
          target = "/prometheus"  # 時系列データベースの保存先
        }
      ]

      # Bind マウント設定（リモートサーバーのファイル）
      bind_mounts = [
        {
          source    = "/opt/monitoring-lab/prometheus/prometheus.yml"
          target    = "/etc/prometheus/prometheus.yml"
          read_only = true
        }
      ]
    }
  }
}

# ----- Prometheus設定ファイル例 -----
# デプロイ後、以下の内容で prometheus.yml を作成してください:
#
# global:
#   scrape_interval: 15s      # メトリクス収集間隔
#   evaluation_interval: 15s  # ルール評価間隔
#
# scrape_configs:
#   # Prometheus自身のメトリクス収集
#   - job_name: 'prometheus'
#     static_configs:
#       - targets: ['localhost:9090']
#
#   # Node Exporter（ホストメトリクス）
#   - job_name: 'node-exporter'
#     static_configs:
#       - targets: ['node-exporter:9100']
#
#   # Zabbix Serverメトリクス（オプション）
#   - job_name: 'zabbix'
#     static_configs:
#       - targets: ['zbx_server:10051']
#
# 設定ファイルをボリュームに配置する方法:
# 1. Prometheusコンテナを一時起動
# 2. docker cp でファイルをコピー
# 3. または、docker_container モジュールに upload 機能を追加
#
# アクセス情報:
# Web UI: http://localhost:9090
# API: http://localhost:9090/api/v1/query
