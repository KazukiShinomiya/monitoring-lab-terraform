# Feature Specification: SLO + Error Budget 管理基盤 (Sloth)

**Feature Branch**: `013-slo-sloth`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "013-slo: Sloth を使った SLO + Error Budget 管理基盤の導入。既存の Prometheus + Grafana + Alertmanager スタックに乗っかり、YAML で SLO を定義してアラートルールと Grafana ダッシュボードを自動生成する。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - SLO定義からアラートルール自動生成 (Priority: P1)

エンジニア（ジント）が監視対象サービスの「許容できる障害率」をYAMLファイルで定義する。定義した内容からPrometheusのRecording RulesとAlerting Rulesが自動生成され、従来の閾値ベースアラートをError Budgetベースのアラートに置き換えられる。

**Why this priority**: SLO基盤の核心であり、これなしには他のユーザーストーリーが成立しない。YAMLで定義 → ルール自動生成 の流れが確立すればMVPとして機能する。

**Independent Test**: SLO YAMLを1つ定義し、Prometheusが新しいRecording Rules/Alerting Rulesを認識していることをPrometheus UIで確認することで独立してテスト可能。

**Acceptance Scenarios**:

1. **Given** SLO YAMLファイルが `config/sloth/` ディレクトリに存在する、**When** Sloth CLIを実行する、**Then** Prometheusのルールファイル（`.yml`）が生成される
2. **Given** 生成されたルールファイルがPrometheusに反映されている、**When** Prometheus UIの `/rules` を確認する、**Then** `sloth_slo_*` 形式のRecording Rulesと `SLOBudgetBurn` 形式のAlerting Rulesが表示される
3. **Given** SLO目標値を変更してSlothを再実行した、**When** Prometheusが設定をリロードする、**Then** 更新後の目標値に基づいたルールが反映される

---

### User Story 2 - Error Budget ダッシュボードで消費状況を可視化 (Priority: P2)

エンジニアがGrafanaを開くと、各サービスのError Budget残量（今月あと何%まで障害を許容できるか）と消費速度（Burning Rate）が一目でわかる。「今このサービスはどのくらいの速さでError Budgetを消費しているか」を視覚的に把握できる。

**Why this priority**: SLOを定義しても可視化できなければ運用に活かせない。ダッシュボードがあることで「SLO違反に近い状態」を事前に察知できる。

**Independent Test**: GrafanaでError Budgetダッシュボードを開き、対象サービスの残量%と30日間のBurning Rateグラフが表示されることを確認することで独立してテスト可能。

**Acceptance Scenarios**:

1. **Given** Slothで生成されたRecording Rulesが稼働している、**When** GrafanaのSLOダッシュボードを開く、**Then** 各SLO対象サービスのError Budget残量（%）が表示される
2. **Given** SLOダッシュボードが表示されている、**When** 特定サービスのパネルを確認する、**Then** Fast Burn（1時間/6時間窓）とSlow Burn（3日/30日窓）の消費速度グラフが表示される
3. **Given** Error Budgetが0%を下回っている（SLO違反状態）、**When** ダッシュボードを確認する、**Then** 残量が赤色で表示され視覚的に警告が伝わる

---

### User Story 3 - Error Budget枯渇時のSlack通知 (Priority: P3)

Error Budgetが急速に消費されている（またはすでに枯渇している）場合、既存のAlertmanager経由でSlackに通知が届く。「このまま続くと今月のSLO目標を達成できない」状態を早期に検知できる。

**Why this priority**: P1/P2でSLOの可視化ができた後、能動的に「見に行く」のではなく「通知で気づける」状態にする。既存Alertmanager基盤の活用。

**Independent Test**: Burning RateをPrometheusの時刻を操作して閾値超えの状態を作り出し、Slack通知が届くことで独立してテスト可能。

**Acceptance Scenarios**:

1. **Given** Fast Burnアラートのルールが有効になっている、**When** Burning Rateが14.4倍（1時間窓）または6倍（6時間窓）を超える、**Then** Alertmanager経由でSlackの `#alerts` チャンネルに通知が届く
2. **Given** Error Budgetの消費速度が正常範囲に戻った、**When** Burning Rateが閾値以下に低下する、**Then** Slack通知のRESOLVEDメッセージが届く
3. **Given** 複数SLOが同時にBurnしている、**When** Alertmanagerがアラートを受信する、**Then** severity（page/ticket）に応じてグループ化・抑制されて通知される

---

### Edge Cases

- SLO目標値が100%に設定された場合、Error Budgetは0になり実質的にアラートが常時FIRINGになる
- 対象サービスのメトリクスが存在しない（エクスポーターが停止している）場合、SLIの計算ができずRecording Rulesがエラーになる可能性がある
- Prometheusが再起動直後のRecording Rules計算は過去データがないため、Error Budget残量の表示が不正確になる

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: SLOをYAMLファイルで定義できる（サービス名、SLI（`up` メトリクスによるスクレイプ成功率）、目標値（0〜99.9%）、期間（30日）を含む）
- **FR-002**: Sloth CLIがSLO YAMLからPrometheusのMulti-windowルール（Recording Rules + Alerting Rules）を生成し、`task slo:generate` コマンド1つで実行できる
- **FR-003**: Slothが生成したルールは `config/prometheus/slo-rules.yml` として出力され、既存の `alerts.yml` とは独立したファイルとしてPrometheusに追加される。設定変更後5分以内に有効になる
- **FR-004**: Sloth公式ダッシュボードJSON（`sloth-overview.json`）を `config/grafana/provisioning/dashboards/` に配置し、Grafana再起動後に手動設定なしで表示できる
- **FR-005**: Error BudgetがFast Burn（急速消費）またはSlow Burn（緩慢消費）の状態になった場合、AlertmanagerがSlack通知を送信する
- **FR-006**: SLOアラートは severity に応じて2段階に分類される（`page`: 即時対応必要 / `ticket`: 翌業務日対応で可）
- **FR-007**: 初期SLO定義対象は監視基盤コア4件（Prometheus / Grafana / Alertmanager / Loki）の可用性SLOとする

### Key Entities

- **SLO定義**: サービス名・SLI種別（`up` メトリクスによるスクレイプ成功率）・目標値（%）・期間（days）・ラベル群を持つ設定単位
- **Error Budget**: SLO目標値から導出される許容障害量（例: 99.5% SLO → 0.5% = 月216分の障害を許容）
- **Burning Rate**: Error Budgetの消費速度。1.0 = 目標ちょうどのペース、14.4 = 1時間で1日分を消費
- **Alerting Window**: Fast Burn（1h/6h窓）とSlow Burn（3d/30d窓）の2ペアでアラート条件を評価

## Clarifications

### Session 2026-04-05

- Q: SLI（サービスレベル指標）の計測方式は何を使うか → A: `up` メトリクスのみ（スクレイプ成功 = 正常）
- Q: Slothの実行トリガーは何か → A: Taskfileコマンドで手動実行（`task slo:generate`）
- Q: 既存 `alerts.yml` との関係はどうするか → A: 完全に別ファイルで共存（既存はそのまま、Sloth生成ルールは `slo-rules.yml` として新規追加）
- Q: GrafanaダッシュボードのソースはどうするかA: Sloth公式ダッシュボードJSON（`sloth-overview.json`）をそのまま採用し `config/grafana/provisioning/dashboards/` に配置
- Q: SLO対象サービスの初期範囲はどこまでか → A: 監視基盤コア4件（Prometheus / Grafana / Alertmanager / Loki）

## Assumptions

- SLOの計算期間は30日ローリングウィンドウを採用する（学習環境として実用的な標準値）
- Slothはコンテナまたはローカルバイナリとして実行し、Terragrunt管理対象の常駐コンテナとはしない
- 初期定義するSLOは監視基盤コア4件（Prometheus / Grafana / Alertmanager / Loki）の可用性SLOとする
- SLO YAMLからルールファイル生成は `task slo:generate` コマンドによる手動実行（CI統合はスコープ外）

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: SLO YAMLを変更してSlothを実行してから5分以内に、Prometheus UIで新しいRecording Rulesが確認できる
- **SC-002**: GrafanaのSLOダッシュボードで全SLO対象サービスのError Budget残量（%）とBurning Rateグラフが手動操作なしで表示できる
- **SC-003**: Burning Rateが閾値（Fast: 14.4倍、Slow: 1.0倍超過）を超えた場合にSlack通知が届く（Alertmanager FIRING確認）
- **SC-004**: 新しいサービスのSLOを追加する場合、YAML定義の記述からダッシュボード表示まで手動のGrafana操作が不要である
