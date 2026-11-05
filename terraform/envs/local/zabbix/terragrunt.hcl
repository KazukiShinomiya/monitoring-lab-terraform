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
      # 公式イメージに Python を足した派生イメージ（config/zabbix/server/Dockerfile）
      # 本番ホストで scripts/build-zabbix-server.sh を実行してから apply する
      image = "zabbix-server-local:alpine-8.0.0"

      # Zabbix Serverのデフォルトポート
      internal_port = 10051
      external_port = 10051  # Zabbix AgentやZabbix Proxyからの接続用

      # 環境変数設定
      env = [
        "DB_SERVER_HOST=postgres",
        "DB_SERVER_PORT=5432",
        "POSTGRES_USER=zabbix",
        "POSTGRES_PASSWORD=${get_env("POSTGRES_PASSWORD", "")}",
        "POSTGRES_DB=zabbix",
        "ZBX_DB_NAME=zabbix",
        "ZBX_CACHESIZE=128M",
        "ZBX_HISTORYCACHESIZE=64M",
        "ZBX_TRENDCACHESIZE=32M",
        "ZBX_VALUECACHESIZE=128M",
        "ZBX_STARTPOLLERS=10",
        "ZBX_STARTPINGERS=5",
        "ZBX_STARTDISCOVERERS=3",
        "PHP_TZ=Asia/Tokyo",
        # 外部スクリプト用環境変数
        "SWITCHBOT_TOKEN=${get_env("SWITCHBOT_TOKEN", "YOUR_SWITCHBOT_TOKEN")}",
        "SWITCHBOT_SECRET=${get_env("SWITCHBOT_SECRET", "YOUR_SWITCHBOT_SECRET")}",
        "SWITCHBOT_TIMEOUT=10"
      ]

      # ボリュームマウント設定
      volumes = [
        {
          source = "zbx_server_data"
          target = "/var/lib/zabbix"  # Zabbixモジュール・スクリプト用
        }
      ]

      # Bind マウント設定
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/zabbix/scripts/externalscripts"
          target    = "/usr/lib/zabbix/externalscripts"
          read_only = true
        },
        {
          source    = "/home/ubuntu/monitoring-lab/zabbix/scripts/alertscripts"
          target    = "/usr/lib/zabbix/alertscripts"
          read_only = true
        }
      ]
    }

    # ----- Zabbix Web UI -----
    # ユーザーインターフェース
    zbx_web = {
      # Zabbix Web公式イメージ（Apache + PostgreSQL対応版 / バージョン固定で再現性を確保）
      image = "zabbix/zabbix-web-apache-pgsql:alpine-8.0.0"

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
        "POSTGRES_PASSWORD=${get_env("POSTGRES_PASSWORD", "")}",
        "POSTGRES_DB=zabbix",
        "ZBX_DB_NAME=zabbix",
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

    # ----- Zabbix MCP Server -----
    # AI エージェント向けの API。認証は利用者ごとの Zabbix API トークン（クライアント側で持つ）
    zbx_mcp = {
      image = "zabbix/zabbix-mcp-server:alpine-8.0.0"

      internal_port = 8443
      external_port = 8443

      # 証明書は本番ホストで scripts/zabbix-mcp-tls.sh を実行して作る（リポジトリには置かない）
      # 接続元の許可は ZBX_MCP_ALLOWEDIP で与える。未設定なら loopback のみで、外からは届かない
      # ツールは読み取りのみ。history_get / item_get / macro_get / interface_get / lld_get と書き込みは拒否
      env = [
        "ZBX_FRONTEND_URL=http://zbx_web:8080/api_jsonrpc.php",
        "ZBX_ALLOWEDIP=${get_env("ZBX_MCP_ALLOWEDIP", "127.0.0.1,::1")}",
        "ZBX_TLSACCEPT=cert",
        "ZBX_TLSCERTFILE=server.crt",
        "ZBX_TLSKEYFILE=server.key",
        "ZBX_ALLOWTOOL_REGEXP_0=^(hostgroup|templategroup|host|template|problem|maintenance|trigger)_get$",
        "ZBX_DENYTOOL_1=*"
      ]

      volumes = []

      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/zabbix/mcp-tls"
          target    = "/var/lib/zabbix/enc"
          read_only = true
        }
      ]
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
