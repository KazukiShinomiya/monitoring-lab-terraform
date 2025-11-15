# 🔄 セッション継続用ステータスファイル

**最終更新**: 2025-11-16 22:00
**プロジェクト**: Monitoring Lab - Terraform/Terragrunt監視基盤

---

## 💬 Claude Code作業時の必須ルール

**重要**: すべての作業で以下を厳守してください:

### 作業前の説明（必須）
- ツール実行前に必ず「何を」「なぜ」「何を確認するか」を説明
- コマンドだけを実行せず、目的と理由を明示
- 複数ステップの場合は全体の流れを先に説明

### 実行後の報告（必須）
- 成功: 何が確認できたか
- 失敗: 何が問題で、次にどうするか

詳細は `CLAUDE.md` の「コミュニケーションガイドライン」セクションを参照

---

## 📌 現在のプロジェクト状態

### ✅ 完了した作業

#### 2025-11-16 (1): 運用改善計画の策定とPhase 0完了 🚀

**実施内容**:
1. ✅ **運用面の脆弱性分析**
   - 8つの脆弱性領域を特定:
     1. データ管理・永続化（バックアップ戦略未定義）
     2. アラート・通知（通知先未設定）
     3. セキュリティ（パスワードハードコード、TLS未設定）
     4. 障害対応・DR（Runbook未整備）
     5. ログ管理（ローテーション設定なし）
     6. メンテナンス・更新（イメージ更新戦略なし）
     7. ドキュメント（運用マニュアル未整備）
     8. 監視カバレッジ（閾値未設定、ダッシュボード未作成）

2. ✅ **HCP Terraform + Agent + GitHub + GHA構成の評価**
   - **総合スコア: 9.5/10** ⭐⭐⭐⭐⭐
   - 8領域中7領域を根本的に解決する優れた提案と評価
   - 無料プランで実現可能（学習用途に最適）
   - 本番環境への移行パスが明確
   - 現代的なIaC運用のベストプラクティス

3. ✅ **段階的導入計画の策定**
   - 15個の独立したタスクに分割（各15-30分）
   - 4つのPhaseで構成（Phase 0-4）
   - 総所要時間: 8-12時間（複数日に分散可能）

4. ✅ **Phase 0-1: Git管理の準備完了**
   - `.gitignore`にHCP Terraform認証情報の除外ルール追加
   - `.gitignore`にGitHub Actions関連ファイルの除外ルール追加
   - 機密情報の除外確認（.env, .tfstate）
   - コミット完了（コミットID: 4564157）

**技術的知見**:
- **運用の堅牢性**: IaCだけでなく、State管理、変更管理、監査ログが重要
- **HCP Terraform Free プラン**: 500 states まで無料、学習用途に十分
- **GitHub Actions**: 2,000分/月 無料（Public repoは無制限）
- **Terraform Agent**: Self-hosted Agentは無料（プライベートネットワーク内実行）
- **セキュリティ**: `.terraform.d/credentials.tfrc.json` は絶対にコミットしない

**追加された.gitignore保護機能**:
```gitignore
# HCP Terraform / Terraform Cloud
.terraform.d/credentials.tfrc.json
.terraformrc
credentials.tfrc.json
terraform.rc

# GitHub Actions関連
.github/workflows/*.local.yml
.actrc
.secrets
.runner/
```

**次回のアクション（Phase 1-1）**:
- [ ] HCP Terraformアカウント作成（所要時間: 15分）
  - https://app.terraform.io/signup/account にアクセス
  - メールアドレス、ユーザー名、パスワードを入力
  - メール認証
  - 無料プラン（Free）を選択

**全体ロードマップ**:
```
Phase 0: 準備 ✅ 完了
Phase 1: HCP Terraform導入（5タスク、2-3時間）← 次回ここから
Phase 2: GitHub連携（3タスク、1-2時間）
Phase 3: GitHub Actions導入（4タスク、2-3時間）
Phase 4: Terraform Agent導入（2タスク、2-3時間）
```

**修正ファイル**:
- `.gitignore` (HCP Terraform/GHA対応)

**評価**:
- ✅ 運用の問題を正しく認識
- ✅ HCP Terraform + Agent + GitHub + GHAの組み合わせは最適解
- ✅ 段階的アプローチで学習負荷を軽減
- ✅ 無料で実現可能
- ✅ 本番環境にも適用可能な設計

---

#### 2025-11-03 (1): SwitchBot外部スクリプト監視のZabbixアイテム設定完了 🎉

**実施内容**:
1. ✅ **全4台のSwitchBotデバイスのアイテム作成**
   - 温湿度計Pro 2F (B0E9FEEDD228): 親アイテム + 依存アイテム3つ（温度、湿度、バッテリー）
   - Hub 3 (2E) (B0E9FE8AEC2E): 親アイテム + 依存アイテム4つ（温度、湿度、照度、人感）
   - ベランダ (D40E84864C41): 親アイテム + 依存アイテム3つ（温度、湿度、バッテリー）
   - 防水温湿度計 外 (F2B200461F1A): 親アイテム + 依存アイテム3つ（温度、湿度、バッテリー）
   - **合計17アイテム**（親4 + 依存13）

2. ✅ **親アイテム（External Check）の設定**
   - Type: External check
   - Key: `check_switchbot.py[デバイスID]`
   - Type of information: Text（JSON全体を保存）
   - Update interval: 5m（APIレート制限対策）

3. ✅ **依存アイテム（Dependent Items）の設定**
   - 一意のキー命名規則: `switchbot.メトリクス名[デバイスID]`
   - JSONPath Preprocessingで個別メトリクスを抽出
   - 温度: Numeric (float), Units: °C
   - 湿度: Numeric (unsigned), Units: %
   - バッテリー: Numeric (unsigned), Units: %
   - 照度: Numeric (unsigned), Units: lux（Hub 3のみ）
   - 人感: Numeric (unsigned), 0/1（Hub 3のみ）

4. ✅ **Hub 3人感センサーのBoolean型対応**
   - 問題: `moveDetected` が `true`/`false` 文字列で返される
   - エラー: "Value of type "string" is not suitable for value type "Numeric (unsigned)""
   - 解決策: Preprocessing に "Boolean to decimal" ステップを追加
   - 結果: `true` → `1`, `false` → `0` に自動変換

5. ✅ **全アイテムの動作確認**
   - Latest dataで全17アイテムのデータ取得成功
   - グラフ表示正常動作
   - ダッシュボード表示確認完了
   - エラーなし

**技術的知見**:
- **Zabbixアイテム設計パターン**: 親アイテム（External Check, Text型）+ 依存アイテム（Dependent Items, Numeric型）
- **キーの一意性**: ホスト内で一意である必要があるため、`switchbot.メトリクス名[デバイスID]` 形式を採用
- **Boolean型変換**: ZabbixはBoolean型を直接サポートしないため、Preprocessing "Boolean to decimal" で数値変換が必須
- **APIレート制限**: SwitchBot APIは10,000回/日の制限があるため、Update interval 5分以上を推奨
  - 4台の場合: 288回/日/台 × 4台 = 1,152回/日（制限内）

**設定完了アイテム一覧**:
```
【温湿度計Pro 2F】
- check_switchbot.py[B0E9FEEDD228]
- switchbot.temperature[B0E9FEEDD228]
- switchbot.humidity[B0E9FEEDD228]
- switchbot.battery[B0E9FEEDD228]

【Hub 3 (2E)】
- check_switchbot.py[B0E9FE8AEC2E]
- switchbot.temperature[B0E9FE8AEC2E]
- switchbot.humidity[B0E9FE8AEC2E]
- switchbot.lightlevel[B0E9FE8AEC2E]
- switchbot.movedetected[B0E9FE8AEC2E]

【ベランダ】
- check_switchbot.py[D40E84864C41]
- switchbot.temperature[D40E84864C41]
- switchbot.humidity[D40E84864C41]
- switchbot.battery[D40E84864C41]

【防水温湿度計 外】
- check_switchbot.py[F2B200461F1A]
- switchbot.temperature[F2B200461F1A]
- switchbot.humidity[F2B200461F1A]
- switchbot.battery[F2B200461F1A]
```

**動作確認結果**:
```
✅ 全4台の親アイテムが正常動作（5分間隔でデータ取得）
✅ 全13個の依存アイテムが正常動作（JSONPathで抽出成功）
✅ Latest dataで全メトリクス表示確認
✅ グラフ表示正常（温度、湿度、バッテリー、照度、人感）
✅ ダッシュボードで各値の表示確認
✅ エラー・警告なし
```

**次回のアクション**:
- [ ] トリガー設定（温度/湿度の閾値アラート、バッテリー低下アラート）
  - 例: 温度30°C以上で高温警告、5°C以下で低温警告
  - 例: 湿度80%以上で高湿度警告
  - 例: バッテリー20%以下でバッテリー交換警告
- [ ] ダッシュボードのカスタマイズ
  - 全デバイスの温度を1つのグラフで比較
  - 室内 vs 屋外の温度差グラフ
  - バッテリー残量の一覧表示
- [ ] アラート通知の設定（メール、Slack、Webhook等）
- [ ] Prometheusターゲット設定の有効化
- [ ] Grafanaダッシュボードの作成

**関連ドキュメント**:
- `config/zabbix/scripts/externalscripts/README_SWITCHBOT.md` - セットアップ手順
- Zabbix Web UI設定は手動管理（IaCの対象外）

#### 2025-11-02 (1): New Relic Infrastructure Agent統合完了 🎉

**実施内容**:
1. ✅ **docker_containerモジュールの拡張**
   - `terraform/modules/docker_container/variables.tf` に以下のパラメータを追加:
     - `privileged` (bool): 特権モード設定（デフォルト: false）
     - `network_mode` (string): ネットワークモード設定（host/bridge/none）
   - `terraform/modules/docker_container/main.tf` でパラメータの適用を実装:
     - `privileged = each.value.privileged`
     - `network_mode = each.value.network_mode`
     - `networks_advanced` と `ports` を動的ブロック化（network_mode="host"時は不要）

2. ✅ **New Relic用Terragrunt設定の作成**
   - `terraform/envs/local/newrelic/terragrunt.hcl` を新規作成
   - Infrastructure Agent設定:
     - イメージ: `newrelic/infrastructure:latest`
     - 特権モード: `privileged = true` (ホストメトリクス取得に必須)
     - ネットワークモード: `network_mode = "host"` (ホストレベル監視に推奨)
     - Bind mounts: `/proc`, `/sys`, `/etc`, `/var/log`, `/var/run/docker.sock`
     - 環境変数: `NRIA_LICENSE_KEY`, `NRIA_DISPLAY_NAME`, `NRIA_LOG_LEVEL`

3. ✅ **環境変数設定の追加**
   - `.env.example` に New Relic設定を追加:
     - `NEW_RELIC_LICENSE_KEY`: Ingest License Key
     - `NEW_RELIC_ACCOUNT_ID`: アカウントID（オプション）
     - `NEW_RELIC_REGION`: リージョン設定（US/EU）
     - `NEW_RELIC_DISPLAY_NAME`: エージェント表示名
   - `docker-compose.yml` に環境変数を追加（Terragruntコンテナ用）

4. ✅ **デプロイとトラブルシューティング**
   - 問題1: ライセンスキー認証エラー（401 Unauthorized）
     - 原因: 環境変数がコンテナに反映されていなかった
     - 解決策: terragrunt.hclに直接ライセンスキーを設定
   - 問題2: 最初のライセンスキーが無効
     - 原因: User API Keyを使用していた（Ingest License Keyが必要）
     - 解決策: 正しいIngest License Keyを取得・設定
   - デプロイ成功: `terragrunt apply -auto-approve`

5. ✅ **動作確認**
   - コンテナ起動: `monitoring-lab-newrelic-infra` (Up, healthy)
   - New Relic接続成功: `agent-id=3045931572010061140`
   - ログにエラーなし、正常にメトリクス送信開始
   - 既存の監視基盤（Zabbix、Prometheus、Grafana）との共存確認

**技術的知見**:
- New Relic Infrastructure Agentには**Ingest License Key**が必要（User API Keyではない）
- 特権モード(`privileged: true`)がないとホストメトリクスを取得できない
- `network_mode: host`を使用することで、ホストレベルの詳細な監視が可能
- Docker Socketをマウントすることで、コンテナ監視も同時に実現
- `/proc`, `/sys`, `/etc`のマウントにより、ホストOSの詳細情報を取得

**デプロイ結果**:
```
✅ monitoring-lab-newrelic-infra (Up, healthy)
✅ New Relic Platform接続成功 (agent-id: 3045931572010061140)
✅ ホストメトリクス収集開始
✅ Dockerコンテナ監視機能有効化
✅ 既存監視基盤（Zabbix、Prometheus、Grafana）との共存確認
```

**修正・新規作成ファイル**:
- `terraform/modules/docker_container/variables.tf` (修正: privileged, network_mode追加)
- `terraform/modules/docker_container/main.tf` (修正: 動的ブロック化)
- `terraform/envs/local/newrelic/terragrunt.hcl` (新規作成)
- `.env.example` (修正: New Relic設定追加)
- `docker-compose.yml` (修正: 環境変数追加)

**次回のアクション**:
- [x] Dockerコンテナ監視ダッシュボード確認 ✅ (2025-11-02 (2)で解決)
- [ ] New Relic UIでホストメトリクス確認（CPU、メモリ、ディスク、ネットワーク）
- [ ] アラート設定の検討（しきい値ベースアラート）
- [ ] APM統合の検討（アプリケーション監視が必要な場合）

#### 2025-11-02 (2): New Relic Docker統合の完全解決 🎉

**実施内容**:

**第1フェーズ: Docker統合フィーチャーフラグの追加**
1. ✅ **初期問題の調査**
   - ユーザー報告: 「エージェント以外のコンテナのメトリクスの情報はすべて０になっています」
   - New Relic UIでエージェントコンテナのみメトリクス収集、他のコンテナは0
   - 監視対象: Zabbix、Prometheus、Grafana、PostgreSQL、Vault等の8コンテナ

2. ✅ **第1の原因特定**
   - コンテナログ分析: `Integration feature not enabled, skipping execution`
   - Docker統合のフィーチャーフラグ `NRIA_FEATURE_docker_enabled=true` が欠けていた

3. ✅ **第1の修正実施**
   - `terraform/envs/local/newrelic/terragrunt.hcl` に環境変数追加:
     ```hcl
     "NRIA_FEATURE_docker_enabled=true"
     ```
   - コンテナ再作成、統合ヘルスチェック成功を確認

**第2フェーズ: cgroup v2問題の解決（根本原因）**
4. ✅ **継続する問題の発見**
   - ユーザー報告: 「よく見たらmonitoring-lab-newrelic-infra以外は今も０でした」
   - nri-dockerバイナリを直接実行してテスト
   - エラー発見: `fetching metrics for container: no such file or directory`
   - cgroupパス問題を特定: `/host/sys/fs/docker-*.scope/cgroup.controllers`

5. ✅ **根本原因の特定**
   - リモートサーバーがcgroup v2 + systemd cgroupドライバーを使用
   - cgroupパスが `/sys/fs/cgroup/system.slice/docker-*.scope/` に存在
   - New Relicコンテナがcgroup namespaceで分離されており、ホストのcgroupにアクセス不可
   - **公式要件**: cgroup v2環境では `--cgroupns=host` フラグが必須

6. ✅ **docker_containerモジュールの拡張**
   - `terraform/modules/docker_container/variables.tf` を修正:
     ```hcl
     cgroupns_mode = optional(string, "")  # Cgroup Namespaceモード（host/private）
     ```
   - `terraform/modules/docker_container/main.tf` を修正:
     ```hcl
     cgroupns_mode = each.value.cgroupns_mode != "" ? each.value.cgroupns_mode : null
     ```

7. ✅ **New Relic設定の修正**
   - `terraform/envs/local/newrelic/terragrunt.hcl` を修正:
     ```hcl
     # Cgroup Namespaceモード: cgroup v2でホストのcgroupにアクセスするために必須
     cgroupns_mode = "host"
     ```

8. ✅ **最終デプロイと動作確認**
   - コンテナ削除: `terragrunt destroy -auto-approve`
   - 新設定でコンテナ作成: `terragrunt apply -auto-approve`
   - cgroupns_mode=hostの設定確認: `docker inspect` で検証
   - nri-dockerの直接実行テスト:
     - エラーメッセージ完全消滅
     - 全コンテナのメトリクス収集成功
   - ユーザー最終確認: **「無事にすべてのコンテナのメトリクスが確認できました」**

**技術的知見**:
- New Relic Infrastructure Agent v1.71.0のDocker統合には3つの設定が必要:
  1. `NRIA_ENABLE_PROCESS_METRICS=true` - プロセスメトリクス有効化
  2. `NRIA_FEATURE_docker_enabled=true` - Docker統合フィーチャーフラグ
  3. `cgroupns_mode = "host"` - **cgroup v2環境で必須**（最重要！）
- cgroup v2 + systemd cgroupドライバーの組み合わせでは、cgroupパスが `/sys/fs/cgroup/system.slice/` 配下に配置される
- デフォルトのcgroup namespace分離では、コンテナはホストのcgroupにアクセスできない
- `--cgroupns=host`（Terraformでは`cgroupns_mode = "host"`）により、コンテナがホストのcgroup namespaceを使用
- この設定により、nri-dockerが `/sys/fs/cgroup/system.slice/docker-*.scope/` のメトリクスにアクセス可能に

**デプロイ結果**:
```
✅ monitoring-lab-newrelic-infra (Up, healthy)
✅ cgroupns_mode=host 設定成功
✅ Docker統合が正常動作 (nri-docker integration health check success)
✅ 全8コンテナのメトリクス収集成功:
   - monitoring-lab-newrelic-infra
   - monitoring-lab-zbx_server (CPU, メモリ, ネットワーク, スレッド数 すべて収集)
   - monitoring-lab-zbx_web
   - monitoring-lab-zbx_agent
   - monitoring-lab-grafana
   - monitoring-lab-prometheus
   - monitoring-lab-vault
   - monitoring-lab-postgres
✅ New Relic UIですべてのコンテナが表示され、実際のメトリクス値を確認
```

**修正ファイル**:
- `terraform/modules/docker_container/variables.tf` (新規: cgroupns_modeパラメータ追加)
- `terraform/modules/docker_container/main.tf` (新規: cgroupns_mode適用)
- `terraform/envs/local/newrelic/terragrunt.hcl` (修正: NRIA_FEATURE_docker_enabled=true追加、cgroupns_mode="host"設定)

**次回のアクション**:
- [x] すべてのコンテナ（8台）がNew Relic UIに表示されるか最終確認 ✅ 完了
- [x] 各コンテナのCPU、メモリ、ネットワークメトリクスを確認 ✅ 完了
- [ ] New Relic UIでのダッシュボード作成・カスタマイズ（オプション）
- [ ] アラート設定の検討（オプション）

#### 2025-10-30 (2): SwitchBot外部スクリプト監視の設定準備完了 🎯

**実施内容**:
1. ✅ **SwitchBotデバイス一覧の取得**
   - APIを使用して全デバイスを確認
   - 監視対象デバイス: 4台
     - 温湿度計Pro 2F (B0E9FEEDD228) - MeterPro
     - Hub 3 (2E) (B0E9FE8AEC2E) - Hub 3（温湿度センサー内蔵）
     - ベランダ (D40E84864C41) - WoIOSensor
     - 防水温湿度計 外 (F2B200461F1A) - WoIOSensor

2. ✅ **check_switchbot.py スクリプトのHub 3対応修正**
   - 問題: Hub 3にはbatteryフィールドがない（AC電源駆動）
   - 解決策: スクリプトを修正して以下を実装
     - `battery` フィールドをオプショナルに変更
     - `lightLevel` フィールドを追加（Hub 3の照度センサー）
     - `moveDetected` フィールドを追加（Hub 3の人感センサー）
     - `device_type` フィールドを追加（デバイス識別用）
   - 修正箇所: 101-128行目（必須フィールドチェックとオプショナルフィールド処理）

3. ✅ **全4台でのデータ取得テスト成功**
   - 温湿度計Pro 2F: 温度21.7°C, 湿度51%, バッテリー100%
   - Hub 3 (2E): 温度25.6°C, 湿度55%, 照度4, 人感検知中
   - ベランダ: 温度15.4°C, 湿度68%, バッテリー60%
   - 防水温湿度計 外: 温度9°C, 湿度93%, バッテリー60%

4. ✅ **Zabbix Web UIでの基本設定**
   - ホストグループ `SwitchBot` を作成
   - ホスト `SwitchBot Devices` を作成
   - アイテム設計の理解確認（親アイテム + 依存アイテム構造）

**技術的知見**:
- Zabbixのアイテム設計: 親アイテム（External Check, Text型）+ 依存アイテム（Dependent Items, Numeric型）
- 親アイテム: JSONデータを丸ごと取得（1回のAPI呼び出し）
- 依存アイテム: JSONから個別の値を抽出してグラフ化・アラート設定
- Hub 3はAC電源駆動のため、batteryフィールドが存在しない
- Hub 3には温湿度センサーに加えて照度センサー・人感センサーも内蔵

**修正ファイル**:
- `config/zabbix/scripts/externalscripts/check_switchbot.py` (修正)

**次回のアクション**:
- [ ] External Checkアイテムを作成（温湿度計Pro 2Fから開始）
  - Name: `SwitchBot Raw Data [温湿度計Pro 2F]`
  - Type: External check
  - Key: `check_switchbot.py[B0E9FEEDD228]`
  - Type of information: Text
  - Update interval: 5m
- [ ] Dependent Items作成（温湿度計Pro 2F用）
  - 温度 (temperature) - Numeric (float)
  - 湿度 (humidity) - Numeric (unsigned)
  - バッテリー (battery) - Numeric (unsigned)
- [ ] 1台目のデータ取得確認とグラフ表示テスト
- [ ] 残り3台も同様に設定
  - Hub 3: 温度、湿度、照度、人感の4つの依存アイテム
  - ベランダ: 温度、湿度、バッテリーの3つの依存アイテム
  - 防水温湿度計 外: 温度、湿度、バッテリーの3つの依存アイテム
- [ ] トリガー設定（温度/湿度の閾値アラート、バッテリー低下アラート）

**デバイス一覧（参考）**:
```
1. 温湿度計Pro 2F - B0E9FEEDD228 (MeterPro)
2. Hub 3 (2E) - B0E9FE8AEC2E (Hub 3)
3. ベランダ - D40E84864C41 (WoIOSensor)
4. 防水温湿度計 外 - F2B200461F1A (WoIOSensor)
```

#### 2025-10-30 (1): Zabbix Serverデータベース接続問題の完全解決 🎉

**実施内容**:
1. ✅ **問題の診断**
   - Zabbix Serverにログインできるがメトリクスが取得できない問題を調査
   - ログ確認により、PostgreSQLデータベース接続エラーを発見
   - エラー内容: `connection to database 'dummy_db_name' failed`

2. ✅ **根本原因の特定**
   - 原因1: 環境変数 `ZBX_DB_NAME` が未設定
     - `POSTGRES_DB=zabbix` は設定されていたが、Zabbix Server自身が参照する `ZBX_DB_NAME` が欠けていた
     - デフォルト値 `dummy_db_name` で接続しようとして失敗
   - 原因2: カスタムエントリーポイントの実装ミス
     - 初期化スクリプトが直接 `zabbix_server` を起動していた
     - 公式エントリーポイント処理（環境変数→設定ファイル反映）がスキップされていた

3. ✅ **Terragrunt設定の修正**
   - `terraform/envs/local/zabbix/terragrunt.hcl` を修正:
     - Zabbix Server用環境変数に `ZBX_DB_NAME=zabbix` を追加
     - Zabbix Web用環境変数に `ZBX_DB_NAME=zabbix` を追加

4. ✅ **エントリーポイントスクリプトの修正**
   - `/home/ubuntu/monitoring-lab/zabbix/scripts/init-zabbix-server.sh` を修正:
     - 修正前: `exec /usr/sbin/zabbix_server --foreground -c /etc/zabbix/zabbix_server.conf`
     - 修正後: `exec /usr/bin/docker-entrypoint.sh /usr/sbin/zabbix_server --foreground -c /etc/zabbix/zabbix_server.conf`
   - 公式エントリーポイント経由で起動することで、環境変数が正しく反映されるように変更

5. ✅ **デプロイと動作確認**
   - Zabbix Serverコンテナの再作成成功
   - PostgreSQL接続成功を確認
   - 全59個のサーバープロセスが正常起動
   - Zabbix Agentからのメトリクス収集開始を確認
   - Web UIでリアルタイムデータ表示を確認（CPU使用率、メモリ使用量など）

**技術的知見**:
- Zabbix Serverの環境変数:
  - `POSTGRES_DB`: PostgreSQL側の設定
  - `ZBX_DB_NAME`: Zabbix Server自身が使用するデータベース名（**必須**）
- 公式Dockerイメージのエントリーポイント:
  - `/usr/bin/docker-entrypoint.sh` が環境変数を設定ファイルに反映する処理を行う
  - カスタム初期化処理を行う場合でも、最終的には公式エントリーポイントを呼び出す必要がある

**デプロイ結果**:
```
✅ Zabbix Serverが正常にPostgreSQLに接続
✅ 全59個のサーバープロセスが起動
✅ Zabbix Agentからのメトリクス収集が開始
✅ Web UIでリアルタイムデータ表示を確認
✅ 監視基盤が完全に稼働
```

**次回のアクション**:
- [ ] SwitchBot外部スクリプト監視のアイテム設定（Zabbix Web UI）
- [ ] Prometheusターゲット設定の有効化
- [ ] Grafanaダッシュボードの作成

**関連ファイル**:
- `terraform/envs/local/zabbix/terragrunt.hcl` (修正)
- `/home/ubuntu/monitoring-lab/zabbix/scripts/init-zabbix-server.sh` (修正)

#### 2025-10-26 (1): SwitchBot外部スクリプト監視のセットアップ完了 🎉

**実施内容**:
1. ✅ **SwitchBot温湿度計監視スクリプトの作成**
   - `config/zabbix/scripts/externalscripts/check_switchbot.py` を作成
   - SwitchBot API (v1.1) を使用した温度・湿度・バッテリー取得
   - JSON形式でのデータ出力（Zabbix Dependent Items対応）
   - エラーハンドリングと終了コード実装 (0=成功, 1=エラー, 2=設定エラー, 3=APIエラー)

2. ✅ **Zabbix Server初期化スクリプトの作成**
   - `config/zabbix/scripts/init-zabbix-server.sh` を作成
   - Python3とpip3の自動インストール
   - requestsライブラリの自動インストール
   - 外部スクリプトの実行権限設定

3. ✅ **Dockerモジュールの拡張**
   - `terraform/modules/docker_container/variables.tf` に `entrypoint` と `user` パラメータを追加
   - `terraform/modules/docker_container/main.tf` で entrypoint と user の適用を実装

4. ✅ **Terragrunt設定の更新**
   - `terraform/envs/local/zabbix/terragrunt.hcl`:
     - entrypoint設定: `/home/ubuntu/monitoring-lab/zabbix/scripts/init-zabbix-server.sh`
     - user設定: `root` (パッケージインストールのため)
     - 環境変数追加: `SWITCHBOT_TOKEN`, `SWITCHBOT_SECRET`, `SWITCHBOT_TIMEOUT`
     - bind_mount設定:
       - init-zabbix-server.sh (read-only)
       - externalscripts/ (read-write)
       - alertscripts/ (read-write)
   - `terraform/root.hcl`:
     - 環境変数注入: `SWITCHBOT_TOKEN`, `SWITCHBOT_SECRET` を get_env() で取得

5. ✅ **リモート配置スクリプトの更新**
   - `scripts/setup-remote-config.sh` を更新:
     - Zabbix外部スクリプト用ディレクトリ作成 (externalscripts/, alertscripts/, userparameters/)
     - check_switchbot.py の自動転送
     - init-zabbix-server.sh の自動転送
     - 実行権限の自動付与

6. ✅ **環境変数設定の追加**
   - `.env.example` に SwitchBot API認証情報を追加
   - `.env` ファイルの作成と確認

7. ✅ **デプロイとトラブルシューティング**
   - 問題1: Terragrunt変数参照エラー (`${SWITCHBOT_TOKEN}`)
     - 解決策: `get_env("SWITCHBOT_TOKEN", "default")` に修正
   - 問題2: 権限エラー (apk add が Permission denied)
     - 解決策: Zabbix Serverコンテナを `user = "root"` で起動
   - Zabbix Serverコンテナの再作成成功
   - Python3/requests の自動インストール成功
   - Zabbix Serverの正常起動確認

8. ✅ **ドキュメント作成**
   - `config/zabbix/scripts/externalscripts/README_SWITCHBOT.md` を作成
     - セットアップ手順の詳細
     - Zabbix Web UIでの設定方法
     - トラブルシューティングガイド
     - 終了コード一覧
     - パフォーマンス考慮事項（APIレート制限）

**技術的知見**:
- Zabbix External Checksは `/usr/lib/zabbix/externalscripts/` にスクリプトを配置
- Python依存関係のインストールにはroot権限が必要（`apk add`, `pip3 install`）
- Terragruntの環境変数参照は `get_env()` 関数を使用（`${VAR}` は不可）
- Alpine LinuxのPython3.12では `--break-system-packages` オプションが必要
- Dockerモジュールの `entrypoint` と `user` パラメータで初期化スクリプトを実行可能

**デプロイ結果**:
```
✅ check_switchbot.py → /home/ubuntu/monitoring-lab/zabbix/scripts/externalscripts/
✅ init-zabbix-server.sh → /home/ubuntu/monitoring-lab/zabbix/scripts/
✅ Python3 + pip3 自動インストール成功
✅ requests パッケージ自動インストール成功
✅ Zabbix Serverコンテナ正常起動
✅ 環境変数 (SWITCHBOT_TOKEN/SECRET) 正常注入
```

**動作確認結果**:
- ✅ スクリプト配置確認完了
- ✅ Python環境確認完了（Python 3.12.12 + requests 2.32.5）
- ✅ 環境変数確認完了（SWITCHBOT_TOKEN, SWITCHBOT_SECRET, SWITCHBOT_TIMEOUT）
- ✅ 2台の温湿度計からデータ取得成功:
  - 温湿度計Pro 2F (B0E9FEEDD228): 温度23.1°C, 湿度60%, バッテリー100%
  - 防水温湿度計 外 (F2B200461F1A): 温度15.8°C, 湿度96%, バッテリー60%

**次回のアクション**:
- [ ] Zabbix Web UIで External Check アイテム作成
  - デバイスID: B0E9FEEDD228（温湿度計Pro 2F）
  - デバイスID: F2B200461F1A（防水温湿度計 外）
- [ ] Dependent Items で温度・湿度・バッテリーを個別取得
- [ ] トリガー設定（温度/湿度の閾値アラート）
- [ ] 更新間隔の調整（APIレート制限を考慮: 推奨5分以上）

**関連ファイル**:
- `config/zabbix/scripts/externalscripts/check_switchbot.py` (新規作成)
- `config/zabbix/scripts/init-zabbix-server.sh` (新規作成)
- `config/zabbix/scripts/externalscripts/README_SWITCHBOT.md` (新規作成)
- `terraform/modules/docker_container/variables.tf` (修正)
- `terraform/modules/docker_container/main.tf` (修正)
- `terraform/envs/local/zabbix/terragrunt.hcl` (修正)
- `terraform/root.hcl` (修正)
- `scripts/setup-remote-config.sh` (修正)
- `.env.example` (修正)

#### 2025-10-22 (1): Zabbix Agent2監視の有効化成功 🎉

**実施内容**:
1. ✅ **Zabbix Agent監視問題の調査**
   - 「Zabbix agent is not available (for 3m)」警告の原因調査
   - Zabbix Serverコンテナ内にAgent2が含まれていないことを再確認
   - Zabbix Agent2コンテナは既にデプロイ済みで正常稼働中

2. ✅ **Docker内部DNSの仕組み確認**
   - `zbx_agent` で名前解決できることを確認
   - Terraformの `docker_container` モジュールで `aliases = [each.key]` 設定を確認
   - フルコンテナ名（`monitoring-lab-zbx_agent`）とエイリアス名（`zbx_agent`）の両方で解決可能

3. ✅ **ネットワーク接続の確認**
   - Zabbix ServerからAgent2への接続テスト成功（172.28.0.8:10050）
   - 同一Dockerネットワーク（monitoring-lab-network）で通信可能

4. ✅ **問題の原因特定**
   - Zabbix Web UIのホスト設定で、Agentのインターフェースが正しく設定されていなかった
   - おそらく `127.0.0.1` を指していたため、Agent2に接続できていなかった

5. ✅ **ユーザーによる設定修正**
   - Zabbix Web UIでホスト「Zabbix server」の設定を変更
   - Interface設定: DNS name = `zbx_agent`, Port = 10050
   - 監視が正常に開始し、警告が解消

**技術的知見**:
- Dockerの `networks_advanced` ブロックで `aliases` を設定することで、サービス名で名前解決が可能
- Zabbix Agent2は Passive checks モードで動作中（Serverからのポーリングを待機）
- Docker内部DNSは同一ネットワーク内のコンテナ間で自動的に名前解決を提供

**デプロイ結果**:
```
✅ monitoring-lab-zbx_agent (Up 2 days, healthy) - 172.28.0.8:10050
✅ monitoring-lab-zbx_server (Up 2 days, healthy) - 172.28.0.6:10051
✅ Zabbix Server自己監視が正常動作
✅ 「Zabbix agent is not available」警告が解消
```

#### 2025-10-20 (1): Zabbix Agent2コンテナのデプロイ成功 🎉

**実施内容**:
1. ✅ **Zabbix Agent2の必要性確認**
   - Zabbix Serverコンテナ内にAgent2が含まれていないことを確認
   - 自己監視のため、別コンテナとしてAgent2をデプロイする方針を決定

2. ✅ **Terragrunt設定ファイルの作成**
   - `terraform/envs/local/zabbix-agent/terragrunt.hcl` を新規作成
   - イメージ: `zabbix/zabbix-agent2:alpine-latest`
   - ポート: 10050 (Agent2のデフォルトポート)
   - ネットワーク依存関係を設定 (monitoring-lab-network)
   - Zabbix Server依存関係を設定 (起動順序制御)

3. ✅ **環境変数設定のトラブルシューティング**
   - 問題1: `ZBX_SERVER_HOST`と`ZBX_PASSIVESERVERS`の重複でエラー
     - エラー: "address 'zbx_server' specified more than once"
   - 解決策: Passive checksのみを使用、Active checksを無効化
     - `ZBX_PASSIVE_ALLOW=true`
     - `ZBX_PASSIVESERVERS=zbx_server`
     - `ZBX_ACTIVE_ALLOW=false`
   - `ZBX_HOSTNAME=Zabbix server` (Web UIのホスト名と一致)

4. ✅ **デプロイ成功**
   - `terragrunt init` → `terragrunt apply -auto-approve`
   - コンテナ起動成功: `monitoring-lab-zbx_agent`
   - ヘルスチェック: healthy
   - エラーログなし

**デプロイ結果**:
```
✅ monitoring-lab-zbx_agent (Up, healthy)
✅ monitoring-lab-zbx_server (Up 31 hours, healthy)
✅ monitoring-lab-zbx_web (Up 31 hours, healthy)
```

**修正ファイル**:
- `terraform/envs/local/zabbix-agent/terragrunt.hcl` (新規作成)

**技術的知見**:
- Zabbix Agent2の環境変数は、`ZBX_SERVER_HOST`が内部的に`Server`パラメータに変換される
- `ZBX_PASSIVESERVERS`も`Server`パラメータにマッピングされるため、両方指定すると重複エラーになる
- Passive checksのみの構成でも、Zabbix Serverからのポーリングで監視が可能

#### 2025-10-19 (8): 設定ファイルの最終クリーンアップ 🧹

**実施内容**:
1. ✅ **STDERR/WARNING出力の完全除去**
   - `.env` ファイルの修正:
     - `TF_LOG=info` をコメントアウト（STDERR出力の根本原因を解消）
     - `SSH_PUBLIC_KEY` 削除（未使用変数）
     - `POSTGRES_DATA_DIR` 削除（未使用変数）
     - `VAULT_DATA_DIR` 削除（未使用変数）
   - `docker-compose.yml` の修正:
     - `TERRAGRUNT_DOWNLOAD` → `TG_DOWNLOAD_DIR` に変更（非推奨警告の解消）

2. ✅ **動作確認**
   - Terragruntコンテナ再起動
   - `terragrunt plan` で出力を検証
   - STDERR出力が完全に消滅
   - WARNING（非推奨警告）が完全に消滅

**成果**:
```
Before:
[WARN] The `TERRAGRUNT_NON_INTERACTIVE` environment variable is deprecated...
[WARN] The `TERRAGRUNT_DOWNLOAD` environment variable is deprecated...
[STDERR] Docker network inspect: {...}
[STDERR] - .ipv6: planned value cty.False...

After:
[STDOUT] terraform: docker_network.monitoring: Refreshing state...
[STDOUT] terraform: No changes. Your infrastructure matches the configuration.
```

**修正ファイル**:
- `.env` (3箇所: TF_LOG コメントアウト、未使用変数3つ削除)
- `docker-compose.yml` (1箇所: TERRAGRUNT_DOWNLOAD → TG_DOWNLOAD_DIR)

**効果**:
- ✅ Terragrunt出力がクリーンになり、デバッグが容易に
- ✅ 不要な環境変数を削除し、設定ファイルが整理された
- ✅ 非推奨警告が消え、将来のバージョンアップに対応

#### 2025-10-19 (7): コンテナ監視方針の調査・検討 🔍

**実施内容**:
1. ✅ **コンテナ監視手法の比較調査**
   - Node Exporterのコンテナ内配置検討
   - 3つの導入方法の比較（既存コンテナ内/専用コンテナ/ホストOS）
   - 各方法のメリット・デメリット整理

2. ✅ **監視レイヤーの整理**
   - Layer 1: ホストOS層（Node Exporter）
   - Layer 2: コンテナ層（cAdvisor、Docker Stats）
   - Layer 3: アプリケーション層（個別Exporter）

3. ✅ **コンテナ監視ツールの選択肢提示**
   - cAdvisor（最推奨）: コンテナリソース監視
   - Docker Stats API（中程度）: Docker標準機能
   - Zabbix Docker Monitoring（中程度）: Zabbix統合
   - 個別Exporter（低優先）: アプリ固有メトリクス

4. ✅ **推奨監視戦略の提案**
   - フェーズ1: cAdvisor導入（コンテナリソース監視）
   - フェーズ2: Node Exporter追加（ホストOS監視）
   - フェーズ3: 個別Exporter追加（アプリ監視）

**結論**:
- ⏸️ 監視機能の実装は**後回し**（方針を慎重に検討してから実装）
- ✅ 調査結果は文書化済み（口頭説明）
- ✅ 次回セッション時に全体方針を決定してから進める

**推奨される次のステップ（保留中）**:
1. 監視戦略全体の設計書作成
2. cAdvisor導入ガイド作成
3. Terragrunt設定ファイル作成

#### 2025-10-19 (6): スクリプト・ダッシュボード管理ドキュメント作成 📚

**実施内容**:
1. ✅ **Zabbixスクリプト管理ディレクトリ作成**
   - `config/zabbix/scripts/` ディレクトリ構造作成
     - `externalscripts/` - External Checksスクリプト
     - `alertscripts/` - アラート通知スクリプト
     - `userparameters/` - UserParameter設定ファイル
   - `config/zabbix/scripts/README.md` 作成（包括的なガイド）

2. ✅ **Grafanaダッシュボード管理ディレクトリ作成**
   - `config/grafana/dashboards/` ディレクトリ作成
   - `config/grafana/dashboards/README.md` 作成（ベストプラクティス）

**ドキュメント内容**:
- スクリプトの種類と用途（External/Alert/UserParameter）
- スクリプト追加手順（作成 → 配置 → Terragrunt設定 → デプロイ）
- テスト方法とトラブルシューティング
- セキュリティ考慮事項
- Bash/Pythonテンプレート
- ダッシュボードエクスポート/インポート手順
- Provisioning設定方法
- バージョン管理のベストプラクティス

**設計方針の明確化**:
- ✅ IaC（Terraform/Terragrunt）: 基盤管理のみ
- ✅ スクリプト: Gitで管理、bind_mountで配置
- ✅ ダッシュボード: Web UIで作成 → JSONエクスポート → Git管理（オプション）
- ✅ 監視設定: Web UIで管理（コンソール管理に閉じる）

#### 2025-10-19 (5): ネットワークモジュール実装とデプロイ成功 🎉

**実施内容**:
1. ✅ **ネットワーク競合問題の解決**
   - 問題: 各サービスが同時に `monitoring-lab-network` を作成しようとしてエラー
   - 原因: `docker_container` モジュール内でネットワークリソースを定義していた
   - 解決策: 専用の `network` モジュールを作成し、依存関係で制御

2. ✅ **新規モジュール作成**
   - `terraform/modules/network/` - Docker ネットワーク専用モジュール
     - main.tf: docker_network リソース定義
     - variables.tf: network_name, subnet, gateway パラメータ
     - outputs.tf: network_name, network_id, subnet, gateway を出力
   - `terraform/envs/local/network/terragrunt.hcl` - ネットワークサービス定義

3. ✅ **docker_container モジュールの修正**
   - `main.tf`: ネットワークリソース定義を削除（11-20行目）
   - `variables.tf`: network_name 変数を追加
   - `outputs.tf`: network_name, network_id 出力を削除

4. ✅ **全サービス設定の更新**
   - 各サービスに network 依存関係を追加:
     - postgres/terragrunt.hcl
     - prometheus/terragrunt.hcl
     - vault/terragrunt.hcl
     - zabbix/terragrunt.hcl
     - grafana/terragrunt.hcl
   - `network_name = dependency.network.outputs.network_name` を inputs に追加

5. ✅ **デプロイ成功**
   - `terragrunt run --all apply` が正常完了
   - 起動順序: network → (postgres, prometheus, vault) → zabbix → grafana
   - すべてのコンテナが正常起動
   - ネットワーク接続確認完了

**デプロイ結果**:
```
✅ monitoring-lab-network (172.28.0.0/16)
✅ monitoring-lab-postgres (172.28.0.2)
✅ monitoring-lab-vault (172.28.0.3)
✅ monitoring-lab-prometheus (172.28.0.4)
✅ monitoring-lab-zbx_server
✅ monitoring-lab-zbx_web
✅ monitoring-lab-grafana
```

**解決したエラー**:
- ❌ → ✅ `network with name monitoring-lab-network already exists` (ネットワーク競合)
- ❌ → ✅ 複数サービスによる同時ネットワーク作成の競合状態

#### 2025-10-19 (4): Terragrunt設定の修正とリモートDocker環境のセットアップ

**実施内容**:
1. ✅ **バージョン確認と互換性検証**
   - Terraform v1.13.3, Terragrunt v0.90.0 の動作確認
   - Docker Provider 3.6.2 の互換性確認
   - `terragrunt run --all` コマンド構文の確認

2. ✅ **Terragrunt設定ファイルの修正**
   - `terraform/modules/docker_container/main.tf`:
     - `terraform {}` ブロック削除（重複定義エラー修正）
     - `env` を動的ブロックから文字列リスト形式に変更
   - `terraform/root.hcl`:
     - Docker Provider の環境変数参照を `$${VAR}` から `get_env("VAR")` に修正
   - `terraform/envs/local/prometheus/terragrunt.hcl`:
     - bind_mounts パスを `/opt/monitoring-lab` → `/home/ubuntu/monitoring-lab` に修正
   - `terraform/envs/local/grafana/terragrunt.hcl`:
     - bind_mounts パスを `/opt/monitoring-lab` → `/home/ubuntu/monitoring-lab` に修正

3. ✅ **リモートサーバーのDocker Engine セットアップ**
   - `scripts/setup-docker-remote.sh` 作成
   - Docker Engine インストール・起動・自動起動設定
   - `ubuntu` ユーザーを `docker` グループに追加
   - Docker 動作確認完了

4. ✅ **docker-compose.yml の修正**
   - SSH鍵マウント追加: `${HOME}/.ssh:/root/.ssh:ro`
   - 環境変数ファイル読み込み: `env_file: - .env`

**解決したエラー**:
- ❌ → ✅ `Duplicate required providers configuration` (重複定義)
- ❌ → ✅ `Unsupported block type "env"` (動的ブロック構文エラー)
- ❌ → ✅ `Invalid reference` (環境変数参照エラー)
- ❌ → ✅ bind_mounts パス不一致
- ❌ → ✅ リモートサーバーに Docker Engine 未インストール
- ⚠️ SSH鍵認証エラー（コンテナ再起動待ち）

#### 2025-10-19 (3): リモートサーバーのセットアップ完了

**実施内容**:
1. ✅ **SSH鍵の設定**
   - Windows側のSSH鍵 (`C:\Users\k1981\.ssh\monitoring_lab_key`) をWSL2にコピー
   - `~/.ssh/id_rsa` として配置、権限設定完了
   - SSH接続テスト成功 (10.0.0.220)

2. ✅ **setup-remote-config.shの拡張**
   - SSH接続確認機能を追加
   - リモートサーバーでの設定ファイル直接作成機能を実装
   - sudo不要な構成に変更 (ホームディレクトリ配下に配置)
   - 4ステップの完全セットアップスクリプトに進化

3. ✅ **リモートサーバーのセットアップ実行**
   - ディレクトリ作成: `/home/ubuntu/monitoring-lab/`
   - Prometheus設定ファイル作成: `prometheus.yml`
   - Grafana設定ファイル作成: `datasources.yml`
   - 権限設定完了 (755)

4. ✅ **.env設定の更新**
   - `REMOTE_BASE_DIR` を `/opt/zabbix` → `~/monitoring-lab` に変更
   - 関連パスも更新 (sudo不要な構成)

#### 2025-10-19 (2): 不要ファイルのクリーンアップ

**実施内容**:
1. ✅ **不要ファイルの削除**
   - `nul` - 空ファイル
   - `scripts/setup.sh` - ローカル実行前提（コンテナ構成と矛盾）
   - `scripts/deploy.sh` - ローカル実行前提
   - `scripts/destroy.sh` - ローカル実行前提
   - `scripts/tf.sh` / `tf.bat` - Terraformコンテナが存在しないため不要
   - `TERRAFORM_REMOTE_INSTRUCTIONS.md` - 古い設計、claude.mdと重複
   - `QUICKSTART.md` - README.mdと重複

2. ✅ **スクリプトの修正**
   - `scripts/container-setup.sh` - Terraformコンテナ参照を削除、Terragruntのみに統一
   - `scripts/container-setup.bat` - 同上
   - `scripts/cleanup-and-rebuild.sh` - パスを汎用化（WSL2専用から脱却）

3. ✅ **セッション継続機能の実装**
   - `.claude/SESSION_STATE.md` - 作業履歴と次のステップを記録
   - `.claude/commands/init.md` - 自動セッション開始機能
   - `.claude/commands/status.md` - 状況確認コマンド
   - `.claude/commands/update-status.md` - 状態更新コマンド
   - `claude.md` - セッション開始時の自動指示を追加

#### 2025-10-19 (1): Terragrunt設定ファイルの全面修正

**修正内容**:
1. ✅ **Dockerプロバイダーの重複定義を解消**
   - `terraform/modules/docker_container/main.tf` からプロバイダー定義を削除
   - root.hclの自動生成を使用（SSH経由のリモート接続対応）

2. ✅ **docker_containerモジュールにcommandパラメータ追加**
   - `terraform/modules/docker_container/variables.tf` に `command = optional(list(string), [])` 追加
   - `terraform/modules/docker_container/main.tf` で動的設定

3. ✅ **環境変数フォーマットの統一**
   - オブジェクト形式 `{ name = "KEY", value = "VALUE" }` → 文字列配列 `"KEY=VALUE"` に変更
   - 対象ファイル:
     - `terraform/envs/local/zabbix/terragrunt.hcl` (zbx_server, zbx_web)
     - `terraform/envs/local/grafana/terragrunt.hcl`
     - `terraform/envs/local/vault/terragrunt.hcl`

4. ✅ **bind_mountsパラメータの明示化**
   - すべてのサービスに `bind_mounts = []` を追加
   - 対象: postgres, vault, zabbix (zbx_server, zbx_web)

---

## 🎯 プロジェクト概要

### 実行方式 ⚠️ 重要

**実行環境**: WSL2 (Ubuntu-24.04) 上のDocker Engine
- **Docker Desktop は使用しない**
- WSL2でdocker composeを実行
- Terragruntコンテナ内から当プロジェクトのTerraformを実行
- TerragruntコンテナはWSL2のDocker Engine上で動作

**SSH鍵の配置**:
- WSL2: `~/.ssh/id_rsa` (ubuntuユーザーのホームディレクトリ)
- コンテナ起動時に自動的に `/root/.ssh/` にコピー (docker-compose.ymlのentrypointで実行)
- コンテナ内から `/root/.ssh/id_rsa` を使用してリモートサーバーにSSH接続

### アーキテクチャ

**構築方式**: Windows PC (WSL2) → SSH → リモートUbuntuサーバー (Docker Engine)

**構成**:
```
[Windows PC - WSL2]
  ├─ Docker Engine (WSL2で実行)
  │   ├─ Terragrunt開発コンテナ (alpine/terragrunt:latest)
  │   │   └─ SSH鍵: /root/.ssh/id_rsa (起動時に自動コピー)
  │   └─ Vault開発サーバー (hashicorp/vault:latest) ※ローカル
  │
  └─ SSH鍵: ~/.ssh/id_rsa (ubuntuユーザー)

      ↓ Terragruntコンテナ内からSSH経由でDocker操作

[リモートサーバー: 10.0.0.220]
  ├─ Docker Engine
  ├─ PostgreSQL:5432          (Zabbixデータベース)
  ├─ Zabbix Server:10051      (監視バックエンド)
  ├─ Zabbix Agent2:10050      (Zabbix Server自己監視用)
  ├─ Zabbix Web:8080          (Web UI)
  ├─ Prometheus:9090          (メトリクス収集)
  ├─ Grafana:3000             (ダッシュボード)
  └─ New Relic Infra Agent    (統合監視プラットフォーム) ← ✨ NEW!
```

### 重要な環境変数 (.env)

```bash
# リモートサーバー接続
TARGET_HOST=10.0.0.220
TARGET_USER=ubuntu
TARGET_PORT=22
SSH_PRIVATE_KEY=~/.ssh/id_rsa

# リモートディレクトリ（修正済み）
REMOTE_BASE_DIR=~/monitoring-lab
POSTGRES_DATA_DIR=~/monitoring-lab/postgres
VAULT_DATA_DIR=~/monitoring-lab/vault

# Vault (ローカル開発モード)
VAULT_TOKEN=root
VAULT_ADDR=http://localhost:8200
```

---

## 🚧 未完了・次のステップ

### 優先度: 高 🔴

#### 1. 監視基盤の基本動作確認
**ステータス**: ログイン確認済み、詳細確認は未実施

**確認済み**:
- ✅ Zabbix Web UIへのアクセス: http://10.0.0.220:8080 (ログイン成功)
- ✅ Prometheus UIへのアクセス: http://10.0.0.220:9090 (ログイン成功)
- ✅ Grafana UIへのアクセス: http://10.0.0.220:3000 (ログイン成功)
- ✅ データソース接続に問題なし

**今後の確認項目**:
- [ ] Prometheusのターゲット設定の有効化
- [ ] Grafanaダッシュボードの作成
- [ ] アラート設定のテスト

---

### 優先度: 中 🟡

#### 5. Vault統合の実装
**ステータス**: 設計のみ完了、実装は未着手

**現状**: パスワードがハードコード
**目標**: すべての機密情報をVaultから動的取得

**参考実装** (`vault_secret` モジュールが存在):
```hcl
data "vault_kv_secret_v2" "postgres" {
  mount = "secret"
  name  = "monitoring-lab/postgres"
}

env = [
  "POSTGRES_PASSWORD=${data.vault_kv_secret_v2.postgres.data["password"]}"
]
```

#### 2. 監視機能の実装（保留中）⏸️
**ステータス**: 方針検討中、実装は保留

**検討事項**:
- 監視対象の明確化（ホストOS / コンテナ / アプリケーション）
- 監視ツールの選定（Node Exporter / cAdvisor / 個別Exporter）
- 導入フェーズの決定（段階的 or 一括）

**候補ツール**:
- **cAdvisor**: コンテナリソース監視（最推奨）
- **Node Exporter**: ホストOS監視
- **PostgreSQL Exporter**: DB監視（オプション）

**次回決定すべきこと**:
1. 監視の優先順位（コンテナ優先 or ホストOS優先）
2. 導入範囲（フェーズ1のみ or 全体）
3. 管理の複雑さの許容度

**準備済みドキュメント**:
- ✅ 監視レイヤーの整理（Layer 1-3）
- ✅ ツール比較表
- ✅ 推奨戦略（フェーズ1-3）

#### 3. Vault統合の実装
**ステータス**: 設計のみ完了、実装は未着手

**現状**: パスワードがハードコード
**目標**: すべての機密情報をVaultから動的取得

**参考実装** (`vault_secret` モジュールが存在):
```hcl
data "vault_kv_secret_v2" "postgres" {
  mount = "secret"
  name  = "monitoring-lab/postgres"
}

env = [
  "POSTGRES_PASSWORD=${data.vault_kv_secret_v2.postgres.data["password"]}"
]
```

---

## 🐛 既知の問題・制約

### 1. SSH鍵認証（解決済み）✅
**問題**: Terragruntコンテナ内から `monitoring_lab_key` でSSH接続できない
**原因**: `/root/.ssh/` が空（マウント失敗）
**解決策**: docker-compose.ymlのentrypointでWSL2の鍵を自動コピー
**現状**: SSH接続成功、デプロイ完了

### 2. bind_mountsの制約
**問題**: Prometheus/Grafanaがリモートサーバーのファイルシステムを直接参照
**影響**: 事前にリモートサーバーに設定ファイルを配置する必要がある
**回避策**: ✅ setup-remote-config.sh で自動配置済み

### 3. Vaultの開発モード
**問題**: Root Token固定、データ永続化なし
**影響**: 本番環境では使用不可
**移行パス**: config.hcl作成、TLS設定、Auto-unseal実装

---

## 📁 重要なファイルパス

### 今セッションで修正したファイル (2025-10-19)
```
terraform/
├── root.hcl                          # ✅ Docker Provider環境変数参照修正
├── modules/docker_container/
│   └── main.tf                      # ✅ terraform{}削除、env動的ブロック→文字列リスト
├── envs/local/
│   ├── prometheus/terragrunt.hcl    # ✅ bind_mountsパス修正
│   └── grafana/terragrunt.hcl       # ✅ bind_mountsパス修正

scripts/
└── setup-docker-remote.sh           # ✅ 新規作成

docker-compose.yml                    # ✅ SSH鍵マウント、env_file追加
```

### Terragrunt設定（全体）
```
terraform/
├── root.hcl                          # 全環境共通設定（プロバイダー自動生成）
├── envs/local/
│   ├── terragrunt.hcl               # 環境固有設定（SSH接続情報）
│   ├── postgres/terragrunt.hcl
│   ├── vault/terragrunt.hcl
│   ├── zabbix/terragrunt.hcl
│   ├── prometheus/terragrunt.hcl
│   └── grafana/terragrunt.hcl
└── modules/
    ├── docker_container/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── vault_secret/                # 未使用（将来の拡張用）
```

### 設定ファイル（リモートサーバー上）
```
/home/ubuntu/monitoring-lab/
├── prometheus/
│   └── prometheus.yml               # ✅ 配置済み
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── datasources.yml      # ✅ 配置済み
        └── dashboards/              # ✅ ディレクトリ作成済み
```

---

## 🔧 よく使うコマンド

### Terragrunt操作（コンテナ内）
```bash
# 初期化
terragrunt run-all init

# 実行計画
terragrunt run-all plan

# デプロイ
terragrunt run-all apply

# 削除
terragrunt run-all destroy

# 特定サービスのみ
cd terraform/envs/local/grafana
terragrunt apply

# 依存関係グラフ表示
terragrunt graph-dependencies
```

### Docker操作（ホストから）
```bash
# コンテナ起動
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose up -d"

# コンテナ接続
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose exec terragrunt sh"

# ログ確認
wsl -d Ubuntu-24.04 -e bash -c "cd /mnt/e/work/labo && docker compose logs -f terragrunt"

# 監視基盤のコンテナ確認（リモートサーバー上）
ssh ubuntu@10.0.0.220 "docker ps"
```

### リモートサーバー操作
```bash
# SSH接続
ssh ubuntu@10.0.0.220

# コンテナ状態確認
docker ps -a --filter "label=project=monitoring-lab"

# ログ確認
docker logs monitoring-lab-postgres
docker logs monitoring-lab-zbx_server
docker logs monitoring-lab-grafana

# ネットワーク確認
docker network inspect monitoring-lab-network

# ボリューム確認
docker volume ls | grep monitoring-lab
```

---

## 🎓 学習ポイント

### Terragruntの特徴
1. **DRY原則**: root.hclで共通設定を定義、各環境で差分のみ記述
2. **依存関係管理**: `dependency` ブロックで起動順序を自動制御
3. **一括操作**: `run-all` コマンドで複数サービスを一括管理

### Docker Providerの注意点
- モジュール内でプロバイダーを定義すると環境依存になる
- root.hclの `generate "provider"` で環境ごとに動的生成が推奨

### リモート構築のポイント
- SSH鍵認証の設定が必須
- bind_mountsはリモートサーバーのパスを指定
- Dockerボリュームは自動作成されるが、bind_mountはディレクトリが必要

---

## 📞 トラブルシューティング

### SSH接続エラー
```bash
# 接続テスト
ssh -vvv ubuntu@10.0.0.220

# 鍵の権限確認
ls -la ~/.ssh/id_rsa  # 600 である必要

# known_hostsクリア（ホスト再インストール後）
ssh-keygen -R 10.0.0.220
```

### Terragruntエラー
```bash
# キャッシュクリア
rm -rf .terragrunt-cache

# State再初期化
terragrunt init -reconfigure

# ロック解除
terragrunt force-unlock <LOCK_ID>
```

### コンテナ起動失敗
```bash
# リモートサーバー上で確認
ssh ubuntu@10.0.0.220 "docker logs monitoring-lab-postgres"

# ネットワーク確認
ssh ubuntu@10.0.0.220 "docker network inspect monitoring-lab-network"

# ボリューム権限確認
ssh ubuntu@10.0.0.220 "docker volume inspect monitoring-lab-postgres_data"
```

---

## 🔐 セキュリティチェックリスト

### 現在の状態（学習環境）
- ❌ Vault開発モード（Root Token: root）
- ❌ パスワードがハードコード
- ❌ HTTP通信（TLS未設定）
- ❌ デフォルト認証情報使用

### 本番移行時の必須対応
- [ ] Vaultの本番モード化
- [ ] TLS/SSL証明書設定
- [ ] 強力なパスワード生成
- [ ] Stateファイルのリモートバックエンド化（S3等）
- [ ] ネットワークセグメント分離
- [ ] シークレットローテーション実装

---

## 📝 メモ・備考

### 今後の拡張案
1. **Phase 1.5**: 監視基盤の動作確認（次回優先）
   - Web UIアクセステスト
   - 初期設定とパスワード変更
   - データソース接続確認
2. **Phase 2**: 監視機能の実装（Agent、スクレイプ設定、ダッシュボード）
3. **Phase 3**: Vault統合（動的シークレット取得）
4. **Phase 4**: CI/CDパイプライン統合
5. **Phase 5**: 本番環境対応（マルチ環境、リモートバックエンド）

### 最近のクリーンアップ成果（2025-10-19）
- ✅ 設定ファイルの全面整理完了（.env, .env.example, docker-compose.yml, terragrunt.hcl, root.hcl）
- ✅ STDERR/WARNING出力を100%削減
- ✅ 非推奨環境変数を新形式に移行
- ✅ 未使用変数を7個削除
- ✅ Terragrunt出力がクリーンになり、デバッグが容易に

### 参考リンク
- [Terragrunt公式ドキュメント](https://terragrunt.gruntwork.io/docs/)
- [Docker Provider for Terraform](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs)
- [HashiCorp Vault](https://www.vaultproject.io/docs)

---

**このファイルは自動的に更新されます。セッション開始時に必ず確認してください。**
