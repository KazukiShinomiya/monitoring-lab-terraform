# MCP Tool Contracts: Docker MCP Server

**Date**: 2026-03-07 | **Branch**: `002-docker-mcp-server`

---

## 読み取り系ツール

### docker_list_containers

全コンテナの名前・状態・起動経過時間を取得する。

**Input Schema**:
```json
{
  "type": "object",
  "properties": {},
  "required": []
}
```
（パラメーターなし）

**Output**: ContainerInfo[] の一覧テキスト

**Example response**:
```
NAME                        STATUS     UPTIME
monitoring-lab-grafana      running    2 hours ago
monitoring-lab-prometheus   running    2 hours ago
monitoring-lab-postgres     running    2 hours ago
monitoring-lab-newrelic     exited     5 minutes ago
```

---

### docker_get_logs

指定コンテナの直近ログを取得する。

**Input Schema**:
```json
{
  "type": "object",
  "properties": {
    "container_name": {
      "type": "string",
      "description": "コンテナ名（部分一致可。候補が複数ある場合は選択を促す）"
    },
    "lines": {
      "type": "number",
      "description": "取得するログ行数（デフォルト: 100）",
      "default": 100
    }
  },
  "required": ["container_name"]
}
```

**Output**: ログ文字列（最大 `lines` 行）

**Error cases**:
- コンテナが見つからない場合: `"Error: コンテナ 'xxx' が見つかりません"`
- 候補が複数ある場合: 候補一覧を返し、絞り込みを促す

---

### docker_get_stats

全コンテナのCPU・メモリ使用量を取得する。

**Input Schema**:
```json
{
  "type": "object",
  "properties": {},
  "required": []
}
```
（パラメーターなし）

**Output**: ContainerStats[] の一覧テキスト

**Example response**:
```
NAME                        CPU%    MEM USAGE / LIMIT    MEM%
monitoring-lab-grafana      0.5%    64MiB / 3.84GiB      1.6%
monitoring-lab-prometheus   2.3%    256MiB / 3.84GiB     6.5%
monitoring-lab-postgres     0.1%    128MiB / 3.84GiB     3.2%
```

---

## 操作系ツール（承認フロー付き）

### docker_restart_container

コンテナを再起動する。`confirmed: false` でドライラン（操作内容の確認のみ）。

**Input Schema**:
```json
{
  "type": "object",
  "properties": {
    "container_name": {
      "type": "string",
      "description": "再起動するコンテナ名（部分一致可）"
    },
    "confirmed": {
      "type": "boolean",
      "description": "false: 操作内容を表示して終了（ドライラン）。true: 実際に再起動を実行。"
    }
  },
  "required": ["container_name", "confirmed"]
}
```

**Output (confirmed=false)**:
```json
{
  "dry_run": true,
  "container_name": "monitoring-lab-grafana",
  "current_status": "running",
  "action": "restart",
  "message": "monitoring-lab-grafana を再起動します。実行するには confirmed=true で再度呼び出してください。"
}
```

**Output (confirmed=true)**:
```json
{
  "success": true,
  "container_name": "monitoring-lab-grafana",
  "action": "restarted",
  "new_status": "running",
  "message": "monitoring-lab-grafana を再起動しました。現在の状態: running"
}
```

**Error cases**:
- コンテナが見つからない場合: エラーメッセージを返す
- 操作失敗の場合: エラーメッセージ + 現在の状態を返す

---

### docker_stop_container

コンテナを停止する。`confirmed: false` でドライラン。

**Input Schema**:
```json
{
  "type": "object",
  "properties": {
    "container_name": {
      "type": "string",
      "description": "停止するコンテナ名（部分一致可）"
    },
    "confirmed": {
      "type": "boolean",
      "description": "false: 操作内容を表示して終了。true: 実際に停止を実行。"
    }
  },
  "required": ["container_name", "confirmed"]
}
```

**Output (confirmed=false)**:
```json
{
  "dry_run": true,
  "container_name": "monitoring-lab-newrelic",
  "current_status": "running",
  "action": "stop",
  "message": "monitoring-lab-newrelic を停止します。実行するには confirmed=true で再度呼び出してください。"
}
```

**Error cases**:
- 既に停止中のコンテナを停止しようとした場合: `"Error: monitoring-lab-newrelic は既に stopped 状態です。"`

---

### docker_start_container

停止中のコンテナを起動する。`confirmed: false` でドライラン。

**Input Schema**:
```json
{
  "type": "object",
  "properties": {
    "container_name": {
      "type": "string",
      "description": "起動するコンテナ名（部分一致可）"
    },
    "confirmed": {
      "type": "boolean",
      "description": "false: 操作内容を表示して終了。true: 実際に起動を実行。"
    }
  },
  "required": ["container_name", "confirmed"]
}
```

**Error cases**:
- 既に稼働中のコンテナを起動しようとした場合: `"Error: monitoring-lab-grafana は既に running 状態です。"`

---

## エラー共通仕様

| エラー種別 | 返却内容 |
|-----------|---------|
| SSH接続失敗 | `"Error: リモートサーバー (10.0.0.220) に接続できません。SSH鍵とネットワーク接続を確認してください。"` |
| コンテナ未発見 | `"Error: コンテナ 'xxx' が見つかりません。docker_list_containers で一覧を確認してください。"` |
| 候補複数 | コンテナ候補一覧を返し、完全名での再指定を促す |
| 操作タイムアウト | `"Error: 操作がタイムアウトしました。コンテナの状態が不明です。docker_list_containers で確認してください。"` |
