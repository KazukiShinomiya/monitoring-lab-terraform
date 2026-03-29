# ==========================================
# GitHub Actions Self-hosted Runner
# ==========================================
# リモートサーバー (10.0.0.220) 上で動作する Self-hosted Runner コンテナ
# GitHub Actions ジョブを受け取り、terragrunt plan / apply を実行する

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
  # network_name は module の required variable だが、
  # network_mode = "host" の場合は networks_advanced ブロックがスキップされる
  network_name = dependency.network.outputs.network_name

  # Runner はステートレス — 永続ボリューム不要
  volumes = []

  services = {
    github-runner = {
      # ========================================
      # バージョン固定（latest タグ使用禁止）
      # アップデート時は PR を通じて変更 → plan で差分確認 → apply
      # 次回アップデート候補: https://hub.docker.com/r/myoung34/github-runner/tags
      # ========================================
      image = "myoung34/github-runner:2.332.0-ubuntu-jammy"

      # ホストネットワークを使用（GitHub への接続 + ポートマッピング不要）
      network_mode = "host"

      # network_mode = "host" のため ports ブロックはスキップされる（モジュール仕様）
      internal_port = 0
      external_port = 0

      env = [
        # GitHub PAT — runner 自動登録・解除に使用（repo scope 必須）
        "ACCESS_TOKEN=${get_env("GH_RUNNER_PAT", "")}",

        # 登録先リポジトリ
        "REPO_URL=https://github.com/KazukiShinomiya/monitoring-lab-terraform",

        # GitHub 上の表示名
        "RUNNER_NAME=monitoring-lab-runner-01",

        # ジョブルーティング用ラベル（workflow の runs-on で参照）
        "LABELS=self-hosted,linux,monitoring-lab",

        # runner 作業ディレクトリ
        "RUNNER_WORKDIR=/tmp/runner-work",

        # コンテナ内 root ユーザーでの実行を許可
        "RUNNER_ALLOW_RUNASROOT=true",
      ]

      # ======================================
      # Docker ソケットのバインドマウント
      # runner から Docker デーモンへ直接アクセス
      # 注意: ホスト Docker への完全アクセスを許可する（学習環境では許容）
      # ======================================
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

# ----- GitHub Actions Runner 情報 -----
#
# 登録確認:
#   GitHub → Settings → Actions → Runners → monitoring-lab-runner-01
#
# コンテナログ確認:
#   docker logs monitoring-lab-github-runner
#
# 手動停止（登録解除も自動実行）:
#   docker stop monitoring-lab-github-runner
#
# バージョンアップ手順:
#   1. image タグを変更した PR を作成
#   2. plan ワークフローで差分確認
#   3. main にマージして apply ワークフローで自動更新
#
