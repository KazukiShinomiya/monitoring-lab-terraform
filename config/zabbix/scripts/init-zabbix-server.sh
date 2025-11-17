#!/bin/sh
# ==========================================
# Zabbix Server初期化スクリプト
# ==========================================
# このスクリプトは以下を実行します:
# 1. Python3とpipのインストール（rootユーザーとして）
# 2. 外部スクリプト用のPythonパッケージインストール
# 3. Zabbix Serverの起動（Zabbixユーザーとして）

set -e

echo "=========================================="
echo "Zabbix Server初期化開始"
echo "=========================================="

# Python3とpipのインストール（Alpine Linux）
echo "[1/3] Python3とpipをインストール中..."
if ! command -v python3 &> /dev/null; then
    apk add --no-cache python3 py3-pip
    echo "✓ Python3とpipのインストール完了"
else
    echo "✓ Python3は既にインストール済み"
fi

# 外部スクリプト用のPythonパッケージインストール
echo "[2/3] Pythonパッケージをインストール中..."
pip3 install --no-cache-dir --break-system-packages requests
echo "✓ requestsパッケージのインストール完了"

# 外部スクリプトの実行権限確認
if [ -d "/usr/lib/zabbix/externalscripts" ]; then
    echo "[3/3] 外部スクリプトの権限を設定中..."
    chmod +x /usr/lib/zabbix/externalscripts/*.py 2>/dev/null || true
    chmod +x /usr/lib/zabbix/externalscripts/*.sh 2>/dev/null || true
    echo "✓ 外部スクリプトの権限設定完了"
fi

echo "=========================================="
echo "初期化完了 - Zabbix Serverを起動します"
echo "=========================================="

# 元のエントリーポイントを実行（Zabbix Server起動）
exec /usr/sbin/zabbix_server --foreground -c /etc/zabbix/zabbix_server.conf
