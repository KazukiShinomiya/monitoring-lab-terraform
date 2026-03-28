# Feature Specification: Grafana Tempo + OpenTelemetry Collector によるトレーシング基盤の導入

**Feature Branch**: `011-tempo`
**Created**: 2026-03-28
**Status**: Draft
**Input**: User description: "Grafana Tempo + OpenTelemetry Collector によるトレーシング基盤の導入。既存スタック (Prometheus + Loki + Grafana) にTracesを追加してLGTM Stackを完成させる。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - トレースデータの収集と保存 (Priority: P1)

オペレーターとして、アプリケーションやインフラコンポーネントから送信されたトレースデータを受信・保存できる環境を整備したい。これにより、分散システム内でのリクエストの流れを把握できるようになる。

**Why this priority**: トレーシング基盤の根幹。Tempo が稼働しない限り他のユーザーストーリーはすべて機能しない。最小限の MVP として「Tempo が OTLP でトレースを受け取れる」ことが最初の価値提供となる。

**Independent Test**: Tempo コンテナが起動し、OTLP エンドポイント (gRPC 4317 / HTTP 4318) にテスト用トレースを送信して、HTTP API (3200) でクエリできれば独立してテスト完了。

**Acceptance Scenarios**:

1. **Given** Tempo コンテナが起動している、**When** OTLP gRPC (4317) にサンプルトレースを送信する、**Then** Tempo の HTTP API でそのトレースを取得できる
2. **Given** Tempo コンテナが起動している、**When** OTLP HTTP (4318) にサンプルトレースを送信する、**Then** 同様にトレースが保存・取得できる
3. **Given** Tempo コンテナを再起動した、**When** 再起動前に保存されたトレースをクエリする、**Then** データが永続化されており取得できる

---

### User Story 2 - Grafana でトレースを可視化・メトリクスと相関分析 (Priority: P2)

オペレーターとして、Grafana の Explore 画面からトレースを検索・閲覧し、Prometheus メトリクスのグラフ上の特定時点からトレースにジャンプ (Exemplar 連携) できるようにしたい。

**Why this priority**: トレースを「見る」手段が確立して初めて運用価値が生まれる。Exemplar によるメトリクス→トレース相関は、障害時の根本原因調査を劇的に高速化する。

**Independent Test**: Grafana Explore で Tempo データソースを選択し、TraceID 検索でウォーターフォールビューが表示されれば完了。Exemplar 連携は Prometheus データソースにもスクレイプが必要。

**Acceptance Scenarios**:

1. **Given** Grafana に Tempo データソースが設定されている、**When** Explore でトレースを TraceID 検索する、**Then** トレースのウォーターフォールビューが表示される
2. **Given** Prometheus が Tempo のメトリクスをスクレイプしている、**When** Grafana のメトリクスグラフ上で Exemplar マーカーをクリックする、**Then** 対応するトレースの詳細が表示される
3. **Given** Tempo データソースが設定されている、**When** サービス名・期間・タグでトレースをフィルタリングする、**Then** 条件に一致するトレース一覧が表示される

---

### User Story 3 - OpenTelemetry Collector によるトレースルーティング (Priority: P2)

オペレーターとして、アプリケーションが OpenTelemetry Collector (OTel Collector) 経由でトレースを Tempo に送信できる中継点を持ちたい。将来的に複数バックエンドへの送信やサンプリング設定の一元管理が可能になる。

**Why this priority**: OTel Collector は OTLP の標準的な中継点であり、アプリケーション側の変更を最小化しつつバックエンドの柔軟な切り替えを可能にする。Tempo への直接送信の代替・補完として必要。

**Independent Test**: OTel Collector コンテナが起動し、OTLP gRPC/HTTP を受け付けてトレースを Tempo に転送できれば完了。

**Acceptance Scenarios**:

1. **Given** OTel Collector が起動している、**When** OTLP gRPC (4317) にトレースを送信する、**Then** Collector 経由で Tempo にトレースが保存される
2. **Given** OTel Collector が起動している、**When** OTLP HTTP (4318) にトレースを送信する、**Then** 同様に Tempo にルーティングされる
3. **Given** OTel Collector の設定ファイルを変更した、**When** `sync-config.sh otel-collector` を実行する、**Then** 新しい設定がリモートサーバーに転送されコンテナが再起動される

---

### User Story 4 - IaC による Tempo / OTel Collector のデプロイ管理 (Priority: P3)

オペレーターとして、Tempo と OTel Collector を既存の Terragrunt パターンに沿って宣言的に管理し、`terragrunt apply` でデプロイ・更新できるようにしたい。

**Why this priority**: 既存スタックと同じ運用フローで管理できることが保守性の観点で重要。IaC 化により再現性が確保される。

**Independent Test**: 既存の `terragrunt run --all plan` に tempo/otel-collector ワークスペースが含まれ、差分なし (No changes) になれば完了。

**Acceptance Scenarios**:

1. **Given** Terraform state が存在しない状態、**When** `terragrunt apply` を実行する、**Then** Tempo コンテナと OTel Collector コンテナが作成される
2. **Given** コンテナが稼働中、**When** 設定を変更して `terragrunt apply` を実行する、**Then** コンテナが更新される (差分適用)
3. **Given** HCP Terraform が Local モードに設定されている、**When** `terragrunt run --all plan` を実行する、**Then** tempo/otel-collector を含む全ワークスペースがプランされる

---

### Edge Cases

- Tempo コンテナのストレージが不足した場合、古いトレースはどう扱われるか？ (デフォルトの保持期間設定で管理)
- OTel Collector が Tempo に接続できない場合、受信したトレースはどうなるか？ (Collector のログにエラー記録、データは消失)
- 既存の `datasources.yml` に Tempo エントリを追記する際の構文エラーがあった場合の挙動
- Prometheus が Exemplar を収集するために必要な設定が欠けている場合の動作 (Exemplar なしでグラフは表示されるが相関ジャンプは不可)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムは Grafana Tempo 3.x をリモート Docker 環境 (10.0.0.220) にデプロイし、HTTP (3200)、OTLP gRPC (4317)、OTLP HTTP (4318) の各ポートで接続を受け付けなければならない
- **FR-002**: システムは OpenTelemetry Collector をデプロイし、OTLP gRPC (4317) / OTLP HTTP (4318) でトレースを受信して Tempo に転送しなければならない
- **FR-003**: Grafana の `datasources.yml` に Tempo データソースを追加し、Grafana 再起動後に Explore からトレースを参照できなければならない
- **FR-004**: Prometheus の `prometheus.yml` に Tempo のメトリクス収集ジョブを追加し、Exemplar によるメトリクス→トレース相関を有効化しなければならない
- **FR-005**: `scripts/sync-config.sh` に `tempo` および `otel-collector` サブコマンドを追加し、設定ファイルのリモート転送とコンテナ再起動ができなければならない
- **FR-006**: Tempo と OTel Collector は既存の Terragrunt `docker_container` モジュールを用いて定義し、HCP Terraform の Local 実行モードで管理されなければならない
- **FR-007**: Tempo のトレースデータは Docker ボリュームに永続化され、コンテナ再起動後もデータが保持されなければならない
- **FR-008**: Tempo / OTel Collector は既存の monitoring-lab Docker ネットワークに接続し、Grafana・Prometheus と通信できなければならない

### Key Entities

- **Trace**: 単一リクエストのエンドツーエンドの処理フロー。TraceID で一意に識別され、複数の Span から構成される
- **Span**: トレース内の個々の処理単位。サービス名、操作名、開始・終了時刻、タグ、ステータスを持つ
- **Exemplar**: Prometheus メトリクスのデータポイントに付加されるメタデータ。TraceID を含み、メトリクスとトレースを結びつける

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Grafana Explore から TraceID でトレースを検索し、ウォーターフォールビューが 3 秒以内に表示される
- **SC-002**: OTLP エンドポイントにトレースを送信してから 10 秒以内に Grafana で参照できる (準リアルタイム可視化)
- **SC-003**: Prometheus メトリクスのグラフ上の Exemplar マーカーから、対応するトレース詳細に 1 クリックでジャンプできる
- **SC-004**: `sync-config.sh tempo` および `sync-config.sh otel-collector` が既存コマンドと同じインターフェースで動作し、実行から反映まで 30 秒以内に完了する
- **SC-005**: `terragrunt run --all plan` が tempo / otel-collector ワークスペースを含む全サービスを差分なし (No changes) で完了する
- **SC-006**: Tempo コンテナ再起動後、再起動前に保存されたトレースデータが参照可能な状態で保持されている

## Assumptions

- Exemplar を生成するアプリケーション (例: Prometheus クライアントライブラリを使うサービス) は既に存在するか、将来導入される想定。本フィーチャーでは Tempo 側の受け入れ準備のみを行い、Exemplar 送信側のアプリケーション実装は対象外とする
- トレース保持期間はデフォルト設定 (Tempo デフォルト: 336時間 = 14日) を採用する
- OTel Collector は単一インスタンス構成 (高可用性なし) とし、学習環境として許容する
- 認証・TLS 設定は既存スタックに倣い省略する (学習環境)
- Tempo は `local` ストレージバックエンドを使用し、オブジェクトストレージへの移行は将来フェーズとする
- SC-001/SC-002/SC-004 のパフォーマンス基準 (3秒・10秒・30秒) は学習環境では計測ツールのセットアップをスコープ外とし、目視確認で代替する
