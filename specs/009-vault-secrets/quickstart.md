# Quickstart: Vault シークレット管理 Step 1

**Branch**: `009-vault-secrets`
**Date**: 2026-03-16

## 前提条件

- [ ] Vault コンテナが稼働中（`docker ps | grep vault-dev`）
- [ ] WSL2 から Vault API に接続可能（`curl http://10.0.0.220:8200/v1/sys/health`）
- [ ] `.env` に `SLACK_WEBHOOK_URL` が設定済み（初回移行時のみ必要）

---

## Step 1: Vault にシークレットを格納する

```bash
# vault-secrets Workspace を初期化
cd terraform/envs/local/vault-secrets
../../../scripts/tg.sh init

# 実行計画を確認
../../../scripts/tg.sh plan

# 適用（Vault に alertmanager シークレットが書き込まれる）
../../../scripts/tg.sh apply
```

## Step 2: Vault への格納を確認する

```bash
# Vault HTTP API で確認
curl -s \
  -H "X-Vault-Token: root" \
  http://10.0.0.220:8200/v1/secret/data/monitoring-lab/alertmanager \
  | jq '.data.data'
# 期待値: {"slack_webhook_url": "https://hooks.slack.com/..."}
```

## Step 3: Alertmanager を Vault 経由で同期する

```bash
# .env の SLACK_WEBHOOK_URL をコメントアウト（Vault からの取得を強制）
# vim .env  →  # SLACK_WEBHOOK_URL=...

# 同期実行（Vault から URL を取得して反映）
./scripts/sync-config.sh alertmanager
```

## Step 4: 動作確認

```bash
# amtool で設定検証
ssh ubuntu@10.0.0.220 "docker exec monitoring-lab-alertmanager \
  amtool check-config /etc/alertmanager/alertmanager.yml"
# 期待値: Checking '/etc/alertmanager/alertmanager.yml'  SUCCESS

# アラートを手動で確認（オプション）
# Prometheus で cAdvisor を一時停止 → Slack 通知確認
```

---

## URL のローテーション手順

1. `.env` の `SLACK_WEBHOOK_URL` を新しい URL に更新
2. `terragrunt apply` で Vault を更新
3. `./scripts/sync-config.sh alertmanager` で反映
4. Slack に通知が届くことを確認

---

## トラブルシューティング

### Vault から URL を取得できない

```bash
# Vault の稼働確認
curl -s http://10.0.0.220:8200/v1/sys/health | jq '.initialized'
# true であれば稼働中

# シークレットの存在確認
curl -s -H "X-Vault-Token: root" \
  http://10.0.0.220:8200/v1/secret/metadata/monitoring-lab/alertmanager \
  | jq '.data'
```

### Vault dev モード再起動後（シークレット消失）

```bash
# vault コンテナ確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@10.0.0.220 'docker ps | grep vault'"

# シークレット再格納
cd terraform/envs/local/vault-secrets
../../../scripts/tg.sh apply
```
