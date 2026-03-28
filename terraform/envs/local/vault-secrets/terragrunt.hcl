# ==========================================
# Vault Secrets Workspace（独立設定）
# ==========================================
# AlertmanagerのSlack Webhook URLをVaultに格納する。
# vault プロバイダーを使うため root.hcl を include せず独立設定とする。

terraform {
  source = "../../../modules/vault_secret"
}

# HCP Terraform backend（state管理のみ）
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"

  contents = <<EOF
terraform {
  cloud {
    organization = "YOUR_TF_ORG"

    workspaces {
      name = "monitoring-lab-local-vault-secrets"
    }

    hostname = "app.terraform.io"
  }
}
EOF
}

# Terraform required_providers（vault のみ）
generate "terraform_config" {
  path      = "terraform_generated.tf"
  if_exists = "overwrite"

  contents = <<EOF
terraform {
  required_version = ">= 1.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}
EOF
}

# Vault プロバイダー設定
generate "provider_config" {
  path      = "provider_generated.tf"
  if_exists = "overwrite"

  contents = <<EOF
provider "vault" {
  address         = "${get_env("VAULT_ADDR", "http://YOUR_SERVER_IP:8200")}"
  token           = "${get_env("VAULT_TOKEN", "root")}"
  skip_tls_verify = true
}
EOF
}

inputs = {
  project_name = "monitoring-lab"
  mount_path   = "secret"

  # Alertmanager Slack Webhook URL（必須: .envの SLACK_WEBHOOK_URL から取得）
  alertmanager_slack_webhook_url = get_env("SLACK_WEBHOOK_URL")

  # PostgreSQL認証情報
  db_password = get_env("POSTGRES_PASSWORD", "zabbix_password")

  # Grafana認証情報
  grafana_admin_password = get_env("GRAFANA_ADMIN_PASSWORD", "admin")
}
