# Feature Specification: Grafana Pyroscope 継続的プロファイリング基盤

**Feature Branch**: `015-pyroscope`  
**Created**: 2026-04-19  
**Status**: Draft  
**Input**: Grafana Pyroscope を使った継続的プロファイリング基盤の構築。Prometheus remote_write と同様に OpenTelemetry Collector 経由でプロファイルデータを収集し、Grafana から CPU・メモリプロファイルを可視化する。LGTM+P Stack の P（Profiling）として観測可能性スタックを完成させる。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pyroscope バックエンドの稼働と自己監視（Priority: P1）

オペレーターとして、Pyroscope コンテナを IaC でデプロイし、稼働確認ができる。プロファイルデータの受信・蓄積が開始されると、監視スタック全体の CPU・メモリプロファイルが長期的に蓄積される。

**Why this priority**: LGTM+P スタックの P 柱となる基盤コンポーネントであり、他のすべてのプロファイリング機能の前提条件。IaC によるデプロイを先行させることで、以降の可視化・相関分析が可能になる。

**Independent Test**: `curl -sf http://YOUR_SERVER_IP:4040/ready` → "200 OK" が返り、Prometheus が Pyroscope のメトリクス（`:4040/metrics`）をスクレイプできれば US1 完了。

**Acceptance Scenarios**:

1. **Given** Pyroscope コンテナが存在しない状態で、**When** `terragrunt apply` を実行したとき、**Then** `monitoring-lab-pyroscope` コンテナが起動し、ポート 4040 でヘルスチェック（`/ready`）が成功する
2. **Given** Pyroscope が稼働中で、**When** Prometheus がスクレイプを実行したとき、**Then** `pyroscope_distributor_received_profiles_total` などのメトリクスが Prometheus に蓄積される（Constitution 原則 V）
3. **Given** Pyroscope コンテナが異常停止したとき、**When** Prometheus が次回スクレイプを実行したとき、**Then** 既存の `TargetDown` アラートが自動的に発火する

---

### User Story 2 - Grafana フレームグラフでプロファイルを可視化（Priority: P2）

オペレーターとして、Grafana Explore から Pyroscope データソースを選択し、各 Go サービス（Prometheus、Grafana、Tempo 等）の CPU・メモリプロファイルをフレームグラフで確認できる。

**Why this priority**: プロファイルデータが蓄積されていても可視化できなければ価値がない。Grafana への統合により既存の LGTM スタックと同じ操作感でプロファイルを参照できる。

**Independent Test**: Grafana Explore → "Pyroscope" データソース → `{service_name="prometheus"}` → プロファイルタイプ "cpu" → フレームグラフが表示される。

**Acceptance Scenarios**:

1. **Given** Pyroscope データソースが Grafana に追加された状態で、**When** Explore でサービスを選択しクエリを実行したとき、**Then** 5 秒以内にフレームグラフが表示される
2. **Given** Grafana の Explore 画面で、**When** Pyroscope データソースからプロファイルタイプ（cpu/memory/goroutine）を切り替えたとき、**Then** 対応するプロファイルデータが表示される
3. **Given** Pyroscope に 30 分以上のデータが蓄積された状態で、**When** 時間範囲を "Last 1 hour" に設定したとき、**Then** プロファイルデータが連続的に表示される

---

### User Story 3 - メトリクス・トレース・プロファイルの相関分析（Priority: P3）

オペレーターとして、Grafana Explore の "Profiles for this flame graph" 機能や Exemplar リンクを通じて、Prometheus メトリクス・Tempo トレース・Pyroscope プロファイルを横断的に参照し、パフォーマンス問題の根本原因を特定できる。

**Why this priority**: 個別の可視化よりも「観測可能性の三本柱 + プロファイル」の相関分析が LGTM+P スタック完成の本質的価値。ただし US1/US2 が前提のため P3。

**Independent Test**: Grafana Explore で Prometheus の CPU スパイクを確認した後、同時刻の Pyroscope プロファイルへのリンクをクリックしてフレームグラフが開けば US3 完了。

**Acceptance Scenarios**:

1. **Given** Prometheus と Pyroscope の両方にデータがある状態で、**When** Grafana Explore の Prometheus パネルからプロファイルへのリンクを使用したとき、**Then** 同じ時刻・同じサービスの Pyroscope プロファイルが表示される
2. **Given** Tempo トレースと Pyroscope プロファイルが同時刻に存在する状態で、**When** トレース詳細画面から "Profile" リンクを選択したとき、**Then** 対応するプロファイルが Pyroscope で表示される
3. **Given** CPU 使用率が高いサービスが Prometheus で検出された状態で、**When** Pyroscope で同時刻のプロファイルを参照したとき、**Then** CPU を消費している関数スタックがフレームグラフで特定できる

---

### Edge Cases

- Pyroscope が停止中でも Prometheus・Grafana 等の既存サービスへの影響がないこと（独立性）
- Pyroscope 再起動後、プロファイルデータが消失しないこと（Docker Volume による永続化）
- 対象サービスが pprof エンドポイントを公開していない場合、スクレイプエラーが発生しても他サービスのプロファイル収集は継続すること
- プロファイルデータ量が増大した場合、Pyroscope の保持期間設定（デフォルト）でディスク使用量が管理されること

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムは Pyroscope シングルノードコンテナを IaC（Terragrunt）でデプロイし、ポート 4040 でプロファイル受信 API および Prometheus 互換メトリクスエンドポイントを提供すること
- **FR-002**: システムは Prometheus の pprof スクレイプ機能（`scrape_configs` の `scrape_interval` および `/debug/pprof/` エンドポイント）を使用して、対象 Go サービスのプロファイルを Pyroscope に転送すること
- **FR-003**: システムは Grafana に Pyroscope データソースをプロビジョニングファイルで追加し、Explore からフレームグラフを表示できること
- **FR-004**: システムは Docker Volume（`pyroscope_data`）でプロファイルデータを永続化し、コンテナ再起動後もデータが保持されること
- **FR-005**: システムは Constitution 原則 V に従い、Pyroscope コンテナ自身を Prometheus のスクレイプ対象（Job として prometheus.yml に追加）とすること
- **FR-006**: プロファイル収集対象は監視スタック内の Go サービス（Prometheus、Grafana、Tempo、VictoriaMetrics、Pyroscope 自身）の pprof エンドポイントとすること
- **FR-007**: 既存の Prometheus・Grafana・アラートルールへの変更は最小限（prometheus.yml への追記と datasources.yml への追記のみ）とし、既存サービスの動作に影響を与えないこと

### Key Entities

- **Pyroscope コンテナ**: プロファイルデータの収集・蓄積・クエリバックエンド。ポート 4040（HTTP API）。Docker Volume `pyroscope_data` でデータ永続化
- **プロファイル**: Go サービスの pprof データ（CPU、メモリ、goroutine）。Pyroscope 形式で蓄積。`service_name` ラベルで識別
- **pprof スクレイプターゲット**: Prometheus が `scrape_configs` で定期収集する Go サービスの `/debug/pprof/` エンドポイント群

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Pyroscope ヘルスチェック（`/ready`）が "200 OK" を返し、コンテナが正常稼働していること
- **SC-002**: Prometheus が Pyroscope のメトリクスをスクレイプでき、`pyroscope_distributor_received_profiles_total` が増加し続けること（データ転送の継続的動作確認）
- **SC-003**: Grafana Explore で Pyroscope データソースからプロファイルクエリを実行し、5 秒以内にフレームグラフが表示されること
- **SC-004**: `task tg:plan` を実行したとき、全 HCP Workspace で "No changes" が返ること（Constitution 原則 I）
