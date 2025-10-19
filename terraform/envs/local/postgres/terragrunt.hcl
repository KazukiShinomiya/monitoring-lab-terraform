# ==========================================
# PostgreSQL Service Configuration
# ==========================================
# Zabbixのバックエンドデータベースとして使用するPostgreSQLの設定

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
  # ネットワーク名（networkサービスから取得）
  network_name = dependency.network.outputs.network_name

  # 永続ボリュームの定義
  volumes = [
    "postgres_data"  # PostgreSQLのデータディレクトリ用
  ]

  # PostgreSQLサービスの定義
  services = {
    postgres = {
      # PostgreSQL公式イメージ（Alpine版で軽量化）
      image = "postgres:15-alpine"

      # PostgreSQLのデフォルトポート
      internal_port = 5432
      external_port = 5432  # ホストからの直接接続用（開発時のみ）

      # 環境変数設定
      env = [
        # データベース名
        "POSTGRES_DB=zabbix",

        # ユーザー名
        "POSTGRES_USER=zabbix",

        # パスワード（本来はVaultから取得すべき）
        # TODO: Vault連携実装後に vault_kv_secret から取得するように変更
        "POSTGRES_PASSWORD=YOUR_POSTGRES_PASSWORD",

        # 文字エンコーディング（日本語対応）
        "POSTGRES_INITDB_ARGS=--encoding=UTF-8 --locale=C",

        # パフォーマンスチューニング（開発環境用）
        "POSTGRES_SHARED_BUFFERS=256MB",
        "POSTGRES_EFFECTIVE_CACHE_SIZE=1GB"
      ]

      # ボリュームマウント設定
      volumes = [
        {
          source = "postgres_data"          # 上記で定義したボリューム名
          target = "/var/lib/postgresql/data"  # PostgreSQLのデータディレクトリ
        }
      ]

      # Bind マウント設定
      bind_mounts = []
    }
  }
}
