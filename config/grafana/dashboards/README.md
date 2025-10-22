# Grafana ダッシュボード管理

このディレクトリには、Grafanaのダッシュボード定義（JSON）を配置します。

---

## 📁 ディレクトリ構成

```
config/grafana/
├── provisioning/
│   ├── datasources/
│   │   └── datasources.yml         # データソース自動登録（実装済み）
│   └── dashboards/
│       └── dashboards.yml          # ダッシュボードプロビジョニング設定
├── dashboards/                      # ダッシュボードJSON格納
│   ├── README.md                   # このファイル
│   ├── system-overview.json        # 例: システム概要ダッシュボード
│   ├── docker-monitoring.json      # 例: Docker監視ダッシュボード
│   └── zabbix-metrics.json         # 例: Zabbix連携ダッシュボード
└── plugins/                         # カスタムプラグイン（オプション）
```

---

## 🎨 ダッシュボード管理方針

### 基本方針: Web UIでの管理を推奨

- ✅ **作成・編集**: Grafana Web UI（http://YOUR_SERVER_IP:3000）
- ✅ **試行錯誤**: UI上で自由にカスタマイズ
- ✅ **バージョン管理**: 完成したらJSONエクスポート → Git管理

### Git管理が推奨されるダッシュボード

- 🔄 本番環境で使用する重要なダッシュボード
- 🔄 複数環境（dev/staging/prod）で共有するダッシュボード
- 🔄 チームで標準化したいダッシュボード
- 🔄 定期的に更新される標準テンプレート

### Git管理不要なダッシュボード

- 🚫 個人用の実験的ダッシュボード
- 🚫 一時的な調査用ダッシュボード
- 🚫 頻繁に変更されるダッシュボード

---

## 🚀 ダッシュボードのエクスポート手順

### ステップ1: Grafana Web UIでエクスポート

1. Grafana にログイン（http://YOUR_SERVER_IP:3000）
2. ダッシュボードを開く
3. 画面右上の **Share** → **Export** をクリック
4. **Save to file** をクリック
5. JSONファイルがダウンロードされる

### ステップ2: リポジトリに配置

```bash
# ダウンロードしたJSONをリポジトリに移動
cd /e/work/labo
mv ~/Downloads/system-overview.json config/grafana/dashboards/

# 可読性向上のため整形（オプション）
# jq コマンドが利用可能な場合
jq . config/grafana/dashboards/system-overview.json > temp.json
mv temp.json config/grafana/dashboards/system-overview.json
```

### ステップ3: Gitにコミット

```bash
git add config/grafana/dashboards/system-overview.json
git commit -m "Add: System overview dashboard"
```

---

## 📥 ダッシュボードのインポート手順

### 方法1: Web UIで手動インポート

1. Grafana にログイン
2. 左サイドバー **+** → **Import** をクリック
3. **Upload JSON file** で `system-overview.json` を選択
4. データソースを選択
5. **Import** をクリック

### 方法2: Provisioning機能で自動インポート

#### ステップ1: Provisioningディレクトリにコピー

```bash
# リモートサーバーに配置
scp config/grafana/dashboards/*.json \
  ubuntu@YOUR_SERVER_IP:/home/ubuntu/monitoring-lab/grafana/dashboards/
```

#### ステップ2: Provisioning設定ファイル作成

`config/grafana/provisioning/dashboards/dashboards.yml` を作成:

```yaml
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

#### ステップ3: Terragrunt設定を更新

`terraform/envs/local/grafana/terragrunt.hcl` に bind_mount を追加:

```hcl
bind_mounts = [
  {
    source    = "/home/ubuntu/monitoring-lab/grafana/provisioning"
    target    = "/etc/grafana/provisioning"
    read_only = true
  },
  # ダッシュボードディレクトリを追加
  {
    source    = "/home/ubuntu/monitoring-lab/grafana/dashboards"
    target    = "/var/lib/grafana/dashboards"
    read_only = true
  }
]
```

#### ステップ4: Grafanaを再起動

```bash
# Terragruntで反映
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose exec terragrunt sh"
cd /workspace/terraform/envs/local/grafana
terragrunt apply

# または、コンテナ再起動のみ
ssh ubuntu@YOUR_SERVER_IP
docker restart monitoring-lab-grafana
```

---

## 📋 ダッシュボードJSON編集のベストプラクティス

### 1. 環境依存情報の削除

エクスポートしたJSONには環境固有の情報が含まれるため、以下を削除/修正:

```json
{
  "id": null,              // ✅ null に設定（自動採番させる）
  "uid": "system-overview", // ✅ 一意のIDを設定
  "version": 0,            // ✅ 0 に設定
  "timezone": "browser",   // ✅ 環境依存を避ける
  // "gnetId": null,       // ✅ 削除してOK
  // 以下は保持
  "title": "System Overview",
  "tags": ["system", "overview"],
  "panels": [ ... ]
}
```

### 2. データソース参照の標準化

```json
// ❌ NG: 環境固有のID参照
"datasource": {
  "uid": "P1809F7CD0C75ACF3"
}

// ✅ OK: 名前参照（環境間で移植可能）
"datasource": {
  "type": "prometheus",
  "uid": "${DS_PROMETHEUS}"
}

// または
"datasource": "Prometheus"
```

### 3. 変数（Variables）の活用

```json
"templating": {
  "list": [
    {
      "name": "host",
      "type": "query",
      "datasource": "Prometheus",
      "query": "label_values(node_uname_info, instance)",
      "multi": true,
      "includeAll": true
    }
  ]
}
```

### 4. バージョン情報の記載

```json
{
  "title": "System Overview",
  "description": "System metrics dashboard\n\nVersion: 1.0.0\nAuthor: Your Name\nUpdated: 2025-10-19",
  "tags": ["system", "v1.0.0"]
}
```

---

## 🎨 推奨ダッシュボードテンプレート

### 1. System Overview Dashboard

**目的**: サーバー全体の状態を一目で把握

**主要パネル**:
- CPU使用率（時系列グラフ）
- メモリ使用率（ゲージ）
- ディスク使用率（バー）
- ネットワークトラフィック（時系列グラフ）
- プロセス数（Stat）
- システムアップタイム（Stat）

**データソース**: Prometheus (Node Exporter)

### 2. Docker Monitoring Dashboard

**目的**: Dockerコンテナの稼働状況監視

**主要パネル**:
- コンテナ一覧（Table）
- CPU使用率（時系列グラフ、コンテナ別）
- メモリ使用量（時系列グラフ、コンテナ別）
- ネットワークI/O（時系列グラフ）
- ディスクI/O（時系列グラフ）

**データソース**: Prometheus (cAdvisor)

### 3. Zabbix Integration Dashboard

**目的**: Zabbixで収集したメトリクスの可視化

**主要パネル**:
- アクティブアラート数（Stat）
- トリガー発火履歴（Table）
- ホストステータス（Status History）
- カスタムメトリクス（時系列グラフ）

**データソース**: Zabbix Plugin

---

## 🔧 ダッシュボード開発ワークフロー

### 開発フロー

```
1. Web UIでダッシュボード作成
   ↓
2. プレビュー・調整
   ↓
3. JSONエクスポート
   ↓
4. 環境依存情報を削除
   ↓
5. リポジトリにコミット
   ↓
6. Provisioningで自動デプロイ（オプション）
```

### チーム開発の場合

```
1. 担当者がブランチ作成
   ↓
2. Web UIでダッシュボード作成
   ↓
3. JSONエクスポート → Git Push
   ↓
4. Pull Request作成
   ↓
5. レビュー（スクリーンショット添付推奨）
   ↓
6. Merge → 本番環境にデプロイ
```

---

## 🐛 トラブルシューティング

### ダッシュボードがインポートできない

**エラー**: "Dashboard with the same UID already exists"

**解決策**:
```json
// JSONの uid を変更
{
  "uid": "system-overview-v2"  // 一意の値に変更
}
```

### データソースが見つからない

**エラー**: "Datasource 'Prometheus' not found"

**確認項目**:
1. データソースが登録されているか？
   - Configuration → Data sources で確認

2. データソース名が一致しているか？
   ```json
   "datasource": "Prometheus"  // 大文字小文字を確認
   ```

### Provisioningが動作しない

**確認項目**:
```bash
# Grafanaログ確認
docker logs monitoring-lab-grafana | grep -i provisioning

# ディレクトリマウント確認
docker exec monitoring-lab-grafana ls -la /etc/grafana/provisioning/dashboards/

# ファイル権限確認
ssh ubuntu@YOUR_SERVER_IP
ls -la ~/monitoring-lab/grafana/dashboards/
```

### パネルが表示されない

**確認項目**:
1. データソース接続状態
   - Configuration → Data sources → Test

2. クエリの確認
   - パネル編集 → Query Inspector

3. 時間範囲の確認
   - 右上の時間範囲選択を確認

---

## 📚 参考リソース

### Grafana公式ドキュメント
- [Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/json-model/)
- [Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/best-practices-for-creating-dashboards/)

### サンプルダッシュボード
- [Grafana Dashboard Gallery](https://grafana.com/grafana/dashboards/)
- [Node Exporter Full](https://grafana.com/grafana/dashboards/1860)
- [Docker Monitoring](https://grafana.com/grafana/dashboards/893)

### ツール
- [jq](https://stedolan.github.io/jq/) - JSON整形・検証ツール
- [Grafana Dashboard Linter](https://github.com/grafana/dashboard-linter) - ダッシュボード品質チェック

---

## 🔐 セキュリティ考慮事項

### 機密情報の除外

エクスポート前に以下を確認:

```bash
# ✅ OK: パブリックリポジトリでも問題なし
- ダッシュボードレイアウト
- パネル設定
- クエリ定義

# ❌ NG: 機密情報を含めない
- データソース認証情報（自動的に除外される）
- 実際のメトリクス値（スクリーンショットに注意）
- 内部ホスト名（変数化推奨）
```

### アクセス制御

```json
// ダッシュボードにアクセス権限を設定（Web UIで設定）
// JSONには含まれないため、環境ごとに再設定が必要
```

---

## 📝 ダッシュボードメタデータテンプレート

各ダッシュボードJSONに以下の情報を含めることを推奨:

```json
{
  "title": "System Overview",
  "description": "Overall system health monitoring dashboard\n\n**Version**: 1.0.0\n**Author**: Your Name\n**Created**: 2025-10-19\n**Updated**: 2025-10-19\n**Tags**: system, infrastructure\n**Data Sources**: Prometheus (Node Exporter)\n\n**Panels**:\n- CPU Usage\n- Memory Usage\n- Disk Usage\n- Network Traffic\n\n**Requirements**:\n- Node Exporter running on target hosts\n- Prometheus scraping Node Exporter metrics",
  "tags": ["system", "infrastructure", "v1.0.0"],
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "links": [],
  "liveNow": false,
  "panels": [ ... ]
}
```

---

## 🔄 バージョン管理のベストプラクティス

### セマンティックバージョニング

```
1.0.0 - 初版リリース
1.1.0 - パネル追加（後方互換あり）
1.1.1 - クエリ修正（バグフィックス）
2.0.0 - 大幅な変更（後方互換なし）
```

### CHANGELOG記載例

```json
{
  "description": "System Overview Dashboard\n\n**Changelog**:\n- v1.2.0 (2025-10-20): Add network traffic panel\n- v1.1.0 (2025-10-19): Add disk I/O metrics\n- v1.0.0 (2025-10-18): Initial release"
}
```

### Gitタグの活用

```bash
# ダッシュボードの重要バージョンをタグ付け
git tag -a dashboard-system-overview-v1.0.0 -m "System Overview Dashboard v1.0.0"
git push origin dashboard-system-overview-v1.0.0
```

---

**このディレクトリを活用して、効果的なダッシュボードを構築してください！**
