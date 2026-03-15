# Feature Specification: Alertmanager導入 — アラート通知基盤

**Feature Branch**: `004-alertmanager-slack`
**Created**: 2026-03-13
**Status**: Draft
**Input**: User description: "Alertmanager導入 — PrometheusアラートをSlack等に通知する基盤を構築する。Terragrunt管理のコンテナとしてリモートサーバー（YOUR_SERVER_IP）にデプロイし、既存のalerts.ymlと連携させる。通知先はSlack（Webhook）を想定。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — アラート発生時にSlackで即座に気づく (Priority: P1)

監視対象（コンテナ、物理機器、Prometheus自身）で異常が発生した際、担当者がSlackチャンネルに通知を受け取り、迅速に対応できる。

**Why this priority**: 監視基盤の本来の目的である「気づき」を実現する最重要シナリオ。アラートが飛んでこなければ監視している意味がない。

**Independent Test**: スクレイプターゲットを意図的にダウンさせ、Slackに通知が届くことを確認することで単体テスト可能。

**Acceptance Scenarios**:

1. **Given** Prometheusがスクレイプターゲットのダウンを検知したとき、**When** アラートが firing 状態に移行したとき、**Then** 担当者のSlackチャンネルに1分以内に通知が届く
2. **Given** Slackに通知が届いたとき、**When** 担当者が通知を確認したとき、**Then** アラート名・発生時刻・対象リソース・重要度が読み取れる
3. **Given** アラートが解消したとき（resolved）、**When** 対象が正常に戻ったとき、**Then** Slackに解消通知が届く

---

### User Story 2 — 重要度別にアラートをルーティングする (Priority: P2)

`critical`（サービス影響あり）と `warning`（注意レベル）を別チャンネルまたは別メッセージスタイルで受け取り、重大度に応じた対応優先度を判断できる。

**Why this priority**: アラートが1つのチャンネルに無差別に流れると重要なものが埋もれる。P1が機能した後、次に改善すべきUX。

**Independent Test**: `severity: critical` と `severity: warning` のアラートをそれぞれ発火させ、通知の見た目や届け先が異なることを確認できる。

**Acceptance Scenarios**:

1. **Given** `severity: critical` なアラートが発火したとき、**When** 通知が届いたとき、**Then** 視覚的に `warning` と区別できる（色・ラベル等）
2. **Given** `severity: warning` なアラートが発火したとき、**When** 通知が届いたとき、**Then** critical より目立たない形で通知される

---

### User Story 3 — アラートの重複通知を抑制する (Priority: P3)

同一アラートが繰り返し firing 状態になっても、一定時間内は重複して通知されない。解消後に再発した場合のみ再通知される。

**Why this priority**: アラートが頻発すると通知疲れ（alert fatigue）を招く。基本機能が安定してから改善すべき課題。

**Independent Test**: 同一アラートを連続発火させた際に、一定時間内は1件のみ通知されることを確認できる。

**Acceptance Scenarios**:

1. **Given** アラートが firing 中のとき、**When** 同一アラートが再度 firing になったとき、**Then** 4時間以内は重複通知されない
2. **Given** アラートが一度 resolved になり、**When** 同じアラートが再び firing になったとき、**Then** 新規通知が届く

---

### Edge Cases

- 通知サービス（Slack）が一時的に接続できない場合、通知はキューイングされ復旧後に送信されるか？
- 複数のアラートが同時に発火した場合（例: TargetDown が複数）、通知はどのようにまとめられるか？
- Alertmanager自身がダウンした場合、誰がそれを検知するか？（自己監視の死角）
- アラートが数日間 firing 状態のまま続いた場合、定期的な再通知はあるか？

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: システムはPrometheusが生成したアラートを受信し、指定のSlackチャンネルへ通知しなければならない
- **FR-002**: 通知メッセージにはアラート名・重要度（severity）・発生時刻・対象リソースの識別情報・説明文を含まなければならない
- **FR-003**: アラートが resolved になった際、解消通知をSlackに送信しなければならない
- **FR-004**: `severity: critical` と `severity: warning` は異なる視覚表現で通知されなければならない
- **FR-005**: 同一アラートが firing 中の間、繰り返し通知される間隔は4時間以上でなければならない（通知疲れ防止）
- **FR-006**: 通知基盤はIaCで管理され、設定変更はコードの変更とデプロイ操作のみで反映できなければならない
- **FR-007**: 通知基盤は既存のPrometheusアラートルール（alerts.yml）と無設定変更で連携できなければならない

### Key Entities

- **アラート**: Prometheusが生成する状態変化イベント。アラート名・重要度（severity）・ラベル群・アノテーション（summary/description）を持つ
- **ルーティングルール**: アラートの属性（severity等）に基づいて通知先と通知方法を決定する設定。コードで管理される
- **通知レシーバー**: Slackチャンネル等の具体的な通知宛先。接続情報は環境変数で管理される
- **シレンス（将来拡張）**: 特定期間・条件下でアラート通知を抑制するルール

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: アラート発生から60秒以内にSlack通知が届く（Prometheusのfor条件を満たした後）
- **SC-002**: 既存の全7アラートルール（TargetDown / ContainerHighCPU / ContainerHighMemory / PrometheusConfigReloadFailed / PrometheusTSDBCompactionsFailed / RTX830LANInterfaceDown / SynologyHighCPU / SynologyDiskHighUsage）がSlackに通知される
- **SC-003**: 通知から対象リソースと重要度の読み取りに要する時間が10秒以内（通知内容の明瞭性）
- **SC-004**: 通知基盤がダウンした場合でも、Prometheusのアラートルール評価は継続する（独立した障害域）
- **SC-005**: 設定ファイルへの変更が、サービス再起動なしにホットリロードで反映される

## Assumptions

- Slack Incoming Webhook URLは事前に取得済みで、`.env`ファイルで管理する
- 通知先チャンネルは学習用の専用チャンネルを1〜2個用意する（既存チャンネルへの混入を避ける）
- アラートの重要度分類は既存のラベル（`severity: critical` / `severity: warning`）を踏襲する
- メトリクスの長期保存（Thanos等）はこのフェーズのスコープ外とする
- PagerDuty等の他の通知サービスへの対応は将来拡張とする
- Alertmanager自体の可用性監視（二重監視）は今フェーズのスコープ外とする

## Out of Scope

- メール通知
- PagerDuty / Opsgenie 等との連携
- Alertmanagerの冗長化（HA構成）
- アラートルール自体の変更・追加（alerts.yml はこのフェーズで触らない）
- メトリクスの長期保存設定
