# WOWHoneypot 監視システム - クイックスタート

## 概要

このガイドは、新しいセッションでWOWHoneypot監視システムの実装を開始するためのクイックリファレンスです。

## プロジェクト状況

### 完了済み
- ✅ 要件定義書作成
- ✅ アーキテクチャ設計書作成
- ✅ VPS上のWOWHoneypotログフォーマット確認

### 未着手
- ⬜ ログ同期スクリプト実装
- ⬜ Exporter開発
- ⬜ GeoIP統合
- ⬜ Terragrunt設定
- ⬜ Grafanaダッシュボード作成

## ドキュメント

### 必読ドキュメント

1. **要件定義書**: `docs/wow-honeypot-monitoring-requirements.md`
   - プロジェクト概要、環境構成、要件
   - 収集するメトリクス一覧
   - セキュリティ考慮事項

2. **アーキテクチャ設計書**: `docs/wow-honeypot-monitoring-architecture.md`
   - ディレクトリ構造
   - コンポーネント設計（コード例付き）
   - Dockerイメージ、Terragrunt設定
   - セットアップ手順

## 重要な情報

### VPS環境

- **ホスト**: ik1-427-45900.vs.sakura.ne.jp
- **ログパス**: `/home/ubuntu/WOWHoneypot-master/log/`
- **ログファイル**:
  - `access_log`: 266MB, 115,984行
  - `wowhoneypot.log`: 13MB

### ログフォーマット（access_log）

```
[タイムスタンプ] 送信元IP 宛先:ポート "HTTPリクエスト" ステータス マッチ結果 Base64データ
```

例:
```
[2026-05-03 01:15:25+0900] 77.83.39.197 153.127.59.154:80 "GET /.env HTTP/1.1" 200 False R0VUIC8uZW52...
```

### 自宅環境

- **ネットワーク**: 10.0.0.220
- **Prometheus**: http://10.0.0.220:9090
- **Grafana**: http://10.0.0.220:3000

## 次のステップ（Phase 1）

### 1. ディレクトリ構造作成

```bash
# monitoring-lab-terraform ディレクトリで実行
mkdir -p config/wow-exporter/{exporter,scripts}
mkdir -p terraform/envs/local/wow-exporter
mkdir -p scripts
```

### 2. ログ同期スクリプト作成

ファイル: `config/wow-exporter/scripts/sync-logs.sh`

詳細は `docs/wow-honeypot-monitoring-architecture.md` 参照

### 3. SSH設定

```bash
# VPSへの接続設定を ~/.ssh/config に追加
# 詳細は architecture.md の「セットアップ手順」参照
```

### 4. ログ同期テスト

```bash
bash config/wow-exporter/scripts/sync-logs.sh
```

## Phase 2: Exporter開発

### 必要なファイル

1. `config/wow-exporter/exporter/__init__.py`
2. `config/wow-exporter/exporter/main.py`
3. `config/wow-exporter/exporter/parser.py`
4. `config/wow-exporter/exporter/geoip.py`
5. `config/wow-exporter/exporter/metrics.py`
6. `config/wow-exporter/requirements.txt`
7. `config/wow-exporter/Dockerfile`

コード例は全て `docs/wow-honeypot-monitoring-architecture.md` に記載済み

## Phase 3: GeoIP設定

### MaxMind GeoLite2

1. アカウント登録: https://www.maxmind.com/en/geolite2/signup
2. ライセンスキー取得
3. データベースダウンロード

詳細は architecture.md 参照

## Phase 4: インフラ統合

### Terragrunt設定

ファイル: `terraform/envs/local/wow-exporter/terragrunt.hcl`

### Prometheus設定更新

Prometheus設定ファイルにscrape_configs追加

### Grafanaダッシュボード

- 攻撃統計パネル
- 地理的分布マップ
- 時系列グラフ

## よくある質問

### Q: VPSへのSSH接続はパスワード認証ですか？

A: はい。SSH鍵認証への移行を推奨（architecture.md参照）

### Q: リアルタイム監視は必要ですか？

A: 不要。日次集計で十分です。

### Q: GeoIPは必須ですか？

A: はい。攻撃傾向分析のため、国別・都市別の情報が重要です。

### Q: 既存のPrometheus/Grafanaへの影響は？

A: 既存サービスに影響なし。新しいexporterとdashboardを追加するのみ。

## トラブルシューティング

問題が発生したら、以下を確認：

1. VPSへのSSH接続
   ```bash
   ssh root@ik1-427-45900.vs.sakura.ne.jp
   ```

2. ログファイルの存在
   ```bash
   ls -lh /home/ubuntu/WOWHoneypot-master/log/
   ```

3. Dockerコンテナ状態
   ```bash
   docker ps | grep wow
   ```

## 参考リンク

- WOWHoneypot GitHub: https://github.com/morihisa/WOWHoneypot
- MaxMind GeoLite2: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data
- Prometheus Exporters: https://prometheus.io/docs/instrumenting/writing_exporters/

## 連絡先

質問や問題があれば、要件定義書とアーキテクチャ設計書を参照してください。
