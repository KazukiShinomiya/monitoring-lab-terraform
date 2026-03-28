# Research: Grafana Tempo + OpenTelemetry Collector トレーシング基盤

**Feature**: 011-tempo
**Date**: 2026-03-28

---

## 1. Grafana Tempo 3.x — ローカルバックエンド単一バイナリ構成

### Decision
Tempo 3.4.x を **all-in-one (single binary)** モードで、**local filesystem** バックエンドで動作させる。

### Rationale
- 学習環境では Distributed モード (distributor/ingester/querier 分離) は不要
- `grafana/tempo:latest` は single binary として起動し、`-config.file` 一つで制御できる
- local バックエンドはオブジェクトストレージ不要で即座に動作する
- 将来の本番化時は S3 バックエンドへの設定変更のみで移行可能

### Key Configuration (Tempo 3.x)
```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 336h   # 14日

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal

metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: monitoring-lab
  storage:
    path: /var/tempo/generator/wal
  traces_storage:
    path: /var/tempo/generator/traces

overrides:
  defaults:
    metrics_generator:
      processors: [service-graphs, span-metrics]
      generate_native_histograms: both
```

### Alternatives considered
- **Distributed mode**: 複雑すぎる（学習環境不要）
- **GCS/S3 backend**: 外部サービス依存が生じる（学習環境不要）
- **Jaeger/Zipkin**: OTel標準から外れる。Tempo + OTLP が現在のベストプラクティス

---

## 2. OpenTelemetry Collector — トレースルーティング構成

### Decision
`otel/opentelemetry-collector-contrib` イメージを使用し、OTLP receiver → OTLP exporter (Tempo) のシンプルなパイプラインを構成する。

### Rationale
- `-contrib` バリアントは全レシーバー/エクスポーターを含み、将来の拡張に対応
- シンプルなパイプライン (receiver: otlp → exporter: otlp/tempo) でまず動かす
- バッチ処理プロセッサーを追加することで効率を上げる

### Key Configuration (OTel Collector)
```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tempo]
```

### Alternatives considered
- `otel/opentelemetry-collector` (core): 一部エクスポーターが不足する可能性
- Alloy (Grafana Agent後継): Loki/Tempo統合には強力だが、学習コストが高い
- 直接 Tempo に OTLP 送信: Collector なしのシンプル構成も可能だが、将来の柔軟性が失われる

---

## 3. ポート割り当て戦略 — 競合回避

### Decision
- **Tempo**: 外部ポート `3200` (HTTP) のみ公開。4317/4318 は Docker ネットワーク内のみ
- **OTel Collector**: 外部ポート `4317` (OTLP gRPC) を公開

### Rationale
既存の `docker_container` モジュールは **1サービスにつき1ポートペア** のみサポート（`internal_port`, `external_port` が各1つ）。

ポート重複の回避:
| サービス | 外部ポート | 内部ポート | 用途 |
|---------|----------|----------|------|
| Tempo | 3200 | 3200 | HTTP API・Grafana データソース・Prometheus スクレイプ |
| OTel Collector | 4317 | 4317 | OTLP gRPC 受信（アプリからのトレース送信） |

OTel Collector の HTTP (4318) は外部非公開。Docker ネットワーク内のコンテナは `otel-collector:4318` で接続可能。
Tempo の OTLP ポート (4317/4318) は外部非公開。OTel Collector が Docker ネットワーク経由で `tempo:4317` に接続。

### Constraint Acknowledged
モジュール拡張 (複数ポートサポート) は本フィーチャーのスコープ外。必要になった場合は別フィーチャーとして対処する。

---

## 4. Grafana Tempo データソース — Exemplar 連携設定

### Decision
Grafana の `datasources.yml` に Tempo データソースを追加し、Prometheus との双方向リンクを設定する。

### Key Configuration
```yaml
# Tempo datasource
- name: Tempo
  type: tempo
  uid: tempo
  access: proxy
  url: http://tempo:3200
  jsonData:
    httpMethod: GET
    serviceMap:
      datasourceUid: prometheus
    nodeGraph:
      enabled: true
    tracesToLogs:
      datasourceUid: loki
      filterByTraceID: true
      filterBySpanID: false
    tracesToMetrics:
      datasourceUid: prometheus
      spanStartTimeShift: '-5m'
      spanEndTimeShift: '5m'

# Prometheus datasource の変更 (Exemplar リンク追加)
- name: Prometheus
  ...
  jsonData:
    ...
    exemplarTraceIdDestinations:
      - name: traceID
        datasourceUid: tempo
```

`deleteDatasources` リストに `Tempo` を追加することも必要。

---

## 5. Prometheus — Exemplar ストレージ有効化

### Decision
`prometheus.yml` に以下を追加:

```yaml
storage:
  exemplar_storage:
    enable_exemplar_storage: true
    max_exemplars: 100000
```

かつ scrape_protocols に OpenMetrics を追加 (Exemplar 収集に必要):

```yaml
global:
  ...
  scrape_protocols:
    - OpenMetricsText1.0.0
    - OpenMetricsText0.0.1
    - PrometheusText0.0.4
```

Tempo スクレイプジョブ:
```yaml
- job_name: 'tempo'
  static_configs:
    - targets: ['tempo:3200']
```

### Rationale
- Exemplar は OpenMetrics フォーマットで公開される。Prometheus のデフォルト `PrometheusText0.0.4` のみでは Exemplar は収集されない
- `max_exemplars: 100000` は学習環境として十分

---

## 6. HCP Terraform Workspace 命名規則

### Decision
既存パターン `monitoring-lab-local-{service}` に従い:
- `monitoring-lab-local-tempo`
- `monitoring-lab-local-otel-collector`

### Note
新規 Workspace は HCP Terraform UI または API で **Local** 実行モードに手動変更が必要（デフォルトは Remote）。

---

## 7. sync-config.sh 拡張パターン

### Decision
既存の `sync_loki()` / `sync_promtail()` と同じパターンで追加:

```bash
sync_tempo() {
  ssh mkdir -p .../tempo
  scp config/tempo/tempo.yml → remote
  docker restart monitoring-lab-tempo
}

sync_otel_collector() {
  ssh mkdir -p .../otel-collector
  scp config/otel-collector/otel-collector.yml → remote
  docker restart monitoring-lab-otel-collector
}
```

`all` ターゲットにも追加。

---

## 8. Constitution Check 結果 (研究後確認)

| 原則 | 適合状況 |
|------|---------|
| I. IaC (Terragrunt) | ✅ 既存 `docker_container` モジュール再利用 |
| II. セキュリティ | ✅ 認証なし設定は学習環境として許容、技術的負債として記録 |
| III. ドキュメント駆動 | ✅ spec → research → plan → tasks の順序遵守 |
| IV. モジュール化 DRY | ✅ 既存モジュール利用、新規モジュール不要 |
| V. 自己監視 | ✅ Prometheus が Tempo をスクレイプ (Job 9)、TargetDown アラートが監視 |
