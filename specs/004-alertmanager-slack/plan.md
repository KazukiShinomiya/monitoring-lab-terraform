# Implementation Plan: Alertmanager導入 — アラート通知基盤

**Branch**: `004-alertmanager-slack` | **Date**: 2026-03-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-alertmanager-slack/spec.md`

## Summary

Prometheusが評価するアラートルール（alerts.yml、7種類）をSlackに通知するAlertmanager基盤を構築する。既存の `docker_container` Terragruntモジュールを使ってリモートサーバー（YOUR_SERVER_IP）にコンテナをデプロイし、severity（critical/warning）による色分け通知と inhibit_rules による通知疲れ防止を実装する。

## Technical Context

**Language/Version**: HCL (Terraform/Terragrunt)、YAML (Alertmanager config)
**Primary Dependencies**: `prom/alertmanager:latest`、既存 `docker_container` Terragruntモジュール
**Storage**: N/A（Alertmanagerはステートレス動作。silencesは再起動時にリセット許容）
**Testing**: `amtool check-config`（設定検証）、cAdvisor停止による手動発火テスト
**Target Platform**: Docker on Ubuntu 22.04 (YOUR_SERVER_IP)
**Project Type**: Infrastructure (IaC)
**Performance Goals**: アラート発生から60秒以内にSlack通知（SC-001）
**Constraints**: 既存 `docker_container` モジュールで対応可能。新規モジュール作成不要（Constitution IV 準拠）
**Scale/Scope**: 1コンテナ、7アラートルール、1 Slack チャンネル

## Constitution Check

### I. Infrastructure as Code (IaC) ✅

- Alertmanager は `terraform/envs/local/alertmanager/terragrunt.hcl` で定義
- 手動での Docker run は禁止。すべてTerragrunt経由
- HCP Terraform Workspace `monitoring-lab-local-alertmanager` を作成しLocal実行モードで管理
- apply後に `terragrunt plan` が "No changes" を示すことを確認

### II. セキュリティファースト ✅

- Slack Webhook URL は `.env` に `SLACK_WEBHOOK_URL` として格納（Gitコミット禁止）
- `alertmanager.yml` 内は `<YOUR_SLACK_WEBHOOK_URL>` プレースホルダーで管理
- 実際のURLはリモートサーバー上の設定ファイルにのみ存在

### III. ドキュメント駆動開発 ✅

- 本計画書に基づき実装を開始
- 設計上の意思決定は `research.md` に根拠とともに記録済み

### IV. モジュール化とDRY原則 ✅

- 既存 `docker_container` モジュールを再利用
- 新規モジュール作成なし（モジュールの汎用性で対応可能と判断）

### V. 自己監視の可観測性 ✅

- Alertmanager自身の監視: 既存 `TargetDown` アラートが Alertmanager のスクレイプ失敗をカバー
- Alertmanager の `/metrics` エンドポイントを Prometheus にスクレイプ追加（タスクに含める）

## Project Structure

### Documentation (this feature)

```text
specs/004-alertmanager-slack/
├── plan.md              # This file
├── research.md          # Phase 0 output ✅
├── data-model.md        # Phase 1 output ✅
├── quickstart.md        # Phase 1 output ✅
├── contracts/
│   └── alertmanager.yml.example   # Alertmanager設定テンプレート ✅
├── checklists/
│   └── requirements.md  # Spec検証チェックリスト ✅
└── tasks.md             # Phase 2 output（/speckit.tasks で生成）
```

### Source Code (repository root)

```text
config/
├── alertmanager/
│   └── alertmanager.yml           # 新規作成（Alertmanager設定）
└── prometheus/
    └── prometheus.yml             # 変更（alerting: セクション追加）

terraform/envs/local/
└── alertmanager/
    └── terragrunt.hcl             # 新規作成（Alertmanagerコンテナ定義）

.env.example                       # 変更（SLACK_WEBHOOK_URL を追加）
```

**Structure Decision**: 既存の `config/<service>/` + `terraform/envs/local/<service>/` パターンを踏襲。

## Implementation Design

### コンテナ仕様

| 項目 | 値 |
|------|-----|
| イメージ | `prom/alertmanager:latest` |
| コンテナ名 | `monitoring-lab-alertmanager` |
| 内部ポート | 9093 |
| 外部ポート | 9093 |
| 設定ファイル | `/etc/alertmanager/alertmanager.yml` |
| ネットワーク | `monitoring-lab-network` |
| 依存関係 | `network` モジュール |
| HCP Workspace | `monitoring-lab-local-alertmanager` |

### Alertmanager 設定設計

詳細は `contracts/alertmanager.yml.example` を参照。

```yaml
route:
  receiver: 'slack-notifications'   # warningのデフォルト
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h               # FR-005準拠
  routes:
    - match: {severity: critical}
      receiver: 'slack-critical'
      repeat_interval: 1h

receivers:
  - name: 'slack-notifications'     # warning: 黄色
  - name: 'slack-critical'          # critical: 赤色

inhibit_rules:
  - source_match: {severity: critical}
    target_match: {severity: warning}
    equal: ['alertname', 'job']
```

### Prometheus設定変更

`config/prometheus/prometheus.yml` に `alerting:` セクションを追加:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

# Alertmanager のメトリクスもスクレイプ（SC-004 自己監視）
scrape_configs:
  # ... 既存 ...
  - job_name: 'alertmanager'
    static_configs:
      - targets: ['alertmanager:9093']
```

## デプロイ手順

```
Step 1: config/alertmanager/alertmanager.yml 作成
Step 2: terraform/envs/local/alertmanager/terragrunt.hcl 作成
Step 3: config/prometheus/prometheus.yml に alerting: セクション追加
Step 4: .env.example に SLACK_WEBHOOK_URL を追加
Step 5: リモートサーバーにディレクトリ・ファイルを配置 (scp)
Step 6: HCP Workspace 作成 + Local モード設定
Step 7: terragrunt init + apply
Step 8: Prometheus ホットリロード（alerting section 反映）
Step 9: 動作確認（cAdvisor 停止テスト）
Step 10: commit & push
```

## リスクと対策

| リスク | 対策 |
|--------|------|
| Slack Webhook URL の漏洩 | `.env` 管理 + `.gitignore` 確認 |
| Alertmanager起動後のPrometheus未連携 | ホットリロード忘れ防止のためタスクに手順を明記 |
| HCP Workspace が Remote モードで作成される | 作成直後に API で Local モードに変更（既知の手順あり） |
| Alertmanager自身のダウン無検知 | Prometheusの TargetDown がカバー（スクレイプ追加で解決） |
