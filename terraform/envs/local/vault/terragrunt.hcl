# ==========================================
# HashiCorp Vault Service Configuration
# ==========================================
# 機密情報管理用のVaultサーバー設定（開発モード）

# ----- 親設定の継承 -----
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ----- Terraformモジュールの指定 -----
terraform {
  source = "../../../modules/docker_container"
}

# ----- サービス固有の変数 -----
inputs = {
  # 永続ボリュームの定義
  # 注意: 開発モードではボリュームを使用しない（メモリ内で動作）
  volumes = []

  # Vaultサービスの定義
  services = {
    vault = {
      # Vault公式イメージ
      image = "hashicorp/vault:latest"

      # VaultのデフォルトAPIポート
      internal_port = 8200
      external_port = 8200

      # 環境変数設定
      env = [
        "VAULT_DEV_ROOT_TOKEN_ID=root",
        "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200",
        "VAULT_LOG_LEVEL=info"
      ]

      # ボリュームマウント設定
      # 開発モードではデータを永続化しないため空
      volumes = []

      # Bind マウント設定
      bind_mounts = []
    }
  }
}

# ----- 注意事項 -----
# 【開発モードの特徴】
# ✓ 自動的にUnseal状態で起動
# ✓ Root Token = "root" で固定
# ✓ HTTPで通信（TLS無効）
# ✓ データはメモリ内のみ（再起動で消失）
#
# 【本番環境への移行時の変更点】
# 1. VAULT_DEV_* 環境変数を削除
# 2. 設定ファイルをボリュームマウント
# 3. TLS証明書の設定
# 4. Unseal Keyの安全な管理
# 5. Auto-unseal機能の検討
