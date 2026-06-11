# Implementation Plan: Pyroscope 継続的プロファイリング基盤

**Branch**: `015-pyroscope` | **Date**: 2026-05-07（バックフィル: 2026-06-08） | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/015-pyroscope/spec.md`

> **注**: 本書類は実装・デプロイ完了後（`grafana/pyroscope:2.0.2` 本番稼働中）に Speckit ADLC 整合のため後追い作成（バックフィル）した。「これから作る計画」ではなく、**実際に行った実装の計画記録**である。

---

## Summary

Grafana Pyroscope（v2.0.2）を Monolithic モードで単一コンテナとして導入し、LGTM スタックの "P"（Profiles）を担う。`docker_container` モジュールでデプロイし、`:4040` でメトリクスを公開して既存 Prometheus がスクレイプ、Grafana には `grafana-pyroscope-datasource` を provisioning で追加する。プロファイルデータは名前付きボリューム `pyroscope_data` で永続化する。

**スコープ境界**: Pyroscope v2.x は pull-based pprof スクレイプを `config.yml` で設定できないため、初期スコープは「サーバー稼働 + メトリクス統合 + datasource 接続 + 永続化」までとし、セルフプロファイルの実収集（Alloy/SDK 経由）は次フェーズに繰り延べる。

---

## Technical Context

**Language/Version**: HCL (Terragrunt), YAML (Pyroscope config)
**Primary Dependencies**: `grafana/pyroscope:2.0.2`, Prometheus, Grafana 10+
**Storage**: Docker named volume `pyroscope_data`（`/data`）
**Testing**: `/ready` ヘルスチェック, Prometheus `up{job="pyroscope"}`, Grafana datasource 接続確認
**Target Platform**: WSL2 (Ubuntu-24.04) 上の Terragrunt / リモート Docker Engine (YOUR_SERVER_IP)
**Project Type**: IaC 設定（単一プロジェクト）
**Performance Goals**: N/A（学習用途、最小構成）
**Constraints**: 既存サービスとのポート競合なし（:4040）、`:latest` タグ禁止（固定タグ必須）
**Scale/Scope**: 単一コンテナ、セルフメトリクスのみ

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原則 | 状態 | 根拠 |
|---|---|---|
| I. Infrastructure as Code | ✅ PASS | Pyroscope コンテナは Terragrunt（`docker_container` モジュール）で管理。設定は Git 管理 |
| II. セキュリティファースト | ✅ PASS | 設定にシークレットなし。ローカルネットワーク限定、`.env` 参照なし |
| III. ドキュメント駆動開発 | ✅ PASS | Speckit ADLC 書類を整備（spec → research → plan → data-model → tasks → quickstart）※実装先行・書類バックフィル |
| IV. モジュール化・DRY | ✅ PASS | 既存 `docker_container` モジュールを再利用。新規モジュール定義なし |
| V. 自己監視の可観測性 | ✅ PASS | Pyroscope 自身を Prometheus 監視対象に組み込み、`TargetDown` で死活監視 |

**判定**: 全原則クリア。

> **バックフィルの誠実性に関する注記**: 原則 III は「ドキュメント駆動開発」を求めるが、本フィーチャーは実装が書類に先行した。この乖離を記録し、書類を後追いで整備することで整合を回復した。今後の新規フィーチャーでは specify → plan → implement の順序を維持する。

---

## Project Structure

### Documentation (this feature)

```text
specs/015-pyroscope/
├── plan.md              # このファイル
├── spec.md              # 機能仕様書
├── research.md          # Phase 0 調査結果（バックフィル）
├── data-model.md        # サービス構成・メトリクス・依存関係（バックフィル）
├── quickstart.md        # 動作確認手順（バックフィル）
├── contracts/
│   └── pyroscope-config-schema.yml   # 設定インターフェース契約（バックフィル）
├── checklists/
│   └── requirements.md  # 仕様品質チェックリスト
└── tasks.md             # 実装タスク（バックフィル・全完了）
```

### Source Code (repository root)

```text
config/
├── pyroscope/
│   └── config.yml                   # [新規] pyroscopedb.data_path 設定
├── prometheus/
│   └── prometheus.yml               # [変更] pyroscope ジョブ追加
└── grafana/provisioning/datasources/
    └── datasources.yml              # [変更] Pyroscope datasource 追記

terraform/envs/local/pyroscope/
└── terragrunt.hcl                   # [新規] コンテナ定義（image 固定 2.0.2）
```

**Structure Decision**: 単一プロジェクト（IaC 設定）。新規ディレクトリは `config/pyroscope/` と `terraform/envs/local/pyroscope/`。

---

## Implementation Phases

### Phase A: Pyroscope サーバー起動（P1 基盤）

**目標**: Pyroscope コンテナがリモートで稼働し `/ready` が応答する

1. `config/pyroscope/config.yml` を作成（`pyroscopedb.data_path: /data`）
2. `terraform/envs/local/pyroscope/terragrunt.hcl` を作成
   - `image = "grafana/pyroscope:2.0.2"`（固定タグ）
   - port 4040、`pyroscope_data` ボリューム、bind mount
3. リモートに config を scp（`/home/ubuntu/monitoring-lab/pyroscope/`）
4. HCP Workspace 作成 → 実行モードを Local に変更
5. `terragrunt apply` でコンテナ起動
6. `/ready` 確認（起動直後の 503 は正常猶予）

**完了条件**: Pyroscope コンテナが Up、`/ready` が 200

---

### Phase B: Prometheus メトリクス統合（P2）

**目標**: Prometheus が `pyroscope` ジョブを UP として認識

1. `config/prometheus/prometheus.yml` に `pyroscope` ジョブを追加（`targets: ['pyroscope:4040']`）
2. `task sync:prometheus` でリモート反映 + ホットリロード
3. Prometheus UI `/targets` で `pyroscope` ジョブ UP を確認

**完了条件**: SC-002 — `up{job="pyroscope"} == 1`

---

### Phase C: Grafana datasource 統合（P1 可視化）

**目標**: Grafana に Pyroscope データソースが自動プロビジョニングされる

1. `config/grafana/provisioning/datasources/datasources.yml` に Pyroscope datasource を追記
   - `type: grafana-pyroscope-datasource`、`uid: pyroscope`、`url: http://pyroscope:4040`
2. `task sync:grafana` でリモート反映 + Grafana 再起動
3. Grafana の Data sources 一覧で Pyroscope の接続テスト成功を確認

**完了条件**: FR-004 — Pyroscope datasource が接続可能

---

### Phase D: 永続化・バージョン固定・整合確認

**目標**: 再起動耐性とドリフト防止を確保

1. コンテナ再起動で `pyroscope_data` のデータ保持を確認（SC-003）
2. `image` を `:latest` → `:2.0.2` に固定（2026-05-30 実施、Tempo/OTel の教訓）
   - apply で `forces replacement`（1 add/1 destroy）→ ボリューム保持・瞬断4秒を確認
3. `task tg:plan` で全 Workspace "No changes" を確認（Constitution I, SC-005）

**完了条件**: SC-003 / SC-004 / SC-005 達成、`:2.0.2` ピン済み

---

## 依存関係と実施順序

```
Phase A → Phase B → Phase C → Phase D
（A 完了でサーバー稼働 → B/C は A に依存、相互は並列可 → D で締め）
```

---

## リスクと軽減策

| リスク | 影響 | 軽減策 | 結果 |
|---|---|---|---|
| `:latest` タグの破壊的変更 | コンテナ再作成時に挙動変化 | 固定タグ `2.0.2` にピン | ✅ 対処済み（2026-05-30） |
| v2.x で pull スクレイプ設定不可 | SC-001 完全達成不可 | スコープを縮小、Alloy/SDK を次フェーズへ | ⚠️ 部分達成として記録 |
| イメージタグ変更時のデータ消失 | プロファイル履歴喪失 | 名前付きボリューム使用 | ✅ 保持を実証（瞬断4秒） |

---

## Complexity Tracking

Constitution Check 違反なし（原則 III の順序逸脱はバックフィルで是正済み）。このセクションは不要。

---

## 残作業（次フェーズ候補）

- セルフプロファイル実収集: Grafana Alloy 導入または Pyroscope SDK 組み込み（SC-001 完全達成）
- Exemplar → Profile 相関リンク（US3 発展形、`uid: pyroscope` で参照先は確保済み）
