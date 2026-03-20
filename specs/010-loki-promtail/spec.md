# Feature Specification: Loki + Promtail ログ収集基盤

**Feature Branch**: `010-loki-promtail`
**Created**: 2026-03-20
**Status**: Draft
**Input**: Loki + Promtail によるログ収集基盤の追加。既存の Prometheus + Grafana スタックにログ収集を統合し、メトリクスとログの相関分析を可能にする。Terragrunt の既存 docker_container モジュールを使ってリモートDocker環境（YOUR_SERVER_IP）にデプロイする。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - ログ収集基盤のデプロイ (Priority: P1)

監視基盤の運用者（ジント）が、`terragrunt run-all apply` を実行することで Loki と Promtail がリモート環境に起動し、監視基盤コンテナのログが自動的に Loki に収集される状態になる。

**Why this priority**: ログが収集されなければ後続のすべての機能が成立しない。他のストーリーの前提条件となる最小の価値単位。

**Independent Test**: Loki と Promtail のコンテナが起動した直後に、Loki の HTTP API でログエントリが存在することを確認できれば独立して検証可能。

**Acceptance Scenarios**:

1. **Given** `terraform/envs/local/loki` と `terraform/envs/local/promtail` が存在しない状態で、**When** `terragrunt run-all apply` を実行したとき、**Then** 両コンテナが monitoring-lab ネットワーク内で Running 状態になる
2. **Given** Loki と Promtail が起動している状態で、**When** 任意の監視基盤コンテナがログを出力したとき、**Then** 30 秒以内に Loki の API（`/loki/api/v1/query`）でそのログが取得できる
3. **Given** Loki が停止した状態で、**When** Promtail がログを収集しようとしたとき、**Then** Promtail はエラーをログに記録しつつ自動リトライを継続し、Loki 再起動後に収集を再開する

---

### User Story 2 - Grafana でのログ検索・閲覧 (Priority: P2)

監視基盤の運用者が Grafana の Explore 画面を開き、LogQL を使って任意のコンテナのログを検索・閲覧できる。コンテナ名やログレベルでフィルタリングして素早く目的のログにたどり着ける。

**Why this priority**: ログ収集基盤が稼働した次のステップは、実際に人間が閲覧できること。Grafana は既存スタックの一部であり、追加の UI コストなしに実現できる。

**Independent Test**: Grafana の Explore 画面で Loki データソースを選択し、`{container_name=~".+"}` を実行してログ一覧が表示されれば独立して検証可能。

**Acceptance Scenarios**:

1. **Given** Grafana に Loki データソースが設定されている状態で、**When** Explore 画面でコンテナ名を指定した LogQL クエリを実行したとき、**Then** 対象コンテナのログが時系列順に表示される
2. **Given** ログが Loki に蓄積されている状態で、**When** 特定のキーワード（例: `error`）で全文検索したとき、**Then** 該当するログエントリのみが絞り込まれて表示される
3. **Given** Loki データソースが設定されていない状態で、**When** Grafana を起動したとき、**Then** プロビジョニング設定により自動的に Loki データソースが追加されている

---

### User Story 3 - メトリクスとログの相関分析 (Priority: P3)

監視基盤の運用者が Grafana のダッシュボードまたは Explore 画面で、Prometheus アラート発生時刻と同じ時間軸で対象コンテナのログを確認し、障害の根本原因を素早く特定できる。

**Why this priority**: メトリクス+ログの相関分析がこの機能の最終的な価値。P1/P2 が完了していれば Grafana の標準機能で実現できるが、設定と操作手順の整備が必要。

**Independent Test**: 既存の cAdvisor ダッシュボードでメトリクスの時刻を指定し、同じ時刻のコンテナログを Explore で確認できれば独立して検証可能。

**Acceptance Scenarios**:

1. **Given** Prometheus と Loki の両方にデータが蓄積されている状態で、**When** Grafana Explore で左ペインに Prometheus メトリクス・右ペインに Loki ログを同一時間範囲で表示したとき、**Then** 両者の時系列が同期して表示される（Split view）
2. **Given** アラートが発生したとき、**When** アラート発生時刻の前後 5 分のログを LogQL で検索したとき、**Then** 1 分以内に対象コンテナのエラーログを特定できる

---

### Edge Cases

- Promtail が収集済みのログを再起動後に重複して収集しないか（position ファイルによる重複排除の動作確認）
- Loki が一時停止した場合に Promtail がログを失わずにリトライするか
- 単一コンテナのログ量が急増した場合（バースト時）の Loki への影響
- 既存の Grafana プロビジョニング設定（datasources.yml）への追加変更が既存データソースに影響しないか
- コンテナ名に特殊文字が含まれる場合のラベル付与の挙動

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Loki サービスが monitoring-lab ネットワーク内で常時稼働し、ログエントリを受け入れる状態であること
- **FR-002**: Promtail サービスが monitoring-lab ネットワーク上の全監視基盤コンテナのログを自動収集すること
- **FR-003**: 収集されたログがコンテナ名・サービス名・ホスト名のラベル付きで Loki に保存されること
- **FR-004**: Grafana に Loki データソースがプロビジョニング設定により自動追加されること（手動設定不要）
- **FR-005**: ログの保持期間がデフォルト 7 日間で設定されること（学習環境として十分な量を保持しつつストレージを節約）
- **FR-006**: Loki と Promtail が既存の Terragrunt `docker_container` モジュールを使ってデプロイ・削除できること
- **FR-007**: Promtail がリモートサーバーの Docker ソケット（`/var/run/docker.sock`）経由でコンテナログを読み取り、コンテナ名・イメージ名などのメタデータをラベルとして付与した上で 30 秒以内に Loki へ転送すること
- **FR-008**: Promtail の収集状態（position）がコンテナ再起動をまたいで保持され、ログの重複収集が発生しないこと
- **FR-009**: Loki が Prometheus のスクレイプ対象として登録され、Loki 自身のメトリクス（取り込みレート・クエリレイテンシ・ストレージ使用量など）が Grafana で確認できること

### Key Entities

- **Log Stream**: コンテナ名・ジョブ名・ホスト名などのラベルセットで識別されるログの集合。同一ラベルのエントリはひとつのストリームとして管理される
- **Log Entry**: タイムスタンプ・ラベルセット・ログ行テキストの組み合わせ。Loki に保存される最小単位
- **Loki Data Source**: Grafana が Loki に接続するための設定。URL・認証情報・タイムアウト値などを含む

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 監視基盤の全コンテナが出力したログが 30 秒以内に Loki で検索可能になること
- **SC-002**: Grafana の Explore 画面で LogQL クエリを実行し、任意のコンテナのログが 5 秒以内に表示されること
- **SC-003**: Prometheus アラート発生時刻から 1 分以内に、同時刻の対象コンテナのエラーログを特定できること
- **SC-004**: `terragrunt run-all apply` 単一コマンドで Loki・Promtail を含む全サービスがデプロイできること
- **SC-005**: Loki コンテナ再起動後も、再起動前のログデータが引き続き検索可能であること（永続化確認）

## Clarifications

### Session 2026-03-20

- Q: Promtail のログ収集方式（Docker ソケット vs ファイルシステムパス）→ A: Docker ソケット（`/var/run/docker.sock`）経由
- Q: Loki 自己監視を本フィーチャーのスコープに含めるか → A: 含める（Prometheus スクレイプ対象に追加、Grafana でメトリクス確認可能にする）

## Assumptions

- Promtail の収集対象は monitoring-lab ネットワーク上のコンテナのみ（ホスト OS のシステムログは対象外）
- 認証なし（Loki の認証機能は学習環境では有効化しない）
- ログ保持期間は 7 日間（ストレージ容量との兼ね合いで調整可能）
- Grafana プロビジョニングへの追加は既存の `datasources.yml` に Loki エントリを追記する形で対応
- VictoriaMetrics（⑦ バックログ）とは独立したフィーチャーとして実装し、依存関係は持たない
