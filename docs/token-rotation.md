# HCP Terraform API トークン ローテーション手順

`.env` の `TF_TOKEN_app_terraform_io` に設定する **HCP Terraform User API token**（`atlasv1.` 形式）の発行・更新・失効手順をまとめる。

---

## 対象トークン

| 項目 | 内容 |
|---|---|
| 変数名 | `TF_TOKEN_app_terraform_io`（`.env` 内） |
| 形式 | `atlasv1.xxxxx...` |
| 種別 | HCP Terraform **User API token** |
| 発行元 | <https://app.terraform.io/app/settings/tokens> → **Tokens** セクション → **Create an API token** |
| 推奨有効期限 | **90日**（四半期ごとのローテーション） |

> ⚠️ 同画面の **Github App OAuth Token** は GitHub VCS 連携用で別物。本トークンとは無関係なので触らない。

---

## このトークンが切れると止まるもの

```
TF_TOKEN_app_terraform_io が無効化
  ├─ Terragrunt CLI（plan/apply）→ 認証エラー
  └─ MCP terragrunt-server      → HCP操作が全滅
※ Docker / Prometheus / Alertmanager の各MCPは無関係（影響なし）
※ リモート稼働中の監視スタック本体（コンテナ群）も影響なし
```

影響範囲は **IaC操作系のみ**。監視機能そのものは動き続ける。

---

## 平時のローテーション手順（無停止）

**原則: 新を立ててから旧を倒す。**

1. HCP で新 API token を発行
   - <https://app.terraform.io/app/settings/tokens> → **Create an API token**
   - Description: `monitoring-lab-cli-YYYY-MM`（用途と発行月が分かる名前）
   - Expiration: 90日
   - **Generate token** → 表示された `atlasv1.` を **その場でコピー**（再表示不可）
2. `.env` の `TF_TOKEN_app_terraform_io=` を新トークンに差し替え（101行目付近）
   - 引用符は不要。`=` の直後にそのまま貼る
   - `TF_CLOUD_ORGANIZATION` / `TF_CLOUD_WORKSPACE` は触らない
3. 疎通確認（下記コマンド）で `OK: <ユーザー名>` を確認
4. HCP で **旧トークンを失効**（Tokens 一覧 → 該当行の × / Remove）
5. MCP terragrunt-server は次回起動時に自動で新トークンを拾う
   （`.mcp.json` が実行時に `.env` から読む設計のため、手動更新は不要）

---

## 緊急時（トークン漏洩）の手順

平時と順序が逆になる。**漏れた鍵は即失効が最優先。**

1. HCP で漏洩トークンを **即座に失効**（Delete）
2. 漏洩経路の痕跡を除去（`.env` 以外に平文が残っていないか確認）
   - 過去に `settings.local.json` の許可リストに平文が固着した事例あり
3. 新トークンを発行 → `.env` 更新 → 疎通確認
4. git 履歴に漏れていないか検証（下記）

---

## 疎通確認コマンド

```bash
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && source .env && \
  curl -s --header \"Authorization: Bearer \$TF_TOKEN_app_terraform_io\" \
  https://app.terraform.io/api/v2/account/details | \
  python3 -c \"import sys,json; print('OK:', json.load(sys.stdin)['data']['attributes']['username'])\""
```

`OK: <ユーザー名>` が返れば成功。

---

## git 履歴へのトークン漏洩チェック

```bash
cd /mnt/e/work/labo
# トークン形式が全履歴に存在しないか（0 件であること）
git log --all -p | grep -c "atlasv1"
# .env / settings.local.json が一度もコミットされていないか（出力が空であること）
git log --all --oneline -- .env .claude/settings.local.json
```

---

## トークンの取り扱い原則

- **`.env` だけが正しい置き場**。`.gitignore` 済みであることが前提
- 許可リスト（`settings.local.json`）・コマンド履歴・git にトークンを直書きしない
- 「Treat these tokens like passwords」— HCP の画面表示の通り、パスワードと同等に扱う
- 期限切れ前に更新する（90日サイクルをカレンダー等でリマインド）
