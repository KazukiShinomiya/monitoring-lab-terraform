# Implementation Plan: Alertmanager MCP サーバー

**Branch**: `006-alertmanager-mcp` | **Date**: 2026-03-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-alertmanager-mcp/spec.md`

---

## Summary

Alertmanager API v2 を Claude Code の MCP ツールとして公開する TypeScript サーバーを実装する。既存の `docker-server`（`mcp/docker-server/`）と同一のアーキテクチャを採用し、4つのツール（get_alerts / silence_alert / list_silences / delete_silence）を提供する。破壊的操作には `confirmed: true` パラメータを必須とする安全設計。

---

## Technical Context

**Language/Version**: TypeScript 5.x + Node.js 22 (LTS)
**Primary Dependencies**: `@modelcontextprotocol/sdk ^1.0.0`, `zod ^4.x`
**Storage**: N/A（ステートレス。Alertmanager が永続化を担う）
**Testing**: vitest ^4.x（既存サーバーと同一バージョン）
**Target Platform**: WSL2 (Ubuntu-24.04) 上の Docker コンテナ（`node:22-alpine`）
**Project Type**: Single（MCP サーバー単体）
**Performance Goals**: ツール呼び出し → 応答 3 秒以内（SC-002 準拠）
**Constraints**: ALERTMANAGER_HOST は環境変数で設定（ハードコード禁止）
**Scale/Scope**: 4 ツール、1 HTTP クライアント、3 テストファイル

---

## Constitution Check

| 原則 | 評価 | 備考 |
|------|------|------|
| I. IaC | ✅ | MCP サーバーはローカル docker run で起動。`.mcp.json` が「定義」。リモートサーバー変更なし |
| II. セキュリティ | ✅ | ALERTMANAGER_HOST は環境変数管理。`confirmed` 必須で破壊的操作を保護 |
| III. ドキュメント駆動 | ✅ | spec → research → data-model → contracts → plan の順で作成済み |
| IV. DRY | ✅ | `docker_container` モジュール不使用（MCP はローカル実行）。TypeScript コード構造は docker-server と共通 |
| V. 可観測性 | ✅ | MCP サーバーはローカル開発ツール。cAdvisor 対象外は設計上の許容（⑧で確認済み） |

**Constitution Check: 全原則 PASS。実装に進む。**

---

## Project Structure

### Documentation (this feature)

```text
specs/006-alertmanager-mcp/
├── spec.md              ✅ 作成済み
├── research.md          ✅ 作成済み
├── data-model.md        ✅ 作成済み
├── quickstart.md        ✅ 作成済み
├── contracts/
│   └── alertmanager-mcp-tools.md  ✅ 作成済み
├── checklists/
│   └── requirements.md  ✅ 作成済み
└── tasks.md             （/speckit.tasks で生成）
```

### Source Code (repository root)

```text
mcp/alertmanager-server/
├── Dockerfile                      # node:22-alpine ベース
├── package.json                    # @modelcontextprotocol/sdk + zod + vitest
├── tsconfig.json                   # docker-server と同一設定
├── src/
│   ├── index.ts                    # McpServer 初期化・ツール登録
│   ├── alertmanager-client.ts      # Alertmanager API v2 HTTP クライアント
│   ├── types.ts                    # Alert / Silence の TypeScript 型定義
│   └── tools/
│       ├── get-alerts.ts           # alertmanager_get_alerts ハンドラー
│       ├── silence-alert.ts        # alertmanager_silence_alert ハンドラー
│       ├── list-silences.ts        # alertmanager_list_silences ハンドラー
│       ├── delete-silence.ts       # alertmanager_delete_silence ハンドラー
│       └── __tests__/
│           ├── get-alerts.test.ts
│           ├── silence-alert.test.ts
│           └── silence-management.test.ts
└── dist/                           # ビルド成果物（.gitignore）
```

**Structure Decision**: docker-server と同一レイアウト。`alertmanager-client.ts` が docker-server の `docker-client.ts` に相当する。

---

## Implementation Design

### AlertmanagerClient クラス

```typescript
class AlertmanagerClient {
  private baseUrl: string;

  constructor() {
    this.baseUrl = process.env.ALERTMANAGER_HOST ?? 'http://YOUR_SERVER_IP:9093';
  }

  async getAlerts(filter?: { severity?: string }): Promise<Alert[]>
  async createSilence(params: CreateSilenceParams): Promise<{ silenceId: string }>
  async getSilences(): Promise<Silence[]>
  async deleteSilence(silenceId: string): Promise<void>
}
```

### confirmed パターン（全破壊的操作に適用）

```typescript
if (!confirmed) {
  return { content: [{ type: 'text', text: dryRunMessage }] };
}
// 実際の操作を実行
```

### ビルドパイプライン

```
npm run build  →  tsc  →  dist/
docker build   →  node:22-alpine + npm ci + tsc
```

---

## .mcp.json 追記内容

```json
"alertmanager": {
  "command": "wsl",
  "args": [
    "-d", "Ubuntu-24.04", "--",
    "docker", "run", "--rm", "-i",
    "--env", "ALERTMANAGER_HOST=http://YOUR_SERVER_IP:9093",
    "monitoring-lab-alertmanager-mcp"
  ]
}
```

---

## GitHub Actions (mcp-ci.yml) 更新

既存の `.github/workflows/mcp-ci.yml` に `alertmanager-server` のビルド+テストジョブを追加する。

---

## Complexity Tracking

なし（Constitution 全原則 PASS、複雑さの追加なし）
