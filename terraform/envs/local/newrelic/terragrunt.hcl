# ==========================================
# New Relic Infrastructure Agent Configuration
# ==========================================
# リモートDockerホストのシステムメトリクスとコンテナ監視を行う
# New Relic Infrastructure Agentの設定

# ----- 親設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- Terraformモジュールの指定 -----
terraform {
  source = "../../../modules/docker_container"
}

# ----- 依存関係 -----
# New Relicはホストネットワークを使用するため、
# monitoring-lab-networkには接続しないが、
# 他のサービスと共存するためにnetworkが存在することを確認
dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}

# ----- サービス固有の変数 -----
inputs = {
  # network_mode="host"の場合、実際にはnetwork_nameは使用されない
  # しかし、モジュールの変数定義上必須なので指定
  network_name = dependency.network.outputs.network_name

  # New Relicには永続ボリュームは不要
  volumes = []

  # New Relic Infrastructure Agentサービスの定義
  services = {
    newrelic-infra = {
      # New Relic Infrastructure Agent公式イメージ
      image = "newrelic/infrastructure:latest"

      # network_mode="host"のため、これらのポートは実際には使用されない
      # しかし、モジュールの変数定義上必須なので、ダミー値を設定
      internal_port = 0
      external_port = 0

      # 特権モード: ホストのシステムメトリクスにアクセスするために必須
      privileged = true

      # ホストネットワークモード: ホストレベルの監視に推奨
      network_mode = "host"

      # Cgroup Namespaceモード: cgroup v2でホストのcgroupにアクセスするために必須
      cgroupns_mode = "host"

      # コマンド引数設定（デフォルトのまま）
      command = []

      # 環境変数設定
      env = [
        # New Relic License Key（必須）
        # 環境変数から取得: .envファイルに NEW_RELIC_LICENSE_KEY を設定
        "NRIA_LICENSE_KEY=${get_env("NEW_RELIC_LICENSE_KEY", "YOUR_LICENSE_KEY_HERE")}",

        # Infrastructure Agent表示名（オプション）
        "NRIA_DISPLAY_NAME=monitoring-lab-docker-host",

        # ログレベル（オプション: debug, info, warn, error）
        "NRIA_LOG_LEVEL=info",

        # Docker統合を有効化（重要！）
        "NRIA_ENABLE_PROCESS_METRICS=true",

        # Docker統合のフィーチャーフラグを有効化
        "NRIA_FEATURE_docker_enabled=true",

        # Verbose mode（詳細ログ）
        "NRIA_VERBOSE=0"
      ]

      # ボリュームマウント設定（空）
      volumes = []

      # Bind マウント設定（ホストのシステム情報にアクセス）
      bind_mounts = [
        # Dockerソケット（コンテナ監視に必須）
        {
          source    = "/var/run/docker.sock"
          target    = "/var/run/docker.sock"
          read_only = true
        },
        # システムファイルシステム情報
        {
          source    = "/sys"
          target    = "/host/sys"
          read_only = true
        },
        # システム設定ファイル
        {
          source    = "/etc"
          target    = "/host/etc"
          read_only = true
        },
        # プロセス情報
        {
          source    = "/proc"
          target    = "/host/proc"
          read_only = true
        },
        # ログファイル（オプション）
        {
          source    = "/var/log"
          target    = "/host/var/log"
          read_only = true
        }
      ]
    }
  }
}

# ----- デプロイ後の確認方法 -----
# 1. コンテナの起動確認:
#    docker ps | grep newrelic-infra
#
# 2. ログ確認:
#    docker logs monitoring-lab-newrelic-infra
#
# 3. New Relic UIでの確認:
#    https://one.newrelic.com/infrastructure
#    → Hostsタブで "monitoring-lab-docker-host" が表示されることを確認
#
# 4. メトリクスの確認:
#    https://one.newrelic.com/infrastructure/hosts/{host_id}
#    → CPU、メモリ、ディスク、ネットワークのメトリクスが収集されていることを確認
#
# 5. Dockerコンテナの監視:
#    https://one.newrelic.com/infrastructure/docker
#    → 監視基盤のコンテナ（Zabbix、Prometheus、Grafana等）が表示されることを確認

# ----- トラブルシューティング -----
# License Keyエラーが出る場合:
#   → .env ファイルに NEW_RELIC_LICENSE_KEY が正しく設定されているか確認
#   → License Keyは https://one.newrelic.com/admin-portal/api-keys/home から取得
#
# コンテナが起動しない場合:
#   → docker logs monitoring-lab-newrelic-infra でエラーを確認
#   → privileged権限が必要なため、Dockerホストが対応しているか確認
#
# メトリクスが表示されない場合:
#   → コンテナログでエラーがないか確認
#   → New Relic UIの接続状態を確認（5-10分待つ必要がある場合あり）
