# Feature Specification: 物理機器監視 (Physical Device Monitoring)

**Created**: 2026-02-22
**Status**: Design Complete / Implementation Pending
**Priority**: Medium
**Depends On**: `existing-infrastructure.md` (Baseline), Phase 3 完了

---

## 概要

宅内の物理機器（ルーター、NAS、Linux/Windowsマシン）をPrometheusベースの監視基盤に統合する。
SNMP対応機器はSNMP Exporterコンテナ経由で、汎用マシンはNode Exporter / Windows Exporterで収集する。

**対象機器**:
- Yamaha RTX830（ルーター/スイッチ）
- Synology NAS（1台、Docker非対応モデル）
- Linux マシン群
- Windows マシン群

---

## User Scenarios & Testing

### User Story 1 - ネットワーク機器の監視 (Priority: P1)

**シナリオ**:
インフラ管理者として、RTX830のWAN/LANインターフェーストラフィックとリンク状態をリアルタイムで把握したい。
これにより、回線の輻輳やインターフェース障害を早期に検知できる。

**Independent Test**:
`http://YOUR_SERVER_IP:9090/targets` でSNMPターゲット（RTX830）が `UP` 状態であることを確認。
Grafanaダッシュボードに WAN 通信量グラフが表示されること。

---

### User Story 2 - NAS の監視 (Priority: P1)

**シナリオ**:
インフラ管理者として、SynologyのCPU使用率、メモリ使用量、ディスク空き容量をGrafanaで確認したい。
ディスク逼迫の前兆を事前に把握してデータ消失リスクを低減する。

**Independent Test**:
`http://YOUR_SERVER_IP:9090/targets` でSNMPターゲット（Synology）が `UP` 状態であることを確認。
`hrStorageUsed / hrStorageSize` のメトリクスがPrometheusで取得できていること。

---

### User Story 3 - Linux マシンの監視 (Priority: P2)

**シナリオ**:
インフラ管理者として、宅内のLinuxマシン群のCPU、メモリ、ディスク、ネットワークを一元的に監視したい。

**Independent Test**:
各LinuxマシンのNode Exporterエンドポイント（`:9100/metrics`）にPrometheusからアクセスできること。

---

### User Story 4 - Windows マシンの監視 (Priority: P2)

**シナリオ**:
インフラ管理者として、宅内のWindowsマシン群のリソース状況とサービス状態を把握したい。

**Independent Test**:
各WindowsマシンのWindows Exporterエンドポイント（`:9182/metrics`）にPrometheusからアクセスできること。

---

## アーキテクチャ設計

### 全体像

```
【宅内物理機器】                          【監視基盤 @ YOUR_SERVER_IP】

RTX830 ─────────────────(SNMP)──────────┐
Synology NAS ────────────(SNMP)──────────┼──→ SNMP Exporter :9116 (新規) ──┐
                                          │                                   ├──→ Prometheus ──→ Grafana
Linux マシン群 ──── Node Exporter :9100  ─┤──→ 直接スクレイプ ──────────────┘
                                          │
Windows マシン群 ─ Windows Exporter :9182─┘──→ 直接スクレイプ
```

### コンポーネント一覧

| コンポーネント | 種別 | 管理方法 | 配置先 |
|--------------|------|---------|--------|
| SNMP Exporter | 新規コンテナ | Terragrunt | YOUR_SERVER_IP |
| snmp.yml | 設定ファイル | Gitリポジトリ | `config/snmp/snmp.yml` |
| Node Exporter | バイナリ | 手動インストール | 各Linuxマシン |
| Windows Exporter | MSI | 手動インストール | 各Windowsマシン |
| prometheus.yml | 設定ファイル（更新） | Gitリポジトリ | `config/prometheus/prometheus.yml` |
| Physical Devices ダッシュボード | Grafana JSON | Gitリポジトリ | `config/grafana/provisioning/dashboards/` |

---

## 技術設計

### SNMP Exporter コンテナ（Terragrunt）

**ファイルパス**: `terraform/envs/local/snmp-exporter/terragrunt.hcl`

```hcl
services = {
  snmp-exporter = {
    image         = "prom/snmp-exporter:latest"
    internal_port = 9116
    external_port = 9116
    bind_mounts = [
      {
        source    = "/home/ubuntu/monitoring-lab/snmp/snmp.yml"
        target    = "/etc/snmp_exporter/snmp.yml"
        read_only = true
      }
    ]
  }
}
```

**HCP Terraform Workspace**: `monitoring-lab-local-snmp-exporter`（自動作成）

---

### SNMP 設定ファイル

**ファイルパス**: `config/snmp/snmp.yml`

```yaml
modules:
  # ネットワーク共通: インターフェース統計（RTX830, Synology共通）
  if_mib:
    walk: [ifXTable, ifTable]
    auth:
      community: public
    version: 2

  # Synology専用: システムリソース + ストレージ
  synology:
    walk:
      - hrStorage        # ディスク使用量
      - hrProcessorLoad  # CPU使用率
      - ifXTable         # ネットワーク統計
    auth:
      community: public
    version: 2
```

---

### 各機器の事前設定

#### RTX830 (Yamaha)

RTX830のCLIで以下を投入:

```
snmp community public ro
snmp host YOUR_SERVER_IP community public version 2
save
```

> ⚠️ ファームウェアバージョンによってコマンド構文が異なる場合あり。実施前にヤマハCLIリファレンスで確認すること。

#### Synology DSM

```
コントロールパネル → ターミナルとSNMP → SNMP タブ
  ☑ SNMPサービスを有効にする
  バージョン: SNMPv2c
  コミュニティ: public
```

---

### Node Exporter（Linux マシン）

```bash
# systemdサービスとして導入
# /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target

# UFWファイアウォール許可（監視サーバーのみ許可）
ufw allow from YOUR_SERVER_IP to any port 9100
```

**取得メトリクス**: CPU、メモリ、ディスクI/O、ネットワーク、システムロード

---

### Windows Exporter（Windows マシン）

```powershell
# MSIインストーラーでサービス登録
msiexec /i windows_exporter-<version>-amd64.msi /quiet

# Windowsファイアウォール許可（監視サーバーのみ）
New-NetFirewallRule -DisplayName "Windows Exporter" `
  -Direction Inbound -Protocol TCP -LocalPort 9182 `
  -RemoteAddress YOUR_SERVER_IP -Action Allow
```

**取得メトリクス**: CPU、メモリ、ディスク、ネットワーク、Windowsサービス状態

---

### prometheus.yml 追加内容

```yaml
# SNMP機器（RTX830 + Synology）
- job_name: 'snmp_devices'
  static_configs:
    - targets:
      - <RTX830_IP>    # ← 要確認
      labels:
        device_type: router
        device_name: rtx830
    - targets:
      - <Synology_IP>  # ← 要確認
      labels:
        device_type: nas
        device_name: synology
  metrics_path: /snmp
  params:
    module: [if_mib]
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: snmp-exporter:9116

# Linux マシン群
- job_name: 'node_exporter'
  static_configs:
    - targets:
      - <Linux_Machine_IP>:9100  # ← 各マシンのIPを追加
      labels:
        device_type: physical_server

# Windows マシン群
- job_name: 'windows_exporter'
  static_configs:
    - targets:
      - <Windows_Machine_IP>:9182  # ← 各マシンのIPを追加
      labels:
        device_type: physical_pc
```

---

### Grafana ダッシュボード計画

**新規ファイル**: `config/grafana/provisioning/dashboards/physical-devices.json`

| パネル | メトリクス | 対象 |
|--------|-----------|------|
| WAN通信量（送受信） | `rate(ifHCOutOctets[5m])` / `rate(ifHCInOctets[5m])` | RTX830 |
| インターフェース状態 | `ifOperStatus` | RTX830 |
| NAS CPU使用率 | `hrProcessorLoad` | Synology |
| NAS ディスク使用率 | `hrStorageUsed / hrStorageSize * 100` | Synology |
| Linux CPU使用率 | `rate(node_cpu_seconds_total{mode!="idle"}[5m])` | Linux群 |
| Linux メモリ使用率 | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | Linux群 |
| Linux ディスク使用率 | `(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100` | Linux群 |
| Windows CPU使用率 | `100 - rate(windows_cpu_time_total{mode="idle"}[5m]) * 100` | Windows群 |
| Windows メモリ使用率 | `100 - windows_os_physical_memory_free_bytes / windows_cs_physical_memory_bytes * 100` | Windows群 |

---

## 実装フェーズ計画

### Phase 1: SNMP基盤（RTX830 + Synology）【優先度: 高】

- [ ] Step 1-1: RTX830でSNMP設定コマンド投入
- [ ] Step 1-2: Synology DSMでSNMP有効化
- [ ] Step 1-3: `config/snmp/snmp.yml` 作成
- [ ] Step 1-4: `terraform/envs/local/snmp-exporter/terragrunt.hcl` 作成
- [ ] Step 1-5: `terragrunt init` & `apply`（snmp-exporterデプロイ）
- [ ] Step 1-6: `prometheus.yml` にSNMPジョブ追加
- [ ] Step 1-7: Grafana Physical Devicesダッシュボード作成（SNMP部分）
- [ ] Step 1-8: 疎通確認（Prometheus targets, Grafana表示）

### Phase 2: Linux マシン監視【優先度: 中】

- [ ] Step 2-1: 監視対象IPリストの確定
- [ ] Step 2-2: 各LinuxマシンへNode Exporterインストール
- [ ] Step 2-3: ファイアウォール設定（9100番ポート）
- [ ] Step 2-4: `prometheus.yml` にnode_exporterジョブ追加
- [ ] Step 2-5: Grafanaダッシュボード更新（Linux部分）

### Phase 3: Windows マシン監視【優先度: 中】

- [ ] Step 3-1: 監視対象IPリストの確定
- [ ] Step 3-2: 各WindowsマシンへWindows Exporterインストール
- [ ] Step 3-3: Windowsファイアウォール設定（9182番ポート）
- [ ] Step 3-4: `prometheus.yml` にwindows_exporterジョブ追加
- [ ] Step 3-5: Grafanaダッシュボード更新（Windows部分）

---

## 未確定事項（実装前に確認要）

| 項目 | 状態 | 備考 |
|------|------|------|
| RTX830 の IPアドレス | ❓ 未確定 | — |
| Synology の IPアドレス | ❓ 未確定 | — |
| Linux マシンの台数とIP | ❓ 未確定 | — |
| Windows マシンの台数とIP | ❓ 未確定 | — |
| SNMP コミュニティ名 | ❓ `public` で良いか確認要 | セキュリティ観点では変更推奨 |
| Synology MIBの範囲 | ❓ 標準のみか Synology独自MIBも使うか | 独自MIBはMIBファイル追加が必要 |

---

## 依存関係

```
既存: prometheus (monitoring-lab-local-prometheus)
  └── 新規: snmp-exporter (monitoring-lab-local-snmp-exporter)
        └── 設定: config/snmp/snmp.yml (bind mount)

既存: prometheus.yml
  └── 追加: snmp_devices / node_exporter / windows_exporter ジョブ

既存: grafana
  └── 追加: physical-devices.json ダッシュボード
```

---

## セキュリティ考慮事項

- SNMP v2c は暗号化なし。宅内ネットワーク限定での使用に留める
- コミュニティ名は将来的に Vault に移行することを推奨
- Node Exporter / Windows Exporter は監視サーバー（YOUR_SERVER_IP）からのみアクセス許可
- SNMP Exporter は内部ネットワークのみ（外部ポート公開不要）
