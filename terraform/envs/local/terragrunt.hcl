# ==========================================
# Local Environment Configuration
# ==========================================
# このファイルはローカル環境（自宅ラボ）専用の設定を定義します。

# ----- Root設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- ローカル環境固有の変数 -----
locals {
  # 環境名
  env = "local"

  # Vaultの接続情報（開発モード）
  vault_address = "http://localhost:8200"

  # リモートサーバー接続情報（環境変数から取得）
  target_host        = get_env("TARGET_HOST", "192.168.1.42")
  target_user        = get_env("TARGET_USER", "ubuntu")
  target_port        = get_env("TARGET_PORT", "22")
  ssh_private_key    = get_env("SSH_PRIVATE_KEY", "~/.ssh/id_rsa")

  # リモートサーバー上の配置先ディレクトリ
  remote_base_dir    = get_env("REMOTE_BASE_DIR", "/home/ubuntu/monitoring-lab")

  # 注意: 本来は環境変数やシークレット管理ツールから取得すべき
  # 例: vault_token = get_env("VAULT_TOKEN")
  # 開発環境では .env ファイルから読み込むことも可能
}

# ----- 共通Input変数の追加 -----
# Root設定の inputs に加えて、ローカル環境固有の変数を追加
inputs = merge(
  {
    # Vault関連設定
    vault_address = local.vault_address

    # リモートサーバー接続情報
    target_host        = local.target_host
    target_user        = local.target_user
    target_port        = local.target_port
    ssh_private_key    = local.ssh_private_key

    # リモート配置ディレクトリ
    remote_base_dir    = local.remote_base_dir
  }
)
