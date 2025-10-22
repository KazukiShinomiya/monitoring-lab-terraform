# Zabbix カスタム監視スクリプト管理

このディレクトリには、Zabbix Serverで使用するカスタム監視スクリプトを配置します。

---

## 📁 ディレクトリ構成

```
config/zabbix/scripts/
├── README.md                    # このファイル
├── externalscripts/            # External Checksスクリプト
│   ├── check_disk_usage.sh    # 例: ディスク使用率チェック
│   ├── check_ssl_cert.py      # 例: SSL証明書有効期限チェック
│   └── check_api_response.sh  # 例: API応答時間チェック
├── alertscripts/               # アラート通知スクリプト
│   ├── send_slack.sh          # 例: Slack通知
│   └── send_email.py          # 例: メール通知
└── userparameters/             # UserParameter設定ファイル
    └── custom_metrics.conf     # 例: カスタムメトリクス定義
```

---

## 🔧 スクリプトの種類

### 1. External Scripts (externalscripts/)
Zabbix Serverから直接実行される外部スクリプト。

**用途**:
- リモートホストへのHTTP/HTTPSチェック
- API監視
- カスタムメトリクス収集

**実行場所**: Zabbix Serverコンテナ内
**パス**: `/usr/lib/zabbix/externalscripts/`

**スクリプト例**:
```bash
#!/bin/bash
# check_disk_usage.sh
# 使用方法: check_disk_usage.sh <hostname> <mount_point> <warning> <critical>

HOSTNAME=$1
MOUNT=$2
WARN=$3
CRIT=$4

USAGE=$(ssh $HOSTNAME "df -h $MOUNT | tail -1 | awk '{print \$5}' | sed 's/%//'")

if [ $USAGE -ge $CRIT ]; then
    echo "CRITICAL: Disk usage is ${USAGE}%"
    exit 2
elif [ $USAGE -ge $WARN ]; then
    echo "WARNING: Disk usage is ${USAGE}%"
    exit 1
else
    echo "OK: Disk usage is ${USAGE}%"
    exit 0
fi
```

### 2. Alert Scripts (alertscripts/)
トリガー発火時に実行される通知スクリプト。

**用途**:
- Slack/Teams通知
- カスタムメール送信
- チケット自動起票（Jira, Redmine等）

**実行場所**: Zabbix Serverコンテナ内
**パス**: `/usr/lib/zabbix/alertscripts/`

**スクリプト例**:
```bash
#!/bin/bash
# send_slack.sh
# 使用方法: send_slack.sh <channel> <message>

WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
CHANNEL=$1
MESSAGE=$2

curl -X POST $WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d "{\"channel\": \"$CHANNEL\", \"text\": \"$MESSAGE\"}"
```

### 3. UserParameter Files (userparameters/)
Zabbix Agentのカスタムメトリクス定義。

**用途**:
- Zabbix Agentで収集するカスタムメトリクス定義
- アプリケーション固有のメトリクス

**配置場所**: Zabbix Agentコンテナ内
**パス**: `/etc/zabbix/zabbix_agentd.d/`

**設定例**:
```conf
# custom_metrics.conf
UserParameter=custom.app.users,/usr/local/bin/count_users.sh
UserParameter=custom.app.response_time,curl -s -o /dev/null -w '%{time_total}' http://localhost:8080/health
UserParameter=custom.disk.inode[*],df -i $1 | tail -1 | awk '{print $$5}' | sed 's/%//'
```

---

## 🚀 スクリプト追加手順

### ステップ1: スクリプトの作成

```bash
# このリポジトリ内で作成
cd /e/work/labo/config/zabbix/scripts/externalscripts
vim check_custom_metric.sh

# 実行権限付与
chmod +x check_custom_metric.sh

# ローカルでテスト
./check_custom_metric.sh
```

### ステップ2: リモートサーバーへの配置

```bash
# setup-remote-config.sh を拡張するか、手動でコピー
scp config/zabbix/scripts/externalscripts/check_custom_metric.sh \
  ubuntu@10.0.0.220:/home/ubuntu/monitoring-lab/zabbix/scripts/externalscripts/
```

### ステップ3: Terragrunt設定の更新

`terraform/envs/local/zabbix/terragrunt.hcl` の `zbx_server` に bind_mount を追加:

```hcl
bind_mounts = [
  {
    source    = "/home/ubuntu/monitoring-lab/zabbix/scripts/externalscripts"
    target    = "/usr/lib/zabbix/externalscripts"
    read_only = true
  },
  {
    source    = "/home/ubuntu/monitoring-lab/zabbix/scripts/alertscripts"
    target    = "/usr/lib/zabbix/alertscripts"
    read_only = true
  }
]
```

### ステップ4: Terragruntで反映

```bash
# WSL2でTerragruntコンテナに接続
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose exec terragrunt sh"

# Zabbixサービスのみ再デプロイ
cd /workspace/terraform/envs/local/zabbix
terragrunt plan
terragrunt apply
```

### ステップ5: Zabbix Web UIで設定

1. **Configuration** → **Hosts** → 対象ホスト選択
2. **Items** → **Create item**
3. Type: **External check** を選択
4. Key: `check_custom_metric.sh[{HOST.CONN},{ITEM.KEY.PARAM1}]`
5. 保存

---

## 🧪 スクリプトのテスト方法

### コンテナ内でテスト

```bash
# リモートサーバーに接続
ssh ubuntu@10.0.0.220

# Zabbix Serverコンテナ内でスクリプト実行
docker exec monitoring-lab-zbx_server \
  /usr/lib/zabbix/externalscripts/check_custom_metric.sh arg1 arg2

# 終了コードを確認
echo $?  # 0=OK, 1=WARNING, 2=CRITICAL
```

### ログで確認

```bash
# Zabbix Serverログ
docker logs monitoring-lab-zbx_server | grep "check_custom_metric"

# デバッグレベルログを有効化（必要に応じて）
# terragrunt.hcl で環境変数追加: "ZBX_DEBUGLEVEL=4"
```

---

## 📋 スクリプト作成のベストプラクティス

### 1. シバン（Shebang）の明記
```bash
#!/bin/bash
# または
#!/usr/bin/env python3
```

### 2. エラーハンドリング
```bash
set -euo pipefail  # エラー時に即座に終了

# コマンド失敗時の処理
if ! result=$(some_command 2>&1); then
    echo "ERROR: Command failed: $result"
    exit 2
fi
```

### 3. タイムアウト設定
```bash
# 30秒でタイムアウト
timeout 30s curl -s http://example.com || echo "TIMEOUT"
```

### 4. ログ出力
```bash
# 標準出力: Zabbixに返す値
# 標準エラー: ログに記録（Zabbix Serverログに表示）
echo "Metric value: 42"
echo "Debug info: processed 100 items" >&2
```

### 5. 終了コード
```bash
exit 0  # 成功
exit 1  # 警告レベル（オプション、Zabbixでは未使用）
exit 2  # エラー
```

### 6. パラメータ検証
```bash
if [ $# -lt 2 ]; then
    echo "Usage: $0 <hostname> <metric_name>"
    exit 2
fi
```

---

## 🔒 セキュリティ考慮事項

### 1. 認証情報の管理
```bash
# ❌ NG: スクリプト内にハードコード
PASSWORD="secret123"

# ✅ OK: 環境変数から取得
PASSWORD="${ZABBIX_SCRIPT_PASSWORD}"

# ✅ BEST: Vaultから取得（将来の拡張）
PASSWORD=$(vault kv get -field=password secret/monitoring/api)
```

### 2. インジェクション対策
```bash
# ❌ NG: ユーザー入力をそのまま実行
eval "ls $USER_INPUT"

# ✅ OK: 入力検証
if [[ ! $USER_INPUT =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Invalid input"
    exit 2
fi
```

### 3. 権限の最小化
- スクリプトは read-only でマウント
- 必要最小限の権限で実行
- sudoは極力避ける

---

## 📚 参考リソース

### Zabbix公式ドキュメント
- [External checks](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/external)
- [Custom alertscripts](https://www.zabbix.com/documentation/current/en/manual/config/notifications/media/script)
- [User parameters](https://www.zabbix.com/documentation/current/en/manual/config/items/userparameters)

### スクリプトサンプル集
- [Zabbix Community Scripts](https://github.com/zabbix/community-templates)
- [Zabbix Share](https://share.zabbix.com/cat-apps)

---

## 🐛 トラブルシューティング

### スクリプトが実行されない

**確認項目**:
1. 実行権限があるか？
   ```bash
   docker exec monitoring-lab-zbx_server ls -la /usr/lib/zabbix/externalscripts/
   ```

2. シバンが正しいか？
   ```bash
   docker exec monitoring-lab-zbx_server head -1 /usr/lib/zabbix/externalscripts/your_script.sh
   ```

3. スクリプト内のコマンドがコンテナ内に存在するか？
   ```bash
   docker exec monitoring-lab-zbx_server which curl
   ```

4. bind_mountが正しく設定されているか？
   ```bash
   docker inspect monitoring-lab-zbx_server | grep -A 10 Mounts
   ```

### パーミッションエラー

```bash
# リモートサーバー上で権限確認
ssh ubuntu@10.0.0.220
ls -la ~/monitoring-lab/zabbix/scripts/externalscripts/

# 必要に応じて権限修正
chmod 755 ~/monitoring-lab/zabbix/scripts/externalscripts/your_script.sh
```

### スクリプトの出力が取得できない

```bash
# Zabbix Serverログで確認
docker logs monitoring-lab-zbx_server | tail -100

# 手動実行でテスト
docker exec -it monitoring-lab-zbx_server sh
cd /usr/lib/zabbix/externalscripts
./your_script.sh
```

---

## 📝 スクリプトテンプレート

### Bash External Check テンプレート

```bash
#!/bin/bash
#
# スクリプト名: template_check.sh
# 説明: 〇〇を監視するスクリプト
# 作成者: Your Name
# 作成日: YYYY-MM-DD
#
# 使用方法: template_check.sh <arg1> <arg2>
# 終了コード: 0=OK, 2=ERROR
#

set -euo pipefail

# 引数チェック
if [ $# -lt 2 ]; then
    echo "ERROR: Insufficient arguments"
    echo "Usage: $0 <arg1> <arg2>" >&2
    exit 2
fi

ARG1="$1"
ARG2="$2"

# タイムアウト設定（秒）
TIMEOUT=30

# メイン処理
main() {
    # ここに監視ロジックを記述
    local result
    result=$(timeout ${TIMEOUT}s some_command "$ARG1" "$ARG2" 2>&1) || {
        echo "ERROR: Command failed"
        return 2
    }

    # 結果を出力（Zabbixが取得）
    echo "$result"
    return 0
}

# 実行
if main; then
    exit 0
else
    exit 2
fi
```

### Python External Check テンプレート

```python
#!/usr/bin/env python3
"""
スクリプト名: template_check.py
説明: 〇〇を監視するスクリプト
作成者: Your Name
作成日: YYYY-MM-DD

使用方法: template_check.py <arg1> <arg2>
終了コード: 0=OK, 2=ERROR
"""

import sys
import argparse
import logging

# ログ設定（stderr出力 → Zabbix Serverログに記録）
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stderr
)

def main(arg1, arg2):
    """メイン処理"""
    try:
        # ここに監視ロジックを記述
        result = perform_check(arg1, arg2)

        # 結果を出力（stdout → Zabbixが取得）
        print(result)
        return 0

    except Exception as e:
        logging.error(f"Check failed: {e}")
        print(f"ERROR: {e}")
        return 2

def perform_check(arg1, arg2):
    """監視処理の実装"""
    # 例: APIチェック
    import requests
    response = requests.get(f"http://{arg1}/api/{arg2}", timeout=30)
    response.raise_for_status()
    return response.json()['metric']

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Custom Zabbix check')
    parser.add_argument('arg1', help='First argument')
    parser.add_argument('arg2', help='Second argument')
    args = parser.parse_args()

    sys.exit(main(args.arg1, args.arg2))
```

---

## 🔄 バージョン管理

### Git管理のベストプラクティス

```bash
# スクリプトのコミット
git add config/zabbix/scripts/
git commit -m "Add: Custom disk usage check script"

# 変更履歴の確認
git log -- config/zabbix/scripts/

# スクリプトの差分確認
git diff HEAD~1 config/zabbix/scripts/externalscripts/check_disk.sh
```

### スクリプトのバージョン表記

```bash
#!/bin/bash
# Version: 1.0.0
# Changelog:
#   1.0.0 (2025-10-19): Initial release
#   1.1.0 (2025-10-20): Add timeout handling
```

---

**このディレクトリを活用して、効果的なカスタム監視を実装してください！**
