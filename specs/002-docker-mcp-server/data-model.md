# Data Model: Docker MCP Server

**Date**: 2026-03-07 | **Branch**: `002-docker-mcp-server`

---

## エンティティ定義

### ContainerInfo（コンテナ情報）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `name` | string | コンテナ名（例: `monitoring-lab-grafana`） |
| `status` | ContainerStatus | 稼働状態 |
| `uptime` | string | 起動経過時間（例: `2 hours ago`） |

### ContainerStatus（コンテナ状態）

```
"running" | "stopped" | "paused" | "restarting" | "exited" | "dead" | "created"
```

### ContainerStats（リソース使用量）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `name` | string | コンテナ名 |
| `cpu_percent` | string | CPU使用率（例: `2.34%`） |
| `memory_usage` | string | メモリ使用量（例: `128MiB / 4GiB`） |
| `memory_percent` | string | メモリ使用率（例: `3.12%`） |

### OperationResult（操作結果）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `success` | boolean | 操作成否 |
| `container_name` | string | 操作対象のコンテナ名（完全名） |
| `action` | string | 実行した操作（"restarted" / "stopped" / "started"） |
| `new_status` | ContainerStatus | 操作後の実際の状態 |
| `message` | string | 結果メッセージ |

### DryRunResult（ドライラン結果）

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `dry_run` | true | ドライランであることを示すフラグ |
| `container_name` | string | 操作対象のコンテナ名（完全名） |
| `current_status` | ContainerStatus | 現在の状態 |
| `action` | string | 実行予定の操作 |
| `message` | string | 確認メッセージ（「〜を再起動します。confirmed=true で実行してください。」） |

---

## 状態遷移

```
created → running ← → stopped/exited
              ↓
          restarting → running
              ↓
            paused ← → running
```

操作系ツールは以下の遷移のみ対応:
- `start`: stopped/exited → running
- `stop`: running → stopped
- `restart`: running → restarting → running

既に目的の状態にある場合はエラーを返す（Edge Case対応）。
