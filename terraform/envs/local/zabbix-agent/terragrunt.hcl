# ==========================================
# Zabbix Agent2 Configuration
# ==========================================
# Zabbix Server自身を監視するためのAgent2設定

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

# Zabbix Serverが先に起動している必要がある
dependency "zabbix" {
  config_path = "../zabbix"

  # Zabbix Serverが起動するまで待機
  mock_outputs = {
    container_ids = {}
  }
}

# ----- サービス固有の変数 -----
inputs = {
  network_name = dependency.network.outputs.network_name

  # 永続ボリュームの定義
  volumes = []

  # Zabbix Agent2サービスの定義
  services = {
    # ----- Zabbix Agent2 -----
    # Zabbix Serverを監視するエージェント
    zbx_agent = {
      # Zabbix Agent2公式イメージ（バージョン固定で再現性を確保）
      image = "zabbix/zabbix-agent2:alpine-7.4.3"

      # Zabbix Agent2のデフォルトポート
      internal_port = 10050
      external_port = 10050  # Zabbix Serverからの接続用

      # 環境変数設定
      env = [
        # Zabbix Server接続設定（Passive checks用のみ）
        "ZBX_PASSIVE_ALLOW=true",           # Passive checksを許可
        "ZBX_PASSIVESERVERS=zbx_server",    # Passive checksを許可するサーバー

        # Active checksは無効化（Server重複エラー回避）
        "ZBX_ACTIVE_ALLOW=false",           # Active checksを無効化

        # Agent自身の設定
        "ZBX_HOSTNAME=Zabbix server",       # Zabbix Web UIで設定されているホスト名と一致させる
        "ZBX_METADATA=Linux",               # メタデータ（Auto-registration用）

        # タイムゾーン
        "TZ=Asia/Tokyo",

        # デバッグレベル（本番環境では3に下げる）
        "ZBX_DEBUGLEVEL=3"
      ]

      # ボリュームマウント設定
      volumes = []

      # Bind マウント設定
      # ホストのシステム情報を取得するため、一部のパスをマウント
      bind_mounts = []
    }
  }
}

# ----- アクセス情報 -----
# Zabbix Agent2は10050ポートでZabbix Serverからの接続を待ち受けます
# Zabbix Web UIでホスト設定を以下のように変更してください:
#
# 1. Configuration > Hosts > "Zabbix server" を選択
# 2. Interfaces タブで:
#    - Type: Agent
#    - IP address: zbx_agent (DNSを使用)
#    - Port: 10050
# 3. Update をクリック
#
# これでZabbix ServerがZabbix Agent2からメトリクスを収集できるようになります。
