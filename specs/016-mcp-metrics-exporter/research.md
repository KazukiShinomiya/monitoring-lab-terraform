# Research: MCP メトリクスエクスポータ

**Feature**: 016-mcp-metrics-exporter | **Date**: 2026-06-17

Phase 0 の設計判断を、根拠と却下した代替案とともに記録する。spec の前提・制約と、実機検証の結果に基づく。

---

## D1. 計測値の収集経路（pull vs push）

**Decision**: push 方式。各 MCP サーバーが OpenTelemetry SDK で OTLP/gRPC を用い、稼働中の otel-collector（`10.0.0.220:4317`）へ計測値を送出する。

**Rationale**:
- MCP サーバーは Claude Code が `docker run --rm -i` で WSL2 ローカル Docker Engine 上に起動する**短命コンテナ**で、固定の待受アドレス・ライフタイムを持たない。リモート（10.0.0.220）の Prometheus からの pull スクレイプは、対象が存在する保証も到達経路も無く**成立しない**。
- 過去「⑧ MCP 可観測性は設計上問題なし」と結論づけた真因はこの pull 不成立にあった。push がこの構造的制約を解く唯一の道。

**実機検証（2026-06-17）**:
- WSL2 ホスト → `10.0.0.220:4317`: TCP OPEN
- WSL2 デフォルト bridge の docker コンテナ → `10.0.0.220:4317`: OPEN
- → MCP コンテナからの OTLP push 経路が物理的に成立することを確認済み。

**Alternatives considered**:
- *Pushgateway*: 別の常駐サービス追加が必要（FR-008 違反）。かつ短命ジョブ向けだが OTLP より統合度が低く、既存 LGTM 基盤（otel-collector）と二重化する。却下。
- *pull スクレイプ（現状維持）*: 上記理由で不成立。却下。

---

## D2. otel-collector → メトリクスストアへの転送方式

**Decision**: otel-collector に metrics パイプラインを増設し、`prometheusremotewrite` exporter で既存 VictoriaMetrics（`http://victoriametrics:8428/api/v1/write`）へ転送する（案B1）。

**Rationale（実機調査で裏付け）**:
- `config/prometheus/prometheus.yml` は既に `remote_write: http://victoriametrics:8428/api/v1/write` で全メトリクスを VM に集約済み。**VM は本基盤の統合メトリクスシンクとして既に remote-write を受けている** → 同じ口に相乗りするだけで新規受信機構が不要。
- Grafana に VictoriaMetrics データソース（`type: prometheus`, `uid: victoriametrics`, PromQL 互換）が既設。ダッシュボードは追加プラグインなしで即クエリ可能。
- **既存コンテナの再作成・フラグ変更が一切不要**。変更は otel-collector.yml（bind mount・scp + 再起動）と Grafana ダッシュボード追加のみ。最小リスク。
- `docker_container` モジュールの単一 publish ポート制約（otel-collector は 4317 のみ公開）を**回避**できる。remote-write は otel-collector からの outbound のため新規 publish ポート不要。

**Alternatives considered**:
- *案A: otel-collector に `prometheus` exporter（新ポート 8889 等）+ Prometheus スクレイプ*: `docker_container` モジュールが単一ポートしか publish できず、**モジュール改修という力技**が必要。影響範囲が広く却下。
- *案B2: `prometheusremotewrite` → Prometheus（`9090/api/v1/write`）*: Prometheus に `--web.enable-remote-write-receiver` フラグ追加が必要（現状未設定 → コンテナ再作成）。VM 経由より変更点が多い。却下。
- *案C: MCP → OTLP/HTTP で VictoriaMetrics の OTLP 受信口（`8428/opentelemetry/v1/metrics`）へ直送し、otel-collector を経由しない*: otel-collector 変更ゼロで最小に見えるが、(1) ユーザーが otel-collector 経由を明示選択、(2) トレースが既に otel-collector を通る以上、テレメトリの単一ingress（front door）を otel-collector に統一する方がアーキテクチャとして一貫、(3) batching/buffering を collector に集約できる、という理由で**otel-collector 経由を採用**。案C は将来 collector を介さない軽量経路が要る場合の退避案として記録。

**可視化データソースの注記**: 本方式では MCP メトリクスは VictoriaMetrics に格納される（Prometheus は remote-write を受けない構成）。よって Grafana ダッシュボードは **VictoriaMetrics データソース**を参照する。spec の「Prometheus/Grafana で可視化」の意図（既存 LGTM 基盤上での可視化）は満たす——VM は同一基盤の構成要素であり Grafana が可視化層。

---

## D3. 計測値の型と temporality

**Decision**:
- ツール呼び出し回数 = **Counter**（`mcp_tool_invocations_total`）。属性: `service`, `tool`, `status`(success/error)。
- ツール実行時間 = **Histogram**（`mcp_tool_duration_seconds`）。属性: `service`, `tool`。
- **Aggregation Temporality は cumulative（累積）**を明示設定する。

**Rationale**:
- `prometheusremotewrite` exporter および Prometheus/VM のカウンタ意味論は cumulative（単調増加）を前提とする。delta temporality だと Prometheus 側で `rate()` 等が破綻する。
- OpenTelemetry JS の OTLP メトリクス exporter は既定で cumulative。ただし短命プロセスの再起動でカウンタが 0 に戻る（プロセスごとに新 series）点に留意。`service`/`tool` ラベルは共通だが各プロセス起動分が時系列上はリセットとして現れうる → ダッシュボード側は `increase()`/`sum by` で扱い、利用者視点の合算（Edge Case: 複数インスタンス）を成立させる。
- レイテンシ Histogram は明示的バケット境界を定義（例: 5ms〜30s の対数的バケット）。ツールは外部コマンド(docker/ssh)を呼ぶため秒オーダーまでカバーする。

**Alternatives considered**:
- *delta temporality*: 短命プロセスに一見適合するが Prometheus エコシステムと不整合。却下。
- *ExponentialHistogram*: VM は対応するが学習目的には明示バケットの方が理解しやすい。明示バケットを採用。

---

## D4. ephemeral 終了時の flush（本設計の核心）

**Decision**: `PeriodicExportingMetricReader` を用いつつ、**プロセス終了の全経路で `meterProvider.shutdown()`（forceFlush 内包）を await してから `process.exit()` する**。これを共通ヘルパーが集中管理する。

**Rationale**:
- MCP コンテナは秒単位で終了しうるため、`PeriodicExportingMetricReader` の定期 interval（既定 60s 等）が**一度も発火しない**ケースが大半。したがって shutdown 時 flush が事実上唯一の送出経路（spec US2/FR-006、SC-002）。
- 終了経路は複数あり、すべてをカバーする必要がある:
  1. `SIGINT` / `SIGTERM`（Claude Code がコンテナ停止時に送出）→ 現状は即 `process.exit(0)` → **flush を挟むよう変更**。
  2. stdio transport クローズ（Claude が切断、stdin EOF）→ transport の `onclose` で flush + exit。
  3. `uncaughtException` / `unhandledRejection` → 既存ハンドラ（`process.exit(1)`）。best-effort で flush を試みるが、計測機構自体がクラッシュ要因にならないこと（FR-007）を優先。
- flush にはタイムアウト（例: 2s）を設け、収集先到達不能時もプロセス終了が無限に待たないようにする（Edge Case: 送出先到達不能）。

**Alternatives considered**:
- *定期エクスポートのみ（interval 短縮）*: interval を 1s 等に縮めても、起動〜終了が 1s 未満なら取りこぼす。かつ常時送出はオーバーヘッド。shutdown flush が確実。却下。
- *atexit 相当のみ*: Node に同期 atexit でのネットワーク flush は不可。非同期 shutdown を明示 await する設計が必須。

---

## D5. 4サーバー共通の計装ヘルパー（DRY）

**Decision**: `mcp/shared/telemetry.ts` に単一実装。提供 API:
- `initTelemetry(serviceName)`: Resource（`service.name`）付き MeterProvider を構築し OTLP exporter を接続。`MCP_TELEMETRY_DISABLED` 等の環境変数で無効化可能（FR-012）。
- `instrumentTool(toolName, handler)`: ツールハンドラをラップし、Counter/Histogram を記録（成功/失敗・所要時間）。本来の戻り値・例外はそのまま透過（FR-011）。失敗しても握りつぶしてツール応答を阻害しない（FR-007）。
- `shutdownTelemetry()`: flush + provider shutdown。終了経路から await 呼び出し。

**Rationale**:
- 原則IV（DRY）。4サーバーで定義・属性・送出を一致（FR-009）。
- 各サーバーは独立 npm パッケージ・独立 Dockerfile のため、ビルドコンテキストに `shared/` を含める方式を採る（D6）。

**Alternatives considered**:
- *各サーバーにコピペ*: DRY 違反。定義のドリフトを生む（image 固定戦役で学んだ「乖離は静かに育つ」）。却下。
- *npm workspaces 化 + 内部パッケージ公開*: 最も正統だが、4つの独立 Dockerfile・既存ビルドフローへの影響が大きい。学習環境では過剰。`shared/` 取り込み方式で十分。将来 workspace 化の余地は残す。

---

## D6. 共通ヘルパーの各イメージへの取り込み方法

**Decision**: 各サーバーの Dockerfile のビルドコンテキストを `mcp/` に広げる（または `shared/` を各 build 時にコピー）。各 `package.json` に `@opentelemetry/*` 依存を追加。tsconfig の `rootDir`/include を shared を含むよう調整。

**Rationale**:
- 単一実装を物理的に共有する最小手段。`docker build` のコンテキスト指定（`mcp/` をルートに、各 server を `-f` 指定）で `shared/` を同梱できる。
- 既存の `.mcp.json` の `docker run monitoring-lab-*-mcp` は不変——イメージ名・起動方法は変えない（FR-011 のインターフェース不変と整合）。

**検証事項（Phase A で確定）**: 既存 Dockerfile の構造（ビルドコンテキスト・COPY 範囲）を確認し、shared 取り込みの最小改修を決める。tsconfig の `rootDir: "src"`（TS6 移行で全サーバーに設定済み）と shared 配置の整合に注意。

**Alternatives considered**:
- *shared を各 server/src にシンボリックリンク/コピー生成*: ビルド前生成ステップが増え CRLF/LF 等の環境差を呼び込む。Docker コンテキスト同梱の方が単純。却下寄りだが Phase A で Dockerfile 構造次第で再検討。

---

## D7. 監視対象の自己監視（原則V）と otel-collector への影響

**Decision**: otel-collector に metrics パイプラインを足しても、既存の traces パイプラインと自己テレメトリ（`:8888`）は不変に保つ。新メトリクスには Grafana ダッシュボード（US3）を同一サイクルで用意。

**Rationale**:
- 原則V「新サービス追加時は監視設定も同一タスクで」。本機能自体が MCP の監視を実現するものであり、その産物（メトリクス）の可視化（ダッシュボード）まで含めて完結とする。
- otel-collector 自身の health は既存どおり Prometheus `otel-collector` job + `:8888` で監視継続。metrics パイプライン増設後、collector の `otelcol_exporter_sent_metric_points` 等で送出健全性も観測可能（運用上の副次利得）。

---

## D8. 送出プロトコルの転換: OTLP/gRPC → OTLP/HTTP（2026-07-12 実装フェーズで確定）

**Decision**: 計装ヘルパーの送出は **OTLP/HTTP(protobuf, 4318)** とする（当初の D1/D2 は OTLP/gRPC(4317) を想定していた）。otel-collector に 4318 を恒久公開（`docker_container` モジュールに `extra_ports` を追加）。

**Rationale（すべて実測に基づく）**:
- **WSL2 環境からの gRPC(h2c) はサイレント不達**: WSL コンテナ/ホストいずれからも TCP 接続は 3ms で成立するのに、gRPC 送信はエラーも成功も返さず 15 秒以上沈黙する（Windows ホストの node からは同一バージョンで到達可）。WSL2 NAT と HTTP/2(h2c) の相性問題と推定。原因深掘りは費用対効果が悪く、HTTP/1.1 転換で回避。
- OTLP/HTTP(JSON) の手投げ・OTLP/HTTP(protobuf) exporter とも end-to-end 到達を実証済み。

**Additional findings（同フェーズで確定した重要知見）**:
1. **flush は「forceFlush → ref付き settle(500ms) → shutdown → exit」の順が必須**: forceFlush/shutdown は送信完了前に resolve するため、直後の `process.exit` が送信中のリクエストを殺す（SC-002 で 5回中4回喪失を実測）。
2. **gracefulExit は冪等ガード必須**: stdin `end`/`close`/`transport.onclose` は連続発火し、2発目が `process.exit` を先に踏むと1発目の flush が失われる（shutdownTelemetry 自体の冪等性だけでは不十分）。
3. **`service.instance.id`（プロセスごと UUID）が必須**: 短命プロセスが同一系列へ同値 cumulative を書くと `increase()` がリセットを検出できず合算が 0 に潰れる。独立系列化し、集計は `sum(max_over_time(...))` で行う（contracts/metrics-contract.md 改訂済み）。
4. **バージョン完全固定**: `^` レンジで sdk-metrics 2.8.0→2.9.0 が混入し 0.207.0 系 exporter と噛み合わず調査が難航。@opentelemetry 5 パッケージと base image（node:22.20.0-alpine）を exact pin。
5. **VictoriaMetrics の検索遅延（~30s）**: 書き込み直後の instant query は直近サンプルを返さず「不達」の幻を生む。検証は 60 秒以上待つか広い窓 + `max_over_time` で照会する。

**Alternatives considered**:
- *gRPC の原因深掘り（WSL2 NAT / grpc-js の HTTP/2 フレーム調査)*: 学習環境の費用対効果に見合わない。HTTP/1.1 で完全動作するため転換が合理的。
- *collector を経ず VM の remote_write へ直接送出*: OTel 標準から外れ、リトライ/バッチの実装負担が増える。却下。

---

## 未解決事項

なし。spec に `[NEEDS CLARIFICATION]` は無く、送出方式・転送先・flush 要件・対象4サーバーは全て確定。Phase A 着手時に確認するのは「既存 Dockerfile のビルドコンテキスト構造」（D6）のみで、これは設計分岐ではなく実装詳細。
