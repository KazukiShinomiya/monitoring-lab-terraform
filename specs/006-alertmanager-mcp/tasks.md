# Tasks: Alertmanager MCP サーバー

**Input**: Design documents from `/specs/006-alertmanager-mcp/`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅

**Tests**: 安全設計（confirmed パラメータガード）のユニットテストのみ含む（US2・US3）。

**Organization**: Phase 1→2 は直列必須。Phase 3〜5 は Phase 2 完了後に順次可。US2・US3 は実装上密接なため直列推奨。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並行実施可能（別ファイル・他タスクへの依存なし）
- **[Story]**: 所属するユーザーストーリー（US1/US2/US3）

---

## Phase 1: Setup（プロジェクト初期化）

**Purpose**: `mcp/alertmanager-server/` ディレクトリとビルド設定を作成する

- [x] T001 `mcp/alertmanager-server/` ディレクトリを作成し、`src/tools/__tests__/` までのサブディレクトリ構造を作成する
- [x] T002 `mcp/alertmanager-server/package.json` を作成する（`docker-server/package.json` と同じ依存構成: `@modelcontextprotocol/sdk`, `zod`, `vitest`, `typescript`, `@types/node`。name: `monitoring-lab-alertmanager-mcp`）
- [x] T003 [P] `mcp/alertmanager-server/tsconfig.json` を作成する（`docker-server/tsconfig.json` の内容をそのまま使用）
- [x] T004 [P] `mcp/alertmanager-server/Dockerfile` を作成する（`docker-server/Dockerfile` と同構成: `node:22-alpine`、`apk add openssh-client`、`npm ci` + `npm run build`）

---

## Phase 2: Foundational（共通基盤）

**Purpose**: 全ツールが依存する型定義・HTTP クライアント・McpServer スキャフォールドを作成する

**⚠️ CRITICAL**: このフェーズ完了前は US 実装を開始しないこと

- [x] T005 `mcp/alertmanager-server/src/types.ts` を作成する（Alert・Silence・Matcher の TypeScript 型定義。`data-model.md` のフィールド定義を完全に反映する）
- [x] T006 `mcp/alertmanager-server/src/alertmanager-client.ts` を作成する（AlertmanagerClient クラス: コンストラクタで `ALERTMANAGER_HOST` 環境変数を読み取り、`getAlerts(filter?)` / `createSilence(params)` / `getSilences()` / `deleteSilence(silenceId)` の4メソッドを実装。Alertmanager API v2 を `fetch` で呼び出す）
- [x] T007 `mcp/alertmanager-server/src/index.ts` を作成する（McpServer スキャフォールド: `name: 'monitoring-lab-alertmanager-mcp', version: '1.0.0'`、`SIGINT`/`SIGTERM`/`uncaughtException`/`unhandledRejection` ハンドラー追加。ツール登録は後続フェーズで追加）

**Checkpoint**: プロジェクト構造・型定義・HTTPクライアント完成。US実装に進める。

---

## Phase 3: User Story 1 — アラート確認 (Priority: P1) 🎯 MVP

**Goal**: `alertmanager_get_alerts` ツールを呼び出し、アクティブアラートを一覧表示できること

**Independent Test**: Claude Code から `alertmanager_get_alerts` を呼び出し、リアルタイムのアラート状況（または「発火中のアラートはありません」）が返ること

### Implementation for User Story 1

- [x] T008 [US1] `mcp/alertmanager-server/src/tools/get-alerts.ts` を作成する（`handleGetAlerts(severity?: string)` 関数: AlertmanagerClient.getAlerts() を呼び出し、contracts/alertmanager-mcp-tools.md の出力フォーマット通りに整形して返す。silencedBy/inhibitedBy も表示する）
- [x] T009 [US1] `alertmanager_get_alerts` ツールを `mcp/alertmanager-server/src/index.ts` に登録する（Zod スキーマ: `severity: z.enum(['critical','warning']).optional()`、説明文: 「アクティブなアラートを一覧で取得する。severity でフィルタ可能」）
- [x] T010 [US1] WSL2 で `npm ci && npm run build` を実行し、コンパイルエラーがないことを確認する（`mcp/alertmanager-server/`）
- [x] T011 [US1] `docker build -t monitoring-lab-alertmanager-mcp .` で Docker イメージをビルドし、`alertmanager_get_alerts` の出力が contracts のフォーマットと一致することを確認する

**Checkpoint**: US1 完了。アラート確認フローが動作している。

---

## Phase 4: User Story 2 — サイレンス作成 (Priority: P2)

**Goal**: `alertmanager_silence_alert` を呼び出し、confirmed=false → ドライラン、confirmed=true → 実際に silence が作成されること

**Independent Test**: `alertmanager_silence_alert(alertname="TestAlert", duration_hours=1, confirmed=false)` → ドライラン表示。`confirmed=true` で再実行 → Alertmanager UI で silence を確認

### Implementation for User Story 2

- [x] T012 [US2] `mcp/alertmanager-server/src/tools/silence-alert.ts` を作成する（`handleSilenceAlert(params)` 関数: confirmed=false で contracts のドライランフォーマットを返す。confirmed=true で AlertmanagerClient.createSilence() を呼び出し、silence ID を含む成功メッセージを返す。過去の endsAt はバリデーションエラー）
- [x] T013 [US2] `mcp/alertmanager-server/src/tools/__tests__/silence-alert.test.ts` を作成する（テストケース: `confirmed=false` はドライランを返し API を呼ばない / `confirmed=true` は API を呼んで silence ID を返す / 過去の終了時刻はエラー）
- [x] T014 [US2] `alertmanager_silence_alert` ツールを `mcp/alertmanager-server/src/index.ts` に登録する（Zod スキーマ: `alertname: z.string()`, `duration_hours: z.number().positive().default(2)`, `additional_matchers: z.array(...).optional()`, `comment: z.string().default('...')`, `confirmed: z.boolean()`）
- [x] T015 [US2] Docker イメージを再ビルドし、ドライランと実際のサイレンス作成が contracts の出力フォーマット通りに動作することを確認する

**Checkpoint**: US1 + US2 完了。アラート確認→サイレンスのフローが繋がっている。

---

## Phase 5: User Story 3 — サイレンス管理 (Priority: P3)

**Goal**: `alertmanager_list_silences` で有効サイレンス一覧を確認し、`alertmanager_delete_silence` で不要なサイレンスを削除できること

**Independent Test**: `alertmanager_list_silences` → サイレンス一覧確認。`alertmanager_delete_silence(silence_id="...", confirmed=false)` → ドライラン確認。`confirmed=true` で削除 → 一覧から消えることを確認

### Implementation for User Story 3

- [x] T016 [P] [US3] `mcp/alertmanager-server/src/tools/list-silences.ts` を作成する（`handleListSilences()` 関数: AlertmanagerClient.getSilences() を呼び出し、contracts のフォーマットで一覧を返す。空のとき「有効なサイレンスはありません」を返す）
- [x] T017 [P] [US3] `mcp/alertmanager-server/src/tools/delete-silence.ts` を作成する（`handleDeleteSilence(silenceId, confirmed)` 関数: confirmed=false でドライランを返す。confirmed=true で AlertmanagerClient.deleteSilence() を呼び出す。存在しない ID はエラー）
- [x] T018 [US3] `mcp/alertmanager-server/src/tools/__tests__/silence-management.test.ts` を作成する（テストケース: list は全サイレンスを返す / delete confirmed=false はドライランを返し API を呼ばない / delete confirmed=true は API を呼ぶ / 存在しない ID はエラー）
- [x] T019 [US3] `alertmanager_list_silences` と `alertmanager_delete_silence` を `mcp/alertmanager-server/src/index.ts` に登録する（`delete_silence` の Zod スキーマ: `silence_id: z.string()`, `confirmed: z.boolean()`）
- [x] T020 [US3] Docker イメージを再ビルドし、全4ツールが contracts の出力フォーマット通りに動作することをエンドツーエンドで確認する

**Checkpoint**: 全3 US 完了。全4ツールが動作している。

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: MCP 登録・CI 追加・ドキュメント整備・コミット

- [x] T021 [P] `.mcp.json` に `alertmanager` サーバーエントリを追加する（`quickstart.md` の `.mcp.json` 追記内容を参照）
- [x] T022 [P] `.github/workflows/mcp-ci.yml` に `alertmanager-server` のビルド+テストジョブを追加する（既存の `docker-server` ジョブをテンプレートにして `mcp/alertmanager-server` へのパスに変更）
- [x] T023 [P] `docs/mcp-servers.md` に alertmanager-server のセクションを追加する（ツール一覧・用途・confirmed パターンの説明）
- [x] T024 Claude Code を再起動し、`mcp__alertmanager__*` ツール（get_alerts / silence_alert / list_silences / delete_silence）が deferred tools に表示されることを確認する
- [x] T025 変更ファイルをコミットする（`feat: Alertmanager MCP サーバーの実装`）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし。即開始可能
- **Foundational (Phase 2)**: Phase 1 完了後。**US実装をブロック**
- **US1 (Phase 3)**: Phase 2 完了後
- **US2 (Phase 4)**: Phase 2 完了後（US1 と並行可能だが同一 index.ts を編集するため直列推奨）
- **US3 (Phase 5)**: Phase 2 完了後（US2 完了後が望ましい）
- **Polish (Phase 6)**: 全 US 完了後

### Parallel Opportunities

- T003 と T004: tsconfig.json と Dockerfile は独立して並行作成可能
- T016 と T017: list-silences.ts と delete-silence.ts は独立して並行作成可能
- T021、T022、T023: .mcp.json / mcp-ci.yml / docs は独立して並行作成可能

---

## Parallel Example: Phase 6

```bash
# T021, T022, T023 を並行作成:
Task A: .mcp.json に alertmanager エントリ追加
Task B: .github/workflows/mcp-ci.yml に alertmanager-server ジョブ追加
Task C: docs/mcp-servers.md に alertmanager-server セクション追加
```

---

## Implementation Strategy

### MVP First (User Story 1 のみ)

1. Phase 1: Setup（T001-T004）
2. Phase 2: Foundational（T005-T007）
3. Phase 3: US1（T008-T011）— **`alertmanager_get_alerts` が動けば MVP 達成**
4. **STOP and VALIDATE**: Claude Code から実際にアラート一覧を確認
5. US2・US3 は後続で追加

### Incremental Delivery

1. Setup + Foundational → 共通基盤完成
2. US1 → `alertmanager_get_alerts` 動作（MVP！）
3. US2 → `alertmanager_silence_alert` 動作（confirmed ガード確認）
4. US3 → `alertmanager_list_silences` + `alertmanager_delete_silence` 動作
5. Polish → MCP 登録・CI 追加・コミット

---

## Summary

| フェーズ | タスク数 | 内容 |
|---------|---------|------|
| Phase 1: Setup | 4 | ディレクトリ・package.json・tsconfig・Dockerfile |
| Phase 2: Foundational | 3 | types.ts・AlertmanagerClient・index.ts スキャフォールド |
| Phase 3: US1 (P1) | 4 | get-alerts.ts 実装・登録・ビルド確認 |
| Phase 4: US2 (P2) | 4 | silence-alert.ts 実装・テスト・登録・確認 |
| Phase 5: US3 (P3) | 5 | list/delete-silences.ts 実装・テスト・登録・確認 |
| Phase 6: Polish | 5 | .mcp.json / CI / docs / 動作確認 / コミット |
| **合計** | **25** | |

**MVP スコープ**: Phase 1-3（T001〜T011）の11タスク完了で `alertmanager_get_alerts` が機能する状態になる。
