# Feature Specification: Phase 3 - 監視機能拡充

**Created**: 2026-01-01
**Status**: Draft
**Priority**: High
**Depends On**: `existing-infrastructure.md` (Baseline)

## 概要

Phase 2で構築した基盤上に、実用的な監視機能を追加する。
PrometheusとGrafanaを活用し、コンテナメトリクスの収集と可視化を実現する。

---

## User Scenarios & Testing

### User Story 1 - コンテナメトリクスの収集 (Priority: P1)

**シナリオ**:
監視担当者として、Dockerコンテナ（8台）のリソース使用状況（CPU、メモリ、ネットワーク）をリアルタイムで把握したい。
これにより、リソース枯渇やパフォーマンス問題を早期に検知できる。

**Why this priority**:
- 監視基盤の最も基本的な機能
- コンテナ障害の早期検知に直結
- 他の機能（ダッシュボード、アラート）の前提条件

**Independent Test**:
Prometheusの`/targets`ページで、すべてのターゲットが"UP"状態であることを確認。
`container_cpu_usage_seconds_total`などのメトリクスがPrometheusにスクレイプされていることを確認。

**Acceptance Scenarios**:

1. **Given** Prometheus設定ファイルが更新されている
   **When** Prometheusコンテナが再起動される
   **Then** 設定ファイルが正常にロードされ、エラーログが出力されない

2. **Given** Dockerエンジンのメトリクスエンドポイントが有効
   **When** Prometheusがスクレイプを実行
   **Then** 8つのコンテナすべてのメトリクスが収集される

3. **Given** メトリクスが収集されている
   **When** PromQLクエリ`container_memory_usage_bytes`を実行
   **Then** 各コンテナのメモリ使用量がリアルタイムで表示される

---

### User Story 2 - Grafanaダッシュボードの作成 (Priority: P1)

**シナリオ**:
監視担当者として、Grafanaで一目で全コンテナの状態を把握できるダッシュボードが欲しい。
個別のコンテナやサービスごとの詳細も確認できる。

**Why this priority**:
- 収集したメトリクスを活用するための必須機能
- 運用者がシステムの健全性を一目で判断できる
- 学習目的でGrafanaのベストプラクティスを実践

**Independent Test**:
Grafana (`http://10.0.0.220:3000`) にアクセスし、「Monitoring Lab Overview」ダッシュボードが表示される。
すべてのパネルがデータを表示し、エラーがない。

**Acceptance Scenarios**:

1. **Given** Prometheusデータソースが設定されている
   **When** Grafanaダッシュボードを開く
   **Then** リアルタイムでメトリクスが表示される

2. **Given** 8つのコンテナが稼働中
   **When** 「Container Resource Usage」パネルを確認
   **Then** CPU、メモリ、ネットワークI/Oが各コンテナごとに表示される

3. **Given** ダッシュボードが作成されている
   **When** Grafanaを再起動
   **Then** ダッシュボードが永続化されており、再度アクセス可能

---

### User Story 3 - 基本的なアラートルール (Priority: P2)

**シナリオ**:
監視担当者として、コンテナがダウンした場合やリソース使用率が閾値を超えた場合に通知を受け取りたい。

**Why this priority**:
- 自動的な異常検知により、手動監視の負担を軽減
- ダウンタイムの最小化
- Phase 1-2より優先度低（まずはデータ収集と可視化を優先）

**Independent Test**:
Prometheusの`/alerts`ページで、定義されたアラートルールが表示される。
テスト的にコンテナを停止し、アラートが発火することを確認。

**Acceptance Scenarios**:

1. **Given** アラートルールが定義されている
   **When** コンテナが停止
   **Then** 1分以内にアラートが"Firing"状態になる

2. **Given** CPU使用率アラートが設定されている
   **When** コンテナのCPU使用率が80%を超える
   **Then** アラートが発火し、Prometheusのアラートページに表示される

3. **Given** アラートが発火している
   **When** 問題が解決される（コンテナ再起動、リソース解放）
   **Then** アラートが自動的に"Resolved"状態になる

---

### User Story 4 - Zabbix統合ダッシュボード (Priority: P3)

**シナリオ**:
監視担当者として、Grafanaで Prometheus（コンテナメトリクス）とZabbix（SwitchBot温湿度計）のデータを統合して表示したい。

**Why this priority**:
- 監視データの統合による包括的なビュー
- Phase 3の最終目標だが、他の機能の完成後でも可

**Independent Test**:
Grafanaで「Integrated Monitoring」ダッシュボードを開き、Prometheus と Zabbixの両方のデータが表示される。

**Acceptance Scenarios**:

1. **Given** ZabbixプラグインがGrafanaにインストール済み
   **When** Zabbixデータソースを設定
   **Then** Zabbix APIに接続でき、ホストとアイテムが取得できる

2. **Given** 統合ダッシュボードが作成されている
   **When** ダッシュボードを開く
   **Then** 上部にコンテナメトリクス、下部にSwitchBot温湿度データが表示される

---

### Edge Cases

- **Prometheusが再起動した場合**: スクレイプ設定が保持され、自動的に再開される
- **Grafanaが再起動した場合**: ダッシュボードとデータソース設定が永続化されている
- **リモートDockerホストが一時的にダウンした場合**: Prometheusはスクレイプ失敗をログに記録し、復旧後に自動再開
- **メトリクスデータが大量になった場合**: Prometheusの保持期間（15日）により古いデータは自動削除

---

## Requirements

### Functional Requirements

#### Prometheusスクレイプ設定

- **FR-001**: Prometheus設定ファイル（`prometheus.yml`）にDockerメトリクスのスクレイプジョブを追加する
- **FR-002**: スクレイプ間隔は15秒とする（リアルタイム性とストレージのバランス）
- **FR-003**: スクレイプターゲットはリモートDockerホスト（10.0.0.220）のDocker Engineメトリクスエンドポイント
- **FR-004**: Prometheusコンテナ再起動時に設定が自動的にリロードされる
- **FR-005**: 設定ファイルはGit管理され、バージョン管理される

#### Grafanaダッシュボード

- **FR-006**: Grafanaに「Monitoring Lab Overview」という名前のダッシュボードを作成
- **FR-007**: ダッシュボードには以下のパネルを含む:
  - コンテナ一覧と稼働状態
  - CPU使用率（コンテナ別、時系列）
  - メモリ使用量（コンテナ別、時系列）
  - ネットワークI/O（送受信、時系列）
  - ディスクI/O（読み書き、時系列）
- **FR-008**: ダッシュボードはJSON形式でGit管理される
- **FR-009**: ダッシュボードはGrafanaのプロビジョニング機能で自動デプロイされる
- **FR-010**: 変数機能を使用してコンテナの切り替えが可能

#### アラートルール

- **FR-011**: Prometheusに以下のアラートルールを定義:
  - コンテナダウン検知（1分以上応答なし）
  - CPU使用率高（80%以上が5分継続）
  - メモリ使用率高（90%以上が5分継続）
- **FR-012**: アラートルールファイルは`/etc/prometheus/alerts.yml`に配置
- **FR-013**: アラートルールファイルはGit管理される
- **FR-014**: Prometheusの`/alerts`ページでアラート状態を確認可能

### Non-Functional Requirements

- **NFR-001**: Prometheusのメトリクス保持期間は15日間
- **NFR-002**: Grafanaダッシュボードの応答時間は3秒以内
- **NFR-003**: Prometheusスクレイプの失敗率は5%以下（ネットワーク一時障害を考慮）
- **NFR-004**: すべての設定ファイルは Infrastructure as Code（IaC）原則に準拠

### Key Entities

- **Prometheus Scrape Job**: スクレイプ対象、間隔、ラベルを定義
- **Grafana Dashboard**: パネル、クエリ、変数、レイアウトを含む
- **Prometheus Alert Rule**: アラート名、PromQLクエリ、継続時間、重大度を定義
- **Container Metrics**: CPU、メモリ、ネットワーク、ディスクのリソース使用状況

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Prometheusが8つのコンテナすべてからメトリクスを収集している（`/targets`で確認、すべて"UP"）
- **SC-002**: Grafanaダッシュボードが正常に表示され、リアルタイムでデータが更新される（3秒以内）
- **SC-003**: 定義されたアラートルールが正常に動作する（テストでコンテナ停止 → アラート発火を確認）
- **SC-004**: すべての設定ファイルがGit管理され、`git status`で差分なし
- **SC-005**: Terraform/Terragruntで`plan`実行時に差分なし（インフラ変更がコード化されている）
- **SC-006**: ドキュメント（`CLAUDE.md`、`SESSION_STATE.md`）が更新されている

---

## Technical Approach（実装方針）

### 1. Prometheusスクレイプ設定

**方法**:
- `config/prometheus/prometheus.yml`を編集
- Docker Engine Metricsエンドポイントをスクレイプターゲットとして追加
- Terragruntで Prometheusコンテナを再デプロイ（設定リロード）

**ファイル**:
- `config/prometheus/prometheus.yml`
- `terraform/envs/local/prometheus/terragrunt.hcl`

### 2. Grafanaダッシュボード

**方法**:
- Grafana UIでダッシュボードを作成
- JSON形式でエクスポート
- `config/grafana/provisioning/dashboards/`に配置
- Terragruntで Grafanaコンテナを再デプロイ（プロビジョニング）

**ファイル**:
- `config/grafana/provisioning/dashboards/monitoring-lab-overview.json`
- `config/grafana/provisioning/dashboards/dashboard.yml` (プロビジョニング設定)
- `terraform/envs/local/grafana/terragrunt.hcl`

### 3. アラートルール

**方法**:
- `config/prometheus/alerts.yml`を作成
- Prometheusコンテナにマウント
- `prometheus.yml`でアラートルールファイルを読み込むよう設定
- Terragruntで Prometheusコンテナを再デプロイ

**ファイル**:
- `config/prometheus/alerts.yml`
- `config/prometheus/prometheus.yml`（`rule_files`セクション追加）
- `terraform/envs/local/prometheus/terragrunt.hcl`

---

## Dependencies

### Prerequisites
- Phase 2完了（HCP Terraform State移行済み）
- すべてのコンテナが正常に稼働中
- PrometheusとGrafanaがアクセス可能

### External Dependencies
- Docker Engine Metrics API（リモートホスト側で有効化が必要な場合あり）
- Grafana Zabbixプラグイン（User Story 4用、すでにインストール済み）

---

## Risks & Mitigation

### Risk 1: Docker Engine Metrics APIが無効
**Impact**: Prometheusがメトリクスを収集できない
**Probability**: Medium
**Mitigation**: リモートホストでDocker Engineの設定を確認し、Metrics APIを有効化

### Risk 2: Grafanaダッシュボードのプロビジョニング失敗
**Impact**: 手動でダッシュボードを再作成する必要がある
**Probability**: Low
**Mitigation**: プロビジョニング設定を事前にテストし、Grafanaログを確認

### Risk 3: Prometheusのストレージ容量不足
**Impact**: メトリクスデータが記録されなくなる
**Probability**: Low（15日保持期間で計算済み）
**Mitigation**: ディスク使用量を監視し、必要に応じて保持期間を調整

---

## Out of Scope (Phase 3では実施しない)

- ❌ Vault本番モード化（Phase 4）
- ❌ TLS/SSL証明書導入（Phase 4-5）
- ❌ Alertmanager統合（Phase 4、現時点ではPrometheusのアラート表示のみ）
- ❌ 長期メトリクスストレージ（Phase 4、15日間で十分）
- ❌ Zabbix Agent2の追加（Phase 4、現在の自己監視で十分）

---

## Next Steps After Phase 3

Phase 3完了後、以下の選択肢を検討：
- **Phase 4**: 運用改善（Alertmanager、GitHub Actions、ドキュメント整備）
- **Vault統合**: パスワード管理のVault化
- **セキュリティ強化**: TLS/SSL導入

---

**Specification Version**: 1.0.0
**Created**: 2026-01-01
**Constitutional Compliance**: ✅ すべての原則に準拠
**Estimated Effort**: 1-2セッション（Spec-Drivenアプローチにより効率化）
