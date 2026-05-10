# プロジェクト アーキテクチャ

**目的**: Terraform + Terragrunt + Vault を使用した学習用オブザーバビリティ基盤

## 稼働中サービス（リモート YOUR_SERVER_IP）

| サービス | ポート | URL / 認証 |
|---------|--------|-----------|
| Grafana | 3000 | http://YOUR_SERVER_IP:3000 (admin/admin) |
| Prometheus | 9090 | http://YOUR_SERVER_IP:9090 |
| Loki | 3100 | 内部のみ |
| cAdvisor | 8081 | http://YOUR_SERVER_IP:8081 |
| WOW Exporter | 9200 | http://YOUR_SERVER_IP:9200/metrics |
| Zabbix Web | 8080 | http://YOUR_SERVER_IP:8080 (Admin/zabbix) |
| Vault | 8200 | http://YOUR_SERVER_IP:8200 (token: root) |
| PostgreSQL | 5432 | 内部のみ |

## HCP Terraform

- Organization: `YOUR_TF_ORG`
- Workspace命名: `monitoring-lab-local-{service}`
- 8 Workspace すべて Local実行モード

## ディレクトリ構成

```
monitoring-lab-terraform/
├── terraform/
│   ├── root.hcl              # ルート設定（共通）
│   ├── modules/              # 再利用モジュール
│   └── envs/local/           # 環境別設定
│       ├── network/
│       ├── prometheus/
│       ├── grafana/
│       ├── loki/ promtail/
│       ├── cadvisor/
│       ├── wow-exporter/
│       └── zabbix/ vault/ postgres/ newrelic/
├── config/                   # サービス設定ファイル
│   ├── prometheus/           # prometheus.yml, alerts.yml
│   ├── grafana/provisioning/ # datasources, dashboards
│   ├── loki/ promtail/
│   └── wow-exporter/         # Pythonエクスポーター
└── .claude/
    ├── SESSION_STATE.md      # 作業継続用ステータス
    ├── skills/               # スキル定義
    ├── agents/               # サブエージェント
    └── docs/                 # このファイル等
```

## 現在のフェーズ

- **Phase 3**: IaC追跡完了（cAdvisor, Loki, Promtail, WOW Exporter）
- **保留中**: `backup/local-work-20260504` → `origin/master` マージ（自宅環境）
- **次**: Phase 4 運用改善（GitHub Actions, Alertmanager通知）
