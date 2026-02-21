# タスク: Phase 3 - 監視機能拡充

**入力**: `.specify/memory/` の設計ドキュメント
**前提条件**: plan.md（必須）、spec.md（必須）

**テスト**: Prometheus/Grafanaエンドポイントでの手動検証を使用

**構成**: ユーザーストーリーごとにタスクをグループ化し、独立した実装とテストを可能にする

## フォーマット: `[ID] [P?] [Story] 説明`

- **[P]**: 並列実行可能（異なるファイル、依存関係なし）
- **[Story]**: 所属するユーザーストーリー（US1, US2, US3, US4）
- 説明には正確なファイルパスを含める

## パス規約

- **Terraform/Terragrunt**: `terraform/envs/local/[service]/terragrunt.hcl`
- **設定ファイル**: `config/[service]/[file]`
- **モジュール**: `terraform/modules/docker_container/`

---

## Phase 1: セットアップ（共有インフラ）

**目的**: cAdvisorサービスの追加とdocker_containerモジュールの確認

- [ ] T001 docker_containerモジュールがbind_mountsをサポートしているか確認 `terraform/modules/docker_container/main.tf`
- [ ] T002 cAdvisorサービス定義を作成 `terraform/envs/local/cadvisor/terragrunt.hcl`
- [ ] T003 cAdvisorディレクトリで `terragrunt init` を実行 `terraform/envs/local/cadvisor/`
- [ ] T004 `terragrunt apply` でcAdvisorコンテナをデプロイ
- [ ] T005 cAdvisorの稼働確認: `curl http://YOUR_SERVER_IP:8080/metrics | grep container_cpu`

**チェックポイント**: cAdvisorが稼働し、`:8080/metrics` でコンテナメトリクスを公開している

---

## Phase 2: 基盤（ブロッキング前提条件）

**目的**: Prometheus設定ファイルのリモートホストへの配置確認

**⚠️ 重要**: User Stories 1-4はPrometheusがcAdvisorをスクレイプできるまで開始不可

- [ ] T006 リモートホストのディレクトリ構造を確認: `ssh ubuntu@YOUR_SERVER_IP "ls -la ~/monitoring-lab/prometheus/"`
- [ ] T007 Grafanaプロビジョニングディレクトリを確認: `ssh ubuntu@YOUR_SERVER_IP "ls -la ~/monitoring-lab/grafana/provisioning/"`

**チェックポイント**: リモートホストのディレクトリが設定ファイル配置の準備完了

---

## Phase 3: User Story 1 - コンテナメトリクスの収集 (優先度: P1) MVP

**ゴール**: Prometheusがすべてのコンテナからメトリクスを収集する

**独立テスト**:
- `http://YOUR_SERVER_IP:9090/targets` ですべてのターゲットが "UP" 状態
- `container_cpu_usage_seconds_total` メトリクスがPrometheusに存在

### User Story 1 の実装

- [ ] T008 [US1] Prometheus設定にcAdvisorスクレイプジョブを追加 `config/prometheus/prometheus.yml`
- [ ] T009 [US1] prometheus.ymlをリモートホストにアップロード: `scp config/prometheus/prometheus.yml ubuntu@YOUR_SERVER_IP:~/monitoring-lab/prometheus/`
- [ ] T010 [US1] Prometheus設定をリロード: `curl -X POST http://YOUR_SERVER_IP:9090/-/reload`
- [ ] T011 [US1] スクレイプターゲットを確認 `http://YOUR_SERVER_IP:9090/targets` - cAdvisorが"UP"であること
- [ ] T012 [US1] コンテナメトリクスを確認: `curl "http://YOUR_SERVER_IP:9090/api/v1/query?query=container_cpu_usage_seconds_total" | jq`

**チェックポイント**: PrometheusがcAdvisorからコンテナメトリクスを正常にスクレイプしている

---

## Phase 4: User Story 2 - Grafanaダッシュボードの作成 (優先度: P1)

**ゴール**: Grafanaで全コンテナの状態を一目で把握できるダッシュボードを提供

**独立テスト**:
- `http://YOUR_SERVER_IP:3000` で「Monitoring Lab Overview」ダッシュボードが表示される
- すべてのパネルがデータを表示し、エラーがない

### User Story 2 の実装

- [ ] T013 [P] [US2] ダッシュボードプロビジョニング設定を作成 `config/grafana/provisioning/dashboards/dashboards.yml`
- [ ] T014 [P] [US2] 概要パネル付きダッシュボードJSONを作成 `config/grafana/provisioning/dashboards/monitoring-lab-overview.json`
- [ ] T015 [US2] dashboardsディレクトリをリモートホストにアップロード: `scp -r config/grafana/provisioning/dashboards/ ubuntu@YOUR_SERVER_IP:~/monitoring-lab/grafana/provisioning/`
- [ ] T016 [US2] Grafanaを再起動してプロビジョニングされたダッシュボードをロード: `ssh ubuntu@YOUR_SERVER_IP "docker restart monitoring-lab-grafana"`
- [ ] T017 [US2] ダッシュボードを確認 `http://YOUR_SERVER_IP:3000/dashboards` - 「Monitoring Lab Overview」が存在すること
- [ ] T018 [US2] すべてのパネルがエラーなくデータを表示していることを確認

**チェックポイント**: Grafanaダッシュボードがリアルタイムのコンテナメトリクスを表示している

---

## Phase 5: User Story 3 - 基本的なアラートルール (優先度: P2)

**ゴール**: コンテナダウンやリソース高負荷時にアラートが発火する

**独立テスト**:
- `http://YOUR_SERVER_IP:9090/alerts` でアラートルールが表示される
- テストでコンテナ停止時にアラートが "Firing" 状態になる

### User Story 3 の実装

- [ ] T019 [US3] アラートルールファイルを作成 `config/prometheus/alerts.yml`
- [ ] T020 [US3] prometheus.ymlにrule_filesセクションを追加 `config/prometheus/prometheus.yml`
- [ ] T021 [US3] alerts.ymlをリモートホストにアップロード: `scp config/prometheus/alerts.yml ubuntu@YOUR_SERVER_IP:~/monitoring-lab/prometheus/`
- [ ] T022 [US3] 更新したprometheus.ymlをアップロード: `scp config/prometheus/prometheus.yml ubuntu@YOUR_SERVER_IP:~/monitoring-lab/prometheus/`
- [ ] T023 [US3] Prometheus terragrunt.hclを更新してalerts.ymlをマウント `terraform/envs/local/prometheus/terragrunt.hcl`
- [ ] T024 [US3] `terragrunt apply` でアラートルール付きPrometheusコンテナを再作成
- [ ] T025 [US3] アラートルールのロードを確認 `http://YOUR_SERVER_IP:9090/rules`
- [ ] T026 [US3] コンテナを停止してアラートをテスト: `ssh ubuntu@YOUR_SERVER_IP "docker stop monitoring-lab-vault"`
- [ ] T027 [US3] 1分後にアラートが発火していることを確認 `http://YOUR_SERVER_IP:9090/alerts`
- [ ] T028 [US3] テストコンテナを再起動: `ssh ubuntu@YOUR_SERVER_IP "docker start monitoring-lab-vault"`

**チェックポイント**: アラートルールが動作 - コンテナ停止で発火、再起動で解決

---

## Phase 6: User Story 4 - Zabbix統合ダッシュボード (優先度: P3)

**ゴール**: GrafanaでPrometheusとZabbixのデータを統合表示

**独立テスト**:
- 「Integrated Monitoring」ダッシュボードでPrometheusとZabbixの両方のデータが表示される

### User Story 4 の実装

- [ ] T029 [US4] GrafanaでZabbixデータソースが設定されているか確認 `http://YOUR_SERVER_IP:3000/datasources`
- [ ] T030 [US4] 統合ダッシュボードJSONを作成 `config/grafana/provisioning/dashboards/integrated-monitoring.json`
- [ ] T031 [US4] 統合ダッシュボードをアップロード: `scp config/grafana/provisioning/dashboards/integrated-monitoring.json ubuntu@YOUR_SERVER_IP:~/monitoring-lab/grafana/provisioning/dashboards/`
- [ ] T032 [US4] Grafanaを再起動: `ssh ubuntu@YOUR_SERVER_IP "docker restart monitoring-lab-grafana"`
- [ ] T033 [US4] 統合ダッシュボードがPrometheusとZabbixの両方のデータを表示していることを確認

**チェックポイント**: 統合ダッシュボードがコンテナメトリクスとSwitchBotセンサーデータを表示

---

## Phase 7: 仕上げ & 横断的関心事

**目的**: 最終検証とドキュメント更新

- [ ] T034 全Workspaceで `terragrunt plan` を実行 - すべて「No changes」であること
- [ ] T035 すべての設定ファイルがコミット済みか確認: `git status`
- [ ] T036 SESSION_STATE.mdをPhase 3完了状態に更新
- [ ] T037 [P] CLAUDE.mdのPhase 3セクションを更新（オプション）
- [ ] T038 説明的なメッセージで全変更をコミット

---

## 依存関係 & 実行順序

### フェーズ依存関係

- **セットアップ (Phase 1)**: 依存なし - 即開始可能
- **基盤 (Phase 2)**: セットアップ完了に依存（cAdvisor稼働）
- **User Story 1 (Phase 3)**: 基盤に依存 - US2/US3の前に完了必須
- **User Story 2 (Phase 4)**: US1完了に依存（表示するメトリクスが必要）
- **User Story 3 (Phase 5)**: US1完了に依存（アラート対象のメトリクスが必要）
- **User Story 4 (Phase 6)**: US2完了に依存（ダッシュボードの拡張）
- **仕上げ (Phase 7)**: すべてのユーザーストーリー完了に依存

### ユーザーストーリー依存関係

```
Phase 1: セットアップ (cAdvisor)
    |
    v
Phase 2: 基盤 (ディレクトリ確認)
    |
    v
Phase 3: US1 - メトリクス収集 (P1) [MVP]
    |
    +-------+-------+
    |               |
    v               v
Phase 4: US2      Phase 5: US3
ダッシュボード    アラート
(P1)             (P2)
    |
    v
Phase 6: US4 - 統合ダッシュボード (P3)
    |
    v
Phase 7: 仕上げ
```

### 並列実行の機会

- T013とT014は並列実行可能（異なるファイル、依存関係なし）
- US2（ダッシュボード）とUS3（アラート）はUS1完了後に並列実行可能
- 仕上げの [P] マーク付きタスクは並列実行可能

---

## 並列実行例: User Story 2

```bash
# 以下のタスクを並列で起動（異なるファイル）:
タスク: "ダッシュボードプロビジョニング設定を作成 config/grafana/provisioning/dashboards/dashboards.yml"
タスク: "概要パネル付きダッシュボードJSONを作成 config/grafana/provisioning/dashboards/monitoring-lab-overview.json"
```

---

## 実装戦略

### MVPファースト（User Story 1 + 2 のみ）

1. Phase 1完了: セットアップ（cAdvisorデプロイ）
2. Phase 2完了: 基盤（ディレクトリ確認）
3. Phase 3完了: User Story 1（PrometheusがcAdvisorをスクレイプ）
4. Phase 4完了: User Story 2（Grafanaダッシュボード）
5. **ここで停止して検証**: ダッシュボードがリアルタイムデータを表示することを確認
6. 準備ができればデプロイ/デモ - これが使用可能なMVP！

### インクリメンタルデリバリー

1. セットアップ + 基盤 → cAdvisor稼働
2. User Story 1追加 → Prometheusがメトリクス収集 → `/targets`で検証
3. User Story 2追加 → Grafanaダッシュボード → デモ (MVP!)
4. User Story 3追加 → アラートルール → コンテナ停止でテスト
5. User Story 4追加 → 統合ダッシュボード → Phase 3完全完了

### 単独開発者戦略

これは1人の開発者による学習プロジェクトなので:

1. フェーズを順番に実行（1 → 2 → 3 → 4 → 5 → 6 → 7）
2. 次に進む前に各チェックポイントを検証
3. 各フェーズ完了後にコミット
4. 主要フェーズ間で休憩を取る

---

## 注意事項

- [P] タスク = 異なるファイル、依存関係なし
- [Story] ラベルはタスクを特定のユーザーストーリーにマッピング
- 各ユーザーストーリーは独立して完了・テスト可能であるべき
- 各フェーズまたは論理グループ後にコミット
- 任意のチェックポイントで停止してストーリーを独立検証可能
- IaC原則: 可能な限りすべての変更をTerraform/Terragrunt経由で
- Prometheus/Grafana設定にはリモートファイルアップロードが必要（bind mounts）

---

## サマリー

| フェーズ | タスク | 並列 | 説明 |
|---------|--------|------|------|
| 1. セットアップ | T001-T005 | 0 | cAdvisorデプロイ |
| 2. 基盤 | T006-T007 | 0 | ディレクトリ確認 |
| 3. US1 (P1) | T008-T012 | 0 | メトリクス収集 - **MVP** |
| 4. US2 (P1) | T013-T018 | 2 | Grafanaダッシュボード |
| 5. US3 (P2) | T019-T028 | 0 | アラートルール |
| 6. US4 (P3) | T029-T033 | 0 | 統合ダッシュボード |
| 7. 仕上げ | T034-T038 | 1 | 最終検証 |

**タスク総数**: 38
**MVPスコープ**: Phase 1-4 (タスク T001-T018) = 18タスク
**並列実行の機会**: 3つのタスクペアを特定
