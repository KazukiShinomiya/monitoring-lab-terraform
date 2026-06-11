# ==========================================
# HashiCorp Vault Server Configuration (Production Mode)
# ==========================================
# 本番モード: 永続ストレージ(file backend) + TLS 有効。
# 開発モード(VAULT_DEV_*)から移行。再起動してもデータが残る。
#
# 配置先: /vault/config/vault.hcl (bind mount, read_only)
# 起動: vault server -config=/vault/config/vault.hcl

# ----- ストレージバックエンド -----
# 単一ノードの学習環境には file backend で十分（raft は HA クラスタ向け）。
# named volume "vault_data" を /vault/file にマウントして永続化する。
storage "file" {
  path = "/vault/file"
}

# ----- リスナー（TLS 有効） -----
# 自己署名証明書を bind mount(/vault/tls) で注入する。
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.crt"
  tls_key_file  = "/vault/tls/vault.key"
}

# ----- UI を有効化 -----
ui = true

# ----- mlock 無効化 -----
# コンテナ環境では IPC_LOCK capability が無いため mlock を無効化する。
disable_mlock = true

# ----- API アドレス -----
# クラスタ外部からアクセスする際のアドバタイズアドレス。
# 実IPをコードに残さないため api_addr はここに書かず、VAULT_API_ADDR 環境変数で
# 注入する（terragrunt.hcl が get_env("TARGET_HOST") 経由で設定）。
