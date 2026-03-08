# 📖 Monitoring Lab — やさしい使い方ガイド

> このファイルは「プロジェクトを作りすぎて自分でも何を作ったか分からなくなった」ときのためのガイドです。
> 技術的な詳細は [README.md](README.md) を参照してください。

---

## 🗺️ まず全体像を把握しよう

```
あなたのPC (Windows)
│
├── WSL2 (Ubuntu-24.04) ← ここでDockerを動かす
│   └── Docker Engine
│       ├── Terragruntコンテナ  ← インフラを操作するツール
│       └── Vaultコンテナ      ← パスワード管理（開発用）
│
└── Claude Code (このツール)
    └── MCP Servers (3本) ← AIがインフラを"見る"ための目
        ├── docker-server       → リモートサーバーのコンテナを操作
        ├── prometheus-server   → メトリクスを取得・分析
        └── terragrunt-server   → インフラの変更を承認フローで実行

        ↕ SSH接続

リモートサーバー (YOUR_SERVER_IP) ← 実際に監視サービスが動いている場所
├── Grafana      :3000  ← ダッシュボード（まずここを見よう）
├── Prometheus   :9090  ← メトリクス収集エンジン
├── Zabbix Web   :8080  ← Zabbix監視画面
├── cAdvisor     :8081  ← コンテナのリソース監視
├── SNMP Exporter:9116  ← RTX830/SynologyのSNMP変換
├── Zabbix Server:10051 ← SwitchBot監視のバックエンド
├── Vault        :8200  ← パスワード管理（開発モード）
└── PostgreSQL   :5432  ← Zabbixのデータ保存
```

**監視対象（データを集めている機器）**:

| 機器 | 場所 | 何を監視？ |
|------|------|-----------|
| SwitchBot温湿度計 × 4 | 部屋各所 | 温度・湿度・バッテリー |
| Yamaha RTX830 | YOUR_ROUTER_IP | ネットワークトラフィック・リンク状態 |
| Synology NAS | YOUR_NAS_IP | CPU・ストレージ使用量 |
| Dockerコンテナ全部 | YOUR_SERVER_IP | CPU・メモリ・ネットワーク |
| Linux机 × 2 | YOUR_LINUX_HOST_1 / .254 | CPU・メモリ・ディスク |

---

## 🎯 今日やりたいことから探す（逆引き）

### 「ダッシュボードを見たい」

→ ブラウザで開くだけ。

```
Grafana   → http://YOUR_SERVER_IP:3000  (admin / admin)
Zabbix    → http://YOUR_SERVER_IP:8080  (Admin / zabbix)
Prometheus → http://YOUR_SERVER_IP:9090
```

---

### 「監視サービスが動いているか確認したい」

```bash
# リモートサーバーのコンテナ一覧
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker ps --format \"table {{.Names}}\t{{.Status}}\"'"
```

全部 `Up` になっていればOK。

---

### 「インフラに変更を加えたい（コンテナの設定を変えたいなど）」

**手順の全体像**:

```
1. terraform/envs/local/<サービス名>/terragrunt.hcl を編集
2. plan で差分を確認
3. apply で反映
```

**実際のコマンド**:

```bash
# 1. WSL2のDockerを起動（PC再起動後など）
wsl -d Ubuntu-24.04 -e bash -c "sudo service docker start"

# 2. 開発コンテナを起動
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d"

# 3. Terragruntコンテナに入る
wsl -d Ubuntu-24.04 -e bash -c "docker exec -it monitoring-lab-terragrunt sh"

# コンテナの中で:
cd /workspace/terraform/envs/local

# 差分確認（何が変わるか確認）
terragrunt run --all plan

# 反映
terragrunt run --all apply
```

---

### 「特定のサービスだけ更新したい」

```bash
# Terragruntコンテナの中で:
cd /workspace/terraform/envs/local/grafana   # ← サービス名を変える
terragrunt plan
terragrunt apply
```

サービス名一覧:
`network` / `postgres` / `vault` / `zabbix` / `zabbix-agent` / `prometheus` / `cadvisor` / `snmp-exporter` / `grafana` / `newrelic`

---

### 「Prometheusの設定を変えた（alerts.yml / prometheus.yml）」

設定ファイルはリポジトリ内で管理しているが、**リモートサーバーにも手動でコピーが必要**。

```bash
# ファイルをリモートサーバーにコピー
wsl -d Ubuntu-24.04 -e bash -c "scp /mnt/e/work/labo/config/prometheus/prometheus.yml ubuntu@YOUR_SERVER_IP:~/monitoring-lab/prometheus/"
wsl -d Ubuntu-24.04 -e bash -c "scp /mnt/e/work/labo/config/prometheus/alerts.yml ubuntu@YOUR_SERVER_IP:~/monitoring-lab/prometheus/"

# Prometheusに設定を再読み込みさせる
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'curl -s -X POST http://localhost:9090/-/reload'"
```

→ Prometheusは再起動不要でホットリロードできる。

---

### 「Grafanaのダッシュボードを追加・変更した」

```bash
# JSONファイルをリモートサーバーにコピー
wsl -d Ubuntu-24.04 -e bash -c "scp /mnt/e/work/labo/config/grafana/provisioning/dashboards/*.json ubuntu@YOUR_SERVER_IP:~/monitoring-lab/grafana/provisioning/dashboards/"

# Grafanaを再起動してプロビジョニングを反映
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker restart monitoring-lab-grafana'"
```

---

### 「Claude CodeのMCP機能を使いたい」

MCP Serversを使うと、Claude Codeがコンテナ状態の確認・メトリクスの取得・Terragruntの実行などを自律的にやってくれる。

詳細は [docs/mcp-servers.md](docs/mcp-servers.md) 参照。

---

## 🔴 「壊れた！」トラブルシューティング

### PC再起動後、何も動かない

**原因**: WSL2のDockerが停止している（毎回必要）。

```bash
wsl -d Ubuntu-24.04 -e bash -c "sudo service docker start"
```

---

### Terragruntコンテナが起動しない

**原因**: Vaultコンテナへの依存がある。

```bash
# Vaultを先に起動
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d vault"

# 少し待ってからTerragruntを起動
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d terragrunt"
```

---

### `terragrunt plan` でエラーが出る

```bash
# キャッシュを消す
wsl -d Ubuntu-24.04 -e bash -c "docker exec monitoring-lab-terragrunt sh -c 'rm -rf /workspace/terraform/envs/local/.terragrunt-cache'"

# 再初期化
wsl -d Ubuntu-24.04 -e bash -c "docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local && terragrunt run --all init'"
```

---

### Prometheusがデータを取れていない

1. `http://YOUR_SERVER_IP:9090/targets` を開く
2. 赤くなっているターゲットを確認
3. 原因に応じて対処:
   - `SNMP Exporter` 系: RTX830/SynologyへのSNMP疎通確認
   - その他: コンテナが動いているか確認

```bash
# ターゲット別の疎通確認
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'snmpwalk -v1 -c monlab YOUR_ROUTER_IP sysDescr.0'"    # RTX830
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'snmpwalk -v2c -c monlab YOUR_NAS_IP sysDescr.0'" # Synology
```

> ⚠️ RTX830はSNMP **v1のみ**対応。v2cはタイムアウトになるので注意。

---

### HCP Terraformで新しいWorkspaceを作ったら動かない

**原因**: 新規WorkspaceのデフォルトはRemote実行モード → Localに変更が必要。

```bash
# <workspace-name> を置き換えて実行
curl -X PATCH "https://app.terraform.io/api/v2/organizations/YOUR_TF_ORG/workspaces/<workspace-name>" \
  -H "Authorization: Bearer $TF_TOKEN_app_terraform_io" \
  -H "Content-Type: application/vnd.api+json" \
  --data '{"data":{"type":"workspaces","attributes":{"execution-mode":"local"}}}'
```

---

## 🗂️ ファイルの在り処（よく触るもの）

```
E:\work\labo\
├── GUIDE.md                        ← このファイル
├── README.md                       ← 技術的な詳細はこちら
├── docker-compose.yml              ← 開発コンテナ(Terragrunt/Vault)の定義
├── .env                            ← 各種トークン・パスワード（Gitに入れない）
│
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml          ← 「何を収集するか」の設定
│   │   └── alerts.yml              ← 「何を警告するか」の設定
│   ├── snmp/
│   │   └── snmp.yml                ← RTX830/SynologyのSNMP定義
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   └── datasources.yml ← GrafanaのデータソースUIDなど
│           └── dashboards/
│               ├── cadvisor.json          ← コンテナ監視ダッシュボード
│               ├── physical-devices.json  ← RTX830/NASダッシュボード
│               └── integrated-monitoring.json ← 総合ダッシュボード
│
├── terraform/
│   └── envs/local/
│       ├── prometheus/terragrunt.hcl  ← Prometheusコンテナの設定
│       ├── grafana/terragrunt.hcl     ← Grafanaコンテナの設定
│       └── ...（他サービスも同様）
│
├── mcp/
│   ├── docker-server/       ← Claude用: Dockerを操作するMCPサーバー
│   ├── prometheus-server/   ← Claude用: Prometheusのデータを取るMCPサーバー
│   └── terragrunt-server/   ← Claude用: Terragruntを実行するMCPサーバー
│
└── docs/
    ├── mcp-servers.md               ← MCP Serverの使い方リファレンス
    ├── monitoring-stack.drawio      ← 監視スタック構成図
    └── network-topology.drawio      ← ネットワーク構成図
```

---

## 🧩 各コンポーネントの役割（一言で）

| コンポーネント | 一言で言うと |
|-------------|------------|
| **Terragrunt** | 「Terraformをもっと便利にするラッパー」。複数サービスを一括で管理できる |
| **Terraform** | 「コードでインフラを定義する」ツール。`.hcl`ファイルに書いた通りにコンテナを作る |
| **HCP Terraform** | Terraformの「状態ファイル」をクラウドで管理するサービス。誰かが変更したかを追跡できる |
| **Vault** | パスワードやトークンを安全に管理するツール（今は開発モードで使用中） |
| **Prometheus** | 各サービスから数値データ（メトリクス）を定期的に収集してくる |
| **cAdvisor** | Dockerコンテナの「CPUとメモリを何%使っているか」をPrometheusに提供する |
| **SNMP Exporter** | RTX830やNASの「SNMP」データをPrometheusが読める形式に変換する |
| **Grafana** | 収集したデータをグラフや表にして見せてくれるダッシュボードツール |
| **Zabbix** | SwitchBotのAPIを呼んで温湿度データを収集する監視サーバー |
| **New Relic** | ホストOSとDockerの統合監視をクラウドで行う（再起動ループは既知の問題） |
| **MCP Server** | Claude Codeが「ツール」として使えるAPI。AIがインフラを直接操作できるようになる |

---

## 📊 現在の状態（2026-03-08時点）

### 動いているもの ✅

- 監視基盤10コンテナがリモートサーバー(YOUR_SERVER_IP)で稼働中
- Grafana ダッシュボード 3枚（cAdvisor / Physical Devices / Integrated）
- Prometheusアラートルール 6本（コンテナ・物理機器）
- SNMP監視: RTX830 + Synology NAS
- Node Exporter: YOUR_LINUX_HOST_1 + YOUR_LINUX_HOST_2（Linux機2台）
- MCP Servers 3本（Docker / Prometheus / Terragrunt）

### やっていないこと 📅

- Vaultの完全活用（現在は開発モードで「何でもできる」状態）
- CI/CD（GitHub Actions + Terragrunt）
- Windows Exporter（常時起動機がないため不要と判断）

---

## 💡 困ったときの判断フロー

```
問題発生
  │
  ├─ 「サービスにアクセスできない」
  │   → まずリモートサーバーのコンテナ状態を確認
  │     wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@YOUR_SERVER_IP 'docker ps'"
  │
  ├─ 「Terragruntコマンドが失敗する」
  │   → キャッシュを消してinitからやり直し
  │
  ├─ 「メトリクスが取れない」
  │   → http://YOUR_SERVER_IP:9090/targets でターゲット状態確認
  │
  └─ 「設定を変えたのに反映されない」
      → 設定ファイルをリモートにscpしてPrometheus/Grafanaをリロード
```

---

*このガイドは [SESSION_STATE.md](.claude/SESSION_STATE.md) と合わせて読むと、より詳細な経緯が分かります。*
