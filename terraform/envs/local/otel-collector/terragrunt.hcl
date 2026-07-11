# ==========================================
# OpenTelemetry Collector Service Configuration
# ==========================================
# OTLP トレースを受信して Tempo に転送するコレクター (ステートレス)
# 外部ポート 4317: アプリやツールからのトレース受信 (外部公開)

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

dependency "tempo" {
  config_path = "../tempo"
  mock_outputs = {
    container_ids = {}
  }
}

# ----- サービス固有の変数 -----
inputs = {
  network_name = dependency.network.outputs.network_name

  # ボリューム不要 (OTel Collector はステートレス動作)
  volumes = []

  # OTel Collector サービスの定義
  services = {
    otel-collector = {
      # OpenTelemetry Collector Contrib 公式イメージ
      # contrib: Prometheus receiver / exporter 等の拡張コンポーネントを含む
      # バージョン固定で再現性を確保
      image = "otel/opentelemetry-collector-contrib:0.148.0"

      # OTLP gRPC ポート (外部公開 — アプリ・telemetrygen からのトレース受信)
      internal_port = 4317
      external_port = 4317

      # OTLP HTTP ポート (016: MCP メトリクスの受信経路)
      # WSL2 環境からの gRPC(h2c) はサイレント不達となることを実測で確認済みのため、
      # MCP 計装は OTLP/HTTP(4318) で送出する（specs/016 research.md 参照）
      extra_ports = [
        { internal = 4318, external = 4318 }
      ]

      # 起動コマンド: 設定ファイルを明示指定
      command = ["--config=/etc/otel-collector/otel-collector.yml"]

      # 環境変数設定（不要）
      env = []

      # Docker Volume 不要 (ステートレス)
      volumes = []

      # Bind マウント設定 (リモートサーバーの設定ファイル)
      # ⚠️ apply 前に必ずリモートサーバーへファイルを転送すること (T015)
      #    転送前に apply するとコンテナ起動失敗
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/otel-collector/otel-collector.yml"
          target    = "/etc/otel-collector/otel-collector.yml"
          read_only = true
        }
      ]
    }
  }
}
