# Research: Alertmanager MCP サーバー

**Branch**: `006-alertmanager-mcp` | **Date**: 2026-03-15

---

## Decision 1: Alertmanager API バージョン

**Decision**: Alertmanager API v2（`/api/v2/`）を使用する

**Rationale**:
- 現在デプロイ中の `prom/alertmanager:latest` は v2 API を提供
- v1 API は deprecated（Alertmanager 0.19 以降）
- v2 は OpenAPI 仕様が公開されており、型安全な実装が可能

**Key Endpoints**:
```
GET  /api/v2/alerts           # アクティブアラート一覧（filter パラメータあり）
GET  /api/v2/silences         # サイレンス一覧
POST /api/v2/silences         # サイレンス作成
DELETE /api/v2/silence/{id}   # サイレンス削除
GET  /api/v2/status           # Alertmanager 状態確認
```

**Alternatives considered**: Alertmanager CLI (`amtool`) をシェルコマンドとして呼び出す方法も検討したが、HTTP API の方がポータブルでテスト可能。

---

## Decision 2: アーキテクチャ（既存 MCP サーバーと統一）

**Decision**: 既存の `docker-server` と同一のアーキテクチャを採用する

**Rationale**:
- TypeScript + `@modelcontextprotocol/sdk` + `McpServer`（高レベルAPI）
- Zod によるパラメータバリデーション
- `src/index.ts`（ツール登録）+ `src/tools/*.ts`（ハンドラー）+ `src/alertmanager-client.ts`（HTTP クライアント）
- Dockerfile: `node:22-alpine` ベース（docker-server と同一）
- `.mcp.json` に `alertmanager` エントリを追加

**Alternatives considered**: Prometheus MCP サーバーが `fetch` を直接使っているパターンもあるが、専用クライアントクラスの方が単体テストしやすい。

---

## Decision 3: HTTP クライアント

**Decision**: Node.js built-in `fetch`（`node-fetch` 不要）を使用する

**Rationale**:
- Node.js 18 以降で `fetch` は標準組み込み（Node 22 使用のため問題なし）
- 追加依存なし → イメージサイズ最小化
- Alertmanager API は JSON REST なので `fetch` で十分

---

## Decision 4: ツール命名規則

**Decision**: `alertmanager_` プレフィックスを統一的に使用する

| ツール名 | Alertmanager API | 操作 |
|---------|-----------------|------|
| `alertmanager_get_alerts` | GET /api/v2/alerts | アクティブアラート一覧 |
| `alertmanager_silence_alert` | POST /api/v2/silences | サイレンス作成 |
| `alertmanager_list_silences` | GET /api/v2/silences | サイレンス一覧 |
| `alertmanager_delete_silence` | DELETE /api/v2/silence/{id} | サイレンス削除 |

**Rationale**: 既存の `docker_*`, `mcp__prometheus__*`, `mcp__terragrunt__*` の命名パターンに合わせる。

---

## Decision 5: 環境変数設計

**Decision**: `ALERTMANAGER_HOST` 環境変数でホスト URL を設定する

```
ALERTMANAGER_HOST=http://YOUR_SERVER_IP:9093  # デフォルト値
```

- `.mcp.json` の `docker run` コマンドに `--env ALERTMANAGER_HOST=$ALERTMANAGER_HOST` を追加
- または、`.env` から読み取る bash インライン展開（terragrunt-server と同じ方式）

**Alternatives considered**: ハードコードは禁止（Constitution II）。Vault 経由は過剰（内部エンドポイント URL はシークレットではない）。

---

## Decision 6: サイレンス期間のデフォルト値

**Decision**: デフォルト期間は 2 時間とする

**Rationale**:
- 一般的な運用メンテナンス作業の時間感覚に合致
- 永続的サイレンスは `.env` のように別途管理すべき（今回スコープ外）
- ユーザーは `duration_hours` で上書き可能

---

## Constitution Check: 原則適合性

| 原則 | 評価 | 備考 |
|------|------|------|
| I. IaC | ✅ | コンテナは docker-compose.yml に定義。リモートサーバーへの変更なし |
| II. セキュリティ | ✅ | ALERTMANAGER_HOST は .env 管理。破壊的操作は confirmed 必須 |
| III. ドキュメント駆動 | ✅ | Speckit ADLC に従っている |
| IV. DRY | ✅ | 既存 docker-server と同一の package.json/tsconfig 構成 |
| V. 可観測性 | ✅ | MCP サーバーはローカル実行（cAdvisor 対象外、設計上の許容） |
