# ==========================================
# Grafana Tempo Service Configuration
# ==========================================
# LGTM Stack の "T" — 分散トレーシングバックエンド
# single binary モード、local filesystem バックエンド

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

  # 永続ボリュームの定義
  # tempo_data: トレースブロック + WAL + metrics_generator WAL を保持
  volumes = [
    "tempo_data"
  ]

  # Tempo サービスの定義
  services = {
    tempo = {
      # Grafana Tempo 公式イメージ
      # v2.10+ は Kafka ベースの新アーキテクチャに移行したため
      # Kafka 不要の学習環境では v2.6.1 (classic single-binary) を使用
      image = "grafana/tempo:2.6.1"

      # HTTP API ポート (Grafana データソース + /ready ヘルスチェック)
      # OTLP ポート (4317/4318) は docker_container モジュールの単一ポート制約により
      # Docker ネットワーク内のみ公開。外部からは OTel Collector 経由でアクセス。
      internal_port = 3200
      external_port = 3200

      # 起動コマンド: 設定ファイルを明示指定
      command = ["-config.file=/etc/tempo/tempo.yml"]

      # 環境変数設定（不要）
      env = []

      # Docker Volume マウント: 永続化ストレージ
      volumes = [
        {
          source = "tempo_data"
          target = "/var/tempo"  # ブロック・WAL・ジェネレーターデータの保存先
        }
      ]

      # Bind マウント設定 (リモートサーバーの設定ファイル)
      # ⚠️ apply 前に必ずリモートサーバーへファイルを転送すること (T009)
      #    転送前に apply するとコンテナ起動失敗
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/tempo/tempo.yml"
          target    = "/etc/tempo/tempo.yml"
          read_only = true
        }
      ]
    }
  }
}
