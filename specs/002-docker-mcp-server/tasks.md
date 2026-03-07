# Tasks: Docker MCP Server

**Input**: Design documents from `specs/002-docker-mcp-server/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/mcp-tools.md

**Tests**: テストは仕様書で明示的に要求されていないため省略。

**Organization**: ユーザーストーリー単位でフェーズを分割し、各ストーリーが独立してテスト・デリバリー可能な構成。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイル、依存なし）
- **[Story]**: 対応するユーザーストーリー（US1〜US5）
- 各タスクには正確なファイルパスを含む

---

## Phase 1: Setup（プロジェクト初期化）

**Purpose**: `mcp/docker-server/` のプロジェクト骨格を構築する

- [ ] T001 Create directory structure `mcp/docker-server/src/tools/` per plan.md
- [ ] T002 Initialize npm project with `@modelcontextprotocol/sdk` and `zod` in `mcp/docker-server/package.json`
- [ ] T003 [P] Configure TypeScript compiler in `mcp/docker-server/tsconfig.json` (target: ES2022, module: NodeNext, outDir: dist)
- [ ] T004 [P] Create `mcp/docker-server/Dockerfile` using `node:22-alpine` + `docker-cli` + `openssh-client` with `StrictHostKeyChecking no` SSH config per R-005

---

## Phase 2: Foundational（全ストーリーの基盤）

**Purpose**: 全ツールが共有する型定義・DockerClient・MCPサーバー骨格を実装する

**CRITICAL**: このフェーズ完了前にユーザーストーリーの実装は開始しない

- [ ] T005 Define shared TypeScript types in `mcp/docker-server/src/types.ts`: `ContainerInfo`, `ContainerStatus`, `ContainerStats`, `OperationResult`, `DryRunResult` per data-model.md
- [ ] T006 Implement `DockerClient` class in `mcp/docker-server/src/docker-client.ts`: `execDocker(args)`, `listContainers()`, `findContainer(name)` (partial match + ambiguity error), `getContainerStatus(name)`, `getLogs(name, lines)`, `getStats()`, `restartContainer(name)`, `stopContainer(name)`, `startContainer(name)` — all using `child_process.execFile('docker', ['-H', 'ssh://ubuntu@10.0.0.220', ...args])` per R-002
- [ ] T007 Create MCP server skeleton in `mcp/docker-server/src/index.ts`: import `Server` from `@modelcontextprotocol/sdk`, setup `StdioServerTransport`, define `tools/list` and `tools/call` handlers (empty, to be extended per story), connect transport per R-001

**Checkpoint**: `npm run build` が成功し、`echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/index.js` が `{"result":{"tools":[]}}` を返すこと

---

## Phase 3: US1 - コンテナ状態の自然言語照会（Priority: P1）MVP

**Goal**: `docker_list_containers` ツールが動作し、全コンテナの名前・状態・起動経過時間を返す

**Independent Test**: Claude Codeに「コンテナの一覧を教えて」と伝えると、稼働中の全コンテナ名・状態・起動経過時間が返ること

- [ ] T008 [US1] Implement `docker_list_containers` tool handler in `mcp/docker-server/src/tools/list-containers.ts`: call `DockerClient.listContainers()`, format output as `NAME / STATUS / UPTIME` table, handle SSH connection error per contracts/mcp-tools.md error spec
- [ ] T009 [US1] Register `docker_list_containers` in `mcp/docker-server/src/index.ts`: add to `tools/list` response with inputSchema `{}`, add `tools/call` dispatch case

**Checkpoint**: 「コンテナの状態を確認して」で全コンテナ一覧が返答される

---

## Phase 4: US2 - コンテナログの取得（Priority: P1）

**Goal**: `docker_get_logs` ツールが動作し、指定コンテナの直近ログを返す

**Independent Test**: 「Grafanaのログを見せて」でログが返り、存在しないコンテナ名では適切なエラーが返ること

- [ ] T010 [US2] Implement `docker_get_logs` tool handler in `mcp/docker-server/src/tools/get-logs.ts`: accept `container_name` (partial match via `DockerClient.findContainer`) and `lines` (default 100), handle not-found / ambiguous match errors per contracts/mcp-tools.md
- [ ] T011 [US2] Register `docker_get_logs` in `mcp/docker-server/src/index.ts`: add to `tools/list` with inputSchema `{container_name: string, lines?: number}`, add `tools/call` dispatch case

**Checkpoint**: 「Prometheusのログを100行見せて」でログが返り、不明コンテナ名ではエラーが返ること

---

## Phase 5: US3 - リソース使用量の確認（Priority: P2）

**Goal**: `docker_get_stats` ツールが動作し、全コンテナのCPU・メモリ使用量を返す

**Independent Test**: 「コンテナのリソース使用量を教えて」で `NAME / CPU% / MEM USAGE / MEM%` 形式の一覧が返ること

- [ ] T012 [US3] Implement `docker_get_stats` tool handler in `mcp/docker-server/src/tools/get-stats.ts`: call `DockerClient.getStats()` using `docker stats --no-stream --format json`, parse into `ContainerStats[]`, format as table string per contracts/mcp-tools.md example response
- [ ] T013 [US3] Register `docker_get_stats` in `mcp/docker-server/src/index.ts`: add to `tools/list` with inputSchema `{}`, add `tools/call` dispatch case

**Checkpoint**: 「どのコンテナが一番リソースを使ってる？」でCPU・メモリ一覧が返ること

---

## Phase 6: US4 - コンテナの再起動（Priority: P2）

**Goal**: `docker_restart_container` ツールが承認フロー付きで動作する。`confirmed=false` でドライラン、`confirmed=true` で実行

**Independent Test**: `confirmed=false` で `DryRunResult` JSON が返り、`confirmed=true` で再起動後 `OperationResult` JSON が返ること

- [ ] T014 [US4] Implement `docker_restart_container` tool handler in `mcp/docker-server/src/tools/restart-container.ts`: (1) `findContainer` で完全名解決、(2) `confirmed=false` → `DryRunResult` を返す、(3) `confirmed=true` → `restartContainer` 実行、完了後 `getContainerStatus` で状態確認して `OperationResult` を返す per contracts/mcp-tools.md and R-003/R-004
- [ ] T015 [US4] Register `docker_restart_container` in `mcp/docker-server/src/index.ts`: add to `tools/list` with inputSchema `{container_name: string, confirmed: boolean}` (both required), add `tools/call` dispatch case

**Checkpoint**: 「Grafanaを再起動して」→ 確認メッセージ → confirmed=true → 再起動完了メッセージ の一連フローが動作すること

---

## Phase 7: US5 - コンテナの停止・起動（Priority: P3）

**Goal**: `docker_stop_container` と `docker_start_container` が承認フロー付きで動作する。既に目的の状態のコンテナへの操作は事前キャンセル

**Independent Test**: 稼働中コンテナの停止・停止中コンテナの起動が承認後に実行される。既にその状態のコンテナへの操作はエラーが返ること

- [ ] T016 [P] [US5] Implement `docker_stop_container` tool handler in `mcp/docker-server/src/tools/stop-container.ts`: `confirmed=false` → `DryRunResult`、`confirmed=true` → 状態確認（running以外はエラー）、`stopContainer` 実行、`OperationResult` 返却 per contracts/mcp-tools.md and R-004
- [ ] T017 [P] [US5] Implement `docker_start_container` tool handler in `mcp/docker-server/src/tools/start-container.ts`: `confirmed=false` → `DryRunResult`、`confirmed=true` → 状態確認（stopped/exited以外はエラー）、`startContainer` 実行、`OperationResult` 返却 per contracts/mcp-tools.md and R-004
- [ ] T018 [US5] Register `docker_stop_container` and `docker_start_container` in `mcp/docker-server/src/index.ts`: add both to `tools/list` with inputSchema `{container_name: string, confirmed: boolean}`, add both `tools/call` dispatch cases

**Checkpoint**: 「New Relicを停止して」→ 確認 → 停止完了。「New Relicを起動して」→ 確認 → 起動完了。停止中コンテナへの停止は「既にstopped状態です」エラーが返ること

---

## Phase 8: Polish & 統合検証

**Purpose**: ビルド・動作確認・Claude Code統合登録

- [ ] T019 Build Docker image and run quickstart.md validation in `mcp/docker-server/`: `docker build -t monitoring-lab-docker-mcp .` → `echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | docker run --rm -i --mount ...` で6ツール全件が `tools/list` に返ること
- [ ] T020 [P] Register MCP server in `.claude/settings.local.json` with WSL2 path `/home/ubuntu/.ssh/id_rsa` per quickstart.md Section 3
- [ ] T021 [P] Update `mcp/docker-server/README.md` with build steps, Claude Code registration, and tool usage examples per quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即時開始可能
- **Foundational (Phase 2)**: Phase 1 完了後 — 全ユーザーストーリーをブロック
- **US1 (Phase 3)**: Phase 2 完了後 — 他ストーリーに非依存
- **US2 (Phase 4)**: Phase 2 完了後 — US1に非依存（並列開始可能）
- **US3 (Phase 5)**: Phase 2 完了後 — US1/US2に非依存（並列開始可能）
- **US4 (Phase 6)**: Phase 2 完了後 — 読み取り系と並列開始可能
- **US5 (Phase 7)**: US4 完了後推奨（承認フローパターンを参照）
- **Polish (Phase 8)**: 必要なフェーズ完了後

### User Story Dependencies

| ストーリー | 優先度 | 依存 | 並列可否 |
|-----------|-------|------|---------|
| US1 コンテナ一覧 | P1 | Phase 2 | US2/US3/US4と並列可 |
| US2 ログ取得 | P1 | Phase 2 | US1/US3/US4と並列可 |
| US3 リソース確認 | P2 | Phase 2 | US1/US2/US4と並列可 |
| US4 再起動 | P2 | Phase 2 | US1-3と並列可 |
| US5 停止・起動 | P3 | US4 | US4後に推奨 |

### 並列実行例

#### Phase 1
```
T001 (ディレクトリ作成) 完了後:
  T002 (package.json) + T003 (tsconfig.json) + T004 (Dockerfile) を並列実行
```

#### Phase 2 完了後
```
T007 完了後:
  T008-T009 (US1) + T010-T011 (US2) + T012-T013 (US3) + T014-T015 (US4) を並列実行
```

#### Phase 7
```
  T016 (stop-container.ts) + T017 (start-container.ts) を並列実行
  T018 (両ツール登録) は T016, T017 完了後
```

---

## Implementation Strategy

### MVP First（US1のみ）

1. Phase 1: Setup 完了
2. Phase 2: Foundational 完了（CRITICAL）
3. Phase 3: US1 完了 → `docker_list_containers` が動作
4. **STOP and VALIDATE**: Claude Codeに接続してコンテナ一覧が取得できることを確認
5. 価値確認後に次のストーリーへ

### Incremental Delivery

1. Setup + Foundational → ビルドが通る基盤
2. **US1** → コンテナ一覧確認が会話で完結（MVP）
3. **US2** → ログ確認も会話で完結
4. **US3** → リソース確認も会話で完結
5. **US4** → 再起動が承認フロー付きで可能
6. **US5** → 停止・起動が承認フロー付きで可能
7. Polish → Dockerイメージ検証・登録完了

---

## Notes

- [P] タスク = 異なるファイル、依存なし → 並列実行推奨
- [Story] ラベルはユーザーストーリーへのトレーサビリティ
- 各ストーリーのCheckpointで実際にClaude Codeと会話して動作確認すること
- 読み取り系3ツール（list/logs/stats）は `confirmed` パラメーター不要
- 操作系3ツールは `confirmed: boolean` 必須（R-003）、実行前状態チェック必須（R-004）
- エラーメッセージはすべて contracts/mcp-tools.md のエラー共通仕様に準拠すること
