# Implementation Readiness Checklist: Grafana Tempo + OpenTelemetry Collector

**Purpose**: 実装開始前に仕様書・計画書・タスクリストの要件品質を検証する。「要件が実装可能な形で書かれているか」を確認するためのリストであり、実装の動作確認ではない。
**Created**: 2026-03-28
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [tasks.md](../tasks.md)
**Depth**: Standard (PR review gate)
**Focus**: インフラデプロイ要件品質・オブザーバビリティ統合要件品質・スコープ境界の明確さ

**Evaluation Legend**:
- `[x]` = PASS（要件品質として十分）
- `[ ]` ⚠️ = Minor gap（許容範囲、実装で対処可能）
- `[ ]` ❌ = **Action Required**（実装前に修正が必要）

---

## Requirement Completeness (要件の網羅性)

- [ ] CHK001 ⚠️ - Tempo が受け付けるべき全ポート (3200, 4317, 4318) の用途・アクセス元が FR-001 に明記されているか？ FR-001 はポート番号を列挙しているが「外部公開 vs Docker ネットワーク内部のみ」の区別が spec 上では曖昧。plan §Constraints に記載あり。 [Completeness, Spec §FR-001]
- [x] CHK002 - OTel Collector が転送先として Tempo を使う際の接続情報 (ホスト名 `tempo:4317`・TLS insecure) が contracts/otel-collector-config-schema.yml に定義されている [Completeness, contracts/]
- [x] CHK003 - Grafana Tempo データソースに必要な全プロパティ (uid, url, serviceMap, tracesToLogs, tracesToMetrics) が contracts/grafana-datasource-changes.yml に網羅されている [Completeness, contracts/]
- [ ] CHK004 ⚠️ - Prometheus が Exemplar を収集するために必要な設定変更 (scrape_protocols, exemplar_storage) が FR-004 には記述がなく plan §B1 のみに記載。FR レベルでの要件定義が不足しているが、plan で補完されている [Completeness, Spec §FR-004]
- [ ] CHK005 ⚠️ - OTel Collector 自身を Prometheus でスクレイプする要件 (ポート 8888) が spec の FR には明記されていない。Constitution 原則 V への対応として tasks.md T017 で追加済みだが、FR-008 に明文化されていない [Completeness, Gap → T017]
- [ ] CHK006 ⚠️ - sync-config.sh の `all` サブコマンドへの tempo/otel-collector 追加が FR-005 に明記されていない。FR-005 は個別サブコマンドのみ記述しており、plan §C3 で補完 [Completeness, Spec §FR-005]
- [x] CHK007 - Docker Volume 名 (`tempo_data`)・マウントパス (`/var/tempo`) が data-model.md と contracts/tempo-config-schema.yml に定義されている [Completeness, data-model.md]

---

## Requirement Clarity (要件の明確さ)

- [ ] CHK008 ⚠️ - FR-001「各ポートで接続を受け付けなければならない」は外部公開/内部のみの区別が spec 上では曖昧。plan §Constraints に「Tempo: 3200 外部公開、OTLP: Docker ネットワーク内のみ」と明記されており、実装上は問題なし [Clarity, Spec §FR-001]
- [ ] CHK009 ⚠️ - FR-007「コンテナ再起動後もデータが保持される」は再起動後の保持を明記しているが、コンテナ削除・再作成後の保持については記述なし。Docker Volume 仕様上、削除しない限り保持されるので実用上問題なし [Clarity, Spec §FR-007]
- [x] CHK010 - SC-001「3 秒以内」・SC-002「10 秒以内」のパフォーマンス計測が学習環境では目視確認で代替される旨を Assumptions に追記済み [Clarity, Spec §SC-001/002, Assumptions]
- [x] CHK011 - FR-004 Exemplar はアプリ側実装も必要なことが Assumptions「Tempo 側の受け入れ準備のみ…アプリケーション実装は対象外」に明記されている [Clarity, Spec §Assumptions]
- [x] CHK012 - FR-008「Grafana・Prometheus と通信できる」は Docker network 内 DNS 解決が前提。data-model.md と contracts が `tempo:3200`、`otel-collector:8888` と明記しており、業界標準として許容範囲 [Clarity, Spec §FR-008]

---

## Requirement Consistency (要件間の整合性)

- [ ] CHK013 ⚠️ - US1 Acceptance Scenario 1/2「OTLP gRPC (4317) に直接トレースを送信」と plan Constraints「4317 は外部非公開」が矛盾。tasks.md の Independent Test 注記で「外部非公開」と修正済みだが、spec.md US1 の記述は依然として誤解を招く表現が残っている [Consistency, Spec §US1]
- [x] CHK014 - docker_container モジュールの単一ポート制約と FR-001 (3ポート) の矛盾が research.md §3 で設計決定として記録されている [Consistency, research.md §3]
- [x] CHK015 - contracts 内で Tempo datasource の `uid: tempo` と Prometheus の `exemplarTraceIdDestinations.datasourceUid: tempo` が一致している [Consistency, contracts/]
- [x] CHK016 - `datasources.yml` の Prometheus datasource に `uid: prometheus`、Loki datasource に `uid: loki` を追加済み。Tempo datasource の `serviceMap`/`tracesToLogs`/`tracesToMetrics` 相関が正しく機能する [Consistency, contracts/, config/grafana/provisioning/datasources/datasources.yml]

---

## Acceptance Criteria Quality (成功基準の測定可能性)

- [x] CHK017 - SC-001 パフォーマンス計測の学習環境における代替手段 (目視確認) を Assumptions に追記済み。CHK010 と同根、同一修正で解消 [Measurability, Spec §SC-001]
- [x] CHK018 - SC-003 (Exemplar 1クリック) はアプリ側実装なしでは検証不可であることが Assumptions に明記されている [Measurability, Spec §SC-003]
- [x] CHK019 - SC-005 (run-all No changes) は HCP Local モード設定が前提であることが tasks.md Phase 2 に明示されている [Measurability, tasks.md §Phase 2]
- [x] CHK020 - SC-006 (再起動後データ保持) の検証手順が tasks.md T012「docker restart → HTTP API でクエリ確認」として定義されている [Measurability, tasks.md §T012]

---

## Scenario Coverage (シナリオの網羅性)

- [x] CHK021 - Tempo の bind_mount ファイル未存在時の起動失敗シナリオが tasks.md T009「apply 前に必須」として対処されている [Coverage, tasks.md §T009]
- [x] CHK022 - OTel Collector → Tempo 接続不可時の動作 (ログにエラー、データ消失) が spec Edge Cases に記述されている [Coverage, Spec §Edge Cases]
- [x] CHK023 - Tempo・OTel Collector の TargetDown アラートは既存のアラートルールで自動カバーされることが plan §Constitution Check に記録されている [Coverage, plan §Constitution Check]
- [ ] CHK024 ⚠️ - `sync-config.sh` 実行時に設定ファイルが存在しない場合の動作が FR-005 に記述なし。既存の `set -e` パターンで自動エラー終了するため実用上問題なし [Coverage, Spec §FR-005]
- [x] CHK025 - FR-003「Grafana 再起動後に Explore からトレースを参照できる」はプロビジョニングによる自動設定を意味することが明示されている [Coverage, Spec §FR-003]

---

## Edge Case Coverage (境界条件の定義)

- [x] CHK026 - Tempo ストレージ上限到達時の動作 (保持期間による自動削除) が spec Edge Cases と contracts/tempo-config-schema.yml に定義されている [Edge Case, Spec §Edge Cases]
- [x] CHK027 - 保持期間 336h がデフォルト値であり変更可能なことが Assumptions と contracts/tempo-config-schema.yml に明記されている [Edge Case, Spec §Assumptions]
- [ ] CHK028 ⚠️ - `datasources.yml` 構文エラー時の動作が Edge Cases に挙げられているが「Grafana が起動しない・既存データソースが消える」等の具体的な動作記述が不明確。学習環境では許容範囲 [Edge Case, Spec §Edge Cases]

---

## Intentional Scope Exclusions (意図的なスコープ外の明確さ)

- [x] CHK029 - Exemplar 生成のアプリ側実装がスコープ外であることと境界 (「Tempo 側受け入れ準備のみ」) が Assumptions に明記されている [Scope Boundary, Spec §Assumptions]
- [x] CHK030 - Assumptions に「SC-001/SC-002/SC-004 のパフォーマンス基準は学習環境では目視確認で代替する」を追記済み。CHK010/CHK017 と同根、同一修正で解消 [Scope Boundary, Spec §Assumptions]
- [x] CHK031 - TLS・認証省略が学習環境の判断であり技術的負債として記録されることが Assumptions と plan §Constitution Check に明記されている [Scope Boundary, Spec §Assumptions]
- [x] CHK032 - OTel Collector HA 構成がスコープ外であることと理由 (学習環境) が Assumptions に明記されている [Scope Boundary, Spec §Assumptions]
- [x] CHK033 - Tempo local ストレージから S3/GCS への移行が将来フェーズであることが Assumptions に明記されている [Scope Boundary, Spec §Assumptions]

---

## Dependencies & Assumptions (依存関係と前提条件)

- [x] CHK034 - HCP Workspace Local モード変更が必須であることが tasks.md Phase 2 (T005/T006) に ⚠️ CRITICAL として明示されている [Dependency, tasks.md §Phase 2]
- [x] CHK035 - Docker ネットワーク依存が data-model.md 依存関係グラフと terragrunt.hcl の dependency 定義として記録されている [Dependency, data-model.md]
- [x] CHK036 - Loki datasource に `uid: loki` を追加済み (CHK016 と同一修正)。tracesToLogs のトレース→ログ相関が正しく機能する [Assumption, contracts/, config/grafana/provisioning/datasources/datasources.yml]
- [ ] CHK037 ⚠️ - quickstart.md の前提条件に telemetrygen 実行用の Docker が必要であることが記述されていない [Dependency, quickstart.md]

---

## 評価サマリー

| 判定 | 件数 | 項目 |
|------|------|------|
| ✅ PASS | 27 | CHK002/003/007/010/011/012/014/015/016/017/018/019/020/021/022/023/025/026/027/029/030/031/032/033/034/035/036 |
| ⚠️ Minor gap | 10 | CHK001/004/005/006/008/009/013/024/028/037 |
| ❌ Action Required | 0 | (全件解消済み) |

### ✅ 修正済み項目

| # | 対象ファイル | 修正内容 |
|---|------------|---------|
| CHK010/017/030 | `specs/011-tempo/spec.md` §Assumptions | 「SC-001/002/004 のパフォーマンス計測は学習環境では目視確認で代替する」を追記済み |
| CHK016/036 | `config/grafana/provisioning/datasources/datasources.yml` | Prometheus datasource に `uid: prometheus`、Loki datasource に `uid: loki` を追加済み |

---

## Notes

- `[x]` = PASS（要件品質として十分）
- `[ ]` ⚠️ = Minor gap（許容範囲、実装で対処可能）
- `[ ]` ❌ = Action Required（実装前に修正が必要）
- CHK016/CHK036 は解消済み (`uid: prometheus` / `uid: loki` 追加)
- CHK010/CHK017/CHK030 は解消済み (Assumptions にパフォーマンス計測注記追加)
- **全 ❌ 解消 → 実装フェーズに進んでよい**
