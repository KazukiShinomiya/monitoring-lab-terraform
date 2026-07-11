# Contract: otel-collector metrics パイプライン増設

**Feature**: 016-mcp-metrics-exporter
**対象**: `config/otel-collector/otel-collector.yml`（リモート `/home/ubuntu/monitoring-lab/otel-collector/otel-collector.yml` に bind mount）

既存の traces パイプライン・自己テレメトリ（`:8888`）は**不変**に保ち、metrics パイプラインと `prometheusremotewrite` exporter を**増設**する。

---

## 変更内容（差分の意図）

### receivers（変更なし）
`otlp`（gRPC `0.0.0.0:4317` / HTTP `0.0.0.0:4318`）は既存のまま。MCP からの OTLP メトリクスも同じ otlp receiver が受ける。

### processors（変更なし or 流用）
既存 `batch` を metrics でも流用する。

### exporters（追加）
```yaml
exporters:
  otlp/tempo:            # 既存（traces 用、変更なし）
    endpoint: "tempo:4317"
    tls:
      insecure: true
  prometheusremotewrite: # 【追加】metrics 用
    endpoint: "http://victoriametrics:8428/api/v1/write"
    tls:
      insecure: true
    # resource 属性を series ラベルへ展開（service.name 等）
    resource_to_telemetry_conversion:
      enabled: true
```

### service.pipelines（metrics を追加）
```yaml
service:
  pipelines:
    traces:              # 既存（変更なし）
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tempo]
    metrics:             # 【追加】
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheusremotewrite]
  telemetry:             # 既存（:8888 自己監視、変更なし）
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus:
                host: "0.0.0.0"
                port: 8888
```

---

## 不変条件（契約として守る）

- **新規 publish ポートを増やさない**: `prometheusremotewrite` は collector からの outbound（`victoriametrics:8428` へ docker ネットワーク内通信）であり、`terragrunt.hcl` の `internal_port`/`external_port`(4317) も bind_mounts も**変更不要**。
- **victoriametrics への到達**: collector とVM は同一 docker ネットワーク（`monitoring-lab-network`）上。Prometheus が既に `victoriametrics:8428/api/v1/write` へ remote_write できている事実が到達性を裏付ける。
- **既存 traces への非干渉**: traces パイプライン・Tempo 連携は無変更。
- **冪等性（憲法I）**: 設定反映は scp + コンテナ再起動（otel-collector はステートレス）。反映後 `terragrunt plan` 全 workspace "No changes"。`terragrunt.hcl` が不変なら image/command の drift も生じない。

---

## 反映手順（quickstart に詳細）

1. `config/otel-collector/otel-collector.yml` をローカル編集
2. リモート `/home/ubuntu/monitoring-lab/otel-collector/otel-collector.yml` へ scp
3. otel-collector コンテナ再起動（`docker restart` or terragrunt apply で再作成）
4. 検証: collector ログにエラーなし、`otelcol_exporter_sent_metric_points{exporter="prometheusremotewrite"}` 増加、VM に `mcp_tool_*` 系列出現

---

## ロールバック

- `prometheusremotewrite` exporter と metrics パイプラインを除去して再 scp + 再起動すれば traces のみの既存状態へ即復帰（ステートレスのためデータ損失なし）。
