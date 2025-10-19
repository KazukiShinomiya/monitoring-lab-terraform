# ==========================================
# Network Service - Terragrunt Configuration
# ==========================================
# 監視基盤の全サービスが使用する共通ネットワークを管理

# 親ディレクトリの設定を継承
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ==========================================
# Terraform設定
# ==========================================
terraform {
  source = "../../../modules/network"
}

# ==========================================
# 入力変数
# ==========================================
inputs = {
  project_name = "monitoring-lab"
  network_name = "monitoring-lab-network"
  subnet       = "172.28.0.0/16"
  gateway      = "172.28.0.1"
}
