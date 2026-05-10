# WOWHoneypot 監視システム 要件定義書

## プロジェクト概要

さくらのVPS上で稼働しているWOWHoneypotのログを、自宅のPrometheus/Grafana環境で可視化し、攻撃傾向の統計分析を行うシステムを構築する。

## 環境構成

### WOWHoneypot (さくらのVPS)

- **ホスト**: your-vps-hostname.example.com
- **インストールパス**: `/home/ubuntu/WOWHoneypot-master`
- **プロセス**: `python3 wowhoneypot.py` (PID: 8136, 2023年から稼働中)
- **ログディレクトリ**: `/home/ubuntu/WOWHoneypot-master/log/`
- **ログファイル**:
  - `access_log`: 266MB, 115,984行 (2020-08-02 ～ 現在)
  - `wowhoneypot.log`: 13MB (エラーログ)

### 監視環境 (自宅ネットワーク)

- **IPアドレス**: YOUR_SERVER_IP
- **管理**: Terragrunt (monitoring-lab-terraform)
- **稼働サービス**:
  - Prometheus: http://YOUR_SERVER_IP:9090
  - Grafana: http://YOUR_SERVER_IP:3000
  - その他: Zabbix, PostgreSQL, Vault

### ネットワーク制約

- 自宅ネットワークはNATの内側
- VPS → 自宅への直接接続は不可
- 自宅 → VPSへのSSH接続は可能

## ログフォーマット

### access_log フォーマット

```
[タイムスタンプ] 送信元IP 宛先:ポート "HTTPリクエスト" ステータスコード マッチ結果 Base64エンコードされたリクエスト詳細
```

**実例**:
```
[2026-05-03 01:15:25+0900] 77.83.39.197 153.127.59.154:80 "GET /.env HTTP/1.1" 200 False R0VUIC8uZW52IEhUVFAvMS4xCkhvc3Q6IDE1My4xMjcuNTkuMTU0ClVzZXItQWdlbnQ6IE1vemlsbGEvNS4wIC...
```

**パース可能な情報**:
- タイムスタンプ (JST)
- 送信元IPアドレス
- 宛先ホスト:ポート
- HTTPメソッド
- リクエストパス
- HTTPバージョン
- ステータスコード
- マッチ結果 (True/False または数値)
- Base64デコードで取得可能:
  - User-Agent
  - 完全なHTTPヘッダー
  - POSTボディ（攻撃ペイロード）

### wowhoneypot.log フォーマット

```
[タイムスタンプ][ログレベル]メッセージ
```

**実例**:
```
[2026-05-03 13:40:19+0900][ERROR]Access from blocklist ip(69.164.217.245). denied.
[2026-05-03 15:15:21+0900][ERROR]Request handling Failed: <class 'ValueError'> - Client(34.62.4.253) data cannot parse. b'\x16\x03\x00\x00i...'
```

## 要件

### 機能要件

#### FR-1: ログ収集
- 自宅からVPSへSSH接続し、ログファイルを定期的にpull
- 日次実行で十分（リアルタイム性は不要）
- 増分同期（rsync）で転送量を最小化

#### FR-2: ログ解析
- access_logをパースして以下の情報を抽出:
  - 送信元IPアドレス
  - タイムスタンプ
  - HTTPメソッド
  - リクエストパス
  - User-Agent
  - ステータスコード
- Base64エンコードされたリクエスト詳細をデコード

#### FR-3: GeoIP情報の付加
- MaxMind GeoLite2を使用
- IPアドレスから以下を取得:
  - 国コード、国名
  - 地域（州/県）
  - 都市
  - 緯度・経度（オプション）
- GeoIPデータベースの定期更新

#### FR-4: メトリクス公開
- Prometheus形式でメトリクスを公開
- ポート: 9150 (wow-honeypot-exporter)
- 以下のメトリクスを提供（後述）

#### FR-5: 可視化
- Grafanaダッシュボードで統計表示
- 攻撃傾向分析
- 地理的分布の可視化

### 非機能要件

#### NFR-1: セキュリティ
- SSH鍵認証の使用
- ログファイルに含まれる機密情報の適切な取り扱い
- VPSの認証情報は環境変数または秘密管理ツール（Vault）で管理

#### NFR-2: 運用性
- ログ同期の自動化（cron）
- エラー時の通知機能
- ログローテーション対応

#### NFR-3: パフォーマンス
- 大容量ログファイル（266MB+）の効率的な処理
- メトリクス生成時のメモリ使用量制限

#### NFR-4: 拡張性
- 他のハニーポットログにも対応できる設計
- 新しいメトリクスの追加が容易

## 収集するメトリクス

### 基本メトリクス

| メトリクス名 | タイプ | 説明 |
|------------|--------|------|
| `wow_honeypot_requests_total` | Counter | 総リクエスト数 |
| `wow_honeypot_requests_by_ip` | Gauge | IPアドレス別リクエスト数（上位N件） |
| `wow_honeypot_requests_by_path` | Gauge | リクエストパス別の回数 |
| `wow_honeypot_requests_by_method` | Gauge | HTTPメソッド別の回数 |
| `wow_honeypot_requests_by_status` | Gauge | ステータスコード別の回数 |
| `wow_honeypot_unique_ips` | Gauge | ユニークIPアドレス数 |

### GeoIPメトリクス

| メトリクス名 | タイプ | 説明 |
|------------|--------|------|
| `wow_honeypot_requests_by_country` | Gauge | 国別リクエスト数 |
| `wow_honeypot_requests_by_city` | Gauge | 都市別リクエスト数（上位N件） |
| `wow_honeypot_unique_countries` | Gauge | ユニーク国数 |

### 攻撃パターンメトリクス

| メトリクス名 | タイプ | 説明 |
|------------|--------|------|
| `wow_honeypot_exploit_attempts` | Gauge | エクスプロイトタイプ別試行回数 |
| `wow_honeypot_suspicious_user_agents` | Gauge | 疑わしいUser-Agent別の回数 |

**エクスプロイトタイプの分類例**:
- `.env` ファイル探索
- `/.git/` 探索
- CGI脆弱性攻撃 (`/cgi-bin/`)
- ルーター脆弱性 (`/HNAP1/`, `/GponForm/`)
- パストラバーサル (`..%2f..%2f`)
- WebShellアップロード試行

### 時系列メトリクス

- 日別の攻撃数推移
- 時間帯別の攻撃パターン
- 国別の時系列トレンド

## アーキテクチャ設計

```
┌─────────────────────────────────────────────────────────────┐
│ さくらのVPS (your-vps-hostname.example.com)                │
│                                                               │
│  WOWHoneypot (PID: 8136)                                     │
│    ↓                                                          │
│  /home/ubuntu/WOWHoneypot-master/log/                        │
│    ├── access_log (266MB)                                    │
│    └── wowhoneypot.log (13MB)                                │
│                                                               │
└───────────────────────────────┬───────────────────────────────┘
                                │
                                │ SSH (自宅 → VPS)
                                │ rsync/scp pull
                                │ 日次 cron実行
                                ↓
┌─────────────────────────────────────────────────────────────┐
│ 自宅ネットワーク (YOUR_SERVER_IP)                                │
│                                                               │
│  ┌────────────────────────────────────────┐                  │
│  │ ログ保存ディレクトリ                    │                  │
│  │ /opt/monitoring-lab/wow-logs/          │                  │
│  │   ├── access_log                        │                  │
│  │   └── wowhoneypot.log                   │                  │
│  └──────────────┬─────────────────────────┘                  │
│                 ↓                                             │
│  ┌────────────────────────────────────────┐                  │
│  │ WOW Honeypot Exporter (Docker)         │                  │
│  │ - Python 3.11                           │                  │
│  │ - prometheus_client                     │                  │
│  │ - geoip2 (MaxMind)                      │                  │
│  │ Port: 9150                              │                  │
│  └──────────────┬─────────────────────────┘                  │
│                 ↓ :9150/metrics                               │
│  ┌────────────────────────────────────────┐                  │
│  │ Prometheus :9090                        │                  │
│  │ - Scrape interval: 30s                  │                  │
│  │ - Retention: 30d                        │                  │
│  └──────────────┬─────────────────────────┘                  │
│                 ↓                                             │
│  ┌────────────────────────────────────────┐                  │
│  │ Grafana :3000                           │                  │
│  │ - WOW Honeypot Dashboard                │                  │
│  │ - 攻撃統計レポート                      │                  │
│  │ - 地理的分布マップ                      │                  │
│  └────────────────────────────────────────┘                  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## 技術スタック

### ログ同期
- **rsync**: 増分同期
- **cron**: 日次実行（例: 毎日 2:00 AM）
- **SSH鍵認証**: セキュアな接続

### Exporter
- **言語**: Python 3.11+
- **ライブラリ**:
  - `prometheus_client`: メトリクス公開
  - `geoip2`: GeoIP情報取得
  - `maxminddb`: GeoIPデータベース読み込み
- **実行環境**: Docker コンテナ
- **ポート**: 9150

### GeoIP
- **データベース**: MaxMind GeoLite2 City
- **ライセンス**: 無料（要アカウント登録）
- **更新頻度**: 週次または月次

### インフラ管理
- **IaC**: Terraform + Terragrunt
- **コンテナ**: Docker (既存のdocker_containerモジュールを利用)
- **ネットワーク**: monitoring-lab-network (既存)

## 実装タスク

### Phase 1: ログ同期機構

1. SSH鍵設定
   - VPSに公開鍵を配置
   - 自宅側で秘密鍵を安全に管理

2. ログ同期スクリプト作成
   - `scripts/sync-wow-logs.sh`
   - rsyncでVPSからログをpull
   - エラーハンドリング

3. cron設定
   - 日次実行（2:00 AM）
   - ログローテーション対応

### Phase 2: Exporter開発

1. ログパーサー実装
   - access_logのパース
   - Base64デコード
   - User-Agent抽出

2. GeoIP統合
   - MaxMind GeoLite2のセットアップ
   - IPアドレス → 地理情報の変換
   - キャッシュ機構

3. メトリクス生成
   - Prometheusメトリクスの定義
   - 効率的な集計処理

4. Dockerイメージ作成
   - Dockerfile作成
   - 依存関係管理

### Phase 3: インフラ統合

1. Terragrunt設定
   - `terraform/envs/local/wow-exporter/terragrunt.hcl`
   - Docker コンテナ定義
   - ボリュームマウント設定

2. Prometheus設定
   - scrape_configs追加
   - `wow-honeypot-exporter` ジョブ定義

3. Grafana Dashboard作成
   - 攻撃統計パネル
   - 地理的分布マップ
   - 時系列グラフ

### Phase 4: テストと調整

1. ログパーサーのテスト
   - 実際のログでの動作確認
   - エッジケース対応

2. パフォーマンス最適化
   - 大容量ログの処理速度改善
   - メモリ使用量の最適化

3. ドキュメント作成
   - セットアップガイド
   - 運用手順書

## セキュリティ考慮事項

1. **認証情報の管理**
   - VPSのSSH接続情報は`.env`ファイルまたはVaultで管理
   - `.gitignore`に秘密鍵を追加

2. **ログファイルの機密性**
   - 攻撃者のIPアドレスは公開情報として扱う
   - VPSのホスト名は既に公開済み

3. **GeoIPデータベース**
   - MaxMindのライセンス条項を遵守
   - データベースファイルをGit管理しない

## 参考情報

- WOWHoneypot: https://github.com/morihisa/WOWHoneypot
- MaxMind GeoLite2: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data
- Prometheus Exporters: https://prometheus.io/docs/instrumenting/writing_exporters/

## 変更履歴

| 日付 | 変更内容 | 作成者 |
|------|---------|--------|
| 2026-05-03 | 初版作成 | Claude Code |
