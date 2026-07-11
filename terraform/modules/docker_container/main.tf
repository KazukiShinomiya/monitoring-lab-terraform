# ==========================================
# Docker Container Module
# ==========================================
# このモジュールは、Docker環境でコンテナベースのサービスを
# 統一的に管理するための共通モジュールです。

# ==========================================
# Docker Volumes
# ==========================================
# 永続化が必要なデータ用のボリュームを動的に作成
resource "docker_volume" "data" {
  for_each = toset(var.volumes)

  name = "${var.project_name}-${each.key}"

  # ラベルでプロジェクトを識別可能に
  labels {
    label = "project"
    value = var.project_name
  }
}

# ==========================================
# Docker Containers
# ==========================================
# 各サービス用のコンテナを動的に作成
resource "docker_container" "service" {
  for_each = var.services

  name  = "${var.project_name}-${each.key}"
  image = each.value.image

  # コマンド引数（オプション）
  command = length(each.value.command) > 0 ? each.value.command : null

  # エントリーポイント上書き（オプション）
  entrypoint = length(each.value.entrypoint) > 0 ? each.value.entrypoint : null

  # 実行ユーザー（オプション）
  user = each.value.user != "" ? each.value.user : null

  # 特権モード（オプション）
  privileged = each.value.privileged

  # ネットワークモード（オプション）
  network_mode = each.value.network_mode != "" ? each.value.network_mode : null

  # Cgroup Namespaceモード（オプション）
  cgroupns_mode = each.value.cgroupns_mode != "" ? each.value.cgroupns_mode : null

  # コンテナを常時稼働させる設定
  restart = "unless-stopped"

  # ネットワーク設定（network_mode="host"の場合は使用しない）
  dynamic "networks_advanced" {
    for_each = each.value.network_mode != "host" ? [1] : []
    content {
      name = var.network_name
      # サービス名でDNS解決できるようにエイリアスを設定
      aliases = [each.key]
    }
  }

  # ポートマッピング（network_mode="host"の場合は不要）
  dynamic "ports" {
    for_each = each.value.network_mode != "host" ? [1] : []
    content {
      internal = each.value.internal_port
      external = each.value.external_port
    }
  }

  # 追加ポートマッピング（extra_ports 指定時のみ。既存サービスは default [] で不変）
  dynamic "ports" {
    for_each = each.value.network_mode != "host" ? each.value.extra_ports : []
    content {
      internal = ports.value.internal
      external = ports.value.external
    }
  }

  # 環境変数の注入（文字列リスト形式）
  env = each.value.env

  # ボリュームマウント設定（Docker Volume）
  dynamic "volumes" {
    for_each = each.value.volumes
    content {
      volume_name    = docker_volume.data[volumes.value.source].name
      container_path = volumes.value.target
    }
  }

  # Bind マウント設定（ホストのファイル/ディレクトリ）
  dynamic "mounts" {
    for_each = each.value.bind_mounts
    content {
      type   = "bind"
      source = mounts.value.source
      target = mounts.value.target
      read_only = mounts.value.read_only
    }
  }

  # ヘルスチェック設定（オプション）
  # 注: Dockerイメージ本来のhealthcheck設定を使用するため、
  # ここでは明示的なhealthcheck定義を行わない
  # healthcheck {
  #   test     = ["CMD-SHELL", "echo 'alive'"]
  #   interval = "30s"
  #   timeout  = "5s"
  #   retries  = 3
  # }
}
