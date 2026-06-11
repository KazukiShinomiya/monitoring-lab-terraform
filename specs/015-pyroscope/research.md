# Research: Pyroscope 継続的プロファイリング基盤

**Feature**: 015-pyroscope
**Date**: 2026-05-07（バックフィル: 2026-06-08）

> **注**: 本書類は実装・デプロイ完了後（v2.0.2 本番稼働中）に Speckit ADLC 整合のため後追い作成（バックフィル）した。記載内容は稼働中の実装実態を反映する。

---

## 決定事項

### 1. Pyroscope のバージョンとデプロイ方式

**Decision**: `grafana/pyroscope:2.0.2` を Monolithic（シングルノード）モードで単一コンテナとして起動

**Rationale**:
- `v2.0.2`（2026-05-07 build）が稼働実績のある安定版。`latest` タグは破壊的変更リスクがあるため固定（011-tempo / OTel での教訓を踏襲、2026-05-30 に `:latest` → `:2.0.2` へピン）
- Monolithic モードは単一プロセスで distributor/ingester/querier 等の全コンポーネントを内包。学習・開発用途では十分で、マイクロサービス分割は不要
- 既存の `docker_container` モジュールにそのまま載る（Constitution IV: モジュール化・DRY）

**Alternatives Considered**:
- マイクロサービスモード: 学習環境ではオーバーエンジニアリング、却下
- `:latest` 運用: Tempo/OTel で破壊的変更に遭った教訓から却下

---

### 2. プロファイル収集方式（重要な制約）

**Decision**: 初期スコープはサーバー起動とメトリクス公開までとし、pull-based pprof スクレイプ設定は見送る

**Rationale**:
- **Pyroscope v2.x では pull-based pprof スクレイプを `config.yml` で設定できない**。`scrape_configs` は CLI フラグまたは外部エージェント（Grafana Alloy）経由に移行された
- プロファイル収集の正攻法は (a) Grafana Alloy 経由の push、(b) アプリへの Pyroscope SDK 組み込み、のいずれか
- 学習基盤の初期段階としては「Pyroscope サーバーが稼働し、Prometheus でメトリクス収集でき、Grafana datasource として接続される」ことを最小到達点とした
- `config.yml` には `pyroscopedb.data_path: /data` のみ記載し、スクレイプ設定はコメントで設計意図を明記

**Alternatives Considered**:
- Grafana Alloy を同時導入してセルフプロファイルを push: スコープが膨らむため次フェーズに繰り延べ
- Pyroscope SDK をアプリに組み込む: 本基盤に被計測アプリがまだ無いため対象外

**含意**: SC-001（Grafana Explore でセルフプロファイルのフレームグラフ表示）は、Alloy/SDK 配線が入るまで**部分達成**。サーバー・datasource・永続化・メトリクス統合（SC-002〜SC-004）は達成済み。

---

### 3. Prometheus メトリクス統合

**Decision**: `prometheus.yml` に `pyroscope` ジョブを追加し、`pyroscope:4040` の `/metrics` をスクレイプ

**Rationale**:
- Pyroscope は `:4040` で Prometheus 互換の `/metrics`（`pyroscope_*` プレフィックス）を公開
- 既存の static_configs パターンを踏襲、新規 exporter 不要
- 既存の `TargetDown` アラートが Pyroscope ダウンを自動検知する（自己監視の可観測性、Constitution V）

**動作確認メトリクス**: `pyroscope_distributor_received_profiles_total` の増加、および `up{job="pyroscope"}` の 1（SC-002）

---

### 4. Grafana datasource 統合

**Decision**: `grafana-pyroscope-datasource` 型のデータソースを provisioning で追加（`uid: pyroscope`）

**Rationale**:
- `grafana-pyroscope-datasource` は Grafana 10+ に組み込み済みで追加プラグイン不要
- `uid: pyroscope` を固定することで、将来の Prometheus Exemplar → Profile 相関リンク（US3 発展形）の参照先を安定させる
- `url: http://pyroscope:4040`、`access: proxy` で監視ネットワーク内部から接続

---

### 5. データ永続化

**Decision**: 名前付き Docker ボリューム `pyroscope_data` を `/data` にマウントし、`pyroscopedb.data_path: /data` を指定

**Rationale**:
- コンテナ再作成・再起動でプロファイルデータを失わない（FR-005 / SC-003）
- 名前付きボリュームはイメージのタグ変更（`forces replacement`）でも保持される（2026-05-30 の v2.0.2 ピン時に瞬断4秒で検証済み）

---

## 未解決事項 / 次フェーズへの繰り延べ

| 項目 | 状態 | 備考 |
|---|---|---|
| セルフプロファイルの実収集（SC-001 完全達成） | 繰り延べ | Grafana Alloy 導入または SDK 組み込みが前提 |
| Exemplar → Profile 相関リンク（US3 発展） | 繰り延べ | `uid: pyroscope` で参照先は確保済み |

---

## 既知の挙動メモ

- Pyroscope v2.x の `/ready`: 内部 ready 後も約30秒の猶予（`Segment Writer not ready: waiting for 30s`）→ 起動直後の 503 は正常挙動
- docker プロバイダーはイメージを**タグ文字列**で追跡 → `:latest` → `:2.0.2` はダイジェスト同一でも `forces replacement`。名前付きボリュームは保持される
