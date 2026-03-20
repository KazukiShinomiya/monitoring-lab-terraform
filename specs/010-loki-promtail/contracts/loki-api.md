# Contract: Loki HTTP API

**Interface**: Loki v3.x HTTP API
**Base URL**: `http://loki:3100`（Docker Network内） / `http://10.0.0.220:3100`（外部アクセス）

---

## ログプッシュ（Promtail → Loki）

### POST /loki/api/v1/push

Promtail がログエントリを Loki に送信するエンドポイント。

**Request**:
```
Content-Type: application/json

{
  "streams": [
    {
      "stream": {
        "container_name": "monitoring-lab-prometheus",
        "job": "containers"
      },
      "values": [
        ["1710000000000000000", "log line text"]
      ]
    }
  ]
}
```

**Response**:
- `204 No Content`: 成功
- `400 Bad Request`: 不正なリクエスト（タイムスタンプの逆順など）
- `500 Internal Server Error`: Loki 内部エラー

---

## ログクエリ

### GET /loki/api/v1/query

インスタントクエリ（現在時刻のログ取得）。

**Query Parameters**:
| パラメータ | 必須 | 説明 | 例 |
|-----------|------|------|-----|
| `query` | ✅ | LogQL クエリ式 | `{container_name="monitoring-lab-prometheus"}` |
| `limit` | - | 返却するエントリ数上限（デフォルト: 100） | `50` |
| `time` | - | クエリ時刻（Unix nano, RFC3339） | `2026-03-20T00:00:00Z` |
| `direction` | - | `forward` / `backward`（デフォルト: `backward`） | `backward` |

**Response**:
```json
{
  "status": "success",
  "data": {
    "resultType": "streams",
    "result": [
      {
        "stream": { "container_name": "monitoring-lab-prometheus" },
        "values": [["1710000000000000000", "log line"]]
      }
    ]
  }
}
```

---

### GET /loki/api/v1/query_range

範囲クエリ（時間範囲内のログ取得）。

**Query Parameters**:
| パラメータ | 必須 | 説明 |
|-----------|------|------|
| `query` | ✅ | LogQL クエリ式 |
| `start` | ✅ | 開始時刻（Unix nano / RFC3339） |
| `end` | ✅ | 終了時刻（Unix nano / RFC3339） |
| `limit` | - | 最大エントリ数（デフォルト: 100） |
| `step` | - | メトリクスクエリのステップ（例: `5m`） |

---

## 検証エンドポイント

### GET /ready

Loki の起動完了確認。

**Response**:
- `200 OK` + `"ready"`: 正常起動
- `503 Service Unavailable`: 起動中 / 異常

### GET /metrics

Prometheus スクレイプ用メトリクスエンドポイント。

**主要メトリクス**:
| メトリクス | 説明 |
|-----------|------|
| `loki_ingester_streams_created_total` | 作成されたストリーム総数 |
| `loki_request_duration_seconds` | クエリレイテンシ |
| `loki_ingester_chunk_stored_bytes_total` | 格納済みバイト数 |
| `loki_boltdb_shipper_compact_tables_operation_total` | コンパクション実行回数 |

---

## 動作確認コマンド（デプロイ後）

```bash
# Loki 起動確認
curl http://10.0.0.220:3100/ready

# ログが収集されているか確認（全コンテナ）
curl -G 'http://10.0.0.220:3100/loki/api/v1/query' \
  --data-urlencode 'query={job="containers"}' \
  --data-urlencode 'limit=5'

# 特定コンテナのログ取得
curl -G 'http://10.0.0.220:3100/loki/api/v1/query' \
  --data-urlencode 'query={container_name="monitoring-lab-prometheus"}'
```
