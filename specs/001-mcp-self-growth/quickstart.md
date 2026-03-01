# Quickstart: MCP自己成長基盤

**対象**: 初めてこのブランチをセットアップするエンジニア

---

## 前提条件

- Node.js v22.x（Windows Git Bash環境）: `node --version` で確認
- SSH鍵: `~/.ssh/monitoring_lab_key`（権限: 600）
- SSH疎通: `ssh ubuntu@10.0.0.220 docker ps` が成功すること
- Prometheusが稼働: `http://10.0.0.220:9090` にアクセスできること

---

## セットアップ手順

### Step 1: 依存関係インストール

```bash
# mcp-servers/docker-mcp
cd mcp-servers/docker-mcp
npm install

# mcp-servers/prometheus-mcp
cd ../prometheus-mcp
npm install

# mcp-servers/terragrunt-mcp
cd ../terragrunt-mcp
npm install
```

### Step 2: ビルド

```bash
cd /e/work/labo/mcp-servers/docker-mcp && npm run build
cd ../prometheus-mcp && npm run build
cd ../terragrunt-mcp && npm run build
```

### Step 3: .mcp.json の確認

プロジェクトルートに `.mcp.json` があることを確認する:

```bash
cat /e/work/labo/.mcp.json
```

期待される内容:
```json
{
  "mcpServers": {
    "docker-mcp": {
      "command": "node",
      "args": ["mcp-servers/docker-mcp/dist/index.js"],
      "env": { "SSH_KEY_PATH": "${HOME}/.ssh/monitoring_lab_key" }
    },
    "prometheus-mcp": {
      "command": "node",
      "args": ["mcp-servers/prometheus-mcp/dist/index.js"],
      "env": { "PROMETHEUS_URL": "http://10.0.0.220:9090" }
    },
    "terragrunt-mcp": {
      "command": "node",
      "args": ["mcp-servers/terragrunt-mcp/dist/index.js"],
      "env": {
        "SSH_KEY_PATH": "${HOME}/.ssh/monitoring_lab_key",
        "TF_TOKEN_app_terraform_io": "${TF_TOKEN_app_terraform_io}"
      }
    }
  }
}
```

### Step 4: Claude Code の再起動

Claude Codeを終了して再起動すると、MCPサーバーが自動で起動される。

セッション内で `/mcp` と入力して登録状態を確認:
```
docker-mcp: connected
prometheus-mcp: connected
terragrunt-mcp: connected
```

---

## 動作確認

### Docker MCPのテスト

Claude Codeのセッションで:
```
コンテナの状態を確認して
```
→ `list_containers` が呼ばれ、全9コンテナの状態が返ってくる

### Prometheus MCPのテスト

```
現在のPrometheusアラートを確認して
```
→ `get_active_alerts` が呼ばれ、発火中のアラートが返ってくる

### Terragrunt MCPのテスト

```
prometheusサービスのTerragruntプランを確認して
```
→ `plan_service` が呼ばれ、差分（または "No changes"）が返ってくる

---

## データ永続化の確認

提案・承認ログは `mcp-servers/.mcp-data/` に保存される:

```bash
ls /e/work/labo/mcp-servers/.mcp-data/
# proposals/  approvals/  reports/

cat /e/work/labo/mcp-servers/.mcp-data/proposals/index.json
```

---

## トラブルシューティング

### MCPサーバーが接続されない
```bash
# ログを確認（stderrに出力される）
node mcp-servers/docker-mcp/dist/index.js 2>&1
```

### SSH接続エラー
```bash
# 鍵のパーミッション確認
ls -la ~/.ssh/monitoring_lab_key
# → -rw------- （600）であること

# 疎通確認
ssh -i ~/.ssh/monitoring_lab_key ubuntu@10.0.0.220 echo "OK"
```

### Prometheus接続エラー
```bash
# エンドポイント確認
curl http://10.0.0.220:9090/api/v1/query?query=up
```

---

## 開発サイクル

コードを変更したら再ビルドが必要:

```bash
cd mcp-servers/docker-mcp && npm run build
# Claude Codeを再起動
```

開発時は `tsx` で直接実行すると高速:
```bash
npx tsx mcp-servers/docker-mcp/src/index.ts
```
