# Research: VictoriaMetrics 長期メトリクス保存基盤

**Branch**: `014-victoria-metrics` | **Date**: 2026-04-19

---

## 決定事項

### Decision 1: VictoriaMetrics Docker イメージ

**Decision**: `victoriametrics/victoria-metrics:v1.140.0` を使用する（特定バージョンにピン）

**Rationale**:
- `stable` タグは Docker Hub に存在しないことを実装時に確認（manifest unknown エラー）
- `latest` タグは破壊的変更のリスクがある（011-tempo の教訓: v2.10.x で Kafka 必須化）
- 特定バージョン `v1.140.0`（2026-04-19 時点の最新）にピンすることで再現性を確保
- シングルノード版（`victoria-metrics`）でスコープ：学習環境のシングルノード構成に適合

**Alternatives considered**:
- `stable`: 採用しない（タグが存在しない）
- `latest`: 採用しない（予期しない API/設定の変更リスク）
- `victoria-metrics-cluster`: 採用しない（学習環境ではオーバースペック、設定複雑）

---

### Decision 2: Prometheus remote_write 設定

**Decision**: prometheus.yml に `remote_write` セクションを追加する。エンドポイントは `http://victoriametrics:8428/api/v1/write`。WAL queue_config も明示設定する。

```yaml
remote_write:
  - url: "http://victoriametrics:8428/api/v1/write"
    queue_config:
      min_backoff: 30ms
      max_backoff: 60s
      max_shards: 4
```

**Rationale**:
- VictoriaMetrics は Prometheus remote_write プロトコルをネイティブサポート
- Docker network 内で `victoriametrics` ホスト名で名前解決される
- `queue_config` で再試行ポリシーを明示することで、VM 停止時の Prometheus への影響を最小化
- `max_shards: 4` は学習環境の負荷に対して十分かつ保守的な値
- Prometheus デフォルトの WAL バッファは 2 時間分（FR-007: VM 停止中も Prometheus 継続動作を保証）

**Alternatives considered**:
- `max_shards` デフォルト（1000）: 採用しない（学習環境でリソース浪費）
- remote_write なし（Grafana Prometheus proxy 経由）: クエリ互換性は担保できるが長期保存不可のため却下

---

### Decision 3: 保持期間の設定

**Decision**: `-retentionPeriod=12` (12ヶ月 = 365日以上) を使用する

**Rationale**:
- VictoriaMetrics のデフォルト単位は「月」。`12` = 12ヶ月 = 約 365日
- v1.82.0 以降 `365d` 形式も使用可能だが、月単位の方が慣用的で VM ドキュメントに準拠
- FR-002「最低365日間の保持」を充足する
- ストレージ使用量見積もり: 監視スタック規模（約10サービス）では 5〜10GB/年程度と想定

**Alternatives considered**:
- `-retentionPeriod=365d`: 同等だが、月単位の方がより短く記述可能
- `-retentionPeriod=24`: 過剰（学習環境では不要）

---

### Decision 4: Grafana データソース型

**Decision**: Grafana 標準の `prometheus` 型データソースを使用する（追加プラグイン不要）

```yaml
- name: VictoriaMetrics
  type: prometheus
  uid: victoriametrics
  url: http://victoriametrics:8428
```

**Rationale**:
- VictoriaMetrics は Prometheus 互換の HTTP API (`/api/v1/query`, `/api/v1/query_range`) を提供
- Grafana の `prometheus` 型データソースがそのまま動作する
- `grafana-victoriametrics-datasource` プラグイン（VM 専用）は MetricsQL 拡張関数のサポートを追加するが、学習環境では不要
- FR-003「既存クエリの再利用」を満たすためクエリ互換性は完全

**Alternatives considered**:
- VM 専用 Grafana プラグイン: 採用しない（Grafana コンテナの環境変数 GF_INSTALL_PLUGINS 変更が必要、学習環境では不要な複雑性）

---

### Decision 5: Terragrunt 依存関係

**Decision**: VictoriaMetrics の Terragrunt 定義は `network` のみに依存する。`prometheus` への依存は不要。

**Rationale**:
- VictoriaMetrics 自体は Prometheus なしで独立起動できる
- Prometheus は VM を参照するが逆は不成立（循環依存を避けるため依存追加しない）
- prometheus.yml の `remote_write` 設定は VM デプロイ後に `sync:prometheus` で反映する（IaC 外の手順として quickstart.md に記載）
- alertmanager, tempo 等と同じパターン（network のみ依存）

**Alternatives considered**:
- prometheus を dependency に追加: 採用しない（逆依存関係になり循環の原因になりうる）

---

### Decision 6: VM 自己監視 (Constitution 原則 V)

**Decision**: prometheus.yml に Job 11 として victoriametrics:8428 を追加する

**Rationale**:
- Constitution 原則 V「本プロジェクトがデプロイするすべてのコンテナは Prometheus のスクレイプ対象」を遵守
- VictoriaMetrics はポート 8428 で `/metrics` を公開する
- 既存の `TargetDown` アラートが自動的に VM ダウンを検知する（追加アラートルール不要）

---

## 変更対象ファイル一覧

| ファイル | 変更内容 |
|---|---|
| `terraform/envs/local/victoriametrics/terragrunt.hcl` | 新規: VM コンテナ定義 |
| `config/prometheus/prometheus.yml` | `remote_write` セクション追加 + Job 11 追加 |
| `config/grafana/provisioning/datasources/datasources.yml` | VictoriaMetrics データソース追加 |
| `scripts/sync-config.sh` | 変更不要（prometheus + grafana sync で対応可能） |
| `Taskfile.yml` | 変更不要（既存の sync:prometheus / sync:grafana で対応可能） |

---

## 技術メモ

- VictoriaMetrics HTTP ポート: `8428`（remote_write 受信 + Prometheus 互換クエリ API）
- Docker Volume: `vm_data` — コンテナ内パス `/victoria-metrics-data`
- コンテナ名: `monitoring-lab-victoriametrics`
- ストレージ自動圧縮: VictoriaMetrics は内部で自動的にデータを圧縮（Gorilla + Zstd）
- 重複排除: remote_write での重複送信は VM が自動排除（Edge Cases SC-003 対応）
