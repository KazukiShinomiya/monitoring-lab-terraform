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
}

# ----- Terraform Backend設定 -----
# ローカル環境では local backend を使用
# 本番環境では S3 や Terraform Cloud への変更を推奨
remote_state {
  backend = "local"

  config = {
    # Stateファイルのパス
    # 例: .terraform-state/local/zabbix/terraform.tfstate
    path = "${local.state_file_dir}/${path_relative_to_include()}/terraform.tfstate"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
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
  # SSH経由でリモートDockerに接続
  host = "ssh://${get_env("TARGET_USER", "ubuntu")}@${get_env("TARGET_HOST", "YOUR_SERVER_IP")}:${get_env("TARGET_PORT", "22")}"

  # SSH鍵のパス指定 + StrictHostKeyCheckingを無効化
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

  # タグ情報（リソース識別用）
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terragrunt"
  }
}

# ----- 依存関係の解決設定 -----
# 依存するモジュールが先に実行されるように制御
# 注意: dependency_optimizations は Terragrunt v0.90.0 では非サポート

# ----- エラーハンドリング -----
# リトライ設定（ネットワークエラーなどの一時的な障害に対応）
retryable_errors = [
  "(?s).*Failed to load state.*",
  "(?s).*Error acquiring the state lock.*",
  "(?s).*connection refused.*"
]

# リトライ回数と待機時間
retry_max_attempts       = 3
retry_sleep_interval_sec = 5
