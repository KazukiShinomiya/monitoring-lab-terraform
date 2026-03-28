# Quickstart: Grafana Tempo + OpenTelemetry Collector 動作確認手順

**Feature**: 011-tempo
**Date**: 2026-03-28

---

## 前提条件

- リモートサーバー (YOUR_SERVER_IP) で monitoring-lab スタックが稼働中
- WSL2 環境から `task` コマンドが使用可能
- Terragrunt コンテナが起動中 (`task start` 済み)

---

## Step 1: Terragrunt デプロイ

```bash
# Tempo をデプロイ
task tg:apply:svc -- tempo

# OTel Collector をデプロイ
task tg:apply:svc -- otel-collector
```

## Step 2: 設定ファイルをリモートサーバーに転送

```bash
# リモートサーバーにディレクトリを作成 (初回のみ)
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'mkdir -p ~/monitoring-lab/tempo ~/monitoring-lab/otel-collector'"

# 設定ファイルを転送
task sync:tempo
task sync:otel-collector

# Prometheus 設定を同期 (Exemplar + Tempo スクレイプ追加後)
task sync:prometheus

# Grafana 設定を同期 (Tempo データソース追加後)
task sync:grafana
```

## Step 3: コンテナ起動確認

```bash
# コンテナ状態を確認
task status
# 期待値: monitoring-lab-tempo と monitoring-lab-otel-collector が "Up" 状態

# Tempo ヘルスチェック
wsl -d Ubuntu-24.04 -e bash -c "curl -s http://YOUR_SERVER_IP:3200/ready"
# 期待値: "ready"

# OTel Collector の起動ログ確認
task logs -- otel-collector
# 期待値: "Everything is ready." が含まれる
```

## Step 4: テスト用トレースを送信

```bash
# telemetrygen を使ってサンプルトレース送信
wsl -d Ubuntu-24.04 -e bash -c "docker run --rm --network host \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces --otlp-endpoint localhost:4317 --otlp-insecure --traces 5"
```

## Step 5: Grafana で確認

1. Grafana を開く: http://YOUR_SERVER_IP:3000
2. 左メニュー → **Explore**
3. データソースで **Tempo** を選択
4. **Search** タブ → **Run query** → トレースが表示されることを確認
5. トレースをクリック → ウォーターフォールビューが表示されることを確認

## Step 6: Prometheus スクレイプ確認

1. Prometheus を開く: http://YOUR_SERVER_IP:9090/targets
2. `tempo` ジョブが **UP** 状態であることを確認

## Step 7: Exemplar 連携確認 (オプション)

1. Grafana → Explore → **Prometheus** データソース
2. メトリクスクエリを入力 (例: `tempo_request_duration_seconds_bucket`)
3. グラフ上に Exemplar マーカー (◆) が表示されることを確認
4. Exemplar マーカーをクリック → Tempo のトレースビューにジャンプすることを確認

---

## トラブルシューティング

| 症状 | 確認コマンド | 対処 |
|------|------------|------|
| Tempo が起動しない | `task logs -- tempo` | `tempo.yml` の構文エラーを確認 |
| OTel Collector が起動しない | `task logs -- otel-collector` | `otel-collector.yml` の構文エラーを確認 |
| トレースが Grafana に表示されない | Tempo ログを確認 | OTel Collector → Tempo の疎通確認 |
| Exemplar が表示されない | Prometheus config 確認 | `scrape_protocols` と `enable_exemplar_storage` が設定されているか確認 |
