---
name: grafana-audit
description: Grafanaダッシュボードの健全性監査（datasource UID 突合・パネルクエリ実弾検証・壊れ方の分類レポート）
---

Grafana ダッシュボードの「死んでいるパネル」を体系的に検出する。調査は読み取り専用——修復はレポートを見てから別途行う。
規模が大きい場合は **grafana-doctor エージェント**に委譲してよい（読み取り専用ツールのみで安全）。

## 前提

- 接続先は `.env` から導出する: `GRAFANA_URL=http://$TARGET_HOST:3000`、認証は `admin:$GRAFANA_ADMIN_PASSWORD`
- `.env` を source する場合は **`unset DOCKER_HOST` を忘れない**（npipe 汚染で WSL docker が壊れる既知の罠）
- クエリ実弾検証の宛先: Prometheus `http://$TARGET_HOST:9090` / VictoriaMetrics `http://$TARGET_HOST:8428`

## 手順

### 1. 実在 datasource の棚卸し

```bash
curl -s -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA_URL/api/datasources" \
  | python3 -c "import sys,json; [print(d['uid'], d['type'], d['name']) for d in json.load(sys.stdin)]"
```

期待される DS: Prometheus / Zabbix / Loki / Tempo / VictoriaMetrics / Pyroscope。

### 2. provisioning JSON から参照 UID を抽出

`config/grafana/provisioning/dashboards/*.json` 全ファイルについて:

- `"datasource"` フィールド（uid 直書き・name 直書き・`${DS_*}` テンプレート変数）を Grep で抽出
- 手順1の実在 UID 一覧と突合 → **存在しない UID を参照するパネルを列挙**

### 3. Grafana に実際にロードされているか確認

```bash
curl -s -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA_URL/api/search?type=dash-db" \
  | python3 -m json.tool
```

ディスク上の JSON と突合し、プロビジョニングされていないダッシュボードを検出。

### 4. パネルクエリの実弾検証

各ダッシュボード JSON の `targets[].expr`（Prometheus/VM 系）を抽出し、対応するデータソースへ直接クエリ:

```bash
curl -s "http://$TARGET_HOST:8428/api/v1/query" --data-urlencode "query=<expr>" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print(len(r), 'series')"
```

`0 series` のクエリ = No data パネルの候補。テンプレート変数（`$job` 等）を含む式は代表値に置換するか「要目視」と分類する。
Zabbix・Loki・Tempo 系パネルはクエリ形式が異なるため、datasource の `/api/datasources/uid/<uid>/health` 相当（または proxy 経由の疎通）でデータソース自体の生死のみ確認する。

### 5. レポート（壊れ方の分類表）

| 分類 | 意味 |
|---|---|
| **A: UID不一致** | 存在しない datasource UID を参照（プロビジョニング再作成で UID が変わった等） |
| **B: クエリ空振り** | DS は健在だがメトリクスが存在しない（メトリクス名変更・ターゲット消滅・label 変更） |
| **C: 未ロード** | JSON はあるが Grafana に出ていない（dashboards.yml のスキャン対象外・JSON 構文エラー） |
| **D: DS異常** | データソース自体が unhealthy（Zabbix 認証切れ等） |
| **E: 要目視** | テンプレート変数・特殊パネルで自動判定不能 |

ダッシュボードごとに「パネル数 / 死亡数 / 分類 / 修復案」を表で出す。修復はレポート承認後に着手する。
