# Tasks: MCP自己成長基盤

**Input**: Design documents from `specs/001-mcp-self-growth/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/prometheus-tools.ts, contracts/terragrunt-tools.ts

**Tests**: テストは仕様書で明示的に要求されていないため省略。

**Organization**: ユーザーストーリー単位でフェーズを分割。Docker MCP Server (`mcp/docker-server/`) は実装・動作確認済みのため対象外。Prometheus MCP と Terragrunt MCP を実装する。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 並列実行可能（異なるファイル、依存なし）
- **[Story]**: 対応するユーザーストーリー（US1〜US3）
- 各タスクには正確なファイルパスを含む

---

## Phase 1: Setup（プロジェクト初期化）

**Purpose**: `mcp/prometheus-server/` と `mcp/terragrunt-server/` の骨格を構築する

- [x] T001 Create directory structures `mcp/prometheus-server/src/tools/` and `mcp/terragrunt-server/src/tools/` per plan.md
- [x] T002 [P] Initialize npm project in `mcp/prometheus-server/package.json` with `@modelcontextprotocol/sdk` and `zod` (mirror `mcp/docker-server/package.json` structure)
- [x] T003 [P] Initialize npm project in `mcp/terragrunt-server/package.json` with `@modelcontextprotocol/sdk`, `zod`, and `uuid` dependencies
- [x] T004 [P] Configure TypeScript in `mcp/prometheus-server/tsconfig.json` (target: ES2022, module: NodeNext, outDir: dist) per `mcp/docker-server/tsconfig.json`
- [x] T005 [P] Configure TypeScript in `mcp/terragrunt-server/tsconfig.json` (target: ES2022, module: NodeNext, outDir: dist)
- [x] T006 [P] Create `mcp/prometheus-server/Dockerfile` using `node:22-alpine` (no SSH needed — HTTP直接アクセス)
- [x] T007 [P] Create `mcp/terragrunt-server/Dockerfile` using `node:22-alpine` + `openssh-client` with `StrictHostKeyChecking no` SSH config per R-002

---

## Phase 2: Foundational（全ストーリーの基盤）

**Purpose**: 全ツールが共有するクライアント・ストレージ・スケルトンを実装する

**CRITICAL**: このフェーズ完了前にユーザーストーリーの実装は開始しない

- [x] T008 Define shared types in `mcp/prometheus-server/src/types.ts`: `Proposal`, `ProposalStatus`, `Evidence`, `ProposalIndex`, `ProposalIndexItem`, `MetricSnapshot` per data-model.md
- [x] T009 Define shared types in `mcp/terragrunt-server/src/types.ts`: `ApprovalLog`, `ConfigSnapshot`, `EffectReport`, `MetricSnapshot` per data-model.md
- [x] T010 [P] Implement `PrometheusClient` in `mcp/prometheus-server/src/prometheus-client.ts`: `query(expr, time?)`, `queryRange(expr, start, end, step)`, `getAlerts()` — using Node.js built-in `fetch` to `http://YOUR_SERVER_IP:9090/api/v1/`
- [x] T011 [P] Implement `SshClient` in `mcp/terragrunt-server/src/ssh-client.ts`: `execSsh(command): string` using `child_process.execFile('ssh', ['-o StrictHostKeyChecking=no', '-i', sshKeyPath, 'ubuntu@YOUR_SERVER_IP', command])` per R-002. コマンドインジェクション防止: サービス名はVALID_SERVICESホワイトリストで検証
- [x] T012 [P] Implement `StorageService` in `mcp/prometheus-server/src/storage.ts`: `saveProposal(p)`, `getProposal(id)`, `updateProposalStatus(id, status)`, `listProposals()` — JSON files at `.mcp-data/proposals/` per data-model.md file layout
- [x] T013 [P] Implement `StorageService` in `mcp/terragrunt-server/src/storage.ts`: `saveApprovalLog(log)`, `getApprovalLog(id)`, `saveEffectReport(report)` — JSON files at `.mcp-data/approvals/` and `.mcp-data/reports/`
- [x] T014 Create MCP server skeleton in `mcp/prometheus-server/src/index.ts`: import `McpServer` from `@modelcontextprotocol/sdk/server/mcp.js`, `StdioServerTransport`, empty tool handlers, connect transport. `console.log` 禁止（stdioはJSON-RPC専用）
- [x] T015 Create MCP server skeleton in `mcp/terragrunt-server/src/index.ts`: same structure as T014

**Checkpoint**: `npm run build` が両サーバーで成功し、`echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | node dist/index.js` が `{"result":{"tools":[]}}` を返すこと

---

## Phase 3: US1 - AIによるインフラ異常の検出と改善提案（Priority: P1）MVP

**Goal**: Prometheus MCP の3ツールが動作し、AIがメトリクス・アラートを参照して改善提案を日本語で生成できる

**Independent Test**: Claude Codeに「インフラの状態を確認して」と伝えると、コンテナのCPU/メモリ状況とアクティブアラートが取得され、問題があれば日本語の改善提案が返ること

- [x] T016 [P] [US1] Implement `query_metrics` tool in `mcp/prometheus-server/src/tools/query-metrics.ts`: `PrometheusClient.query()` を呼び出し `QueryMetricsOutput` 形式で返却。エラー時は SSH 接続エラー相当のメッセージ per contracts/prometheus-tools.ts
- [x] T017 [P] [US1] Implement `query_range` tool in `mcp/prometheus-server/src/tools/query-range.ts`: `start` に `now-1h` 形式をサポート（`Date.now() - duration` に変換）、`PrometheusClient.queryRange()` を呼び出し `QueryRangeOutput` 形式で返却
- [x] T018 [P] [US1] Implement `get_active_alerts` tool in `mcp/prometheus-server/src/tools/get-active-alerts.ts`: `PrometheusClient.getAlerts()` を呼び出し `severity` でフィルタリングして `GetActiveAlertsOutput` 形式で返却
- [x] T019 [US1] Register `query_metrics`, `query_range`, `get_active_alerts` in `mcp/prometheus-server/src/index.ts`: add to `server.tool()` calls with inputSchema from contracts/prometheus-tools.ts
- [x] T020 [US1] Build Docker image: `docker build -t monitoring-lab-prometheus-mcp mcp/prometheus-server/` and validate `echo '...tools/list...' | docker run --rm -i monitoring-lab-prometheus-mcp` returns 3 tools
- [x] T021 [US1] Register prometheus MCP in `.mcp.json`: add `"prometheus"` server entry with `docker run --rm -i monitoring-lab-prometheus-mcp` (no SSH key mount needed — HTTP direct access)

**Checkpoint**: 「コンテナのメモリ使用量を教えて」でPromQLクエリ結果が返り、「アクティブなアラートは？」でアラート一覧が返ること

---

## Phase 4: US2 - 承認ワンステップで安全に変更を適用（Priority: P2）

**Goal**: Terragrunt MCP の5ツールと Prometheus MCP の `compare_metrics` が動作し、提案→承認→適用→効果測定→ロールバックの一連フローが完結する

**Independent Test**: `plan_service` で変更内容確認 → `apply_service`（approval_id付き）で適用 → `compare_metrics` で効果測定 → `rollback_service` で復元、の全ステップが動作すること

- [x] T022 [US2] Implement `compare_metrics` tool in `mcp/prometheus-server/src/tools/compare-metrics.ts`: `baseline_time` と `current_time` の2点で同一PromQLクエリを実行し、delta_absolute・delta_percent・improved・日本語 summary を返却 per contracts/prometheus-tools.ts `CompareMetricsOutput`
- [x] T023 [US2] Register `compare_metrics` in `mcp/prometheus-server/src/index.ts`, rebuild image `monitoring-lab-prometheus-mcp`
- [x] T024 [P] [US2] Implement `plan_service` tool in `mcp/terragrunt-server/src/tools/plan-service.ts`: `SshClient.execSsh()` で `docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local/${service} && terragrunt plan 2>&1'` を実行。VALID_SERVICESホワイトリスト検証必須。`PlanServiceOutput` 形式で返却 per contracts/terragrunt-tools.ts
- [x] T025 [P] [US2] Implement `get_service_config` tool in `mcp/terragrunt-server/src/tools/get-service-config.ts`: `SshClient.execSsh()` で `cat /workspace/terraform/envs/local/${service}/terragrunt.hcl` を実行。`GetServiceConfigOutput` 形式で返却
- [x] T026 [P] [US2] Implement `list_workspaces` tool in `mcp/terragrunt-server/src/tools/list-workspaces.ts`: HCP Terraform API `GET /api/v2/organizations/YOUR_TF_ORG/workspaces` を `fetch()` で呼び出し。`TF_TOKEN` 環境変数から Bearer Token 取得。`ListWorkspacesOutput` 形式で返却
- [x] T027 [US2] Implement `apply_service` tool in `mcp/terragrunt-server/src/tools/apply-service.ts`: (1) `approval_id` で `StorageService.getApprovalLog()` を検索し存在確認（承認なし実行禁止）、(2) `ConfigSnapshot` をSSH経由でキャプチャ、(3) `docker exec monitoring-lab-terragrunt sh -c 'cd ... && terragrunt apply -auto-approve 2>&1'` 実行、(4) `ApplyServiceOutput` 返却 per contracts/terragrunt-tools.ts and FR-006
- [x] T028 [US2] Implement `rollback_service` tool in `mcp/terragrunt-server/src/tools/rollback-service.ts`: (1) `getApprovalLog(approval_id)` で `snapshot_before` を取得、(2) SSH経由で `content_before` をファイルに書き戻し、(3) `terragrunt apply -auto-approve` 実行、(4) `RollbackServiceOutput` 返却 per FR-009（ユーザーが元の値を指定不要）
- [x] T029 [US2] Register all 5 tools in `mcp/terragrunt-server/src/index.ts`: `plan_service`, `get_service_config`, `list_workspaces`, `apply_service`, `rollback_service`
- [x] T030 [US2] Build Docker image: `docker build -t monitoring-lab-terragrunt-mcp mcp/terragrunt-server/` and validate 5 tools returned by `tools/list`
- [x] T031 [US2] Register terragrunt MCP in `.mcp.json`: `docker run --rm -i --mount type=bind,src=/home/ubuntu/.ssh/id_rsa,dst=/root/.ssh/id_rsa,readonly --mount type=bind,src=${PWD}/.mcp-data,dst=/app/.mcp-data monitoring-lab-terragrunt-mcp`. 環境変数 `TF_TOKEN` を `--env` で渡す

**Checkpoint**: 「prometheusのTerragrunt設定を見せて」→設定取得。「planを実行して」→差分確認。apply_service → compare_metrics → rollback_service の一連フローが動作すること

---

## Phase 5: US3 - 緊急度に応じた対応フローの選択（Priority: P3）

**Goal**: AIがアラート状態とメトリクスから緊急度（low/medium/high）を自動分類し、緊急度に応じた Proposal を生成・永続化できる

**Independent Test**: 発火中アラートあり→high、メモリ80%超→medium、全正常→low の3パターンで正しく分類されること

- [x] T032 [US3] Implement urgency classifier in `mcp/prometheus-server/src/urgency.ts`: `classifyUrgency(alerts: GetActiveAlertsOutput, highMemContainers: string[]): 'low' | 'medium' | 'high'` — firing アラートあり→high、メモリ80%超コンテナあり→medium、なし→low
- [x] T033 [US3] Implement `generate_proposal` tool in `mcp/prometheus-server/src/tools/generate-proposal.ts`: (1) `get_active_alerts` + `query_metrics`（全コンテナメモリ使用率）を並列実行、(2) `classifyUrgency()` で緊急度判定、(3) `Proposal` オブジェクト生成（UUID v4、evidence 含む）、(4) `StorageService.saveProposal()` で永続化、(5) Proposal ID と日本語サマリーを返却 per data-model.md `Proposal` schema
- [x] T034 [US3] Register `generate_proposal` in `mcp/prometheus-server/src/index.ts`, rebuild image `monitoring-lab-prometheus-mcp`

**Checkpoint**: 「インフラを分析して改善提案を生成して」で Proposal が `.mcp-data/proposals/` に保存され、緊急度付きの日本語提案が返ること

---

## Phase 6: Polish & 統合検証

**Purpose**: 動作確認・登録・ドキュメント整備・gitignore 設定

- [x] T035 Add `.mcp-data/` to `.gitignore` (個人の監視データ・承認ログを除外) per data-model.md Note
- [x] T036 [P] Validate full US1 flow: Claude Codeに「インフラ状態を確認して改善提案を生成して」→ Proposal生成・保存確認
- [x] T037 [P] Validate full US2 flow: plan_service → （手動でApprovalLog作成）→ apply_service → compare_metrics → rollback_service の動作確認
- [x] T038 [P] Create `mcp/prometheus-server/README.md` with build steps, `.mcp.json` registration, and tool usage examples
- [x] T039 [P] Create `mcp/terragrunt-server/README.md` with build steps, SSH key mount, TF_TOKEN setup, and tool usage examples

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 依存なし — 即時開始可能
- **Foundational (Phase 2)**: Phase 1 完了後 — 全ユーザーストーリーをブロック
- **US1 (Phase 3)**: Phase 2 完了後 — US2/US3 に非依存
- **US2 (Phase 4)**: Phase 2 完了後、US1の `compare_metrics` 追加あり（T022-T023 を先行）
- **US3 (Phase 5)**: Phase 2 完了後 — US1の `get_active_alerts` / `query_metrics` を内部利用（コード依存なし）
- **Polish (Phase 6)**: 必要なフェーズ完了後

### User Story Dependencies

| ストーリー | 優先度 | 依存 | 備考 |
|-----------|-------|------|------|
| US1 インフラ分析・提案 | P1 | Phase 2 | Prometheus MCP 3ツール |
| US2 承認→適用→効果測定 | P2 | Phase 2 + T022-T023 | Terragrunt MCP 5ツール + compare_metrics |
| US3 緊急度分類 | P3 | Phase 2 | generate_proposal ツール追加 |

### 並列実行例

#### Phase 1
```
T001 完了後:
  T002 + T003 + T004 + T005 + T006 + T007 を並列実行
```

#### Phase 2 完了後
```
T016 + T017 + T018 (US1) を並列実行
T024 + T025 + T026 (US2 読み取り系) を並列実行（T022完了後）
```

---

## Implementation Strategy

### MVP First（US1のみ）

1. Phase 1: Setup 完了
2. Phase 2: Foundational 完了（CRITICAL）
3. Phase 3: US1 完了 → `query_metrics`, `query_range`, `get_active_alerts` が動作
4. **STOP and VALIDATE**: Claude Codeで「コンテナの状態を確認して」が動作することを確認
5. 価値確認後に US2 へ

### Incremental Delivery

1. Setup + Foundational → ビルド基盤
2. **US1** → Prometheusメトリクス照会が会話で完結（MVP）
3. **US2** → Terragrunt操作・効果測定が承認フロー付きで可能
4. **US3** → 緊急度分類・Proposal永続化が自動化
5. Polish → 全統合確認・ドキュメント完成

---

## Notes

- [P] タスク = 異なるファイル、依存なし → 並列実行推奨
- Docker MCP Server (`mcp/docker-server/`) は実装済み — このタスクリストには含まない
- `console.log()` 禁止: stdioはJSON-RPC 2.0専用。`console.error()` またはファイルロガーを使用
- apply_service は `approval_id` がストレージに存在することを必須チェック（FR-006: 自動適用禁止）
- rollback_service は `snapshot_before.content_before` を自動復元（FR-009: ユーザーが元の値を指定不要）
- `.mcp-data/` のbind mountパスは起動環境に応じて `.mcp.json` で調整が必要
