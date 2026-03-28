# Implementation Plan: Grafana Tempo + OpenTelemetry Collector トレーシング基盤

**Branch**: `011-tempo` | **Date**: 2026-03-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-tempo/spec.md`

## Summary

Prometheus (metrics) + Loki (logs) + Grafana の既存スタックに Grafana Tempo + OpenTelemetry Collector を追加し、LGTM Stack を完成させる。Tempo は local filesystem バックエンドの single binary モードでデプロイし、OTel Collector が OTLP トレースを中継する。既存の `docker_container` Terragrunt モジュールを再利用し、Prometheus Exemplar と Grafana データソースリンクでメトリクス↔トレース相関を実現する。

---

## Technical Context

**Language/Version**: HCL (Terraform/Terragrunt), YAML (設定ファイル), Bash (sync スクリプト)
**Primary Dependencies**: grafana/tempo:latest, otel/opentelemetry-collector-contrib:latest, 既存 docker_container モジュール
**Storage**: Docker Volume (tempo_data) — local filesystem バックエンド
**Testing**: telemetrygen によるサンプルトレース送信、Grafana Explore での目視確認、Prometheus ターゲット確認
**Target Platform**: リモート Docker Engine (10.0.0.220), WSL2 経由の Terragrunt
**Project Type**: IaC + 設定ファイル (インフラフィーチャー)
**Performance Goals**: トレース送信から Grafana 表示まで 10 秒以内 (SC-002)
**Constraints**:
- `docker_container` モジュールは 1 サービスにつき 1 ポートペアのみ対応
  → Tempo: 3200 外部公開、OTel Collector: 4317 外部公開
  → Tempo の OTLP ポート (4317/4318) は Docker ネットワーク内のみ
- HCP Terraform 新規 Workspace は Local 実行モードへの手動変更が必要
**Scale/Scope**: 2 新規コンテナ (tempo, otel-collector)、5 ファイル変更、2 ファイル新規作成

---

## Constitution Check

| 原則 | 状態 | 備考 |
|------|------|------|
| **I. IaC (Terragrunt)** | ✅ PASS | 既存 `docker_container` モジュール再利用。手動デプロイなし |
| **II. セキュリティファースト** | ✅ PASS | TLS なし・認証なしは学習環境として許容、技術的負債として記録 |
| **III. ドキュメント駆動** | ✅ PASS | spec → research → plan → tasks の順序遵守 |
| **IV. モジュール化 DRY** | ✅ PASS | 新規モジュール不要。既存 `docker_container` モジュールで対応 |
| **V. 自己監視** | ✅ PASS | Job 9 (tempo) を prometheus.yml に追加。TargetDown アラートが自動カバー |

**Gate**: 全原則 PASS。実装フェーズに進んでよい。

---

## Project Structure

### Documentation (this feature)

```text
specs/011-tempo/
├── spec.md              # 機能仕様書
├── research.md          # Phase 0 調査結果 ✅
├── data-model.md        # 設定・依存関係スキーマ ✅
├── quickstart.md        # 動作確認手順 ✅
├── plan.md              # このファイル ✅
├── contracts/           # 設定ファイルスキーマ ✅
│   ├── tempo-config-schema.yml
│   ├── otel-collector-config-schema.yml
│   └── grafana-datasource-changes.yml
└── tasks.md             # Phase 2 output (/speckit.tasks で生成)
```

### Source Code (repository root)

```text
# 新規作成ファイル
config/
├── tempo/
│   └── tempo.yml                          # Tempo 設定ファイル
└── otel-collector/
    └── otel-collector.yml                 # OTel Collector 設定ファイル

terraform/envs/local/
├── tempo/
│   └── terragrunt.hcl                     # Tempo Terragrunt 定義
└── otel-collector/
    └── terragrunt.hcl                     # OTel Collector Terragrunt 定義

# 変更ファイル
config/prometheus/prometheus.yml           # Job 9 追加 + Exemplar 設定
config/grafana/provisioning/datasources/
    datasources.yml                        # Tempo DS 追加 + Prometheus Exemplar リンク
scripts/sync-config.sh                     # tempo / otel-collector サブコマンド追加
Taskfile.yml                               # sync:tempo / sync:otel-collector タスク追加
```

**Structure Decision**: IaC フィーチャーのため src/ 構造は不要。既存の `config/` + `terraform/envs/local/` パターンに追従。

---

## Implementation Phases

### Phase A: 設定ファイル作成 (US1 対応 — P1)

**目標**: Tempo と OTel Collector が起動し、トレースを受信・保存できる状態にする。

#### A1: Tempo 設定ファイル作成
- ファイル: `config/tempo/tempo.yml`
- single binary モード、local backend
- OTLP gRPC (4317) + HTTP (4318) リスナー
- metrics_generator 有効 (service-graphs, span-metrics)
- ブロック保持期間: 336h (14日)

#### A2: OTel Collector 設定ファイル作成
- ファイル: `config/otel-collector/otel-collector.yml`
- receivers: otlp (gRPC 4317, HTTP 4318)
- processors: batch
- exporters: otlp/tempo (→ tempo:4317, insecure)
- pipeline: traces (receiver → processor → exporter)

#### A3: Terragrunt 定義作成 (Tempo)
- ファイル: `terraform/envs/local/tempo/terragrunt.hcl`
- `docker_container` モジュール参照
- 依存: network
- ボリューム: `tempo_data` → `/var/tempo`
- バインドマウント: `~/monitoring-lab/tempo/tempo.yml`
- ポート: 3200 → 3200

#### A4: Terragrunt 定義作成 (OTel Collector)
- ファイル: `terraform/envs/local/otel-collector/terragrunt.hcl`
- `docker_container` モジュール参照
- 依存: network, tempo
- ボリュームなし (ステートレス)
- バインドマウント: `~/monitoring-lab/otel-collector/otel-collector.yml`
- ポート: 4317 → 4317

#### A5: HCP Terraform Workspace の Local 化
- `monitoring-lab-local-tempo` を Local 実行モードに変更
- `monitoring-lab-local-otel-collector` を Local 実行モードに変更
- HCP Terraform UI または API で実施

#### A6: Terragrunt apply
```bash
task tg:apply:svc -- tempo
task tg:apply:svc -- otel-collector
```

#### A7: 設定ファイル転送 + コンテナ確認
```bash
wsl ... ssh ubuntu@10.0.0.220 'mkdir -p ~/monitoring-lab/tempo ~/monitoring-lab/otel-collector'
# scp 設定ファイル → remote
# docker restart / または Terragrunt が初回 apply でマウント済み
```

---

### Phase B: Grafana + Prometheus 統合 (US2 対応 — P2)

**目標**: Grafana でトレースを可視化し、Exemplar によるメトリクス↔トレース相関を確立する。

#### B1: prometheus.yml に Exemplar 設定追加
```yaml
global:
  scrape_protocols:
    - OpenMetricsText1.0.0
    - OpenMetricsText0.0.1
    - PrometheusText0.0.4

storage:
  exemplar_storage:
    enable_exemplar_storage: true
    max_exemplars: 100000
```

#### B2: prometheus.yml に Tempo スクレイプジョブ追加
```yaml
- job_name: 'tempo'
  static_configs:
    - targets: ['tempo:3200']
```

#### B3: datasources.yml に Tempo データソース追加
- `deleteDatasources` に Tempo を追加
- Tempo データソース (uid: tempo, url: http://tempo:3200)
- tracesToLogs → Loki, serviceMap → Prometheus, tracesToMetrics → Prometheus

#### B4: datasources.yml の Prometheus データソース更新
- `exemplarTraceIdDestinations` を jsonData に追加
- `datasourceUid: tempo` で Exemplar → Tempo リンク

#### B5: 設定同期
```bash
task sync:prometheus    # Exemplar 設定 + Job 9 反映
task sync:grafana       # Tempo データソース + Prometheus 更新 反映
```

---

### Phase C: sync-config.sh + Taskfile 拡張 (US3 対応 — P2)

**目標**: 既存の運用フローに tempo/otel-collector を統合する。

#### C1: sync-config.sh に tempo サブコマンド追加
```bash
sync_tempo() {
  step "tempo: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/tempo"
  scp "${REPO_ROOT}/config/tempo/tempo.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/tempo/tempo.yml"
  step "tempo: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-tempo"
  info "tempo 同期完了"
}
```

#### C2: sync-config.sh に otel-collector サブコマンド追加
```bash
sync_otel_collector() {
  step "otel-collector: 設定ファイルを転送中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p ${REMOTE_BASE}/otel-collector"
  scp "${REPO_ROOT}/config/otel-collector/otel-collector.yml" \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_BASE}/otel-collector/otel-collector.yml"
  step "otel-collector: コンテナを再起動中..."
  ssh "${TARGET_USER}@${TARGET_HOST}" "docker restart monitoring-lab-otel-collector"
  info "otel-collector 同期完了"
}
```

#### C3: `all` ターゲットに tempo + otel-collector を追加

#### C4: Taskfile.yml に sync:tempo / sync:otel-collector タスク追加

---

### Phase D: 動作確認 (全 US 統合テスト)

**目標**: quickstart.md の手順通りに全て動作することを確認する。

#### D1: Tempo ヘルスチェック
```bash
curl -s http://10.0.0.220:3200/ready  # "ready" を確認
```

#### D2: OTel Collector 起動確認
```bash
task logs -- otel-collector  # "Everything is ready." を確認
```

#### D3: サンプルトレース送信
```bash
docker run --rm --network host \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces --otlp-endpoint localhost:4317 --otlp-insecure --traces 5
```

#### D4: Grafana Explore で確認
- Tempo データソース → Search → トレース表示確認
- ウォーターフォールビュー表示確認

#### D5: Prometheus ターゲット確認
- http://10.0.0.220:9090/targets → `tempo` ジョブが UP

#### D6: Exemplar 表示確認 (任意)
- Prometheus データソース → Exemplar マーカー表示確認
- マーカークリック → Tempo ジャンプ確認

---

## 実装順序まとめ

```
A1 (tempo.yml)
A2 (otel-collector.yml)
A3 (tempo/terragrunt.hcl)
A4 (otel-collector/terragrunt.hcl)
    ↓
A5 (HCP Workspace Local化) → A6 (apply) → A7 (設定転送)
    ↓
B1 (prometheus.yml Exemplar) + B2 (Job 9)
B3 (datasources.yml Tempo) + B4 (Prometheus更新)
    ↓
B5 (sync:prometheus + sync:grafana)
    ↓
C1 (sync_tempo) + C2 (sync_otel_collector) + C3 (all) + C4 (Taskfile)
    ↓
D (動作確認)
```

---

## リスクと軽減策

| リスク | 軽減策 |
|--------|--------|
| docker_container モジュールの単一ポート制約 | Tempo の OTLP は Docker ネットワーク内部のみ。外部公開は 3200 のみで十分 |
| HCP Workspace の Remote 実行モード | 既知の問題。apply 前に手動で Local に変更 |
| Exemplar 収集のためのアプリ側対応が必要 | 本フィーチャーは Tempo 側の受け入れ準備のみ。アプリ側は別フィーチャーで対応 |
| metrics_generator が過剰なメトリクスを生成 | 学習環境では許容。問題があれば `overrides` で無効化 |
