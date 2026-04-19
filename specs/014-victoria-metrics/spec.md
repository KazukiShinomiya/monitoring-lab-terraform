# Feature Specification: VictoriaMetrics 長期メトリクス保存基盤

**Feature Branch**: `014-victoria-metrics`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "014-victoria-metrics: VictoriaMetrics を使った Prometheus の長期メトリクス保存基盤の構築。remote_write で Prometheus から VictoriaMetrics へメトリクスを転送し、30日を超える長期データの保持と Grafana での可視化を実現する。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 長期メトリクスの自動保存（Priority: P1）

プラットフォームエンジニアが、Prometheus の保持期間（30日）を超えた過去のメトリクスデータを参照したい。現在は30日以前のデータが自動削除されるため、月次レビューや障害の事後分析に限界がある。長期ストレージを導入することで、1年以上前のデータも検索・比較できるようになる。

**Why this priority**: Prometheus の30日制限が現状の観測可能性の最大制約。これを解消すると初めて「傾向分析」が成立し、US2・US3 の前提でもある。

**Independent Test**: 長期ストレージサービスが稼働し、Prometheus から転送が継続していることを API で確認。30日経過後（または意図的に古いタイムスタンプで書き込んで）クエリが返ることで単独テスト可能。

**Acceptance Scenarios**:

1. **Given** 長期ストレージが稼働中、**When** Prometheus が新たなメトリクスをスクレイプする、**Then** そのデータが自動的に長期ストレージへ転送される（手動操作不要）
2. **Given** Prometheus の保持期間（30日）を超えたデータ、**When** 長期ストレージに対してクエリを実行する、**Then** 該当期間のデータが返却される
3. **Given** 長期ストレージが一時的にダウンした、**When** 復旧後、**Then** Prometheus が転送を再試行し、データの欠損が最小化される

---

### User Story 2 - Grafana から長期データを可視化（Priority: P2）

プラットフォームエンジニアが、Grafana の既存ダッシュボードで長期ストレージのデータを参照したい。現在の Prometheus ダッシュボードと同じ操作感で、時間範囲を「過去90日」や「過去1年」に広げてグラフを確認できるようになる。

**Why this priority**: US1 でデータが蓄積されても Grafana から参照できなければ意味がない。US1 完了後に独立して追加できるため P2。

**Independent Test**: Grafana の Explore 画面で長期ストレージのデータソースを選択し、任意の時間範囲でメトリクスを検索してグラフが表示されることを確認。

**Acceptance Scenarios**:

1. **Given** Grafana が稼働中、**When** データソース一覧を開く、**Then** 長期ストレージ用のデータソースが自動プロビジョニングされて表示される
2. **Given** 長期ストレージのデータソースを選択、**When** 時間範囲を「過去90日」に設定してクエリを実行、**Then** データがグラフとして可視化される
3. **Given** 既存の Prometheus ダッシュボード、**When** データソースを長期ストレージに切り替える、**Then** 同じクエリで長期データが表示される（クエリ互換性）

---

### User Story 3 - SLO Error Budget の長期トレンド分析（Priority: P3）

プラットフォームエンジニアが、SLO の Error Budget 消費傾向を複数月にわたって追跡したい。「先月と比べて Prometheus の可用性は改善したか」「季節的なパターンはあるか」といった分析が、長期データがあって初めて可能になる。

**Why this priority**: US1・US2 が揃った上で追加価値を提供する。SLO 基盤（013-slo-sloth）との組み合わせで最大効果を発揮するが、US1・US2 完了後に自然に実現される。

**Independent Test**: Grafana の "SLO Overview" ダッシュボードで長期ストレージをデータソースとして使用し、30日以前の `slo:error_budget:ratio` の推移グラフが表示されることを確認。

**Acceptance Scenarios**:

1. **Given** SLO メトリクス（`slo:error_budget:ratio` 等）が長期ストレージに蓄積されている、**When** 90日間の時間範囲でクエリする、**Then** Error Budget の推移グラフが表示される
2. **Given** 複数サービスの SLO データ、**When** 月次で Error Budget 残量を比較、**Then** サービスごとの傾向差異が視覚化される

---

### Edge Cases

- 長期ストレージが一時停止した場合、Prometheus は WAL（先行書き込みログ）でバッファリングし、復旧後に再送する（デフォルト2時間分）
- ディスク容量が上限に近づいた場合、設定した保持期間を超えた古いデータから自動削除される
- Prometheus と長期ストレージで同一時刻のデータが重複送信された場合、長期ストレージ側で自動的に重複排除される
- 長期ストレージ停止中に Prometheus が再起動した場合、WAL の保持期間を超えた分のデータは欠損する可能性がある（学習環境では許容）

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムは Prometheus が収集した全メトリクスを、スクレイプ後自動的に長期ストレージへ転送しなければならない（手動操作不要）
- **FR-002**: 長期ストレージは最低365日間のメトリクスデータを保持しなければならない
- **FR-003**: 長期ストレージへのクエリは、Prometheus と同じクエリ言語で実行できなければならない（既存クエリの再利用）
- **FR-004**: 長期ストレージは IaC（Terraform/Terragrunt）で管理されなければならない（手動コンテナ操作禁止）
- **FR-005**: Grafana は長期ストレージを独立したデータソースとして追加されなければならない（既存 Prometheus データソースは変更しない）
- **FR-006**: 長期ストレージのデプロイ・設定変更は既存の同期スクリプト・Taskfile を通じて実行できなければならない
- **FR-007**: 長期ストレージが停止中も、Prometheus の通常動作（スクレイプ・アラート評価）は継続されなければならない

### Key Entities

- **長期メトリクスストレージ**: 全 Prometheus メトリクスの永続保存先。保持期間365日以上。Prometheus 互換のクエリ API を提供。
- **転送設定**: Prometheus から長期ストレージへのメトリクス転送ルール。転送対象・バッファ・再試行ポリシーを含む。
- **Grafana データソース（長期）**: 長期ストレージへの接続設定。Grafana プロビジョニングで自動構成。既存の Prometheus データソースとは独立。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Prometheus が収集したメトリクスが、収集から1分以内に長期ストレージでも検索可能になること
- **SC-002**: 長期ストレージが稼働開始から365日後も、初日のデータが検索可能であること（保持期間365日以上）
- **SC-003**: 長期ストレージの追加により、既存の Prometheus スクレイプ設定・アラートルール・Grafana ダッシュボードに一切の変更が不要であること
- **SC-004**: Grafana から「過去90日」の時間範囲でクエリを実行し、結果が5秒以内に返ること

## Assumptions

- 既存の Prometheus（`YOUR_SERVER_IP:9090`）は引き続き30日保持・リアルタイム監視の主役として稼働する
- 長期ストレージはリモートサーバー（`YOUR_SERVER_IP`）上の Docker コンテナとして稼働する
- ストレージ容量は学習環境として十分（数十 GB 程度を想定）
- 長期ストレージへのクエリ互換性は Prometheus 互換 API で担保される
- データ転送は平文 HTTP で行う（学習環境のため TLS は不要）
- 長期ストレージの停止は数分以内で復旧できる前提（学習環境の制約）

## Out of Scope

- 過去30日分のデータを長期ストレージへバックフィル（一括移行）は対象外
- 高可用性・クラスタ構成は対象外（シングルノード）
- 認証・アクセス制御の設定は対象外（学習環境）
- アラートルールを長期ストレージ側で評価することは対象外（Prometheus が担当し続ける）
- 長期ストレージ専用のダッシュボード新規作成は対象外（既存ダッシュボードのデータソース切り替えで対応）
