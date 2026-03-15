# Research: Alertmanager導入 — アラート通知基盤

**Phase**: 0 (Research)
**Date**: 2026-03-13
**Feature**: [spec.md](spec.md)

## 既存インフラとの統合ポイント

### Prometheus → Alertmanager 連携

- **現状**: `config/prometheus/prometheus.yml` に `alerting:` セクションが存在しない
- **対応**: `alertmanager:9093` を指すセクションを追加する必要あり
- **影響範囲**: prometheus.yml の変更 + リモートサーバーへのコピー + Prometheusホットリロード

```yaml
# 追加するセクション
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093
```

- Alertmanager コンテナ名 `alertmanager` は Dockerネットワーク `monitoring-lab-network` 上で解決される（Prometheus と同一ネットワーク）

### アラートルール現状

既存 `config/prometheus/alerts.yml` に7種類のアラートが定義済み（変更不要）:

| アラート名 | severity | グループ |
|-----------|----------|---------|
| TargetDown | critical | target_health |
| ContainerHighCPU | warning | container_resources |
| ContainerHighMemory | warning | container_resources |
| PrometheusConfigReloadFailed | critical | prometheus_health |
| PrometheusTSDBCompactionsFailed | warning | prometheus_health |
| RTX830LANInterfaceDown | warning | physical_devices |
| SynologyHighCPU | warning | physical_devices |
| SynologyDiskHighUsage | warning | physical_devices |

### Terraform モジュール評価

`terraform/modules/docker_container/variables.tf` 確認結果:

- `env`: `list(string)` — "KEY=VALUE" 形式で渡せる（Alertmanagerコンテナへの環境変数注入に使用可能）
- `bind_mounts`: optional — 設定ファイルのマウントに使用
- `command`: optional — Alertmanager起動コマンドの上書きに使用
- **問題なし**: 既存モジュールで対応可能、新規モジュール作成不要

---

## 設計上の決定

### 決定1: Slack Webhook URLの管理方法

**Decision**: `.env` ファイルに `SLACK_WEBHOOK_URL` として格納し、リモートサーバーへの設定ファイルコピー時に手動で埋め込む（`alertmanager.yml` はGit管理するがURLはプレースホルダー `<YOUR_SLACK_WEBHOOK_URL>` とする）

**Rationale**:
- Alertmanager の設定ファイルはネイティブに環境変数展開をサポートしない（v0.27.0時点）
- `envsubst` を使ったエントリーポイントスクリプトも有効だが、学習環境の複雑さを増加させる
- プレースホルダー方式は、URLを直接Gitにコミットせず、かつ設定の可読性を保つ
- 実際のURLは `.env` に記載し、デプロイ時に手動でリモートの設定ファイルに書き込む

**Alternatives considered**:
- `envsubst` エントリーポイント: 有効だが複雑性が増す（将来Phase 4で検討）
- Vault 統合: 本格的なシークレット管理だが現在は dev-mode のため学習用として過剰
- 直接ハードコード: セキュリティポリシー違反

### 決定2: 通知チャンネル構成

**Decision**: 1チャンネル構成 + severity による色分け（`critical` = 赤, `warning` = 黄）

**Rationale**:
- 学習環境での Slack ワークスペース管理コスト最小化
- severity ラベルによる視覚的区別で P2 要件を満たせる
- 将来的な複数チャンネル対応はルーティングルールの変更のみで実現可能

**Alternatives considered**:
- 別チャンネル分離（`#monitoring-critical` / `#monitoring-warning`）: 有効だが2つの Webhook URL 管理が必要

### 決定3: inhibit_rules の設定

**Decision**: `severity: critical` が発火している場合、同一 `job` / `instance` の `severity: warning` を抑制する

**Rationale**:
- サービスダウン（critical）発生時にリソース高負荷（warning）が同時発火する誤報を防ぐ
- Alertmanager の標準的なベストプラクティス

### 決定4: group_by とタイミング設定

| 設定項目 | 値 | 理由 |
|---------|-----|------|
| group_by | `['alertname', 'job']` | 同一種別アラートをまとめる |
| group_wait | 30s | アラート発火直後にまとめて送信 |
| group_interval | 5m | グループへの新アラート追加時の待機時間 |
| repeat_interval | 4h | FR-005 準拠（4時間以上の間隔） |
| resolve_timeout | 5m | 解消判定のタイムアウト |

---

## Alertmanager コンテナ仕様

| 項目 | 値 |
|------|-----|
| イメージ | `prom/alertmanager:latest` |
| ポート | 9093 (内部) / 9093 (外部) |
| 設定ファイル | `/etc/alertmanager/alertmanager.yml` |
| リモートパス | `/home/ubuntu/monitoring-lab/alertmanager/alertmanager.yml` |
| HCP Workspace | `monitoring-lab-local-alertmanager` |
| Terragrunt定義 | `terraform/envs/local/alertmanager/terragrunt.hcl` |

---

## デプロイ手順概要

1. `config/alertmanager/alertmanager.yml` を作成（URLはプレースホルダー）
2. `terraform/envs/local/alertmanager/terragrunt.hcl` を作成
3. `config/prometheus/prometheus.yml` に `alerting:` セクションを追加
4. リモートサーバーにディレクトリとファイルを配置（scp）
5. HCP Terraform Workspace `monitoring-lab-local-alertmanager` を作成してローカルモードに設定
6. `terragrunt init` → `terragrunt apply`
7. Prometheus を `/-/reload` でホットリロード（alerting section 反映）
8. 動作確認: TargetDown を意図的に発火させて Slack 通知を確認
