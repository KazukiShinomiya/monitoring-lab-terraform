# Implementation Plan: Loki + Promtail ログ収集基盤

**Branch**: `010-loki-promtail` | **Date**: 2026-03-20 | **Spec**: [spec.md](./spec.md)
**Input**: 既存の Prometheus + Grafana スタックにログ収集基盤（Loki + Promtail）を追加し、メトリクスとログの相関分析を可能にする

---

## Summary

Loki（ログ集約）と Promtail（ログ収集エージェント）を既存の docker_container Terragrunt モジュールでリモートDocker環境（10.0.0.220）にデプロイする。Promtail は Docker Socket 経由で全監視基盤コンテナのログを収集し、Grafana から LogQL で検索・閲覧できる状態を実現する。Loki 自身は Prometheus のスクレイプ対象として登録し Constitution 原則 V を満たす。

---

## Technical Context

**Language/Version**: HCL (Terragrunt/Terraform) + YAML（設定ファイル）
**Primary Dependencies**: `grafana/loki:3.4.2`、`grafana/promtail:3.4.2`、既存 `docker_container` モジュール
**Storage**: Docker Volume `loki_data`（/loki）、`promtail_positions`（/tmp）
**Testing**: `curl` による HTTP API 疎通確認、Grafana Explore での目視確認
**Target Platform**: リモートDocker Engine（10.0.0.220 / Ubuntu）
**Project Type**: Infrastructure（IaC only）
**Performance Goals**: ログ収集レイテンシ 30秒以内（SC-001）、Grafana LogQL 応答 5秒以内（SC-002）
**Constraints**: 認証なし（学習環境）、保持期間 7日（168h）、既存モジュール使用必須
**Scale/Scope**: 監視基盤コンテナ群（10〜15コンテナ）のログ収集

---

## Constitution Check

*GATE: Phase 0 前に通過必須。Phase 1 設計後に再確認。*

| 原則 | 評価 | 根拠 |
|------|------|------|
| I. IaC | ✅ PASS | 既存 `docker_container` モジュールを使用。手動変更なし |
| II. セキュリティファースト | ✅ PASS | シークレット不要（Loki認証なし）。`.env` 変更なし |
| III. ドキュメント駆動 | ✅ PASS | Speckit ADLC に従い spec → plan → tasks の順序で進行 |
| IV. モジュール化とDRY | ✅ PASS | 新モジュール不要。既存 `docker_container` モジュールで対応可能 |
| V. 自己監視の可観測性 | ✅ PASS | FR-009: Loki を Prometheus スクレイプ対象に追加（Job 8） |

**Constitution Check 結果**: 全原則クリア。実装に進んでよい。

---

## Project Structure

### Documentation (this feature)

```text
specs/010-loki-promtail/
├── spec.md              ✅ 完了
├── plan.md              ✅ このファイル
├── research.md          ✅ 完了（Phase 0）
├── data-model.md        ✅ 完了（Phase 1）
├── quickstart.md        ✅ 完了（Phase 1）
├── contracts/
│   ├── loki-api.md      ✅ 完了（Phase 1）
│   └── terragrunt-interface.md  ✅ 完了（Phase 1）
├── checklists/
│   └── requirements.md  ✅ 完了
└── tasks.md             📅 Phase 2（/speckit.tasks で生成）
```

### Source Code（変更対象ファイル）

```text
# 新規作成
config/
├── loki/
│   └── loki.yml                          # Loki 設定ファイル
└── promtail/
    └── promtail.yml                      # Promtail 設定ファイル（Docker Socket方式）

terraform/envs/local/
├── loki/
│   └── terragrunt.hcl                    # Loki Terragruntサービス定義
└── promtail/
    └── terragrunt.hcl                    # Promtail Terragruntサービス定義

# 既存ファイル変更
config/prometheus/prometheus.yml          # Job 8 (loki) 追加
config/grafana/provisioning/datasources/
    datasources.yml                       # Loki データソース追記
scripts/sync-config.sh                    # loki/promtail 同期オプション追加
```

**Structure Decision**: IaC フィーチャーのため `src/` 等は不要。設定ファイルは `config/<service>/` に、Terragrunt 定義は `terraform/envs/local/<service>/` に配置。既存パターンを踏襲。

---

## Implementation Phases

### Phase A: 設定ファイル作成

**成果物**: `config/loki/loki.yml`、`config/promtail/promtail.yml`

**Loki 設定ポイント**:
- `auth_enabled: false`（認証なし）
- TSDB スキーマ v13（Loki 3.x 推奨）
- `retention_period: 168h`（7日）
- `compactor.retention_enabled: true`

**Promtail 設定ポイント**:
- `docker_sd_configs` 方式（`unix:///var/run/docker.sock`）
- `container_name` / `image` / `logstream` のラベル付与
- positions ファイル: `/tmp/positions.yaml`（Volume化で永続化）

---

### Phase B: Terragrunt サービス定義

**成果物**: `terraform/envs/local/loki/terragrunt.hcl`、`terraform/envs/local/promtail/terragrunt.hcl`

**Loki**:
- Docker Volume: `loki_data` → `/loki`
- Bind Mount: `loki.yml` → `/etc/loki/loki.yml`（read-only）
- 依存: `network`
- Port: 3100

**Promtail**:
- Docker Volume: `promtail_positions` → `/tmp`
- Bind Mount 1: `promtail.yml` → `/etc/promtail/promtail.yml`（read-only）
- Bind Mount 2: `/var/run/docker.sock` → `/var/run/docker.sock`（read-only）
- 依存: `network` + `loki`
- Port: 9080

**HCP Terraform Workspace**: `loki`・`promtail` を新規作成し実行モードを Local に設定

---

### Phase C: 既存設定ファイルの変更

**prometheus.yml への追加**:
```yaml
  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']
```

**datasources.yml への追加**:
```yaml
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true
    version: 1
```

`deleteDatasources` セクションに `Loki` エントリも追加。

**sync-config.sh への追加**:
- `loki` オプション: `loki.yml` を scp → コンテナ再起動
- `promtail` オプション: `promtail.yml` を scp → コンテナ再起動

---

### Phase D: デプロイと動作確認

**手順**:
1. リモートサーバーに設定ファイルを scp
2. HCP Terraform に Workspace 作成（loki/promtail）
3. `terragrunt init && terragrunt apply`（loki → promtail の順）
4. `/ready` エンドポイントで Loki 起動確認
5. 30秒待機後、Loki API でログ収集確認（SC-001）
6. Prometheus Targets で loki が UP を確認
7. Grafana Explore で LogQL 動作確認（SC-002）
8. `terragrunt run-all plan` で No changes を確認

---

## Complexity Tracking

Constitution Check に違反はないため、このセクションは不要。

---

## Design Decisions Summary

| 決定事項 | 内容 | 詳細 |
|---------|------|------|
| イメージバージョン | `3.4.2`（固定） | 再現性確保、バージョン揃え |
| 収集方式 | Docker Socket + docker_sd_configs | メタデータ自動取得 |
| ストレージ | ローカルファイルシステム + TSDB v13 | 学習環境、シンプル構成 |
| 保持期間 | 168h（7日） | ストレージ節約 |
| positions永続化 | Docker Volume（promtail_positions） | 重複収集防止（FR-008） |
| 認証 | なし | 学習環境の前提 |
| Loki自己監視 | Prometheus Job 8 として追加 | Constitution 原則 V 準拠 |
