# WOWHoneypot 監視システム アーキテクチャ

## ディレクトリ構造

```
monitoring-lab-terraform/
├── config/
│   └── wow-exporter/
│       ├── exporter/
│       │   ├── __init__.py
│       │   ├── main.py                    # Exporter メインロジック
│       │   ├── parser.py                   # ログパーサー
│       │   ├── geoip.py                    # GeoIP処理
│       │   └── metrics.py                  # Prometheus メトリクス定義
│       ├── scripts/
│       │   └── sync-logs.sh                # ログ同期スクリプト
│       ├── Dockerfile                      # Exporter Docker イメージ
│       ├── requirements.txt                # Python依存関係
│       └── config.yml                      # Exporter設定ファイル
│
├── terraform/
│   ├── envs/local/
│   │   └── wow-exporter/
│   │       └── terragrunt.hcl              # Terragrunt設定
│   └── modules/
│       └── docker_container/               # 既存モジュール使用
│
├── scripts/
│   ├── setup-wow-exporter.sh               # 初期セットアップスクリプト
│   └── update-geoip-db.sh                  # GeoIPデータベース更新
│
└── docs/
    ├── wow-honeypot-monitoring-requirements.md
    └── wow-honeypot-monitoring-architecture.md  # このファイル
```

## コンポーネント設計

### 1. ログ同期スクリプト (sync-logs.sh)

**目的**: さくらのVPSから自宅へログファイルをpull

**実装**:
```bash
#!/bin/bash
# config/wow-exporter/scripts/sync-logs.sh

# 設定
VPS_HOST="${VPS_HOST:-vps-honeypot}"  # ~/.ssh/config のホスト名
VPS_LOG_DIR="/home/ubuntu/WOWHoneypot-master/log"
LOCAL_LOG_DIR="/opt/monitoring-lab/wow-logs"
LOCK_FILE="/tmp/wow-log-sync.lock"

# ロックファイルチェック（多重実行防止）
if [ -f "$LOCK_FILE" ]; then
    echo "Sync already running"
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# ログディレクトリ作成
mkdir -p "$LOCAL_LOG_DIR"

# rsyncでログを取得
rsync -avz \
    --partial \
    --progress \
    --bwlimit=5000 \
    "${VPS_HOST}:${VPS_LOG_DIR}/" \
    "${LOCAL_LOG_DIR}/"

if [ $? -eq 0 ]; then
    echo "Log sync completed successfully at $(date)"
else
    echo "Log sync failed at $(date)" >&2
    exit 1
fi
```

**Cron設定例**:
```cron
# 毎日 2:00 AM にログ同期
0 2 * * * /opt/monitoring-lab/scripts/sync-logs.sh >> /var/log/wow-log-sync.log 2>&1
```

### 2. ログパーサー (parser.py)

**目的**: access_logをパースしてデータ構造化

**データクラス**:
```python
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

@dataclass
class AccessLogEntry:
    timestamp: datetime
    source_ip: str
    destination: str
    destination_port: int
    http_method: str
    request_path: str
    http_version: str
    status_code: int
    match_result: str  # "False", "True", または数値
    user_agent: Optional[str] = None
    full_headers: Optional[dict] = None
    post_body: Optional[str] = None

    # GeoIP情報（後で追加）
    country_code: Optional[str] = None
    country_name: Optional[str] = None
    city: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
```

**パーサー実装の要点**:
```python
import re
import base64
from datetime import datetime

class AccessLogParser:
    # ログフォーマット
    # [timestamp] source_ip dest:port "HTTP request" status match_result base64_data
    LOG_PATTERN = re.compile(
        r'\[(?P<timestamp>[^\]]+)\]\s+'
        r'(?P<source_ip>[\d\.]+)\s+'
        r'(?P<destination>[^:]+):(?P<port>\d+)\s+'
        r'"(?P<http_request>[^"]+)"\s+'
        r'(?P<status>\d+)\s+'
        r'(?P<match_result>\S+)\s+'
        r'(?P<base64_data>\S+)'
    )

    HTTP_REQUEST_PATTERN = re.compile(
        r'(?P<method>\w+)\s+(?P<path>\S+)\s+HTTP/(?P<version>[\d\.]+)'
    )

    def parse_line(self, line: str) -> Optional[AccessLogEntry]:
        match = self.LOG_PATTERN.match(line)
        if not match:
            return None

        # HTTPリクエスト部分をパース
        http_match = self.HTTP_REQUEST_PATTERN.match(match.group('http_request'))
        if not http_match:
            return None

        # Base64デコード
        try:
            decoded_data = base64.b64decode(match.group('base64_data')).decode('utf-8', errors='ignore')
            headers = self._parse_http_headers(decoded_data)
        except Exception:
            headers = {}

        return AccessLogEntry(
            timestamp=self._parse_timestamp(match.group('timestamp')),
            source_ip=match.group('source_ip'),
            destination=match.group('destination'),
            destination_port=int(match.group('port')),
            http_method=http_match.group('method'),
            request_path=http_match.group('path'),
            http_version=http_match.group('version'),
            status_code=int(match.group('status')),
            match_result=match.group('match_result'),
            user_agent=headers.get('User-Agent'),
            full_headers=headers
        )

    def _parse_timestamp(self, ts_str: str) -> datetime:
        # [2026-05-03 01:15:25+0900] 形式
        return datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S%z')

    def _parse_http_headers(self, decoded_data: str) -> dict:
        headers = {}
        lines = decoded_data.split('\n')
        for line in lines[1:]:  # 最初の行はリクエストライン
            if ':' in line:
                key, value = line.split(':', 1)
                headers[key.strip()] = value.strip()
        return headers
```

### 3. GeoIP処理 (geoip.py)

**目的**: IPアドレスから地理情報を取得

**実装**:
```python
import geoip2.database
import geoip2.errors
from typing import Optional, Dict
from pathlib import Path

class GeoIPResolver:
    def __init__(self, db_path: str = '/opt/geoip/GeoLite2-City.mmdb'):
        self.db_path = Path(db_path)
        self.reader = None
        self._init_reader()

    def _init_reader(self):
        if self.db_path.exists():
            self.reader = geoip2.database.Reader(str(self.db_path))
        else:
            print(f"Warning: GeoIP database not found at {self.db_path}")

    def lookup(self, ip_address: str) -> Optional[Dict[str, str]]:
        if not self.reader:
            return None

        try:
            response = self.reader.city(ip_address)
            return {
                'country_code': response.country.iso_code,
                'country_name': response.country.name,
                'city': response.city.name,
                'latitude': response.location.latitude,
                'longitude': response.location.longitude,
            }
        except (geoip2.errors.AddressNotFoundError, ValueError):
            return None

    def close(self):
        if self.reader:
            self.reader.close()
```

### 4. メトリクス定義 (metrics.py)

**目的**: Prometheusメトリクスの定義と更新

**実装**:
```python
from prometheus_client import Counter, Gauge, Histogram
from prometheus_client.core import GaugeMetricFamily, CounterMetricFamily
from collections import defaultdict, Counter as PyCounter

class WOWHoneypotMetrics:
    def __init__(self):
        # カウンター（累積値）
        self.total_requests = 0

        # ゲージ（現在値）
        self.requests_by_ip = PyCounter()
        self.requests_by_path = PyCounter()
        self.requests_by_method = PyCounter()
        self.requests_by_status = PyCounter()
        self.requests_by_country = PyCounter()
        self.requests_by_city = PyCounter()
        self.exploit_attempts = PyCounter()

        # ユニーク値
        self.unique_ips = set()
        self.unique_countries = set()

    def update_from_entry(self, entry):
        """AccessLogEntryからメトリクスを更新"""
        self.total_requests += 1
        self.requests_by_ip[entry.source_ip] += 1
        self.requests_by_path[entry.request_path] += 1
        self.requests_by_method[entry.http_method] += 1
        self.requests_by_status[entry.status_code] += 1
        self.unique_ips.add(entry.source_ip)

        # GeoIP情報
        if entry.country_code:
            self.requests_by_country[entry.country_code] += 1
            self.unique_countries.add(entry.country_code)

        if entry.city:
            city_key = f"{entry.country_code}:{entry.city}"
            self.requests_by_city[city_key] += 1

        # エクスプロイト分類
        exploit_type = self._classify_exploit(entry.request_path)
        if exploit_type:
            self.exploit_attempts[exploit_type] += 1

    def _classify_exploit(self, path: str) -> Optional[str]:
        """リクエストパスからエクスプロイトタイプを分類"""
        patterns = {
            'env_file_search': r'\.env',
            'git_exposure': r'\.git/',
            'cgi_exploit': r'/cgi-bin/',
            'hnap_exploit': r'/HNAP1/',
            'gpon_exploit': r'/GponForm/',
            'path_traversal': r'\.\.[/\\]',
            'webshell_upload': r'\.(php|asp|jsp|war)',
            'router_exploit': r'/(login|admin|setup)\.cgi',
        }

        for exploit_type, pattern in patterns.items():
            if re.search(pattern, path, re.IGNORECASE):
                return exploit_type

        return None

    def collect(self):
        """Prometheus Collector用のメトリクス生成"""
        # 総リクエスト数
        yield CounterMetricFamily(
            'wow_honeypot_requests_total',
            'Total number of requests',
            value=self.total_requests
        )

        # ユニークIP数
        yield GaugeMetricFamily(
            'wow_honeypot_unique_ips',
            'Number of unique source IPs',
            value=len(self.unique_ips)
        )

        # IPアドレス別（上位20件）
        metric = GaugeMetricFamily(
            'wow_honeypot_requests_by_ip',
            'Requests per source IP',
            labels=['source_ip']
        )
        for ip, count in self.requests_by_ip.most_common(20):
            metric.add_metric([ip], count)
        yield metric

        # 国別
        metric = GaugeMetricFamily(
            'wow_honeypot_requests_by_country',
            'Requests per country',
            labels=['country_code', 'country_name']
        )
        for country_code, count in self.requests_by_country.items():
            # country_nameは別途GeoIPから取得
            metric.add_metric([country_code, ''], count)
        yield metric

        # エクスプロイトタイプ別
        metric = GaugeMetricFamily(
            'wow_honeypot_exploit_attempts',
            'Exploit attempts by type',
            labels=['exploit_type']
        )
        for exploit_type, count in self.exploit_attempts.items():
            metric.add_metric([exploit_type], count)
        yield metric

        # ... その他のメトリクス
```

### 5. Exporter メインロジック (main.py)

**目的**: Prometheusエンドポイントの提供

**実装概要**:
```python
#!/usr/bin/env python3
import time
from prometheus_client import start_http_server, REGISTRY
from pathlib import Path
import argparse

from .parser import AccessLogParser
from .geoip import GeoIPResolver
from .metrics import WOWHoneypotMetrics

class WOWHoneypotCollector:
    def __init__(self, log_path: str, geoip_db_path: str):
        self.log_path = Path(log_path)
        self.parser = AccessLogParser()
        self.geoip = GeoIPResolver(geoip_db_path)
        self.metrics = WOWHoneypotMetrics()
        self._last_position = 0

    def collect(self):
        """ログを解析してメトリクスを生成"""
        self._parse_new_lines()
        return self.metrics.collect()

    def _parse_new_lines(self):
        """前回読み込んだ位置から新しい行を解析"""
        access_log = self.log_path / 'access_log'

        if not access_log.exists():
            return

        with open(access_log, 'r', encoding='utf-8', errors='ignore') as f:
            f.seek(self._last_position)

            for line in f:
                entry = self.parser.parse_line(line.strip())
                if entry:
                    # GeoIP情報を追加
                    geoip_data = self.geoip.lookup(entry.source_ip)
                    if geoip_data:
                        entry.country_code = geoip_data['country_code']
                        entry.country_name = geoip_data['country_name']
                        entry.city = geoip_data['city']
                        entry.latitude = geoip_data['latitude']
                        entry.longitude = geoip_data['longitude']

                    # メトリクス更新
                    self.metrics.update_from_entry(entry)

            self._last_position = f.tell()

def main():
    parser = argparse.ArgumentParser(description='WOW Honeypot Prometheus Exporter')
    parser.add_argument('--log-path', default='/opt/monitoring-lab/wow-logs')
    parser.add_argument('--geoip-db', default='/opt/geoip/GeoLite2-City.mmdb')
    parser.add_argument('--port', type=int, default=9150)
    args = parser.parse_args()

    # Collector登録
    collector = WOWHoneypotCollector(args.log_path, args.geoip_db)
    REGISTRY.register(collector)

    # HTTPサーバー起動
    start_http_server(args.port)
    print(f"WOW Honeypot Exporter started on port {args.port}")

    # 無限ループ
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        collector.geoip.close()

if __name__ == '__main__':
    main()
```

## Docker イメージ

### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# システム依存関係
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Python依存関係
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# アプリケーションコード
COPY exporter/ ./exporter/

# GeoIPディレクトリ作成
RUN mkdir -p /opt/geoip

# 非特権ユーザー
RUN useradd -m -u 1000 exporter && \
    chown -R exporter:exporter /app
USER exporter

EXPOSE 9150

ENTRYPOINT ["python", "-m", "exporter.main"]
```

### requirements.txt

```
prometheus-client==0.20.0
geoip2==4.7.0
maxminddb==2.6.2
```

## Terragrunt 設定

### terraform/envs/local/wow-exporter/terragrunt.hcl

```hcl
# WOW Honeypot Exporter Configuration

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/docker_container"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}

inputs = {
  network_name = dependency.network.outputs.network_name

  volumes = [
    "wow_logs",       # ログファイル保存用
    "wow_geoip_db"    # GeoIPデータベース
  ]

  services = {
    wow_exporter = {
      image = "wow-honeypot-exporter:latest"

      internal_port = 9150
      external_port = 9150

      command = [
        "--log-path=/logs",
        "--geoip-db=/geoip/GeoLite2-City.mmdb",
        "--port=9150"
      ]

      env = []

      volumes = [
        {
          source = "wow_logs"
          target = "/logs"
        },
        {
          source = "wow_geoip_db"
          target = "/geoip"
        }
      ]

      bind_mounts = []
    }
  }
}
```

## Prometheus 設定

### prometheus.yml への追加

```yaml
scrape_configs:
  # ... 既存の設定 ...

  - job_name: 'wow-honeypot-exporter'
    static_configs:
      - targets: ['wow_exporter:9150']
    scrape_interval: 30s
    scrape_timeout: 10s
```

## セットアップ手順

### 1. SSH鍵設定

```bash
# 自宅マシンで実行
ssh-keygen -t ed25519 -f ~/.ssh/vps_wow_honeypot -C "wow-honeypot-monitoring"

# 公開鍵をVPSに配置
ssh-copy-id -i ~/.ssh/vps_wow_honeypot.pub root@ik1-427-45900.vs.sakura.ne.jp

# ~/.ssh/configに追加
cat >> ~/.ssh/config <<EOF
Host vps-honeypot
    HostName ik1-427-45900.vs.sakura.ne.jp
    User root
    IdentityFile ~/.ssh/vps_wow_honeypot
    ServerAliveInterval 60
EOF
```

### 2. GeoIPデータベースのダウンロード

```bash
# MaxMindアカウント登録後、ライセンスキーを取得
# https://www.maxmind.com/en/geolite2/signup

# データベースダウンロード（手動）
wget "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz" \
  -O GeoLite2-City.tar.gz

tar -xzf GeoLite2-City.tar.gz
cp GeoLite2-City_*/GeoLite2-City.mmdb /opt/monitoring-lab/geoip/
```

### 3. Dockerイメージビルド

```bash
cd config/wow-exporter
docker build -t wow-honeypot-exporter:latest .
```

### 4. Terragrunt デプロイ

```bash
cd terraform/envs/local/wow-exporter
terragrunt apply
```

## 運用

### ログ同期の監視

```bash
# ログ同期の実行状況確認
tail -f /var/log/wow-log-sync.log

# 最後の同期時刻確認
ls -lh /opt/monitoring-lab/wow-logs/access_log
```

### メトリクス確認

```bash
# Exporterの動作確認
curl http://localhost:9150/metrics

# Prometheusでクエリ
# http://10.0.0.220:9090/graph
# wow_honeypot_requests_total
```

### GeoIPデータベース更新

月次でGeoIPデータベースを更新：

```bash
#!/bin/bash
# scripts/update-geoip-db.sh

LICENSE_KEY="YOUR_LICENSE_KEY"
DB_DIR="/opt/monitoring-lab/geoip"

wget "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${LICENSE_KEY}&suffix=tar.gz" \
  -O /tmp/GeoLite2-City.tar.gz

tar -xzf /tmp/GeoLite2-City.tar.gz -C /tmp
cp /tmp/GeoLite2-City_*/GeoLite2-City.mmdb ${DB_DIR}/

# Exporterを再起動
docker restart wow_exporter
```

## トラブルシューティング

### Exporterが起動しない

```bash
# ログ確認
docker logs wow_exporter

# ボリューム確認
docker volume inspect wow_logs
docker volume inspect wow_geoip_db
```

### メトリクスが更新されない

```bash
# ログファイルの存在確認
docker exec wow_exporter ls -lh /logs/

# パーサーのテスト
docker exec -it wow_exporter python -m exporter.parser
```

### GeoIP情報が取得できない

```bash
# データベース確認
docker exec wow_exporter ls -lh /geoip/

# 手動テスト
docker exec -it wow_exporter python -c "
from exporter.geoip import GeoIPResolver
resolver = GeoIPResolver('/geoip/GeoLite2-City.mmdb')
print(resolver.lookup('8.8.8.8'))
"
```
