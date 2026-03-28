# Feature Specification: Vault シークレット管理 Step 1 — Alertmanager Webhook URL

**Feature Branch**: `009-vault-secrets`
**Created**: 2026-03-16
**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Vault に Webhook URL を格納する (Priority: P1)

オペレーターが Slack Webhook URL を `.env` ファイルではなく Vault に登録する。
Vault が唯一のシークレット保管場所となり、`.env` への依存を段階的に解消できる。

**Why this priority**: `.env` への依存をなくすことがこの機能の核心であり、他のすべてのストーリーの前提条件となるため。

**Independent Test**: Vault に Webhook URL を格納した後、`vault kv get` コマンドで値を取得できれば単独でテスト可能。Alertmanager の動作とは独立している。

**Acceptance Scenarios**:

1. **Given** Vault dev モードが稼働中（`http://10.0.0.220:8200`）、**When** オペレーターが Terragrunt apply を実行する、**Then** `secret/monitoring-lab/alertmanager` パスに Webhook URL が格納される
2. **Given** Vault に Webhook URL が格納済み、**When** `vault kv get secret/monitoring-lab/alertmanager` を実行する、**Then** `slack_webhook_url` キーで値が取得できる
3. **Given** Webhook URL を Vault に格納する仕組みが整っている、**When** URL をローテーション（更新）する、**Then** Vault 上のシークレットを更新するだけで完了し、他のファイルを変更する必要がない

---

### User Story 2 — Vault から Webhook URL を読み取って Alertmanager を設定する (Priority: P2)

`sync-config.sh` が `.env` ではなく Vault API から Webhook URL を取得し、Alertmanager 設定ファイルに反映する。
`.env` ファイルの `SLACK_WEBHOOK_URL` が不要になる。

**Why this priority**: US1 で格納した URL を実際に利用する仕組みであり、機能の完成に必要。

**Independent Test**: Vault に Webhook URL が格納されている状態で `sync-config.sh alertmanager` を実行し、リモートサーバーに反映された設定ファイルの内容を確認することで単独テスト可能。

**Acceptance Scenarios**:

1. **Given** Vault に Webhook URL が格納済みかつ `.env` の `SLACK_WEBHOOK_URL` が未設定、**When** `sync-config.sh alertmanager` を実行する、**Then** エラーなく Alertmanager 設定がリモートに反映される
2. **Given** sync-config.sh が Vault から URL を取得済み、**When** リモートサーバーの設定ファイルを確認する、**Then** `<YOUR_SLACK_WEBHOOK_URL>` プレースホルダーが実際の URL に置換されている
3. **Given** Vault が停止している、**When** `sync-config.sh alertmanager` を実行する、**Then** Vault 接続エラーが分かりやすいメッセージで表示され、処理が中断される

---

### User Story 3 — Alertmanager が引き続き Slack に通知できることを確認する (Priority: P3)

移行後もアラート通知が正常に機能していることをエンドツーエンドで確認する。
移行によって既存の監視機能が壊れていないことを保証する。

**Why this priority**: US1/US2 の完了後に検証するため、実装上の依存関係はないが品質保証に必要。

**Independent Test**: 既存のアラートを手動で発火させ（例: cAdvisor 停止）、Slack に通知が届くことで単独テスト可能。

**Acceptance Scenarios**:

1. **Given** Vault 経由の設定反映が完了、**When** Prometheus がアラートを発火させる、**Then** Slack `#monitoring-alerts` に通知が届く
2. **Given** 移行前後で Alertmanager の設定内容が同一、**When** `amtool check-config` を実行する、**Then** 設定検証が成功する

---

### Edge Cases

- Vault dev モード再起動時にシークレットが消える → 再度 `terragrunt apply` で格納できること
- `.env` に `SLACK_WEBHOOK_URL` が残っている場合の優先順位 → Vault 優先（`.env` は無視）
- Vault トークン（`root`）が `.env` に定義されていない場合 → 明確なエラーメッセージを表示
- Terragrunt コンテナから Vault（10.0.0.220:8200）へのネットワーク疎通が取れない場合 → `plan` 時にエラーで検出できること

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Vault KV v2 シークレットエンジンに `secret/monitoring-lab/alertmanager` パスで Slack Webhook URL を格納できること
- **FR-002**: 既存の `vault_secret` モジュールを拡張して Alertmanager 用シークレットリソースを追加できること
- **FR-003**: `sync-config.sh` が Vault API から Webhook URL を取得し、alertmanager.yml のプレースホルダーを置換できること
- **FR-004**: `.env` の `SLACK_WEBHOOK_URL` が未設定でも `sync-config.sh alertmanager` が正常完了すること
- **FR-005**: Vault が利用できない場合、`sync-config.sh` は処理を中断して明確なエラーを表示すること
- **FR-006**: 既存の監視アラート（Prometheus → Alertmanager → Slack）の動作を移行後も維持すること
- **FR-007**: Vault dev モード（Root Token: `root`）での動作を前提とし、追加の認証設定を不要とすること

### Key Entities

- **Vault KV v2 シークレット**: `secret/monitoring-lab/alertmanager` に格納されるシークレット。キー `slack_webhook_url` で Webhook URL を保持する。バージョン管理あり（max 5）
- **alertmanager.yml テンプレート**: `config/alertmanager/alertmanager.yml`。`<YOUR_SLACK_WEBHOOK_URL>` プレースホルダーを維持（Vault から取得した値で動的に置換される）
- **sync-config.sh**: Vault API 呼び出し機能を追加。`curl` + Vault HTTP API で URL を取得する

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Slack Webhook URL が `.env` ファイルに記載されていない状態で `sync-config.sh alertmanager` が正常完了する
- **SC-002**: Vault にシークレットを格納してから Alertmanager への反映が 5 分以内に完了する（手動 sync 実行）
- **SC-003**: URL をローテーション（Vault のシークレット更新 + sync 実行）した後、新しい URL でアラート通知が届く
- **SC-004**: 移行前後で既存の Slack アラート通知（FIRING / RESOLVED）が途切れない

---

## Assumptions

- Vault は dev モード（Root Token: `root`）で稼働しており、KV v2 マウント `secret/` はデフォルトで有効化されている
- `sync-config.sh` を実行するホストから Vault API（`http://10.0.0.220:8200`）にアクセスできる
- Vault トークンは `.env` の `VAULT_TOKEN` または環境変数から取得する（デフォルト: `root`）
- Alertmanager はファイルベースの設定を使用するため、Vault ネイティブの動的シークレット取得は行わない（sync 時の静的置換で対応）
- この機能は Step 1 であり、他のシークレット（DB パスワード、Grafana パスワード等）の Vault 管理は対象外

---

## Out of Scope

- Vault 本番モード化（unseal 管理、永続ストレージ設定）
- Alertmanager の Vault ネイティブ連携（エージェントサイドカーパターン等）
- DB 認証情報・Grafana パスワード等、他サービスのシークレット管理
- Vault ポリシーの細分化・最小権限設定
