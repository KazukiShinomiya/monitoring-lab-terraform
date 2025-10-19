# ==========================================
# Zabbix Monitoring Service Configuration
# ==========================================
# Zabbix ServerとZabbix Web UIの設定

# ----- 親設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- Terraformモジュールの指定 -----
terraform {
  source = "../../../modules/docker_container"
}

# ----- 依存関係の定義 -----
dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}

# PostgreSQLが先に起動している必要がある
dependency "postgres" {
  config_path = "../postgres"

  # PostgreSQLが起動するまで待機
  mock_outputs = {
    container_ids = {}
  }
}

# ----- サービス固有の変数 -----
inputs = {
  network_name = dependency.network.outputs.network_name

  # 永続ボリュームの定義
  volumes = [
    "zbx_server_data",  # Zabbix Serverのデータディレクトリ
    "zbx_web_data"      # Zabbix Web UIのセッションデータ
  ]

  # Zabbixサービスの定義
  services = {
    # ----- Zabbix Server -----
    # メトリクス収集・アラート処理を行うバックエンド
    zbx_server = {
      # Zabbix Server公式イメージ（PostgreSQL対応版）
      image = "zabbix/zabbix-server-pgsql:alpine-latest"

      # Zabbix Serverのデフォルトポート
      internal_port = 10051
      external_port = 10051  # Zabbix AgentやZabbix Proxyからの接続用

      # 環境変数設定
      env = [
        "DB_SERVER_HOST=postgres",
        "DB_SERVER_PORT=5432",
        "POSTGRES_USER=zabbix",
        "POSTGRES_PASSWORD=zabbixpass",
        "POSTGRES_DB=zabbix",
        "ZBX_CACHESIZE=128M",
        "ZBX_HISTORYCACHESIZE=64M",
        "ZBX_TRENDCACHESIZE=32M",
        "ZBX_VALUECACHESIZE=128M",
        "ZBX_STARTPOLLERS=10",
        "ZBX_STARTPINGERS=5",
        "ZBX_STARTDISCOVERERS=3",
        "PHP_TZ=Asia/Tokyo"
      ]

      # ボリュームマウント設定
      volumes = [
        {
          source = "zbx_server_data"
          target = "/var/lib/zabbix"  # Zabbixモジュール・スクリプト用
        }
      ]

      # Bind マウント設定
      bind_mounts = []
    }

    # ----- Zabbix Web UI -----
    # ユーザーインターフェース
    zbx_web = {
      # Zabbix Web公式イメージ（Apache + PostgreSQL対応版）
      image = "zabbix/zabbix-web-apache-pgsql:alpine-latest"

      # WebサーバーのHTTPポート
      internal_port = 8080
      external_port = 8080  # ホストからのアクセス用

      # 環境変数設定
      env = [
        "ZBX_SERVER_HOST=zbx_server",
        "ZBX_SERVER_PORT=10051",
        "DB_SERVER_HOST=postgres",
        "DB_SERVER_PORT=5432",
        "POSTGRES_USER=zabbix",
        "POSTGRES_PASSWORD=zabbixpass",
        "POSTGRES_DB=zabbix",
        "PHP_TZ=Asia/Tokyo",
        "ZBX_SERVER_NAME=Monitoring Lab",
        "ZBX_MAXEXECUTIONTIME=600",
        "ZBX_MEMORYLIMIT=256M",
        "ZBX_POSTMAXSIZE=32M",
        "ZBX_UPLOADMAXFILESIZE=16M"
      ]

      # ボリュームマウント設定
      volumes = [
        {
          source = "zbx_web_data"
          target = "/etc/ssl/apache2"  # SSL証明書用（将来の拡張用）
        }
      ]

      # Bind マウント設定
      bind_mounts = []
    }
  }
}

# ----- アクセス情報 -----
# デプロイ後は以下のURLでアクセス可能:
# http://localhost:8080
#
# デフォルト認証情報:
# - ユーザー名: Admin
# - パスワード: zabbix
#
# 初回ログイン後は必ずパスワードを変更してください！
