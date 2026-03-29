# Contract: terraform/envs/local/github-runner/terragrunt.hcl
# Runner コンテナの Terragrunt 定義 (実装の参照定義)

# ==========================================
# GitHub Actions Self-hosted Runner
# ==========================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/docker_container"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}

inputs = {
  network_name = dependency.network.outputs.network_name

  # Runner はステートレス — 永続ボリューム不要
  volumes = []

  services = {
    github-runner = {
      # バージョン固定 (latest タグ使用禁止)
      image = "myoung34/github-runner:2.332.0-ubuntu-jammy"

      # runner はポートを公開しない
      internal_port = 0
      external_port = 0

      env = [
        # GitHub PAT for runner auto-registration
        "ACCESS_TOKEN=${get_env("GH_RUNNER_PAT", "")}",

        # リポジトリ登録設定
        "REPO_URL=https://github.com/KazukiShinomiya/monitoring-lab-terraform",
        "RUNNER_NAME=monitoring-lab-runner-01",
        "LABELS=self-hosted,linux,monitoring-lab",
        "RUNNER_WORKDIR=/tmp/runner-work",

        # root ユーザーでの実行を許可（コンテナ内）
        "RUNNER_ALLOW_RUNASROOT=true",
      ]

      # Docker ソケットのバインドマウント
      bind_mounts = [
        {
          source    = "/var/run/docker.sock"
          target    = "/var/run/docker.sock"
          read_only = false
        }
      ]

      volumes = []
    }
  }
}
