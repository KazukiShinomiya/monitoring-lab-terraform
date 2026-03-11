# MCP Best Practices Checklist: MCP自己成長基盤

**Purpose**: Anthropic MCPベストプラクティスへの準拠を定期的に検証するための監査チェックリスト
**Created**: 2026-03-11
**Feature**: [spec.md](../spec.md)
**対象サーバー**: `mcp/docker-server`, `mcp/prometheus-server`, `mcp/terragrunt-server`
**参照**: [Anthropic MCP Documentation](https://modelcontextprotocol.io/docs)

> **使い方**: 新MCPサーバー追加時・SDK major update時・四半期ごとに実施。各項目を確認したら `[x]` に変更。

---

## 1. API実装パターン

- [ ] CHK001 - 3サーバー全てで `McpServer`（高レベルAPI）を使用しており、低レベル `Server + setRequestHandler` を直接使っていないか？ [Compliance, Spec §FR-001〜003]
- [ ] CHK002 - トランスポートに `StdioServerTransport` を使用しており、代替実装（HTTP等）への切り替え要件が未定義のまま放置されていないか？ [Completeness]
- [ ] CHK003 - `server.tool(name, description, schema, handler)` の4引数シグネチャを全ツールで統一しているか？ [Consistency]
- [ ] CHK004 - `await server.connect(transport)` をエントリポイントの末尾で呼んでおり、接続前にハンドラ登録が完了しているか？ [Clarity]

---

## 2. 入力バリデーション（Zodスキーマ）

- [ ] CHK005 - 全ツールの入力スキーマが `z.string()`, `z.boolean()`, `z.enum()` 等で明示的に型定義されており、`any` や `unknown` をスキーマとして使っていないか？ [Completeness, Spec §FR-001〜003]
- [ ] CHK006 - `.describe()` による日本語説明が全パラメータに付与されており、Claude が文脈から推論せざるを得ない曖昧なパラメータが残っていないか？ [Clarity]
- [ ] CHK007 - `z.enum(VALID_SERVICES)` のような動的な enum で、追加されたサービスがソース（`ssh-client.ts` の `VALID_SERVICES`）に反映されるか？ [Consistency]
- [ ] CHK008 - `z.optional().default(...)` を使うパラメータで、デフォルト値の意味・単位が `.describe()` 内に明記されているか？ [Clarity]

---

## 3. エラーハンドリング

- [ ] CHK009 - 全ツールの handler が `try/catch` で囲まれており、例外が `McpServer` フレームワークまで伝播しないか？ [Coverage, Spec §FR-004]
- [ ] CHK010 - エラー時のレスポンスが `{ content: [{ type: 'text', text: message }], isError: true }` 形式であり、単純な `throw` で終わっていないか？ [Completeness]
- [ ] CHK011 - エラーメッセージが日本語で具体的な対処方法を含んでおり、「エラーが発生しました」のような情報量ゼロのメッセージになっていないか？ [Clarity]
- [ ] CHK012 - SSH接続・Docker接続のタイムアウトが全ツールで適切に設定されており、無限待機するケースが残っていないか？ [Edge Case Coverage]

---

## 4. プロセスライフサイクル

- [ ] CHK013 - 3サーバー全ての `index.ts` に `SIGINT` ハンドラが実装されており、Claude Code 終了時にゾンビプロセスが発生しないか？ [Completeness]
- [ ] CHK014 - 3サーバー全ての `index.ts` に `SIGTERM` ハンドラが実装されており、コンテナ停止時のクリーン終了が保証されているか？ [Completeness]
- [ ] CHK015 - `uncaughtException` ハンドラが `process.stderr.write()` を使っており、MCP プロトコルが流れる `stdout` を汚染しないか？ [Consistency]
- [ ] CHK016 - `unhandledRejection` ハンドラが実装されており、非同期エラーが静かに飲み込まれて MCP 通信が壊れるリスクが排除されているか？ [Coverage]

---

## 5. ツール設計・安全性

- [ ] CHK017 - 破壊的操作（restart/stop/start/apply/rollback）に `confirmed: boolean` または `approval_id: string` の明示的ガードが実装されており、誤操作が防止されているか？ [Spec §FR-008, Compliance]
- [ ] CHK018 - 読み取り専用ツール（list/get/query/plan）と書き込みツール（apply/rollback/restart等）が明確に区別されており、ツール説明に副作用の有無が明記されているか？ [Clarity]
- [ ] CHK019 - `dry_run=true` パターンを使うツールで、副作用なし（保存なし・変更なし）であることがツール説明に明示されているか？ [Clarity]
- [ ] CHK020 - コンテナ名の部分一致検索で複数候補が出た場合の動作（エラー返却・候補一覧提示）が定義されており、曖昧なまま操作されるケースが排除されているか？ [Edge Case Coverage]

---

## 6. 設定・セキュリティ

- [ ] CHK021 - 全 MCP サーバーの設定値（ホスト・ポート・パス等）が環境変数経由で外部化されており、コード内にハードコードされた接続先が残っていないか？ [Compliance]
- [ ] CHK022 - `.mcp.json` の `env` フィールドまたは安全なシークレット管理（Claude Code settings 等）を使っており、シェルスクリプトで `.env` を grep するような脆弱な方法が残っていないか？ [Security, Gap]
- [ ] CHK023 - SSH 接続で `StrictHostKeyChecking=no` を使っている場合、その意図がコメントで明記されており、本番環境への誤適用リスクが管理されているか？ [Assumption]
- [ ] CHK024 - Docker イメージが `--rm -i` フラグで起動されており、MCPセッション終了後にコンテナが残存しないか？ [Compliance]

---

## 7. SDK・依存関係

- [ ] CHK025 - `@modelcontextprotocol/sdk` のバージョンが最新 minor を追跡しており、重要なバグ修正やセキュリティパッチを見逃していないか？ [Dependency]
- [ ] CHK026 - `package.json` の `^1.0.0` 指定が意図した範囲のアップデートを許可しており、破壊的変更が混入するリスクを認識しているか？ [Assumption]
- [ ] CHK027 - Dependabot（または同等の自動更新）が設定されており、SDK 更新を人手で追跡する必要がないか？ [Gap]
- [ ] CHK028 - `devDependencies` と `dependencies` の分類が正しく、実行時に不要なパッケージが Docker イメージに含まれていないか？ [Completeness]

---

## 8. テスト・CI

- [ ] CHK029 - 3サーバー全てに `vitest` によるユニットテストが存在し、ビジネスロジック（dry_run ガード・承認フロー・フィルタ動作）がカバーされているか？ [Coverage, Spec §NFR]
- [ ] CHK030 - GitHub Actions CI が設定されており、`mcp/*/src/index.ts` 変更時にビルド+テストが自動実行されるか？ [Gap]
- [ ] CHK031 - テストのモックデータが実際の型定義（`ProposalIndex`, `ApprovalLog` 等）と一致しており、型エラーでビルドが通らないテストが残っていないか？ [Consistency]
- [ ] CHK032 - 新しい MCP サーバーを追加する際の手順（ビルド・テスト・`.mcp.json` 登録・Docker ビルド）が `docs/mcp-servers.md` に文書化されているか？ [Completeness]

---

## 9. 将来対応（ギャップ項目）

- [ ] CHK033 - MCP の `Resources`（ファイル・URL の公開）や `Prompts`（定型プロンプトテンプレート）が必要になった場合の実装方針が検討されているか？ [Gap]
- [ ] CHK034 - SDK が streaming レスポンス（長時間 apply 中の進捗表示等）をサポートした場合、`apply_service` 等のツールに適用する計画があるか？ [Gap]
- [ ] CHK035 - OAuth 認証が MCP 標準に組み込まれた場合、現在の SSH 鍵ベース認証との整合性を再評価する予定があるか？ [Assumption]

---

## Notes

- **実施タイミング**: 新 MCP サーバー追加時 / `@modelcontextprotocol/sdk` の major update 時 / 四半期レビュー時
- **優先ガードレール**: CHK013〜016（プロセスライフサイクル）・CHK017〜018（破壊的操作ガード）は毎回必須確認
- **自動化済み**: CHK029〜031 は CI で継続的に検証済み（GitHub Actions 設定後）
- **参考**: [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) | [Anthropic MCP Docs](https://modelcontextprotocol.io)
