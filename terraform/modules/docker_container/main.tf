# ==========================================
# Docker Container Module
# ==========================================
# このモジュールは、Docker環境でコンテナベースのサービスを
# 統一的に管理するための共通モジュールです。

terraform {
  required_version = ">= 1.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# ==========================================
# Docker Network
# ==========================================
# 全サービスが通信するための専用ネットワークを作成
resource "docker_network" "monitoring" {
  name   = "${var.project_name}-network"
  driver = "bridge"

  # IPアドレス範囲を明示的に指定（デバッグ用）
  ipam_config {
    subnet  = "172.28.0.0/16"
    gateway = "172.28.0.1"
  }
}

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

  # コンテナを常時稼働させる設定
  restart = "unless-stopped"

  # ネットワーク設定
  networks_advanced {
    name = docker_network.monitoring.name
    # サービス名でDNS解決できるようにエイリアスを設定
    aliases = [each.key]
  }

  # ポートマッピング（ホスト:コンテナ）
  ports {
    internal = each.value.internal_port
    external = each.value.external_port
  }

  # 環境変数の注入
  dynamic "env" {
    for_each = each.value.env
    content {
      # 環境変数を "KEY=VALUE" 形式から分解
      name  = split("=", env.value)[0]
      value = split("=", env.value)[1]
    }
  }

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
  healthcheck {
    test     = ["CMD-SHELL", "echo 'alive'"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}
