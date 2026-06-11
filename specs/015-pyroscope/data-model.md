# Data Model: Pyroscope 継続的プロファイリング基盤

**Feature**: 015-pyroscope
**Date**: 2026-05-07（バックフィル: 2026-06-08）

> **注**: 実装・デプロイ完了後のバックフィル書類。稼働中の実装実態を反映する。

---

## サービス構成エンティティ

### Pyroscope コンテナ（`terraform/envs/local/pyroscope/terragrunt.hcl`）

```
PyroscopeService
├── image: "grafana/pyroscope:2.0.2"   # バージョン固定（latest ドリフト回避）
├── mode: Monolithic（シングルノード）
├── internal_port: 4040                # HTTP API / pprof 受信 / Prometheus 互換 /metrics
├── external_port: 4040
├── command: ["--config.file=/etc/pyroscope/config.yml"]
├── network: monitoring-lab-network    # dependency.network 経由
├── volumes:
│   └── pyroscope_data → /data         # プロファイルデータ永続化（FR-005）
└── bind_mounts:
    └── /home/ubuntu/monitoring-lab/pyroscope → /etc/pyroscope (read_only)
```

### Pyroscope 設定ファイル（`config/pyroscope/config.yml`）

```
PyroscopeConfig
└── pyroscopedb:
    └── data_path: /data               # ボリュームマウント先（FR-005）
# 注: pull-based pprof スクレイプは v2.x では config.yml 非対応
#     → scrape_configs は記載せず、Alloy/SDK 経由を将来課題とする
```

---

## メトリクス（Prometheus 統合）

Pyroscope が `:4040/metrics` で公開する Prometheus 互換メトリクス（主要なもの）。

| メトリクス名 | 種別 | 説明 |
|---|---|---|
| `up{job="pyroscope"}` | gauge | スクレイプ成否（1 = UP）。SC-002 / TargetDown 検知 |
| `pyroscope_distributor_received_profiles_total` | counter | 受信プロファイル数。プロファイル流入の動作確認 |
| `pyroscope_build_info` | gauge | バージョン情報（version="2.0.2"） |

---

## Grafana datasource（`config/grafana/provisioning/datasources/datasources.yml`）

```
PyroscopeDatasource
├── name: "Pyroscope"
├── type: "grafana-pyroscope-datasource"   # Grafana 10+ 組み込み
├── uid: "pyroscope"                        # Exemplar→Profile 相関の安定参照先
├── access: "proxy"
├── url: "http://pyroscope:4040"
├── isDefault: false
└── editable: true
```

---

## ファイル依存関係

```
config/pyroscope/config.yml
        ↓ scp（リモート /home/ubuntu/monitoring-lab/pyroscope/）
        ↓ bind mount → /etc/pyroscope/config.yml
Pyroscope コンテナ起動（:4040）
        ├─→ /metrics ← Prometheus pyroscope ジョブがスクレイプ（SC-002）
        ├─→ /data → pyroscope_data ボリューム（永続化, SC-003）
        └─→ http://pyroscope:4040 ← Grafana datasource が接続（FR-004）
```

---

## 既存ファイルへの変更

| ファイル | 変更内容 |
|---|---|
| `config/prometheus/prometheus.yml` | `pyroscope` ジョブ（`targets: ['pyroscope:4040']`）を追加 |
| `config/grafana/provisioning/datasources/datasources.yml` | Pyroscope datasource を追記 |
| `terraform/envs/local/pyroscope/terragrunt.hcl` | 新規（コンテナ定義） |
| `config/pyroscope/config.yml` | 新規（pyroscopedb 設定） |

---

## ポート割り当て（競合チェック, SC-004 / FR-007）

| サービス | ポート | 備考 |
|---|---|---|
| Pyroscope | 4040 | 既存サービスと競合なし |
| （参考）Tempo | 3200 | 別ポート |
| （参考）Loki | 3100 | 別ポート |
| （参考）Prometheus | 9090 | 別ポート |
