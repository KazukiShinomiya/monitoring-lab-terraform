# ==========================================
# Root Terragrunt Configuration
# ==========================================
# このファイルは全環境（local/dev/prodなど）で共通の設定を定義します。
# 各環境の terragrunt.hcl はこのファイルを include することで設定を継承します。

# ----- ローカル変数定義 -----
locals {
  # プロジェクト名（すべてのリソースのプレフィックスになる）
  project_name = "monitoring-lab"

  # 環境名（envs配下のディレクトリ名から自動取得）
  # パス例: E:\work\labo\terraform\envs\local\zabbix
  # → ["terraform", "envs", "local", "zabbix"] → "local"
  environment = try(
    split("/", get_terragrunt_dir())[length(split("/", get_terragrunt_dir())) - 2],
    "local"
  )

  # Stateファイルの保存先ディレクトリ
  # 例: E:\work\labo\terraform\.terraform-state\local\zabbix
  state_file_dir = "${get_parent_terragrunt_dir()}/.terraform-state/${local.environment}"

  # Docker プロバイダー接続先
  # DOCKER_HOST が設定されていればそれを使用（CI/self-hosted runner: unix socket経由）
  # 未設定の場合は SSH 経由でリモートDockerに接続（開発環境）
  _ssh_target = "ssh://${get_env("TARGET_USER", "ubuntu")}@${get_env("TARGET_HOST", "YOUR_SERVER_IP")}:${get_env("TARGET_PORT", "22")}"
  docker_host = get_env("DOCKER_HOST", local._ssh_target)
}

# ----- Terraform Backend設定 -----
# HCP Terraform (remote backend) を使用
# 各サービスごとに個別のWorkspaceを自動作成
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"

  contents = <<EOF
terraform {
  cloud {
    organization = "${get_env("TF_CLOUD_ORGANIZATION", "YOUR_TF_ORG")}"

    workspaces {
      name = "${local.project_name}-${local.environment}-${basename(get_terragrunt_dir())}"
    }

    # ローカル実行モード（Stateのみクラウドに保存）
    # プライベートネットワークのリソースにアクセスするために必要
    hostname = "app.terraform.io"
  }
}

# ローカル実行を強制
locals {
  execution_mode = "local"
}
EOF
}

# ----- Terraform設定の自動生成 -----
# required_version や required_providers を自動生成
generate "terraform" {
  path      = "terraform_generated.tf"
  if_exists = "overwrite"

  contents = <<EOF
terraform {
  required_version = ">= 1.0"

  # 共通プロバイダーのバージョン制約
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}
EOF
}

# ----- プロバイダー設定の自動生成 -----
# Docker プロバイダーの設定（リモートサーバー接続）
generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite"

  contents = <<EOF
provider "docker" {
  # DOCKER_HOST が設定されていればそれを使用（CI/self-hosted runner環境）
  # 未設定の場合は SSH 経由でリモートDockerに接続（開発環境）
  host = "${local.docker_host}"

  # SSH接続時のみ有効（unix socket使用時は無視される）
  ssh_opts = [
    "-i", "${get_env("SSH_PRIVATE_KEY", "/tmp/.ssh/id_rsa")}",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null"
  ]
}
EOF
}

# ----- 共通Input変数の自動注入 -----
# すべての子モジュールに自動的に渡される変数
inputs = {
  # プロジェクト名
  project_name = local.project_name

  # 環境名
  environment = local.environment

  # SwitchBot API認証情報（環境変数から取得）
  SWITCHBOT_TOKEN  = get_env("SWITCHBOT_TOKEN", "YOUR_SWITCHBOT_TOKEN")
  SWITCHBOT_SECRET = get_env("SWITCHBOT_SECRET", "YOUR_SWITCHBOT_SECRET")

  # タグ情報（リソース識別用）
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terragrunt"
  }
}
