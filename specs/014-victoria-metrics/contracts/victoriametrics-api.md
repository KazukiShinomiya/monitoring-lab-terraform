# Contract: VictoriaMetrics API インターフェース

**Date**: 2026-04-19

---

## エンドポイント一覧

### 受信エンドポイント（remote_write）

```
POST http://victoriametrics:8428/api/v1/write
Content-Type: application/x-protobuf
X-Prometheus-Remote-Write-Version: 0.1.0
```

- Prometheus が自動的に呼び出す（手動操作不要）
- Snappy 圧縮した Protobuf ペイロード

---

### クエリエンドポイント（Prometheus 互換）

```
GET/POST http://victoriametrics:8428/api/v1/query
GET/POST http://victoriametrics:8428/api/v1/query_range
GET      http://victoriametrics:8428/api/v1/series
GET      http://victoriametrics:8428/api/v1/labels
GET      http://victoriametrics:8428/api/v1/label/<name>/values
```

- Grafana Prometheus 型データソースが使用する標準 API
- 既存の PromQL クエリが変更なしで動作する（FR-003）

---

### ヘルスチェック

```
GET http://victoriametrics:8428/health
→ 200 OK: "OK"

GET http://YOUR_SERVER_IP:8428/health
→ 200 OK: "OK"
```

---

### メトリクス（Prometheus スクレイプ対象）

```
GET http://victoriametrics:8428/metrics
→ 200 OK: Prometheus テキスト形式
```

主要メトリクス:
- `vm_rows_inserted_total` — 取り込み行数
- `vm_ingestErrors_total` — 取り込みエラー数
- `vm_cache_size_bytes` — キャッシュ使用量
- `process_resident_memory_bytes` — メモリ使用量

---

## 動作検証コマンド

```bash
# ヘルスチェック
curl -sf http://YOUR_SERVER_IP:8428/health

# メトリクス取り込み確認（up メトリクスが返るか）
curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=up" | python3 -m json.tool

# 長期クエリ（例: 90日前からの Prometheus 稼働状況）
curl -s "http://YOUR_SERVER_IP:8428/api/v1/query_range?query=up&start=$(date -d '90 days ago' +%s)&end=$(date +%s)&step=3600"

# インサート行数確認
curl -s "http://YOUR_SERVER_IP:8428/api/v1/query?query=vm_rows_inserted_total"
```
