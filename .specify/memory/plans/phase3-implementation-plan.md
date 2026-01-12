# Implementation Plan: Phase 3 - 監視機能拡充

**Branch**: `feature/phase3-monitoring-enhancement`
**Date**: 2026-01-01
**Spec**: [phase3-monitoring-enhancement.md](../specs/phase3-monitoring-enhancement.md)
**Status**: Ready for Implementation

---

## Summary

Phase 2で構築した監視基盤上に、実用的な監視機能を追加する。Prometheusでコンテナメトリクスを収集し、Grafanaで可視化、基本的なアラートルールを実装する。すべての変更はInfrastructure as Code (IaC)原則に従い、Terraform/Terragruntで管理する。

**主要な実装内容**:
1. Prometheusスクレイプ設定の拡充（cAdvisorまたはDocker Metrics API）
2. Grafanaダッシュボードの作成とプロビジョニング
3. Prometheusアラートルールの定義
4. （オプション）Zabbix統合ダッシュボード

---

## Technical Context

**Language/Version**:
- HCL (Terraform 1.x, Terragrunt 0.x)
- YAML (Prometheus/Grafana設定ファイル)
- JSON (Grafanaダッシュボード定義)

**Primary Dependencies**:
- Docker Engine (リモートホスト 10.0.0.220)
- Prometheus (prom/prometheus:latest)
- Grafana (grafana/grafana:latest)
- cAdvisor (gcr.io/cadvisor/cadvisor:latest) ← **新規導入**

**Storage**:
- Prometheus TSDB (30日保持)
- Grafana SQLite (ダッシュボード/設定)
- HCP Terraform (State管理)

**Testing**:
- Prometheus `/targets` エンドポイント確認
- Grafana UI動作確認
- Terragrunt plan/apply検証

**Target Platform**:
- リモートDockerホスト (Ubuntu, x86_64)
- WSL2 (Ubuntu) - 開発環境

**Performance Goals**:
- Prometheusスクレイプ間隔: 15秒
- Grafanaダッシュボード応答: <3秒
- スクレイプ成功率: >95%

**Constraints**:
- リモートホストのリソース制限内で動作
- 既存コンテナへの影響最小化
- Git管理必須（すべての設定ファイル）

**Scale/Scope**:
- 監視対象コンテナ: 8台 + cAdvisor
- Grafanaダッシュボード: 1-2個
- アラートルール: 3個

---

## Constitution Check

**GATE: Phase 3実装開始前の必須確認事項**

### ✅ I. Infrastructure as Code (IaC) - NON-NEGOTIABLE

- [x] すべての変更はTerraform/Terragruntで管理
- [x] 手動変更禁止（cAdvisor追加もterragrunt.hclで定義）
- [x] Git管理（設定ファイル、ダッシュボードJSON）
- [x] `terragrunt plan`で差分確認後に`apply`

**検証**: Phase 3完了時に`terragrunt plan`で全Workspaceが差分なしであること

### ✅ II. セキュリティファースト（段階的アプローチ）

- [x] Phase 3はセキュリティ強化「前」のフェーズ
- [x] 平文パスワード許容（Grafana admin:admin）
- [x] HTTP通信許容（HTTPS未設定）
- [ ] 将来対応（Phase 4-5）: Vault統合、TLS/SSL

**検証**: `.env`ファイルがGitに含まれていないこと（`.gitignore`確認）

### ✅ III. ドキュメント駆動開発

- [x] 仕様作成済み（`phase3-monitoring-enhancement.md`）
- [x] この実装計画を`.specify/memory/plans/`に配置
- [ ] 実装後、`SESSION_STATE.md`を更新
- [ ] 実装後、`CLAUDE.md`のPhase 3セクションを更新

**検証**: ドキュメントが最新の実装状態を反映していること

### ✅ IV. モジュール化とDRY原則

- [x] cAdvisorは既存の`docker_container`モジュールを再利用
- [x] Prometheus/Grafana設定は既存のterragrunt.hclを修正
- [x] 設定ファイルは`config/`ディレクトリに集約
- [x] 依存関係は`dependency`ブロックで明示

**検証**: 新規モジュール作成なし、既存モジュールの再利用

### ✅ V. 監視の可観測性（Self-Monitoring）

- [x] Prometheusで全コンテナ（8台 + cAdvisor）を監視
- [x] Grafanaでリアルタイム可視化
- [x] アラートルールで異常検知
- [x] メトリクス永続化（Prometheus 30日保持）

**検証**: Prometheus `/targets`で9個すべてが"UP"状態

---

## Project Structure

### Documentation (this feature)

```
.specify/memory/
├── specs/
│   └── phase3-monitoring-enhancement.md  # 仕様書（作成済み）
├── plans/
│   └── phase3-implementation-plan.md     # この実装計画
└── tasks/
    └── phase3-tasks.md                   # 次ステップで作成
```

### Source Code (repository root)

```
monitoring-lab-terraform/
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml               # 【更新】スクレイプ設定追加
│   │   └── alerts.yml                   # 【新規】アラートルール定義
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── datasources.yml      # 【既存】データソース設定
│           └── dashboards/
│               ├── dashboards.yml       # 【新規】ダッシュボードプロビジョニング設定
│               └── monitoring-lab-overview.json  # 【新規】ダッシュボード定義
│
├── terraform/
│   └── envs/local/
│       ├── cadvisor/                    # 【新規】cAdvisorサービス定義
│       │   └── terragrunt.hcl
│       ├── prometheus/
│       │   └── terragrunt.hcl          # 【更新】アラートルールマウント追加
│       └── grafana/
│           └── terragrunt.hcl          # 【更新】ダッシュボードマウント追加
│
└── .specify/memory/
    ├── specs/                           # 仕様書
    ├── plans/                           # この実装計画
    └── tasks/                           # タスク分解（次ステップ）
```

---

## Phase 0: Research - 既存リソースの現状分析

### 0.1 Prometheusの現状

**現在の設定** (`config/prometheus/prometheus.yml`):
- ✅ グローバル設定: スクレイプ間隔15秒
- ✅ Job 1: Prometheus自身の監視 (localhost:9090)
- ❌ コンテナメトリクス収集: **未設定**（コメントアウト状態）

**現在のボリュームマウント** (`terraform/envs/local/prometheus/terragrunt.hcl`):
- ✅ `prometheus_data` → `/prometheus` (時系列DB)
- ✅ `prometheus.yml` → `/etc/prometheus/prometheus.yml` (Bind Mount)
- ❌ アラートルール: **未マウント**

**必要な変更**:
1. cAdvisorサービスの追加（コンテナメトリクス収集用）
2. `prometheus.yml`にcAdvisorスクレイプジョブを追加
3. `alerts.yml`を作成し、Bind Mountに追加
4. `prometheus.yml`の`rule_files`セクションを有効化

---

### 0.2 Grafanaの現状

**現在の設定** (`terraform/envs/local/grafana/terragrunt.hcl`):
- ✅ データソース: Prometheusプロビジョニング済み (`datasources.yml`)
- ✅ Zabbixプラグインインストール済み
- ❌ ダッシュボード: **未設定**（プロビジョニングなし）

**現在のボリュームマウント**:
- ✅ `grafana_data` → `/var/lib/grafana`
- ✅ `provisioning/` → `/etc/grafana/provisioning` (Bind Mount)

**必要な変更**:
1. `config/grafana/provisioning/dashboards/dashboards.yml`を作成
2. ダッシュボードJSON (`monitoring-lab-overview.json`) を作成
3. リモートホストの`/home/ubuntu/monitoring-lab/grafana/provisioning/dashboards/`にファイルを配置

---

### 0.3 cAdvisor導入の調査

**cAdvisorとは**:
- Google製のコンテナメトリクス収集ツール
- Dockerコンテナの詳細なリソース使用状況を収集
- Prometheusフォーマットでメトリクスを公開 (`:8080/metrics`)

**導入方法**:
1. 新規Terragruntサービス定義: `terraform/envs/local/cadvisor/terragrunt.hcl`
2. HCP Workspace: `monitoring-lab-local-cadvisor`
3. Docker特権モード: `/var/run/docker.sock`のマウントが必要

**cAdvisor vs Docker Metrics API**:
| 項目 | cAdvisor | Docker Metrics API |
|------|----------|-------------------|
| 導入の容易さ | Terragruntで新規コンテナ追加 | Docker Daemonの設定変更が必要 |
| メトリクスの詳細度 | 詳細（ファイルシステム、ネットワーク等） | 基本的なメトリクス |
| リソース使用量 | 追加コンテナ1台 | なし（Docker内蔵） |
| 推奨 | ✅ **採用** | 次善策 |

**決定**: cAdvisorを採用（IaC原則に最も適合）

---

## Phase 1: Data Model & Design

### 1.1 cAdvisor Service Definition

**File**: `terraform/envs/local/cadvisor/terragrunt.hcl`

**設計**:
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/docker_container"
}

dependency "network" {
  config_path = "../network"
}

inputs = {
  network_name = dependency.network.outputs.network_name

  # ボリュームなし（一時データのみ）
  volumes = []

  services = {
    cadvisor = {
      image = "gcr.io/cadvisor/cadvisor:latest"
      internal_port = 8080
      external_port = 8080  # Prometheus用

      command = []
      env = []
      volumes = []

      # 特権モード設定（Docker APIアクセス用）
      bind_mounts = [
        {
          source    = "/var/run/docker.sock"
          target    = "/var/run/docker.sock"
          read_only = true
        },
        {
          source    = "/sys"
          target    = "/sys"
          read_only = true
        },
        {
          source    = "/var/lib/docker"
          target    = "/var/lib/docker"
          read_only = true
        }
      ]

      # 特権モードフラグ（モジュールが対応している場合）
      # privileged = true
    }
  }
}
```

**注意**: `docker_container`モジュールが特権モード (`privileged`) をサポートしているか確認が必要。未対応の場合はモジュール拡張が必要。

---

### 1.2 Prometheus Scrape Configuration

**File**: `config/prometheus/prometheus.yml`

**追加するscrape_configs**:
```yaml
scrape_configs:
  # 既存: Prometheus自身の監視
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          service: 'prometheus'
          tier: 'monitoring'

  # 【新規追加】Job 2: cAdvisor（Dockerコンテナメトリクス）
  - job_name: 'cadvisor'
    scrape_interval: 15s
    static_configs:
      - targets: ['cadvisor:8080']
        labels:
          service: 'cadvisor'
          tier: 'infrastructure'

    # コンテナ名をラベルとして抽出
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'monitoring-lab'
```

**収集されるメトリクス例**:
- `container_cpu_usage_seconds_total{name="monitoring-lab-prometheus"}`
- `container_memory_usage_bytes{name="monitoring-lab-grafana"}`
- `container_network_receive_bytes_total{name="monitoring-lab-zbx_server"}`

---

### 1.3 Prometheus Alert Rules

**File**: `config/prometheus/alerts.yml` (新規作成)

**アラートルール定義**:
```yaml
groups:
  - name: container_alerts
    interval: 30s
    rules:
      # Rule 1: コンテナダウン検知
      - alert: ContainerDown
        expr: up{job="cadvisor"} == 0
        for: 1m
        labels:
          severity: critical
          tier: infrastructure
        annotations:
          summary: "cAdvisor is down"
          description: "cAdvisor at {{ $labels.instance }} has been down for more than 1 minute."

      # Rule 2: コンテナCPU使用率高
      - alert: HighContainerCPU
        expr: |
          rate(container_cpu_usage_seconds_total{name!=""}[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
          tier: infrastructure
        annotations:
          summary: "High CPU usage in container {{ $labels.name }}"
          description: "Container {{ $labels.name }} CPU usage is above 80% (current value: {{ $value }})"

      # Rule 3: コンテナメモリ使用率高
      - alert: HighContainerMemory
        expr: |
          (container_memory_usage_bytes{name!=""} / container_spec_memory_limit_bytes{name!=""}) > 0.9
        for: 5m
        labels:
          severity: warning
          tier: infrastructure
        annotations:
          summary: "High memory usage in container {{ $labels.name }}"
          description: "Container {{ $labels.name }} memory usage is above 90% (current value: {{ $value }})"
```

**`prometheus.yml`の`rule_files`セクション**:
```yaml
rule_files:
  - '/etc/prometheus/alerts.yml'
```

---

### 1.4 Grafana Dashboard Design

**File**: `config/grafana/provisioning/dashboards/monitoring-lab-overview.json`

**ダッシュボード構成**:

#### Row 1: Overview
- **Panel 1**: Container Status (Stat Panel)
  - クエリ: `count(up{job="cadvisor"} == 1)` (稼働中コンテナ数)
  - 表示: 大きな数字

#### Row 2: CPU & Memory
- **Panel 2**: CPU Usage by Container (Graph)
  - クエリ: `rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100`
  - 表示: 時系列グラフ（コンテナ別に色分け）

- **Panel 3**: Memory Usage by Container (Graph)
  - クエリ: `container_memory_usage_bytes{name!=""} / 1024 / 1024`
  - 単位: MiB
  - 表示: 時系列グラフ

#### Row 3: Network I/O
- **Panel 4**: Network Receive (Graph)
  - クエリ: `rate(container_network_receive_bytes_total{name!=""}[5m])`
  - 単位: Bytes/sec

- **Panel 5**: Network Transmit (Graph)
  - クエリ: `rate(container_network_transmit_bytes_total{name!=""}[5m])`
  - 単位: Bytes/sec

#### Row 4: Disk I/O
- **Panel 6**: Disk Read (Graph)
  - クエリ: `rate(container_fs_reads_bytes_total{name!=""}[5m])`

- **Panel 7**: Disk Write (Graph)
  - クエリ: `rate(container_fs_writes_bytes_total{name!=""}[5m])`

**ダッシュボード変数**:
- `$container`: コンテナ名の選択肢（クエリから取得）
- `$interval`: 時間範囲（5m, 15m, 1h, 6h, 1d）

---

### 1.5 Grafana Dashboard Provisioning

**File**: `config/grafana/provisioning/dashboards/dashboards.yml` (新規作成)

```yaml
apiVersion: 1

providers:
  - name: 'Monitoring Lab Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
      foldersFromFilesStructure: false
```

**Grafana terragrunt.hcl更新**:
```hcl
bind_mounts = [
  {
    source    = "/home/ubuntu/monitoring-lab/grafana/provisioning"
    target    = "/etc/grafana/provisioning"
    read_only = true
  },
  # 【新規追加】ダッシュボードJSON
  {
    source    = "/home/ubuntu/monitoring-lab/grafana/provisioning/dashboards"
    target    = "/etc/grafana/provisioning/dashboards"
    read_only = true
  }
]
```

**注意**: Bind Mountは既に`provisioning/`全体をマウントしているため、サブディレクトリ`dashboards/`も自動的に含まれる。追加マウント不要。

---

## Phase 2: Implementation Contracts

### Contract 1: cAdvisorサービス

**責務**: Dockerコンテナのリソースメトリクスを収集し、Prometheusに公開

**入力**: なし（Docker Engineから自動収集）

**出力**:
- Prometheusメトリクス (`http://cadvisor:8080/metrics`)
- コンテナ別のCPU、メモリ、ネットワーク、ディスクメトリクス

**制約**:
- Docker APIへのアクセスが必要（`/var/run/docker.sock`マウント）
- リモートホスト上で実行

**テスト**:
```bash
# cAdvisor稼働確認
curl http://10.0.0.220:8080/metrics | grep container_cpu

# Prometheusからスクレイプ確認
curl http://10.0.0.220:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="cadvisor")'
```

---

### Contract 2: Prometheusスクレイプ

**責務**: cAdvisorからメトリクスを15秒間隔で収集し、30日間保持

**入力**: cAdvisor メトリクスエンドポイント (`http://cadvisor:8080/metrics`)

**出力**:
- 時系列データベース (`/prometheus`)
- PromQL API (`http://prometheus:9090/api/v1/query`)

**制約**:
- スクレイプ失敗率 <5%
- ストレージ容量: 30日保持で約XX GB（要計算）

**テスト**:
```bash
# ターゲット確認
curl http://10.0.0.220:9090/api/v1/targets

# メトリクス取得確認
curl http://10.0.0.220:9090/api/v1/query?query=container_memory_usage_bytes
```

---

### Contract 3: Prometheusアラート

**責務**: 定義されたルールに基づいてアラートを発火・解決

**入力**: 時系列メトリクスデータ

**出力**:
- アラート状態 (`http://prometheus:9090/alerts`)
- Alertmanager連携（Phase 4で実装）

**制約**:
- ルール評価間隔: 30秒
- アラート発火条件: 継続時間（1分または5分）

**テスト**:
```bash
# アラートルール確認
curl http://10.0.0.220:9090/api/v1/rules

# 手動でコンテナ停止してアラート発火テスト
ssh ubuntu@10.0.0.220 "docker stop monitoring-lab-vault"
# 1分後にアラート確認
curl http://10.0.0.220:9090/api/v1/alerts
```

---

### Contract 4: Grafanaダッシュボード

**責務**: Prometheusメトリクスを可視化し、リアルタイムでダッシュボード表示

**入力**: Prometheusデータソース (`http://prometheus:9090`)

**出力**:
- Web UI (`http://10.0.0.220:3000/d/monitoring-lab-overview`)
- 7つのパネル（概要、CPU、メモリ、ネットワーク、ディスク）

**制約**:
- ダッシュボード応答時間 <3秒
- 自動リフレッシュ間隔: 5秒

**テスト**:
```bash
# ダッシュボード存在確認
curl -u admin:admin http://10.0.0.220:3000/api/dashboards/uid/monitoring-lab-overview

# データソース接続確認
curl -u admin:admin http://10.0.0.220:3000/api/datasources
```

---

## Deployment Strategy

### リスク分析

| リスク | 確率 | 影響 | 緩和策 |
|-------|------|------|--------|
| cAdvisor起動失敗（特権モード問題） | Medium | High | モジュール拡張、または手動docker run確認 |
| Prometheusスクレイプ失敗 | Low | Medium | ターゲット設定確認、ネットワーク疎通テスト |
| Grafanaダッシュボード表示エラー | Low | Low | プロビジョニング設定確認、ログ確認 |
| ストレージ容量不足 | Low | Medium | 保持期間30日で計算、ディスク使用量監視 |

---

### デプロイ順序

#### ステップ1: cAdvisor追加

1. `terraform/envs/local/cadvisor/terragrunt.hcl`作成
2. `docker_container`モジュールの特権モード対応確認
3. HCP Terraform Workspace作成（自動）
4. `terragrunt init && terragrunt plan`
5. `terragrunt apply`
6. cAdvisor稼働確認: `curl http://10.0.0.220:8080/metrics`

#### ステップ2: Prometheusスクレイプ設定

1. `config/prometheus/prometheus.yml`更新（cAdvisorジョブ追加）
2. リモートホストにファイルアップロード:
   ```bash
   scp config/prometheus/prometheus.yml ubuntu@10.0.0.220:~/monitoring-lab/prometheus/
   ```
3. Prometheus設定リロード:
   ```bash
   curl -X POST http://10.0.0.220:9090/-/reload
   ```
4. ターゲット確認: `http://10.0.0.220:9090/targets`

#### ステップ3: Prometheusアラートルール

1. `config/prometheus/alerts.yml`作成
2. `config/prometheus/prometheus.yml`の`rule_files`セクション有効化
3. リモートホストにファイルアップロード:
   ```bash
   scp config/prometheus/alerts.yml ubuntu@10.0.0.220:~/monitoring-lab/prometheus/
   ```
4. `terraform/envs/local/prometheus/terragrunt.hcl`更新（Bind Mount追加）
5. `terragrunt plan && terragrunt apply` (Prometheusコンテナ再作成)
6. アラート確認: `http://10.0.0.220:9090/alerts`

#### ステップ4: Grafanaダッシュボード

1. Grafana UIで手動作成 (`http://10.0.0.220:3000`)
2. JSONエクスポート
3. `config/grafana/provisioning/dashboards/monitoring-lab-overview.json`として保存
4. `config/grafana/provisioning/dashboards/dashboards.yml`作成
5. リモートホストにファイルアップロード:
   ```bash
   scp -r config/grafana/provisioning/dashboards/ ubuntu@10.0.0.220:~/monitoring-lab/grafana/provisioning/
   ```
6. Grafana再起動:
   ```bash
   ssh ubuntu@10.0.0.220 "docker restart monitoring-lab-grafana"
   ```
7. ダッシュボード確認: `http://10.0.0.220:3000/d/monitoring-lab-overview`

#### ステップ5: 全体検証

1. すべてのターゲットが"UP"状態: `http://10.0.0.220:9090/targets`
2. アラートルールが読み込まれている: `http://10.0.0.220:9090/rules`
3. Grafanaダッシュボードが表示される: `http://10.0.0.220:3000`
4. `terragrunt plan`で全Workspace差分なし
5. `git status`で未コミットファイルなし

---

## Rollback Plan

### 問題が発生した場合の巻き戻し手順

#### シナリオ1: cAdvisor起動失敗

```bash
# cAdvisorサービスを削除
cd terraform/envs/local/cadvisor
terragrunt destroy -auto-approve

# HCP Workspace削除（オプション）
# Webコンソールまたは Terraform Cloud API
```

#### シナリオ2: Prometheus設定エラー

```bash
# 旧設定に戻す
git checkout HEAD~1 config/prometheus/prometheus.yml
scp config/prometheus/prometheus.yml ubuntu@10.0.0.220:~/monitoring-lab/prometheus/

# Prometheus再起動
ssh ubuntu@10.0.0.220 "docker restart monitoring-lab-prometheus"
```

#### シナリオ3: Grafana表示エラー

```bash
# ダッシュボード削除（UI経由）
# または、プロビジョニングファイル削除
ssh ubuntu@10.0.0.220 "rm -rf ~/monitoring-lab/grafana/provisioning/dashboards/*"
ssh ubuntu@10.0.0.220 "docker restart monitoring-lab-grafana"
```

---

## Success Criteria (検証チェックリスト)

### Phase 3完了基準

- [ ] **SC-001**: Prometheusが9つのターゲットからメトリクス収集
  - `curl http://10.0.0.220:9090/api/v1/targets | jq '.data.activeTargets | length'` → `2` (prometheus + cadvisor)

- [ ] **SC-002**: Grafanaダッシュボードが3秒以内に表示
  - ブラウザで `http://10.0.0.220:3000/d/monitoring-lab-overview` アクセス
  - DevTools → Network → DOMContentLoaded <3秒

- [ ] **SC-003**: アラートルールが正常動作
  - Vaultコンテナを停止 → 1分後にアラート発火確認
  - Vaultコンテナを再起動 → アラート解決確認

- [ ] **SC-004**: すべての設定ファイルがGit管理
  - `git status` → "nothing to commit, working tree clean"

- [ ] **SC-005**: Terraform/Terragruntで差分なし
  - 全Workspace（9個）で `terragrunt plan` → "No changes"

- [ ] **SC-006**: ドキュメント更新
  - `SESSION_STATE.md` → Phase 3完了を記録
  - `CLAUDE.md` → Phase 3セクション更新（オプション）

---

## Known Issues & Workarounds

### Issue 1: docker_containerモジュールが特権モードをサポートしていない

**症状**: cAdvisorがDocker APIにアクセスできず起動失敗

**回避策**:
1. `terraform/modules/docker_container/main.tf`を確認
2. `privileged`パラメータが未対応の場合、モジュールに追加:
   ```hcl
   resource "docker_container" "service" {
     # 既存設定...

     privileged = lookup(each.value, "privileged", false)
   }
   ```
3. またはcAdvisorを一時的に手動で起動し、次のPhaseでモジュール拡張

### Issue 2: Prometheusの`--web.enable-lifecycle`が必要

**症状**: 設定リロードAPI (`/-/reload`) が404エラー

**解決策**:
- `terraform/envs/local/prometheus/terragrunt.hcl`のcommandに既に含まれている
- Prometheusコンテナ再作成で解決: `terragrunt apply`

### Issue 3: Grafanaダッシュボードが即座に反映されない

**症状**: プロビジョニングファイルを配置してもダッシュボードが表示されない

**解決策**:
- Grafana再起動: `docker restart monitoring-lab-grafana`
- `updateIntervalSeconds: 10`で最大10秒待機
- Grafanaログ確認: `docker logs monitoring-lab-grafana`

---

## Next Steps After Implementation

### Phase 3完了後のタスク

1. **タスク作成**: `/speckit.tasks` でPhase 3を具体的なタスクに分解
2. **実装実行**: `/speckit.implement` で各タスクを順次実装
3. **検証**: Success Criteriaの全項目をチェック
4. **ドキュメント更新**: `SESSION_STATE.md`にPhase 3完了を記録
5. **Gitコミット**: 全変更をコミット・プッシュ
6. **Phase 4検討**: 運用改善（Alertmanager、GitHub Actions）へ進むか判断

---

## Appendices

### A. Prometheus PromQL Examples

```promql
# コンテナCPU使用率（%）
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# コンテナメモリ使用量（MiB）
container_memory_usage_bytes{name!=""} / 1024 / 1024

# ネットワーク受信速度（Bytes/sec）
rate(container_network_receive_bytes_total{name!=""}[5m])

# 特定コンテナのCPU使用率
rate(container_cpu_usage_seconds_total{name="monitoring-lab-prometheus"}[5m]) * 100
```

### B. Useful Commands

```bash
# Prometheusターゲット確認
curl http://10.0.0.220:9090/api/v1/targets | jq

# アラート確認
curl http://10.0.0.220:9090/api/v1/alerts | jq

# Grafanaダッシュボード一覧
curl -u admin:admin http://10.0.0.220:3000/api/search | jq

# cAdvisorメトリクス確認
curl http://10.0.0.220:8080/metrics | grep container_cpu

# リモートホストのファイル確認
ssh ubuntu@10.0.0.220 "ls -la ~/monitoring-lab/prometheus/"
ssh ubuntu@10.0.0.220 "cat ~/monitoring-lab/prometheus/prometheus.yml"
```

### C. References

- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [cAdvisor Documentation](https://github.com/google/cadvisor)
- [Grafana Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

**Plan Version**: 1.0.0
**Created**: 2026-01-01
**Ready for**: `/speckit.tasks` (タスク分解)
**Constitutional Compliance**: ✅ All principles verified
