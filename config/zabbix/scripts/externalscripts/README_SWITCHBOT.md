# SwitchBot温湿度計 Zabbix外部スクリプト監視

## 概要

このスクリプトは、SwitchBot温湿度計のデータをZabbixで監視するための外部スクリプトです。
SwitchBot APIを使用して、温度・湿度・バッテリー残量を取得します。

## ファイル

- `check_switchbot.py` - SwitchBot API接続スクリプト

## 前提条件

### 1. SwitchBot APIトークンの取得

1. SwitchBotアプリを開く
2. プロフィール → 設定 → アプリバージョン（10回タップして開発者モードを有効化）
3. プロフィール → 設定 → 開発者向けオプション
4. トークンとシークレットをメモ

### 2. デバイスIDの取得

```bash
# SwitchBot API経由でデバイス一覧を取得
curl -X GET "https://api.switch-bot.com/v1.1/devices" \
  -H "Authorization: YOUR_TOKEN" \
  -H "sign: YOUR_SIGN" \
  -H "t: YOUR_TIMESTAMP" \
  -H "nonce: YOUR_NONCE"
```

または、SwitchBotアプリのデバイス詳細画面で確認可能です。

## セットアップ手順

### ステップ1: 環境変数の設定

`.env`ファイルに以下を追加:

```bash
SWITCHBOT_TOKEN=c1234567890abcdef1234567890abcde
SWITCHBOT_SECRET=abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
SWITCHBOT_TIMEOUT=10
```

### ステップ2: リモートサーバーへのデプロイ

```bash
# プロジェクトルートから実行
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && ./scripts/setup-remote-config.sh"
```

このスクリプトは以下を実行します:
- リモートサーバー上のディレクトリ作成
- 外部スクリプトの転送
- 実行権限の付与

### ステップ3: Terragruntでデプロイ

```bash
# WSL2でTerragruntコンテナに接続
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose exec terragrunt sh"

# Zabbixサービスのみ再デプロイ
cd /workspace/terraform/envs/local/zabbix
terragrunt plan
terragrunt apply
```

### ステップ4: Zabbixでアイテム作成

1. Zabbix Web UI (http://10.0.0.220:8080) にログイン
2. **Configuration** → **Hosts** → 監視対象ホスト選択
3. **Items** → **Create item**

#### アイテム設定例（温度）

```
Name: SwitchBot Temperature
Type: External check
Key: check_switchbot.py[YOUR_DEVICE_ID]
Type of information: Numeric (float)
Units: °C
Update interval: 5m
Applications: Environment
```

#### JSONPath処理（Dependent Items）

メインアイテム（上記）から、個別のメトリクスを抽出:

**温度:**
```
Name: SwitchBot Temperature Value
Type: Dependent item
Master item: SwitchBot Temperature
Type of information: Numeric (float)
Units: °C
Preprocessing:
  - JSONPath: $.temperature
```

**湿度:**
```
Name: SwitchBot Humidity Value
Type: Dependent item
Master item: SwitchBot Temperature
Type of information: Numeric (unsigned)
Units: %
Preprocessing:
  - JSONPath: $.humidity
```

**バッテリー:**
```
Name: SwitchBot Battery Level
Type: Dependent item
Master item: SwitchBot Temperature
Type of information: Numeric (unsigned)
Units: %
Preprocessing:
  - JSONPath: $.battery
```

## スクリプトの動作確認

### コンテナ内で直接実行

```bash
# リモートサーバーに接続
ssh ubuntu@10.0.0.220

# Zabbix Serverコンテナ内でスクリプト実行
docker exec monitoring-lab-zbx_server \
  /usr/lib/zabbix/externalscripts/check_switchbot.py YOUR_DEVICE_ID

# 正常なレスポンス例:
# {"device_id": "ABCD1234", "temperature": 23.5, "humidity": 45, "battery": 100, "timestamp": 1698765432, "exit_code": 0}
```

### デバッグモード

```bash
docker exec monitoring-lab-zbx_server \
  /usr/lib/zabbix/externalscripts/check_switchbot.py YOUR_DEVICE_ID --debug
```

デバッグモードでは、標準エラー出力に詳細情報が表示されます。

## トラブルシューティング

### 1. "Missing SwitchBot credentials" エラー

**原因**: 環境変数が設定されていない

**解決策**:
```bash
# .envファイルを確認
cat /mnt/e/work/labo/.env | grep SWITCHBOT

# Zabbix Serverコンテナ内で環境変数を確認
docker exec monitoring-lab-zbx_server env | grep SWITCHBOT

# コンテナ再起動
ssh ubuntu@10.0.0.220 "docker restart monitoring-lab-zbx_server"
```

### 2. "ModuleNotFoundError: No module named 'requests'" エラー

**原因**: requestsライブラリがインストールされていない

**解決策**:
```bash
# Zabbix Serverコンテナ内でrequestsをインストール
docker exec monitoring-lab-zbx_server pip3 install requests

# または、コンテナ再起動（init-zabbix-server.shが実行される）
docker restart monitoring-lab-zbx_server
```

### 3. "Request timeout" エラー

**原因**: ネットワーク接続が遅い、またはSwitchBot APIが応答しない

**解決策**:
```bash
# タイムアウト値を増やす（.envファイル）
SWITCHBOT_TIMEOUT=30

# または、コマンドライン引数で指定
docker exec monitoring-lab-zbx_server \
  /usr/lib/zabbix/externalscripts/check_switchbot.py YOUR_DEVICE_ID --timeout 30
```

### 4. "API returned status code 190" エラー

**原因**: APIトークンまたはシークレットが無効

**解決策**:
- SwitchBotアプリで新しいトークンを生成
- `.env`ファイルを更新
- Zabbix Serverコンテナを再起動

### 5. Zabbixアイテムがデータを取得できない

**確認項目**:

1. スクリプトの実行権限
   ```bash
   ssh ubuntu@10.0.0.220 "ls -la ~/monitoring-lab/zabbix/scripts/externalscripts/"
   ```

2. bind_mountの設定
   ```bash
   docker inspect monitoring-lab-zbx_server | grep -A 10 Mounts
   ```

3. Zabbix Serverログ
   ```bash
   docker logs monitoring-lab-zbx_server | grep "check_switchbot"
   ```

4. 手動実行で確認
   ```bash
   docker exec monitoring-lab-zbx_server \
     /usr/lib/zabbix/externalscripts/check_switchbot.py YOUR_DEVICE_ID
   ```

## レスポンス形式

### 正常時

```json
{
  "device_id": "ABCD1234",
  "temperature": 23.5,
  "humidity": 45,
  "battery": 100,
  "timestamp": 1698765432,
  "exit_code": 0
}
```

### エラー時

```json
{
  "error": "Request timeout",
  "message": "Request timeout after 10 seconds",
  "exit_code": 1,
  "timestamp": 1698765432
}
```

## 終了コード

| コード | 意味 | 説明 |
|-------|------|------|
| 0 | 成功 | データ取得成功 |
| 1 | 一般エラー | ネットワークエラー、タイムアウト等 |
| 2 | 設定エラー | トークン/シークレット未設定 |
| 3 | APIエラー | SwitchBot APIからのエラーレスポンス |

## パフォーマンスとレート制限

### SwitchBot APIレート制限

- **制限**: 1万リクエスト/日
- **推奨更新間隔**: 5分以上
- **計算**: (24時間 × 60分) / 5分 = 288リクエスト/日/デバイス

### 複数デバイス監視時の注意

デバイスが10台の場合: 288 × 10 = 2,880リクエスト/日（制限内）

## セキュリティ考慮事項

### 1. 環境変数管理

- ✅ `.env`ファイルは`.gitignore`に追加済み
- ❌ スクリプト内にトークンをハードコードしない
- ✅ 本番環境ではVaultへの移行を推奨

### 2. 通信の暗号化

- ✅ SwitchBot APIはHTTPS通信
- ✅ HMAC-SHA256による署名認証

### 3. アクセス制御

- 外部スクリプトはZabbix Serverコンテナ内でのみ実行
- bind_mountはread-onlyに設定可能（現在はfalse）

## カスタマイズ

### タイムアウト値の変更

```bash
# 環境変数で設定
SWITCHBOT_TIMEOUT=30

# コマンドライン引数で上書き
check_switchbot.py DEVICE_ID --timeout 30
```

### デバッグログの有効化

```bash
# デバッグモードで実行
check_switchbot.py DEVICE_ID --debug
```

## 参考リンク

- [SwitchBot API Documentation](https://github.com/OpenWonderLabs/SwitchBotAPI)
- [Zabbix External Checks](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/external)
- [JSONPath Preprocessing](https://www.zabbix.com/documentation/current/en/manual/config/items/preprocessing/jsonpath)

## ライセンス

MIT License

## 作成者

Monitoring Lab Project

## 更新履歴

- **2025-10-26**: 初版作成
  - SwitchBot温湿度計監視スクリプト実装
  - Terragrunt統合
  - ドキュメント作成
