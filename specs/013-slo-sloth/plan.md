# Implementation Plan: SLO + Error Budget 管理基盤 (Sloth)

**Branch**: `013-slo-sloth` | **Date**: 2026-04-05 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/013-slo-sloth/spec.md`

---

## Summary

Sloth CLI（v0.11.0）を使い、`config/sloth/monitoring-lab.yml` に記述した SLO 定義から Prometheus の Multi-window Recording Rules と Alerting Rules を自動生成する。生成物は `config/prometheus/slo-rules.yml` として Git 管理し、既存の `sync-config.sh` で Prometheus にホットリロードする。Grafana には Sloth 公式ダッシュボード JSON をプロビジョニングで配置し、Error Budget の可視化を実現する。新しいコンテナは追加しない（Sloth はワンショット Docker 実行）。

---

## Technical Context

**Language/Version**: HCL (Terragrunt), YAML (Sloth v0.11.0 `prometheus/v1` スキーマ)  
**Primary Dependencies**: `ghcr.io/slok/sloth:v0.11.0`, Prometheus, Grafana, Alertmanager  
**Storage**: N/A（Sloth はステートレス・ファイル生成のみ）  
**Testing**: `sloth validate`（Sloth 組み込み）, `promtool check rules`（Prometheus 組み込み）  
**Target Platform**: WSL2 (Ubuntu-24.04) 上の Docker / リモート Docker Engine (YOUR_SERVER_IP)  
**Project Type**: IaC 設定（単一プロジェクト）  
**Performance Goals**: SC-001 — ルール変更から Prometheus 反映まで5分以内  
**Constraints**: 既存コンテナ定義（Terraform）への変更最小化、新規常駐コンテナ追加なし  
**Scale/Scope**: 初期 SLO 4件（Prometheus / Grafana / Alertmanager / Loki）

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原則 | 状態 | 根拠 |
|---|---|---|
| I. Infrastructure as Code | ✅ PASS | Sloth はワンショット実行で Terraform 管理対象外。生成される `slo-rules.yml` は Git 管理。`prometheus.yml` の変更は既存 `sync-config.sh` パターンに準拠 |
| II. セキュリティファースト | ✅ PASS | SLO YAML にシークレットなし。`.env` 参照なし |
| III. ドキュメント駆動開発 | ✅ PASS | Speckit ADLC フルサイクル（specify → clarify → plan）実施中 |
| IV. モジュール化・DRY | ✅ PASS | 新規コンテナ定義なし。既存 `sync-config.sh` + `Taskfile.yml` を拡張するのみ |
| V. 自己監視の可観測性 | ✅ PASS | 監視基盤自体（Prometheus/Grafana/Alertmanager/Loki）を SLO 対象とし、まさに自己監視を強化する |

**判定**: 全原則クリア。実装開始可能。

---

## Project Structure

### Documentation (this feature)

```text
specs/013-slo-sloth/
├── plan.md              # このファイル
├── spec.md              # 機能仕様書
├── research.md          # Phase 0 調査結果
├── data-model.md        # SLO定義・生成メトリクス・ファイル依存関係
├── quickstart.md        # 動作確認手順
├── contracts/
│   └── sloth-slo-schema.yml   # SLO YAML スキーマ（インターフェース契約）
└── tasks.md             # Phase 2 出力（/speckit.tasks で生成）
```

### Source Code (repository root)

```text
config/
├── sloth/
│   └── monitoring-lab.yml          # [新規] SLO定義（4サービス）
└── prometheus/
    ├── prometheus.yml               # [変更] rule_files に slo-rules.yml 追記
    ├── alerts.yml                   # [変更なし] 既存アラートルール
    └── slo-rules.yml                # [新規・自動生成] Sloth 生成 Recording/Alerting Rules

config/grafana/provisioning/dashboards/
└── sloth-overview.json              # [新規] Sloth 公式ダッシュボード

Taskfile.yml                         # [変更] slo:generate, slo:validate タスク追加
```

**Structure Decision**: 単一プロジェクト（IaC 設定）。新規ディレクトリは `config/sloth/` のみ。既存の `config/prometheus/` および `config/grafana/provisioning/dashboards/` に追加配置する。

---

## Implementation Phases

### Phase A: Sloth SLO 定義と基盤準備（P1 対応）

**目標**: `task slo:generate` 実行で `slo-rules.yml` が生成され、Prometheus に反映される

1. `config/sloth/monitoring-lab.yml` を作成（4件の SLO 定義）
   - SLI: `raw` タイプ、`1 - avg_over_time(up{job="..."}[{{.window}}])`
   - 目標値: Prometheus/Grafana/Alertmanager = 99.5%、Loki = 99.0%
   - Alerting: `page_alert`（page）/ `ticket_alert`（ticket）の2段階

2. `Taskfile.yml` に `slo:generate` と `slo:validate` タスクを追加
   - WSL2 経由で Sloth Docker コンテナをワンショット実行
   - bind mount: `config/sloth/` → `/input`、`config/prometheus/` → `/output`

3. `task slo:generate` を実行し `slo-rules.yml` を生成

4. `task slo:validate` で文法チェック（`promtool check rules`）

5. `config/prometheus/prometheus.yml` の `rule_files` に `slo-rules.yml` を追記

6. `task sync:prometheus` でリモート反映 → Prometheus UI `/rules` で確認

**完了条件**: Prometheus UI に `slo:sli_error:ratio_rate*` の Recording Rules が表示される

---

### Phase B: Grafana ダッシュボード配置（P2 対応）

**目標**: Grafana で Error Budget 残量と Burning Rate が自動表示される

1. Sloth 公式ダッシュボード JSON を取得
   - Docker コンテナ内 `/dist/grafana-dashboard.json` からコピー
   - または Sloth GitHub リリースページからダウンロード

2. `config/grafana/provisioning/dashboards/sloth-overview.json` として配置

3. `task sync:grafana` でリモート反映

4. Grafana UI で `Sloth - SLO Overview` ダッシュボードを開き、4サービスの Error Budget 残量を確認

**完了条件**: SC-002 — Error Budget 残量（%）と Burning Rate グラフが手動操作なしで表示される

---

### Phase C: Alertmanager 統合確認（P3 対応）

**目標**: Burning Rate 閾値超過時に Slack 通知が届く

1. 生成された Alerting Rules の severity ラベルを確認
   - `page` アラート（Fast Burn: 14.4倍 / 6倍）
   - `ticket` アラート（Slow Burn: 3倍 / 1倍）

2. 既存 `config/alertmanager/alertmanager.yml` の routes に severity ラベルの routing が含まれているか確認
   - 未設定の場合は `severity: page` のルートを追加

3. 動作確認: 対象コンテナを一時停止してアラートが FIRING になることを確認

4. Slack 通知の受信確認（FIRING / RESOLVED）

**完了条件**: SC-003 — Slack に `SLOBudgetBurn` アラート通知が届く

---

### Phase D: ドキュメント整備と `sync-config.sh` 確認

**目標**: 運用フローの完結確認

1. `scripts/sync-config.sh` が `slo-rules.yml` も同期対象になっているか確認
   - 既存の `prometheus` オプションは `config/prometheus/` 以下を全て scp するため追加変更不要なはず

2. `run-all plan` で全ワークスペースが "No changes" であることを確認（Constitution I）

3. SESSION_STATE.md 更新（Constitution III）

**完了条件**: SC-004 — 新 SLO YAML 追記 → `task slo:generate` → `task sync:prometheus` → ダッシュボード自動更新まで手動 Grafana 操作が不要

---

## 依存関係と実施順序

```
Phase A → Phase B → Phase C → Phase D
（直列: 各フェーズの完了条件を確認してから次へ）
```

---

## リスクと軽減策

| リスク | 影響 | 軽減策 |
|---|---|---|
| Sloth v0.11.0 の `raw` SLI タイプが `up` メトリクスで正常動作しない | Phase A ブロック | 事前に `sloth validate` で確認。失敗時は `events` タイプへのフォールバックを検討 |
| Prometheus 再起動直後は30日分の Recording Rules 計算結果が不足 | SC-002 の確認が困難 | `slo:error_budget:ratio` が NaN ではなく 1.0（満杯）を返せばOKと判断 |
| Sloth 公式ダッシュボード JSON が v0.11.0 のメトリクス名と不一致 | Phase B ブロック | コンテナ内 `/dist/grafana-dashboard.json` を直接取得することで版整合を保証 |

---

## Complexity Tracking

Constitution Check 違反なし。このセクションは不要。
