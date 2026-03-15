# Data Model: Alertmanager導入 — アラート通知基盤

**Phase**: 1 (Design)
**Date**: 2026-03-13

## エンティティ定義

### AlertmanagerConfig

Alertmanagerの設定全体を表すルートエンティティ。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| global | GlobalConfig | グローバル設定（タイムアウト等） |
| route | Route | ルートルーティングルール |
| receivers | Receiver[] | 通知レシーバーリスト |
| inhibit_rules | InhibitRule[] | 抑制ルールリスト |

### Route

アラートの振り分けルールを表す。ツリー構造で定義される。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| receiver | string | デフォルトレシーバー名 |
| group_by | string[] | グルーピングキー |
| group_wait | duration | グループ初回送信待機時間 |
| group_interval | duration | グループ更新通知間隔 |
| repeat_interval | duration | 繰り返し通知間隔（4h） |
| routes | Route[] | 子ルート（severity別） |
| match | map[string]string | マッチ条件（例: severity=critical） |

### Receiver

通知の送信先を表す。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| name | string | レシーバー識別名 |
| slack_configs | SlackConfig[] | Slack通知設定 |

### SlackConfig

Slack通知の詳細設定。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| api_url | string | Incoming Webhook URL（プレースホルダーで管理） |
| channel | string | 通知先チャンネル |
| title | string | メッセージタイトル（アラート名・重要度を含む） |
| text | string | メッセージ本文（summary/description） |
| color | string | サイドバー色（critical: danger/赤, warning: warning/黄） |
| send_resolved | bool | 解消通知の送信有無（true） |

### InhibitRule

アラート抑制ルール。上位のアラートが発火中は下位を抑制。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| source_match | map[string]string | 抑制元の条件（severity=critical） |
| target_match | map[string]string | 抑制対象の条件（severity=warning） |
| equal | string[] | 一致させるラベル（['alertname', 'job']） |

## 状態遷移

```
アラート状態遷移（Prometheus側）:
inactive → pending（for条件を満たすまで） → firing
firing → resolved（条件が解消）

Alertmanager処理:
firing受信 → グループ化（group_wait=30s待機） → Slack送信
firing継続 → 4時間毎に再通知（repeat_interval=4h）
resolved受信 → 解消通知を送信
```

## ファイル依存関係

```
config/alertmanager/
└── alertmanager.yml          ← 新規作成（routing + receivers + inhibit_rules）

config/prometheus/
└── prometheus.yml            ← 変更（alerting: セクション追加）

terraform/envs/local/alertmanager/
└── terragrunt.hcl            ← 新規作成

.env.example                  ← 変更（SLACK_WEBHOOK_URL を追加）
```
