# MCP Servers - 使い方ガイド

Claude Code から監視基盤を直接操作するための MCP (Model Context Protocol) Server 群です。

---

## 概要

3つの MCP Server が連携して「観測 → AI分析 → 提案 → 承認 → 適用」のループを実現します。

```
Claude Code
  ├── prometheus-server  メトリクス取得・アラート確認・改善提案生成
  ├── docker-server      コンテナ操作・ログ取得・リソース確認
  └── terragrunt-server  設定確認・承認フロー管理・インフラ変更適用
```

### 自己成長ループ

```
Prometheus/Zabbix
      ↓ (観測)
prometheus-server: get_active_alerts / query_metrics
      ↓ (AI分析)
prometheus-server: generate_proposal  → .mcp-data/proposals/ に保存
      ↓ (人間の承認)
terragrunt-server: create_approval    → .mcp-data/approvals/ に保存
      ↓ (適用)
terragrunt-server: apply_service      → terragrunt apply 実行
      ↓ (効果測定)
prometheus-server: compare_metrics   → 変更前後の比較
```

---

## セットアップ

### 前提条件

- WSL2 (Ubuntu-24.04) 上の Docker Engine が起動していること
- `~/.ssh/id_rsa` が WSL2 のホームディレクトリに存在すること（リモートサーバー 10.0.0.220 への接続用）
- `.mcp-data/` ディレクトリが自動作成される

### Dockerイメージのビルド

```bash
# WSL2 上で実行
cd /mnt/e/work/labo

docker build -t monitoring-lab-prometheus-mcp  mcp/prometheus-server/
docker build -t monitoring-lab-docker-mcp      mcp/docker-server/
docker build -t monitoring-lab-terragrunt-mcp  mcp/terragrunt-server/
```

### Claude Code への登録

`.mcp.json` はリポジトリルートに存在します。Claude Code を起動すると自動的に読み込まれます。

```json
{
  "mcpServers": {
    "docker":      { ... },
    "prometheus":  { ... },
    "terragrunt":  { ... }
  }
}
```

> **注意**: `docker` サーバーと `terragrunt` サーバーは SSH 鍵のバインドマウントが必要です。
> WSL2 のパス `/home/ubuntu/.ssh/id_rsa` が存在することを確認してください。

---

## Prometheus MCP Server

**イメージ**: `monitoring-lab-prometheus-mcp`
**接続先**: `http://10.0.0.220:9090`（環境変数 `PROMETHEUS_URL` で変更可）

### ツール一覧

| ツール | 説明 |
|--------|------|
| `query_metrics` | PromQL インスタントクエリ |
| `query_range` | PromQL 範囲クエリ（トレンド分析） |
| `get_active_alerts` | 発火中のアラート一覧 |
| `compare_metrics` | 変更前後のメトリクス比較 |
| `generate_proposal` | インフラ状態の分析と改善提案の生成・保存 |
| `list_proposals` | 保存済み提案の一覧表示 |

### 使い方

**現在のアラートを確認する**
```
get_active_alerts: { severity: "all" }
```

**コンテナのメモリ使用量を確認する**
```
query_metrics: { query: "container_memory_usage_bytes{id=~'/system.slice/docker-.+\\.scope'}" }
```

**過去1時間のCPUトレンドを確認する**
```
query_range: { query: "rate(container_cpu_usage_seconds_total[5m])", start: "now-1h", step: "5m" }
```

**改善提案を生成する**
```
generate_proposal: {}
```
- 発火中のアラートを分析し、緊急度（🔴高 / 🟡中 / 🟢低）を判定
- 同一アラートに対する `pending` 提案が既にある場合はスキップ（重複防止）
- アラートが解消された提案は自動で `applied` に更新

**提案一覧を確認する**
```
list_proposals: { status: "pending" }  # pending / applied / rejected / all
```

---

## Docker MCP Server

**イメージ**: `monitoring-lab-docker-mcp`
**接続先**: `ssh://ubuntu@10.0.0.220`（Docker over SSH）

### ツール一覧

| ツール | 説明 |
|--------|------|
| `docker_list_containers` | コンテナ一覧（全状態） |
| `docker_get_stats` | `monitoring-lab-` コンテナのCPU/メモリ使用量 |
| `docker_get_logs` | 指定コンテナのログ取得 |
| `docker_restart_container` | コンテナの再起動（`confirmed: true` 必須） |
| `docker_stop_container` | コンテナの停止（`confirmed: true` 必須） |
| `docker_start_container` | コンテナの起動（`confirmed: true` 必須） |

### 使い方

**全コンテナのリソース状況を確認する**
```
docker_get_stats: {}
```
`monitoring-lab-` プレフィックスのコンテナのみ表示されます。

**直近1時間のPrometheusログを確認する**
```
docker_get_logs: { container_name: "prometheus", lines: 100, since: "1h" }
```
`since` には `"30m"`, `"2h"`, `"2026-03-08T00:00:00"` などが使えます。

**コンテナを再起動する**
```
docker_restart_container: { container_name: "monitoring-lab-grafana", confirmed: true }
```
`confirmed: true` を明示しないと実行されません。

---

## Terragrunt MCP Server

**イメージ**: `monitoring-lab-terragrunt-mcp`
**接続先**: SSH 経由でリモートの `monitoring-lab-terragrunt` コンテナを操作

### ツール一覧

| ツール | 説明 |
|--------|------|
| `plan_service` | terragrunt plan の実行（読み取り専用） |
| `get_service_config` | サービスの terragrunt.hcl を読み取る |
| `list_workspaces` | HCP Terraform Workspace 一覧 |
| `create_approval` | 提案への承認ログを作成（apply の前提条件） |
| `apply_service` | terragrunt apply の実行（`approval_id` 必須） |
| `rollback_service` | スナップショットからロールバック（`confirmed: true` 必須） |

### 使い方

**Grafana の現在の設定を確認する**
```
get_service_config: { service: "grafana" }
```

**変更前に差分を確認する**
```
plan_service: { service: "prometheus" }
```

**承認ログを作成する**
```
create_approval: {
  proposal_id: "1f24c090-...",
  decision: "approved",
  decided_by: "operator"
}
```
`decision: "rejected"` で却下することもできます。

**承認済みの変更を適用する**
```
apply_service: {
  service: "prometheus",
  approval_id: "取得したapproval_id"
}
```

**問題が起きたときにロールバックする**
```
rollback_service: {
  approval_id: "apply時のapproval_id",
  confirmed: true
}
```

### 対応サービス一覧

`network` / `postgres` / `vault` / `prometheus` / `grafana` /
`zabbix` / `zabbix-agent` / `cadvisor` / `snmp-exporter` / `newrelic`

---

## 典型的なワークフロー

### アラートを確認して対処する

```
1. prometheus: get_active_alerts        → 発火中のアラートを確認
2. docker: docker_get_stats             → リソース使用量を確認
3. docker: docker_get_logs              → 問題のあるコンテナのログを確認
4. docker: docker_restart_container     → 必要であれば再起動
5. prometheus: get_active_alerts        → アラートが解消したか確認
```

### インフラ設定を変更する

```
1. prometheus: generate_proposal        → 改善提案を生成
2. terragrunt: get_service_config       → 現在の設定を確認
3. terragrunt: plan_service             → 変更差分を確認
4. terragrunt: create_approval          → 承認ログを作成（decision: "approved"）
5. terragrunt: apply_service            → 変更を適用
6. prometheus: compare_metrics          → 変更効果を測定
```

---

## データ保存先

| パス | 内容 |
|------|------|
| `.mcp-data/proposals/` | 改善提案ファイル（JSON） |
| `.mcp-data/proposals/index.json` | 提案インデックス |
| `.mcp-data/approvals/` | 承認ログファイル（JSON） |
| `.mcp-data/reports/` | 効果測定レポート（JSON） |

`.mcp-data/` は `.gitignore` に追加済みのため、提案・承認ログはリポジトリに含まれません。
