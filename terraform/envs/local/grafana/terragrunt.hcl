# ==========================================
# Grafana Service Configuration
# ==========================================
# 可視化ダッシュボードを提供するGrafanaの設定

# ----- 親設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- Terraformモジュールの指定 -----
terraform {
  source = "../../../modules/docker_container"
}

# ----- 依存関係の定義 -----
# PrometheusとZabbixが先に起動している必要がある
dependency "prometheus" {
  config_path = "../prometheus"

  mock_outputs = {
    container_ids = {}
  }
}

dependency "zabbix" {
  config_path = "../zabbix"

  mock_outputs = {
    container_ids = {}
  }
}

# ----- サービス固有の変数 -----
inputs = {
  # 永続ボリュームの定義
  volumes = [
    "grafana_data"         # Grafanaのデータベース（SQLite）
  ]

  # Grafanaサービスの定義
  services = {
    grafana = {
      # Grafana公式イメージ（最新安定版）
      image = "grafana/grafana:latest"

      # GrafanaのデフォルトWebポート
      internal_port = 3000
      external_port = 3000  # Web UIアクセス用

      # 環境変数設定
      env = [
        "GF_SECURITY_ADMIN_USER=admin",
        "GF_SECURITY_ADMIN_PASSWORD=admin",
        "GF_SECURITY_ALLOW_EMBEDDING=true",
        "GF_AUTH_ANONYMOUS_ENABLED=false",
        "GF_SERVER_ROOT_URL=http://localhost:3000",
        "GF_SERVER_DOMAIN=localhost",
        "GF_DATABASE_TYPE=sqlite3",
        "GF_DATABASE_PATH=/var/lib/grafana/grafana.db",
        "GF_PATHS_PROVISIONING=/etc/grafana/provisioning",
        "GF_LOG_MODE=console",
        "GF_LOG_LEVEL=info",
        "GF_INSTALL_PLUGINS=alexanderzobnin-zabbix-app",
        "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/home.json"
      ]

      # ボリュームマウント設定（Docker Volume）
      volumes = [
        {
          source = "grafana_data"
          target = "/var/lib/grafana"  # データベース・プラグイン用
        }
      ]

      # Bind マウント設定（リモートサーバーのファイル）
      bind_mounts = [
        {
          source    = "/opt/monitoring-lab/grafana/provisioning"
          target    = "/etc/grafana/provisioning"
          read_only = true
        }
      ]
    }
  }
}

# ----- データソース自動プロビジョニング設定例 -----
# デプロイ後、以下の内容で datasources.yml を作成してください:
#
# ファイルパス: grafana_provisioning/datasources/datasources.yml
#
# apiVersion: 1
#
# datasources:
#   # Prometheusデータソース
#   - name: Prometheus
#     type: prometheus
#     access: proxy
#     url: http://prometheus:9090
#     isDefault: true
#     editable: true
#
#   # Zabbixデータソース（プラグイン必須）
#   - name: Zabbix
#     type: alexanderzobnin-zabbix-datasource
#     access: proxy
#     url: http://zbx_web:8080/api_jsonrpc.php
#     jsonData:
#       username: Admin
#       trends: true
#       cacheTTL: 60
#     secureJsonData:
#       password: zabbix  # TODO: Vault連携後に変更
#     editable: true
#
# ダッシュボード自動プロビジョニング設定例:
# ファイルパス: grafana_provisioning/dashboards/dashboards.yml
#
# apiVersion: 1
#
# providers:
#   - name: 'default'
#     orgId: 1
#     folder: ''
#     type: file
#     options:
#       path: /var/lib/grafana/dashboards
#
# アクセス情報:
# Web UI: http://localhost:3000
# デフォルト認証情報:
#   - ユーザー名: admin
#   - パスワード: admin
#
# 初回ログイン後は必ずパスワードを変更してください！
