# Quickstart: Docker MCP Server

**Branch**: `002-docker-mcp-server`

## 前提条件

- Docker Engine（WSL2上）が起動していること
- SSH鍵 `~/.ssh/id_rsa` が YOUR_SERVER_IP へのアクセス権を持つこと
- Node.js v22.x がインストール済みであること（ビルド用）

---

## 1. ビルド

```bash
cd mcp/docker-server

# 依存パッケージインストール
npm install

# TypeScriptコンパイル
npm run build

# Dockerイメージビルド
docker build -t monitoring-lab-docker-mcp .
```

---

## 2. 動作確認（手動テスト）

```bash
# コンテナ一覧ツールのテスト（ECHOでMCPメッセージを送信）
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  docker run --rm -i \
    --mount type=bind,src=${HOME}/.ssh/id_rsa,dst=/root/.ssh/id_rsa,readonly \
    monitoring-lab-docker-mcp
```

---

## 3. Claude Code への登録

WSL2環境で `.claude/settings.local.json`（または `~/.claude/settings.json`）に追加:

```json
{
  "mcpServers": {
    "docker": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "--mount", "type=bind,src=/home/ubuntu/.ssh/id_rsa,dst=/root/.ssh/id_rsa,readonly",
        "monitoring-lab-docker-mcp"
      ]
    }
  }
}
```

登録後、Claude Code を再起動するとツールが利用可能になる。

---

## 4. 使用例

Claude Codeとの会話で以下のように操作する:

```
ユーザー: コンテナの状態を確認して
Claude: [docker_list_containers を呼び出し、一覧を表示]

ユーザー: Grafanaのログを見せて
Claude: [docker_get_logs(container_name="grafana") を呼び出し、直近100行を表示]

ユーザー: Grafanaを再起動して
Claude: [docker_restart_container(container_name="grafana", confirmed=false) を呼び出し]
        monitoring-lab-grafana を再起動します。よろしいですか？

ユーザー: はい
Claude: [docker_restart_container(container_name="grafana", confirmed=true) を呼び出し]
        monitoring-lab-grafana を再起動しました。現在の状態: running
```

---

## 5. トラブルシューティング

| 症状 | 確認事項 |
|------|---------|
| SSH接続エラー | `ssh ubuntu@YOUR_SERVER_IP` で直接接続できるか確認 |
| SSH鍵マウントエラー | `~/.ssh/id_rsa` のパーミッションが `600` であるか確認 |
| コンテナが見つからない | `monitoring-lab-*` プレフィックスが付いているか確認 |
| タイムアウト | リモートサーバーの Docker が起動しているか確認 |
