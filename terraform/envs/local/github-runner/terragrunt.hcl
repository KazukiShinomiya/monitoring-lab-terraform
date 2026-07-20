# ==========================================
# GitHub Actions Self-hosted Runner
# ==========================================
# リモートサーバー (YOUR_SERVER_IP) 上で動作する Self-hosted Runner コンテナ
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

      # ==========================================================
      # 停止猶予を 60 秒へ延長（Docker 既定は 10 秒）
      # ==========================================================
      # 停止時の自動 deregister は GitHub API を 2 回叩く。10 秒を超えると
      # SIGKILL され、`.credentials` を残したまま死ぬ——これが下記 entrypoint の
      # コメントにある「.credentials は在るが .runner が無い」不整合の発生源だった。
      # entrypoint 側で状態ファイルを全消去する対策が既に入っているため、これは
      # 二重の防壁（不整合を「起こしても直る」に加えて「そもそも起こしにくく」する）。
      stop_timeout = 60

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

      # ==========================================================
      # 起動時に登録状態を完全に消してから本来の entrypoint へ渡す
      # ==========================================================
      # 2026-07-20 のインシデント対策。上流の /entrypoint.sh は再利用無効時に
      # `.runner` だけを削除して config.sh を実行するが、`.credentials` と
      # `.credentials_rsaparams` は残す。config.sh は両方を見て設定済みか判定するため、
      # 「.credentials は在るが .runner が無い」不整合が起きると以後永久に起動できない:
      #
      #   Cannot configure the runner because it is already configured.
      #   An error occurred: Value cannot be null. (Parameter 'configuredSettings')
      #
      # この不整合は停止時の自動 deregister（GitHub API 2 回）が Docker 既定の
      # 10 秒以内に完走できず SIGKILL された場合などに残る。実際 2026-07-12 の apply を
      # 引き金に発症し、RestartCount 10782（約 62 秒周期）で 8 日間ループした。
      # その間 self-hosted ラベル待ちの CI apply は queued のまま消化されない。
      #
      # config.sh には既に --replace が付いており、同名ランナーの再登録は正規の動作。
      # よって毎回まっさらから登録させるのが最も確実で、コンテナの寿命に状態を持たせない
      # （terragrunt.hcl 冒頭「Runner はステートレス」という当初の設計意図とも一致する）。
      #
      # 注意: exec で置き換えるため /entrypoint.sh の shebang（dumb-init）は維持され、
      # シグナル伝播と deregister の trap はそのまま機能する。
      # CMD（./bin/Runner.Listener run ...）はイメージ既定のまま "$@" で引き渡す。
      entrypoint = [
        "/bin/bash", "-c",
        "rm -f /actions-runner/.runner /actions-runner/.credentials /actions-runner/.credentials_rsaparams; exec /entrypoint.sh \"$@\"",
        "--",
      ]

      # entrypoint 上書き時に "$@" へ渡る引数。イメージ既定の CMD と同一だが、
      # ここが空だと Runner.Listener が起動せずコンテナが即終了するため、
      # 既定値の継承に頼らず明示する（イメージ更新時は要追従）。
      command = ["./bin/Runner.Listener", "run", "--startuptype", "service"]

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
