# Tool Contracts: Alertmanager MCP サーバー

**Branch**: `006-alertmanager-mcp` | **Date**: 2026-03-15

---

## alertmanager_get_alerts

**説明**: アクティブなアラートを一覧で取得する

**Input**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `severity` | `"critical"` \| `"warning"` | No | フィルタ条件。省略時は全件返す |

**Output (success)**:
```
🚨 アクティブアラート: 2件

1. [CRITICAL] TargetDown
   ラベル: job=cadvisor, instance=cadvisor:8080
   発生: 2026-03-15T10:00:00Z (35分前)
   状態: firing
   説明: cAdvisor が応答していません

2. [WARNING] SynologyDiskHighUsage
   ラベル: job=snmp_synology
   発生: 2026-03-15T09:30:00Z (65分前)
   状態: silenced by: [0dd03ace]
```

**Output (no alerts)**:
```
✅ 現在発火中のアラートはありません
```

**Error cases**:
- Alertmanager 到達不能 → `❌ Alertmanager に接続できません: http://YOUR_SERVER_IP:9093`

---

## alertmanager_silence_alert

**説明**: 指定したアラートをサイレンスする（confirmed=false でドライラン）

**Input**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `alertname` | string | Yes | サイレンス対象のアラート名 |
| `duration_hours` | number | No | サイレンス持続時間（デフォルト: 2） |
| `additional_matchers` | `{name,value}[]` | No | 追加ラベルマッチャー |
| `comment` | string | No | サイレンス理由（デフォルト: "claude-code によるサイレンス"） |
| `confirmed` | boolean | Yes | false: ドライラン表示のみ、true: 実際に作成 |

**Output (confirmed=false)**:
```
🔍 ドライラン: 以下のサイレンスを作成します

  対象: alertname="SynologyDiskHighUsage"
  期間: 2026-03-15T14:00:00Z 〜 2026-03-15T16:00:00Z (2時間)
  作成者: claude-code
  コメント: NAS空き容量確保困難なため

実際に作成するには confirmed=true で再実行してください
```

**Output (confirmed=true, success)**:
```
✅ サイレンスを作成しました

  Silence ID: a1b2c3d4-...
  対象: alertname="SynologyDiskHighUsage"
  有効期限: 2026-03-15T16:00:00Z
```

**Error cases**:
- `confirmed` パラメータなし → `⚠️ confirmed パラメータが必要です。confirmed=false でドライランを確認してください`
- 過去の終了時刻 → `❌ endsAt が過去の時刻です: ...`

---

## alertmanager_list_silences

**説明**: 有効なサイレンス一覧を取得する

**Input**: なし

**Output (success)**:
```
🔇 有効なサイレンス: 1件

1. ID: 0dd03ace-...
   対象: alertname="SynologyDiskHighUsage"
   有効期限: 2026-12-31T23:59:59Z
   作成者: claude-code
   コメント: NAS空き容量確保困難なため（2026-03-15 設定）
   状態: active
```

**Output (empty)**:
```
✅ 有効なサイレンスはありません
```

---

## alertmanager_delete_silence

**説明**: 指定した silence ID のサイレンスを削除する（confirmed=false でドライラン）

**Input**:
| パラメータ | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `silence_id` | string | Yes | 削除する silence の UUID |
| `confirmed` | boolean | Yes | false: ドライラン表示のみ、true: 実際に削除 |

**Output (confirmed=false)**:
```
🔍 ドライラン: 以下のサイレンスを削除します

  Silence ID: 0dd03ace-...
  対象: alertname="SynologyDiskHighUsage"
  有効期限: 2026-12-31T23:59:59Z

実際に削除するには confirmed=true で再実行してください
```

**Output (confirmed=true, success)**:
```
✅ サイレンスを削除しました

  Silence ID: 0dd03ace-...
  対象: alertname="SynologyDiskHighUsage"
```

**Error cases**:
- 存在しない ID → `❌ 指定されたサイレンスが見つかりません: 0dd03ace-...`
- `confirmed` なし → `⚠️ confirmed パラメータが必要です`
