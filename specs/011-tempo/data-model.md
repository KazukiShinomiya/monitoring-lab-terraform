# Data Model: Grafana Tempo + OpenTelemetry Collector

**Feature**: 011-tempo
**Date**: 2026-03-28

このフィーチャーは IaC + 設定ファイル中心の実装のため、「データモデル」は設定ファイルのスキーマと成果物の構造として定義する。

---

## 設定ファイルスキーマ

### Tempo 設定 (`config/tempo/tempo.yml`)

```
tempo.yml
├── server
│   └── http_listen_port: 3200
├── distributor
│   └── receivers.otlp.protocols
│       ├── grpc: endpoint 0.0.0.0:4317
│       └── http: endpoint 0.0.0.0:4318
├── ingester
│   └── max_block_duration: 5m
├── compactor
│   └── compaction.block_retention: 336h
├── storage
│   └── trace
│       ├── backend: local
│       ├── local.path: /var/tempo/traces
│       └── wal.path: /var/tempo/wal
├── metrics_generator
│   ├── registry.external_labels
│   ├── storage.path: /var/tempo/generator/wal
│   └── traces_storage.path: /var/tempo/generator/traces
└── overrides.defaults.metrics_generator
    └── processors: [service-graphs, span-metrics]
```

### OTel Collector 設定 (`config/otel-collector/otel-collector.yml`)

```
otel-collector.yml
├── receivers
│   └── otlp.protocols
│       ├── grpc: endpoint 0.0.0.0:4317
│       └── http: endpoint 0.0.0.0:4318
├── processors
│   └── batch
│       ├── timeout: 1s
│       └── send_batch_size: 1024
├── exporters
│   └── otlp/tempo
│       ├── endpoint: tempo:4317
│       └── tls.insecure: true
└── service.pipelines.traces
    ├── receivers: [otlp]
    ├── processors: [batch]
    └── exporters: [otlp/tempo]
```

---

## Terragrunt ワークスペース構造

### `terraform/envs/local/tempo/terragrunt.hcl`

```
inputs
├── network_name: (dependency.network)
├── volumes: ["tempo_data"]
└── services
    └── tempo
        ├── image: grafana/tempo:latest
        ├── internal_port: 3200
        ├── external_port: 3200
        ├── command: ["-config.file=/etc/tempo/tempo.yml"]
        ├── volumes: [{source: tempo_data, target: /var/tempo}]
        └── bind_mounts: [{source: remote tempo.yml, target: /etc/tempo/tempo.yml}]
```

### `terraform/envs/local/otel-collector/terragrunt.hcl`

```
inputs
├── network_name: (dependency.network)
├── volumes: []
└── services
    └── otel-collector
        ├── image: otel/opentelemetry-collector-contrib:latest
        ├── internal_port: 4317
        ├── external_port: 4317
        ├── command: ["--config=/etc/otel-collector/otel-collector.yml"]
        ├── volumes: []
        └── bind_mounts: [{source: remote otel-collector.yml, target: /etc/otel-collector/otel-collector.yml}]
```

---

## 変更対象ファイル

| ファイル | 変更種別 | 内容 |
|---------|---------|------|
| `config/tempo/tempo.yml` | 新規作成 | Tempo 設定 |
| `config/otel-collector/otel-collector.yml` | 新規作成 | OTel Collector 設定 |
| `config/prometheus/prometheus.yml` | 追記 | Job 9 (tempo)、Exemplar 設定 |
| `config/grafana/provisioning/datasources/datasources.yml` | 追記 | Tempo データソース、Prometheus Exemplar リンク |
| `terraform/envs/local/tempo/terragrunt.hcl` | 新規作成 | Tempo Terragrunt 定義 |
| `terraform/envs/local/otel-collector/terragrunt.hcl` | 新規作成 | OTel Collector Terragrunt 定義 |
| `scripts/sync-config.sh` | 追記 | tempo/otel-collector サブコマンド |
| `Taskfile.yml` | 追記 | sync:tempo / sync:otel-collector タスク |

---

## 依存関係グラフ (追加分)

```
network ──┬──→ tempo
          └──→ otel-collector ──→ tempo (Docker network)

tempo ──→ grafana (datasource)
tempo ──→ prometheus (scrape job 9)
otel-collector ──→ tempo (trace export)
apps ──→ otel-collector:4317 (OTLP gRPC)
```

---

## リモートサーバーのディレクトリ構造 (追加分)

```
/home/ubuntu/monitoring-lab/
├── tempo/
│   └── tempo.yml
└── otel-collector/
    └── otel-collector.yml
```
