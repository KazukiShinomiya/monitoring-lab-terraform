# Data Model: MCP自己成長基盤

**Branch**: `001-mcp-self-growth` | **Date**: 2026-03-01

---

## エンティティ一覧

### 1. Proposal（改善提案）

AIが生成する変更提案。緊急度分類・対象コンポーネント・期待効果を含む。

```typescript
interface Proposal {
  id: string;               // UUID v4
  urgency: 'low' | 'medium' | 'high';
  target: string;           // 対象コンテナ名または "infrastructure"
  content: string;          // 提案内容（Markdown形式、日本語）
  expected_effect: string;  // 期待効果（定量的に記述）
  evidence: Evidence[];     // 根拠データ（メトリクス・ログ）
  created_at: string;       // ISO 8601
  status: ProposalStatus;
}

type ProposalStatus = 'pending' | 'approved' | 'rejected' | 'applied' | 'rolled_back';

interface Evidence {
  type: 'metric' | 'log' | 'alert';
  source: string;           // "prometheus", "docker_logs", etc.
  data: string;             // 生データまたはサマリー
  timestamp: string;        // ISO 8601
}
```

**バリデーションルール**:
- `id`: UUID v4形式
- `urgency`: enum値のみ
- `target`: `/^[a-z0-9_-]+$/` または "infrastructure"
- `content`: 空文字不可、Markdown
- `evidence`: 少なくとも1件以上（根拠なき提案は却下）
- `created_at`: ISO 8601形式

---

### 2. ApprovalLog（承認ログ）

ユーザーが承認・却下した提案の記録。ロールバック用の設定スナップショットを含む。

```typescript
interface ApprovalLog {
  id: string;               // UUID v4
  proposal_id: string;      // Proposal.id への参照
  decision: 'approved' | 'rejected';
  decided_at: string;       // ISO 8601
  decided_by: string;       // "user"（将来の拡張のため）
  snapshot_before?: ConfigSnapshot;  // 承認時のみ記録（ロールバック用）
  applied_at?: string;      // apply完了時刻
  apply_result?: string;    // apply結果サマリー
}

interface ConfigSnapshot {
  service: string;          // 変更対象サービス名
  file_path: string;        // 変更されたTerragruntファイルパス
  content_before: string;   // 変更前のファイル内容（フル）
  terragrunt_state?: string; // 変更前のterragrunt plan出力
  captured_at: string;      // スナップショット取得時刻
}
```

**バリデーションルール**:
- `proposal_id`: 対応するProposalが存在すること
- `snapshot_before`: decision が "approved" の場合は必須
- `content_before`: ロールバック時に自動復元するため必須

---

### 3. EffectReport（効果測定レポート）

変更適用後のメトリクス比較。定量的な改善値を含む。

```typescript
interface EffectReport {
  id: string;               // UUID v4
  proposal_id: string;      // Proposal.id への参照
  approval_id: string;      // ApprovalLog.id への参照
  measured_at: string;      // 測定時刻（apply後5〜15分後）
  metrics_before: MetricSnapshot[];
  metrics_after: MetricSnapshot[];
  delta_summary: string;    // 改善値の日本語サマリー
  success: boolean;         // 目標達成したか
}

interface MetricSnapshot {
  query: string;            // PromQLクエリ
  value: number;            // スカラー値
  unit: string;             // "bytes", "percent", "count" など
  timestamp: string;        // ISO 8601
}
```

---

### 4. ProposalIndex（提案インデックス）

高速検索用の軽量インデックス。個別JSONを読まずに一覧表示できる。

```typescript
interface ProposalIndex {
  last_updated: string;
  total: number;
  items: ProposalIndexItem[];
}

interface ProposalIndexItem {
  id: string;
  urgency: 'low' | 'medium' | 'high';
  target: string;
  status: ProposalStatus;
  created_at: string;
  content_preview: string;  // contentの先頭100文字
}
```

---

## 状態遷移図

```
[AI生成]
    ↓
 pending ──────────────→ rejected
    |                       （ApprovalLog: decision=rejected）
    ↓ (ユーザー承認)
 approved
    |
    ↓ (terragrunt apply 成功)
 applied ──────────────→ rolled_back
    |                       （ApprovalLog snapshot_before から復元）
    |
    ↓ (永続状態)
[EffectReport 生成]
```

---

## ファイル永続化レイアウト

```
mcp-servers/.mcp-data/
├── proposals/
│   ├── index.json                      # ProposalIndex
│   └── 550e8400-e29b-41d4-a716-XXX.json  # Proposal
├── approvals/
│   ├── index.json
│   └── 6ba7b810-9dad-11d1-80b4-YYY.json  # ApprovalLog
└── reports/
    └── 6ba7b811-9dad-11d1-80b4-ZZZ.json  # EffectReport
```

**Note**: `.mcp-data/` は `.gitignore` に追加する（個人の監視データのため）

---

## エンティティ関係図

```
Proposal (1) ──────────→ (0..1) ApprovalLog
                                      │
                                      ↓
                              (0..1) EffectReport
```
