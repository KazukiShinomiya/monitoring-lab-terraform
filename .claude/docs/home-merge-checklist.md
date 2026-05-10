# 自宅PCでのマージ作業チェックリスト

**対象ブランチ**: `feat/claude-code-best-practices`  
**作成日**: 2026-05-10（このPCにしかない情報を集約）

---

## 1. 事前確認

```bash
# 現在のブランチ状態を確認
git fetch origin
git log --oneline origin/master..origin/feat/claude-code-best-practices
```

---

## 2. `feat/claude-code-best-practices` のマージ

このブランチの変更内容:
- `CLAUDE.md`: 800行のモノリシック構成 → 43行 + `@-import` 構造に簡素化
- `.claude/docs/persona.md` / `environment.md` / `architecture.md`: git追跡に追加
- `.claude/settings.json`: PostToolUseフック（Terraform変更検知）をgit追跡に追加
- `.claude/settings.local.json`: git管理から除外（`gitignore`に追加）
- `.gitignore`: `.claude/` 全体除外 → `.claude/settings.local.json` のみ除外に変更

```bash
# masterを最新化
git checkout master
git pull origin master

# マージ実行
git merge origin/feat/claude-code-best-practices

# 競合が発生した場合は手動解決後
git add .
git commit
```

### 競合が起きやすいファイル

| ファイル | 対応方針 |
|---------|---------|
| `CLAUDE.md` | 自宅版を確認し、このブランチ版（短縮版）を採用 |
| `.gitignore` | 両方の除外ルールを保持して手動マージ |

---

## 3. `settings.local.json` の手動作成（重要）

このファイルはgit管理外のため、**自宅PCには存在しない**。  
以下の内容で `.claude/settings.local.json` を手動作成すること。

```json
{
  "permissions": {
    "allow": [
      "Bash(wsl *)",
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(docker *)",
      "Bash(cp *)",
      "Bash(chmod *)",
      "Bash(cat *)",
      "PowerShell(wsl *)",
      "PowerShell(ssh *)",
      "PowerShell(Invoke-RestMethod *)",
      "PowerShell(Invoke-WebRequest *)",
      "PowerShell($r = Invoke-WebRequest *)",
      "PowerShell($response = Invoke-WebRequest *)",
      "PowerShell(Get-Content *)",
      "PowerShell(Get-ChildItem *)",
      "PowerShell(ls *)",
      "PowerShell(Test-Path *)",
      "PowerShell(Copy-Item *)",
      "PowerShell(Remove-Item *)",
      "PowerShell(& *)",
      "PowerShell(head *)",
      "PowerShell(tail *)",
      "PowerShell(Get-Process *)",
      "PowerShell(Get-Service *)",
      "WebSearch",
      "WebFetch(domain:docs.anthropic.com)",
      "WebFetch(domain:code.claude.com)",
      "WebFetch(domain:www.anthropic.com)",
      "WebFetch(domain:platform.claude.com)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:registry.terraform.io)",
      "WebFetch(domain:developer.hashicorp.com)",
      "Bash(dir Syncing)",
      "Bash(Remove-Item *)"
    ],
    "deny": [],
    "ask": []
  }
}
```

> **注意**: 自宅PCがLinux/macの場合は `PowerShell(*)` 系の許可は不要。  
> 自宅PCもWindows + WSL2環境であれば上記をそのままコピーしてよい。

---

## 4. `.env` ファイルの手動作成（重要）

このファイルもgit管理外のため、**自宅PCには存在しない**。  
`.env.example` をコピーして作成し、以下の値を設定すること。

```bash
cp .env.example .env
```

### 自宅PCで設定が必要な項目

| 変数名 | 取得先 | 備考 |
|--------|--------|------|
| `TF_TOKEN_app_terraform_io` | https://app.terraform.io/app/settings/tokens | **要ローテーション（後述）** |
| `TF_CLOUD_ORGANIZATION` | `k1981-learning-lab` | そのまま使用 |
| `NEW_RELIC_LICENSE_KEY` | New Relic管理コンソール | 現在 `YOUR_LICENSE_KEY_HERE` のまま（未設定でも動作する） |

その他の値（Vault, PostgreSQL, Grafana, Zabbix認証情報）は `.env.example` のデフォルト値で動作する（学習環境のため）。

> ⚠️ **トークンのローテーションを推奨**  
> HCP Terraform API Token は2026-05-10のセッション中に会話ログに露出した。  
> https://app.terraform.io/app/settings/tokens で古いトークンを失効させ、新しいトークンを発行してから `.env` に設定すること。

---

## 5. マージ後の確認

```bash
# settings.local.jsonが gitignore されていることを確認
git status  # settings.local.json が "untracked" または表示されないこと

# settings.jsonが追跡されていることを確認
git ls-files .claude/settings.json  # 出力されること

# CLAUDE.mdが短縮版になっていることを確認
wc -l CLAUDE.md  # 50行以下のはず
```

---

## 6. 既存の自宅マージメモとの関係

`backup/local-work-20260504` ブランチのマージ手順は  
`.claude/SESSION_STATE.md` の「自宅環境へのマージメモ」セクションに詳細あり。

**推奨作業順序**:
1. このファイルの手順（`feat/claude-code-best-practices` マージ）を先に実施
2. その後、SESSION_STATE.md に従い `backup/local-work-20260504` の内容を取り込む
