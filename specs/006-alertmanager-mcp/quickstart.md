# Quickstart: Alertmanager MCP サーバー

## 前提条件

- WSL2 (Ubuntu-24.04) で Docker Engine が起動済み
- `mnt/e/work/labo/.env` に `ALERTMANAGER_HOST` が設定済み（任意、省略時は `http://10.0.0.220:9093`）
- Alertmanager コンテナが `http://10.0.0.220:9093` で稼働中

## ビルド

```bash
# WSL2 から実行
cd /mnt/e/work/labo/mcp/alertmanager-server
docker build -t monitoring-lab-alertmanager-mcp .
```

## 動作確認（スタンドアロン）

```bash
# アラート一覧を取得するテスト
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"alertmanager_get_alerts","arguments":{}}}' \
  | docker run --rm -i monitoring-lab-alertmanager-mcp
```

## Claude Code への登録

`.mcp.json` の `mcpServers` に以下を追加する:

```json
"alertmanager": {
  "command": "wsl",
  "args": [
    "-d", "Ubuntu-24.04", "--",
    "docker", "run", "--rm", "-i",
    "--env", "ALERTMANAGER_HOST=http://10.0.0.220:9093",
    "monitoring-lab-alertmanager-mcp"
  ]
}
```

その後 Claude Code を再起動すると `mcp__alertmanager__*` ツールが利用可能になる。

## ユニットテスト

```bash
cd /mnt/e/work/labo/mcp/alertmanager-server
npm ci
npm test
```

## サイレンス操作の例

```
# アクティブアラートを確認
→ alertmanager_get_alerts

# SynologyDiskHighUsage を 24 時間サイレンス（ドライラン）
→ alertmanager_silence_alert(alertname="SynologyDiskHighUsage", duration_hours=24, confirmed=false)

# 実際に作成
→ alertmanager_silence_alert(alertname="SynologyDiskHighUsage", duration_hours=24, confirmed=true)

# サイレンス一覧を確認
→ alertmanager_list_silences

# サイレンス削除（ドライラン）
→ alertmanager_delete_silence(silence_id="...", confirmed=false)
```
