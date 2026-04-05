# Research: SLO + Error Budget 管理基盤 (Sloth)

**Feature**: 013-slo-sloth  
**Date**: 2026-04-05

---

## 決定事項

### 1. Sloth バージョンとインストール方式

**Decision**: Docker イメージ `ghcr.io/slok/sloth:v0.11.0` を使用、常駐コンテナとしてではなくワンショット実行

**Rationale**:
- `v0.11.0` が最新安定版。`latest` タグは破壊的変更リスクがあるため固定（011-tempo での教訓を踏襲）
- 常駐コンテナが不要なため Terragrunt 管理対象に追加しない。Constitution IV (モジュール化・DRY) に準拠
- Docker ベースにすることで WSL2 環境に Go ランタイムのインストール不要

**Alternatives Considered**:
- バイナリ直接インストール: OS依存が生じるため却下
- 常駐 Sloth コンテナ: オーバーエンジニアリング、学習環境では不要

---

### 2. SLI 計測式（`up` メトリクス向け）

**Decision**: Sloth の `raw` SLI タイプを使用し、`1 - avg_over_time(up{...}[window])` を error_ratio_query として定義

**Rationale**:
- `up` は gauge（0/1）であり、`events` タイプ（counter の rate 比率）には適合しない
- `raw` タイプは PromQL 式を直接記述でき、`{{.window}}` テンプレート変数で Sloth が各ウィンドウ（1h/6h/3d/30d）に自動展開する
- `avg_over_time(up[window])` = ウィンドウ内の「up だった割合」（0〜1）→ `1 - ...` でエラー率に変換

**SLI 式例（Prometheus、Grafana）**:
```
error_ratio_query: "1 - avg_over_time(up{job=\"prometheus\"}[{{.window}}])"
```

**Alternatives Considered**:
- `events` タイプ: counter メトリクスに適しているが `up` は gauge のため不可
- `windows` タイプ: より複雑で学習コストが高い

---

### 3. Prometheus ルールファイルの配置と反映方法

**Decision**: Sloth が生成したルールを `config/prometheus/slo-rules.yml` に出力、`prometheus.yml` の `rule_files` に追記、`sync-config.sh` でリモート反映後に `curl /-/reload` でホットリロード

**Rationale**:
- 既存の `alerts.yml` と並列配置する確立済みパターンを踏襲
- `prometheus.yml` の `rule_files` に1行追記するだけで対応可能
- `sync-config.sh prometheus` が既に `curl /-/reload` を実行するため、追加スクリプト不要

**反映フロー**:
```
task slo:generate
  → Sloth コンテナ実行
  → config/prometheus/slo-rules.yml 生成
  → task sync:prometheus
  → scp 転送 + /metrics reload
  → Prometheus がルール認識（約15秒）
```

---

### 4. Grafana ダッシュボード

**Decision**: Sloth 公式の Grafana ダッシュボード（Grafana.com ID: 14348 相当の JSON）を `config/grafana/provisioning/dashboards/sloth-overview.json` として配置

**Rationale**:
- Sloth が生成する Recording Rules のメトリクス名（`slo:sli_error:ratio_rate_*` 等）に完全対応
- 既存の `dashboards.yml` プロビジョニング設定がディレクトリ内の全 JSON を自動読み込み
- カスタムダッシュボード作成より確実かつ高速

**Sloth 生成ルールの主要メトリクス**:
| メトリクス名 | 内容 |
|---|---|
| `slo:sli_error:ratio_rate{sloth_window}` | 各ウィンドウのエラー率 |
| `slo:error_budget:ratio` | Error Budget 残量（0〜1） |
| `slo:time_period:days` | SLO 計算期間（30日） |
| `slo:objective:ratio` | SLO 目標値（例: 0.995） |

---

### 5. Taskfile タスク設計

**Decision**: `slo:generate`（ルール生成）と `slo:validate`（ルール検証）の2タスクを追加

**Rationale**:
- 既存の `sync:prometheus` タスクのパターン（WSL2経由 Docker 実行）に統一
- 生成と検証を分離することで「生成後 → 検証 → sync」のワークフローが明確になる

**タスク定義**:
```yaml
slo:generate:
  desc: "Sloth で SLO YAML から Prometheus ルールを生成"
  cmds:
    - wsl -d Ubuntu-24.04 -e bash -c "docker run --rm
        -v /mnt/e/work/labo/config/sloth:/input:ro
        -v /mnt/e/work/labo/config/prometheus:/output
        ghcr.io/slok/sloth:v0.11.0 generate
        -i /input/monitoring-lab.yml
        -o /output/slo-rules.yml"

slo:validate:
  desc: "生成された slo-rules.yml を promtool で検証"
  cmds:
    - wsl -d Ubuntu-24.04 -e bash -c "docker run --rm
        -v /mnt/e/work/labo/config/prometheus:/etc/prometheus:ro
        prom/prometheus:latest
        promtool check rules /etc/prometheus/slo-rules.yml"
```

---

## 未解決事項

なし。全 NEEDS CLARIFICATION は clarify フェーズで解消済み。
