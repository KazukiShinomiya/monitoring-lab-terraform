# Data Model: Alertmanager MCP サーバー

**Branch**: `006-alertmanager-mcp` | **Date**: 2026-03-15

---

## エンティティ: Alert（アラート）

Alertmanager が受信・管理するアラートのデータ構造。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `alertname` | string | アラート名（labels.alertname） |
| `severity` | string | 重要度（labels.severity: "critical" / "warning"） |
| `labels` | Record<string, string> | Prometheus ラベル集合 |
| `annotations` | Record<string, string> | アノテーション（description, summary など） |
| `startsAt` | ISO8601 string | アラート発生時刻 |
| `endsAt` | ISO8601 string | アラート終了時刻（0001-01-01 = 未終了） |
| `status.state` | "firing" / "pending" / "resolved" | 現在の状態 |
| `status.inhibitedBy` | string[] | このアラートを抑制している inhibit_rule の源 |
| `status.silencedBy` | string[] | このアラートを抑制している silence ID 一覧 |
| `generatorURL` | string | アラートを生成した Prometheus ルールの URL |

**状態遷移**:
```
pending → firing → resolved
                ↑
         inhibited (inhibitedBy に値あり)
         silenced  (silencedBy に値あり)
```

---

## エンティティ: Silence（サイレンス）

アラートの通知を一時的に抑制するルールのデータ構造。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `id` | string (UUID) | Alertmanager が付与する一意 ID |
| `matchers` | Matcher[] | 対象アラートを特定するラベルマッチャー |
| `startsAt` | ISO8601 string | サイレンス開始時刻 |
| `endsAt` | ISO8601 string | サイレンス終了時刻 |
| `createdBy` | string | 作成者（本システムでは `claude-code` 固定） |
| `comment` | string | サイレンスの理由・説明 |
| `status.state` | "active" / "pending" / "expired" | 現在の状態 |

**Matcher の構造**:

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `name` | string | ラベル名（例: `alertname`, `severity`） |
| `value` | string | 一致する値（例: `SynologyDiskHighUsage`） |
| `isRegex` | boolean | 正規表現マッチを使用するか |
| `isEqual` | boolean | 等号マッチか不等号マッチか |

**状態遷移**:
```
pending → active → expired
```
- `pending`: startsAt が未来
- `active`: startsAt 経過 & endsAt 未到達
- `expired`: endsAt 経過 または手動削除

---

## ツール入力スキーマ（Zod 定義イメージ）

### alertmanager_get_alerts
```typescript
{
  severity?: z.enum(['critical', 'warning']).optional()
  // フィルタなし = 全アクティブアラート
}
```

### alertmanager_silence_alert
```typescript
{
  alertname: z.string(),           // 必須: サイレンス対象のアラート名
  duration_hours: z.number().positive().default(2),  // サイレンス持続時間（時間単位）
  additional_matchers: z.array(z.object({            // 追加マッチャー（省略可）
    name: z.string(),
    value: z.string(),
  })).optional(),
  comment: z.string().default('claude-code によるサイレンス'),
  confirmed: z.boolean(),          // 必須: true で実行、false でドライラン
}
```

### alertmanager_list_silences
```typescript
{
  // パラメータなし（全サイレンス取得）
}
```

### alertmanager_delete_silence
```typescript
{
  silence_id: z.string(),  // 削除する silence の UUID
  confirmed: z.boolean(),  // 必須: true で実行、false でドライラン
}
```
