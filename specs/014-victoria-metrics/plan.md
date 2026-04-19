# Implementation Plan: VictoriaMetrics 長期メトリクス保存基盤

**Branch**: `014-victoria-metrics` | **Date**: 2026-04-19 | **Spec**: `specs/014-victoria-metrics/spec.md`

---

## Summary

VictoriaMetrics シングルノードを Docker コンテナとして `10.0.0.220` にデプロイし、Prometheus の `remote_write` で全メトリクスを自動転送する。保持期間 12ヶ月（FR-002）、Prometheus 互換 API による既存クエリの再利用（FR-003）、Grafana への独立データソース追加（FR-005）を実現する。

既存の Prometheus・Grafana・アラートルールへの変更は最小限（prometheus.yml への追記と datasources.yml への追記のみ）で、SC-003「既存変更なし」を満たす。

---

## Technical Context

**Language/Version**: HCL (Terragrunt/Terraform), YAML  
**Primary Dependencies**: `victoriametrics/victoria-metrics:stable`, 既存 `docker_container` モジュール (`terraform/modules/docker_container/`)  
**Storage**: Docker Volume `vm_data` — local filesystem backend (`/victoria-metrics-data`)  
**Testing**: curl / Prometheus API クエリによる E2E 検証（ユニットテストなし、インフラのため）  
**Target Platform**: Docker Engine on Ubuntu 22.04 (10.0.0.220)  
**Project Type**: Infrastructure-only（新規アプリケーションコードなし）  
**Performance Goals**: SC-004: 過去90日クエリが5秒以内に返ること  
**Constraints**: 学習環境 HTTP のみ（TLS なし）、シングルノード（HA なし）、既存スタックへの影響最小化  
**Scale/Scope**: 全 Prometheus スクレイプメトリクス（Job 1-10）、365日保持、推定 5〜10 GB/年

---

## Constitution Check

*GATE: 全 5 原則への準拠を確認する*

| 原則 | 準拠状況 | 根拠 |
|---|---|---|
| **I. IaC** | ✅ PASS | `terraform/envs/local/victoriametrics/terragrunt.hcl` で管理。手動 docker run 禁止。apply 後 "No changes" 確認（T010） |
| **II. セキュリティ** | ✅ PASS | シークレット不要（認証なし、学習環境として許容）。HTTP のみは Assumptions に明記済み。`.env` / git へのシークレット混入なし |
| **III. ドキュメント駆動** | ✅ PASS | spec.md → plan.md（本ファイル）→ tasks.md の順序を遵守。SESSION_STATE.md 更新は tasks.md の最終タスクに含める |
| **IV. DRY** | ✅ PASS | 既存 `docker_container` モジュールを再利用。新規モジュール不要。インライン `docker_container` リソース定義なし |
| **V. 自己監視** | ✅ PASS | prometheus.yml に Job 11 (`victoriametrics:8428`) を追加。既存 TargetDown アラートが VM ダウンを自動検知 |

**Constitution Check: 全原則 PASS — 実装進行可能**

---

## Project Structure

### Documentation (this feature)

```text
specs/014-victoria-metrics/
├── spec.md              # 機能仕様書（作成済み）
├── plan.md              # 本ファイル
├── research.md          # 技術調査結果（作成済み）
├── data-model.md        # エンティティ定義（作成済み）
├── quickstart.md        # 動作確認手順（作成済み）
├── contracts/
│   ├── victoriametrics-api.md       # VictoriaMetrics API 仕様
│   └── terragrunt-interface.md      # Terragrunt インターフェース定義
└── tasks.md             # /speckit.tasks コマンドで生成（次フェーズ）
```

### Source Code (変更対象ファイル)

```text
terraform/envs/local/
└── victoriametrics/
    └── terragrunt.hcl          # 新規: VM コンテナ定義

config/prometheus/
└── prometheus.yml              # 変更: remote_write + Job 11 追加

config/grafana/provisioning/datasources/
└── datasources.yml             # 変更: VictoriaMetrics データソース追加
```

**変更しないファイル**:
- `scripts/sync-config.sh` — 既存の `sync_prometheus` / `sync_grafana` で対応
- `Taskfile.yml` — 既存タスクで対応
- `config/prometheus/alerts.yml` — 変更不要（TargetDown アラートが流用可能）
- `config/prometheus/slo-rules.yml` — 変更不要

---

## Implementation Phases

### Phase A: VictoriaMetrics コンテナデプロイ（US1 P1）

**目標**: VM コンテナを IaC で起動し、ヘルスチェックが通ること

**成果物**:
- `terraform/envs/local/victoriametrics/terragrunt.hcl`
- HCP Workspace `monitoring-lab-local-victoriametrics` (Local mode)
- コンテナ `monitoring-lab-victoriametrics` 起動確認

**検証**:
```bash
curl -sf http://10.0.0.220:8428/health  # → "OK"
```

---

### Phase B: Prometheus remote_write 設定（US1 P1）

**目標**: Prometheus が VM へメトリクスを自動転送すること（SC-001）

**成果物**:
- `config/prometheus/prometheus.yml` — `remote_write` セクション + Job 11 追加
- `sync:prometheus` でリモートへ反映

**検証**:
```bash
curl -s "http://10.0.0.220:8428/api/v1/query?query=up"  # → status: success
```

---

### Phase C: Grafana データソース追加（US2 P2）

**目標**: Grafana から VictoriaMetrics のデータを参照できること

**成果物**:
- `config/grafana/provisioning/datasources/datasources.yml` — VictoriaMetrics エントリ追加
- `sync:grafana` でリモートへ反映

**検証**:
- Grafana Explore → VictoriaMetrics データソース → `up` クエリ → データ表示

---

### Phase D: E2E 検証・IaC クリーンアップ（全 SC 確認）

**目標**: 全 Success Criteria を確認し、"No changes" 状態を保証

**内容**:
- SC-001〜SC-004 全確認
- `task tg:plan` で全 Workspace "No changes"
- SESSION_STATE.md 更新

---

## Complexity Tracking

Constitution Check 違反なし — このセクションは不要。

---

## Post-Design Constitution Check

*Phase 1 設計完了後の再チェック*

| 原則 | 設計後評価 |
|---|---|
| I. IaC | ✅ terragrunt.hcl 定義確定。モジュール再利用。 |
| II. セキュリティ | ✅ シークレット不使用。HTTP 許容は Assumptions に明記。 |
| III. ドキュメント | ✅ research / data-model / contracts / quickstart 全生成。 |
| IV. DRY | ✅ docker_container モジュールを再利用。Volume 定義も既存パターンと一致。 |
| V. 自己監視 | ✅ Job 11 追加で VM が監視対象に含まれる。TargetDown アラートが流用可能。 |
