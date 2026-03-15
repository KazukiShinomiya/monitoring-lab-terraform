# Feature Specification: Alertmanager MCP サーバー

**Feature Branch**: `006-alertmanager-mcp`
**Created**: 2026-03-15
**Status**: Draft
**Input**: Alertmanager API を Claude Code MCP ツールとして公開。アラート確認・サイレンス操作を AI エージェントから行えるようにする。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — アラート発生時に即座に状況を把握する (Priority: P1)

Claude Code セッション内で、現在発火中のアラートを一覧で確認できる。対象アラートの severity・ラベル・開始時刻・ルーティング先などを把握し、次のアクション（調査・サイレンス・修正）の判断材料にする。

**Why this priority**: アラート確認は他のすべての操作の前提。「何が起きているか」を AI が把握できなければ、後続のサイレンスも提案もできない。他の US への依存なしに独立して機能する。

**Independent Test**: Claude Code で `get_active_alerts` を呼び出し、現在 Alertmanager に登録されているアラートの一覧が返ってくることを確認する。

**Acceptance Scenarios**:

1. **Given** Alertmanager にアクティブなアラートが存在する、**When** `get_active_alerts` を呼び出す、**Then** アラート名・severity・ラベル・発生時刻・状態（firing/pending）の一覧が返される
2. **Given** アラートが存在しない、**When** `get_active_alerts` を呼び出す、**Then** 空リストと「現在発火中のアラートはありません」メッセージが返される
3. **Given** アクティブアラートが存在する、**When** severity でフィルタして呼び出す、**Then** 指定 severity のアラートのみ返される

---

### User Story 2 — 誤検知アラートをサイレンスする (Priority: P2)

SynologyDiskHighUsage のような恒常的な誤検知や、計画メンテナンス中に発火するアラートを Claude Code から直接サイレンスできる。終了日時・対象ラベル・理由コメントを指定して Alertmanager に登録する。

**Why this priority**: US1 でアラートを把握した直後に、操作が必要になるケースが多い。サイレンス操作が UI 不要で AI から完結することで、「調査 → サイレンス」のフローが Claude Code 上で繋がる。

**Independent Test**: `silence_alert` ツールで `alertname=TestAlert` を 1 時間サイレンスし、Alertmanager UI で silence が登録されていることを確認する。

**Acceptance Scenarios**:

1. **Given** `confirmed: true` を含むリクエスト、**When** `silence_alert` を呼び出す、**Then** Alertmanager に silence が作成され、silence ID が返される
2. **Given** `confirmed: true` が指定されていない、**When** `silence_alert` を呼び出す、**Then** 操作は実行されず、確認要求のメッセージが返される
3. **Given** 存在しない alertname を指定、**When** `silence_alert` を呼び出す、**Then** エラーではなく、警告付きで silence が作成される（Alertmanager の仕様通り）
4. **Given** 期限切れの日時を指定、**When** `silence_alert` を呼び出す、**Then** バリデーションエラーが返される

---

### User Story 3 — 有効なサイレンスを確認・削除する (Priority: P3)

現在有効なサイレンスの一覧を確認し、不要になったサイレンスを削除できる。メンテナンス終了後や、誤ってサイレンスを登録したときに対処できる。

**Why this priority**: US1・US2 と組み合わせることでサイレンス管理が完結するが、US1・US2 だけでも十分な価値がある。実装工数が小さいため US2 と同時に実装することが多い。

**Independent Test**: `list_silences` で現在有効なサイレンス一覧を取得し、任意の silence ID を `delete_silence` で削除できることを確認する。

**Acceptance Scenarios**:

1. **Given** Alertmanager にアクティブなサイレンスが存在する、**When** `list_silences` を呼び出す、**Then** silence ID・対象マッチャー・終了時刻・コメントの一覧が返される
2. **Given** 有効な silence ID、**When** `delete_silence` を `confirmed: true` で呼び出す、**Then** silence が削除され、Alertmanager UI で確認できなくなる
3. **Given** 存在しない silence ID を指定、**When** `delete_silence` を呼び出す、**Then** エラーメッセージが返される
4. **Given** `confirmed: true` なし、**When** `delete_silence` を呼び出す、**Then** 操作は実行されず、確認要求のメッセージが返される

---

### Edge Cases

- Alertmanager が起動していない・到達不能な場合、接続エラーを適切なメッセージで返す
- silence の終了日時が過去の場合、バリデーションエラーを返す
- ネットワークタイムアウト発生時、リトライはせずエラーを返す
- Alertmanager API がエラーレスポンスを返した場合、ステータスコードとメッセージを含めてエラーを返す

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムは Alertmanager のアクティブアラートを一覧で返せること
- **FR-002**: アラートを severity（critical/warning）でフィルタリングできること
- **FR-003**: 指定した alertname・ラベル・終了日時・コメントでサイレンスを作成できること
- **FR-004**: 破壊的操作（サイレンス作成・削除）は `confirmed: true` パラメータが必須であること
- **FR-005**: `confirmed: true` なしで破壊的操作を呼び出した場合、操作を実行せず確認メッセージを返すこと
- **FR-006**: 現在有効なサイレンス一覧を返せること
- **FR-007**: 指定した silence ID のサイレンスを削除できること
- **FR-008**: Alertmanager が到達不能な場合、ユーザーフレンドリーなエラーメッセージを返すこと
- **FR-009**: Alertmanager のホスト URL は環境変数で設定可能であること（デフォルト: `http://YOUR_SERVER_IP:9093`）

### Key Entities

- **Alert**: アラート名・severity・ラベル集合・発生時刻・状態（firing/pending）・ジェネレーター URL を持つ
- **Silence**: silence ID・マッチャー（ラベル条件）・開始/終了日時・作成者・コメント・状態（active/expired）を持つ

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Claude Code から 1 回のツール呼び出しで現在のアラート状況を把握できること（追加の UI 操作不要）
- **SC-002**: サイレンス作成操作が 3 秒以内に完了し、Alertmanager UI で即座に確認できること
- **SC-003**: 破壊的操作（サイレンス作成・削除）は `confirmed: true` なしでは実行されないこと（安全設計）
- **SC-004**: 既存の MCP サーバー（docker/prometheus/terragrunt）と同一の操作感で使えること（ツール名・パラメータ命名規則の一貫性）

---

## Assumptions

- Alertmanager は `http://YOUR_SERVER_IP:9093` で稼働しており、Claude Code の実行環境（WSL2）からアクセス可能
- Alertmanager API v2 を使用（`/api/v2/alerts`, `/api/v2/silences`）
- サイレンス作成者（createdBy）は固定文字列 `claude-code` とする
- 既存の MCP サーバーと同じ Node.js + TypeScript + McpServer アーキテクチャを採用
