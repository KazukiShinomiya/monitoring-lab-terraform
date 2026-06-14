# ==========================================
# HashiCorp Vault Service Configuration
# ==========================================
# 機密情報管理用の Vault サーバー設定（本番モード: 永続ストレージ + TLS）

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
  network_name = dependency.network.outputs.network_name

  # 永続ボリュームの定義（本番モード: データを永続化する）
  volumes = ["vault_data"]

  # Vaultサービスの定義
  services = {
    vault = {
      # Vault公式イメージ（バージョン固定で再現性を確保）
      image = "hashicorp/vault:1.20.4"

      # VaultのデフォルトAPIポート
      internal_port = 8200
      external_port = 8200

      # 本番モードで起動。
      # 公式イメージの entrypoint(docker-entrypoint.sh) は "server" を受けると
      # 自動で -config=/vault/config を付与する。ここで重ねて -config を渡すと
      # vault.hcl が二重ロードされ listener が重複し bind 衝突するため、command は
      # "server" のみとし、設定は /vault/config ディレクトリ経由で読ませる。
      command = ["server"]

      # 環境変数設定（本番モード: VAULT_DEV_* を撤去）
      env = [
        "VAULT_ADDR=https://127.0.0.1:8200", # コンテナ内CLI用（self-signed のため verify skip）
        # クラスタアドバタイズアドレス。実IPはコードに残さず TARGET_HOST から注入。
        "VAULT_API_ADDR=https://${get_env("TARGET_HOST", "YOUR_SERVER_IP")}:8200",
        "VAULT_SKIP_VERIFY=true",
        "VAULT_LOG_LEVEL=info"
      ]

      # ボリュームマウント設定（永続ストレージ）
      volumes = [
        {
          source = "vault_data"   # 上で定義した named volume
          target = "/vault/file"  # storage "file" の path と一致させる
        }
      ]

      # Bind マウント設定（config + TLS証明書を注入、読み取り専用）
      bind_mounts = [
        {
          source    = "/home/ubuntu/monitoring-lab/vault/config"
          target    = "/vault/config"
          read_only = true
        },
        {
          source    = "/home/ubuntu/monitoring-lab/vault/tls"
          target    = "/vault/tls"
          read_only = true
        }
      ]
    }
  }
}

# ----- 注意事項 -----
# 【本番モードの運用】
# ✓ データは named volume "vault_data" (/vault/file) に永続化される
# ✓ TLS 有効（自己署名証明書）。クライアントは skip_tls_verify で接続
# ✓ 起動直後は sealed 状態 → operator init / unseal が必要
# ✓ unseal鍵・root token は .env に保管（Gitignore済み）。別途バックアップ推奨
#
# 【次フェーズの課題】
# 1. auto-unseal（Transit / KMS）の検討
# 2. image の固定タグ化（:latest 撤廃）
# 3. unseal鍵のより安全な管理（現状は学習用に .env 保管）
