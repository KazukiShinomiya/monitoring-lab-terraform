---
name: drift-check
description: コード・Terraform State・リモート実態の3層乖離を点検する（run --all plan / 配備済み設定diff / :latestタグ・プレースホルダ汚染検出）
---

このプロジェクトの障害は繰り返し同じ型で起きる: **「コード ≠ State ≠ リモート実態」の3層乖離**
（Loki/Promtail 3層乖離・otel-collector :latest 乖離・プレースホルダ配備で監視盲目1ヶ月）。これを定期点検で早期検出する。

## 点検項目

### 層1: コード vs State — `run --all plan`

```bash
task tg:plan
```

全 workspace で **No changes** が期待値。差分が出たら「コードが先行しているか・実態が手で変えられたか」を切り分ける。

### 層2: リポジトリ正本 vs リモート配備済み設定

パスの対応表は `scripts/sync-config.sh` が正典。主対象:

- `config/prometheus/{prometheus.yml,alerts.yml,slo-rules.yml}` ↔ リモート配備先
- `config/alertmanager/alertmanager.yml` / `config/loki/loki.yml` / `config/promtail/promtail.yml`
- `config/snmp/snmp.yml` / `config/grafana/provisioning/**`

**重要**: リポジトリ正本はプレースホルダ（`YOUR_*`）入りのサニタイズ版。比較は
`sync-config.sh` の `render_config` と同じ要領で **`.env` の実値にレンダリングしてから** リモート実物と diff する。
生のまま diff すると「差分だらけ」に見えて本物のドリフトが埋もれる。

```bash
# 例: レンダリング後に diff（.env source 後は unset DOCKER_HOST を忘れない）
wsl -d Ubuntu-24.04 -e bash -c "ssh ubuntu@\$TARGET_HOST 'cat <リモートパス>'" | diff <(rendered版) -
```

### 層3: 実行中コンテナ vs 宣言イメージ + 汚染検出

1. **タグ固定の破れ**: `terraform/envs/local/**/terragrunt.hcl` を Grep して `:latest` を検出
   （許容済み例外: newrelic[再起動ループ既知]・wow-exporter[ローカルビルド]）
2. **実行イメージの一致**: リモート `docker ps --format '{{.Names}} {{.Image}}'` と terragrunt.hcl の宣言を突合。
   `:latest` は再作成まで中身だけ進む——タグ一致でもダイジェスト乖離がありうる点に留意
3. **配備済みプレースホルダ汚染**: リモートの配備済み設定に `YOUR_*` がコメント行以外で残っていないか検査。
   `sync-config.sh` の `assert_no_placeholder` は**配備時のみ**のガードであり、既に配備済みの汚染はこの点検でしか見つからない

### 層4（軽量ヘルスチェック）: 監視が監視できているか

```bash
curl -s "http://$TARGET_HOST:9090/api/v1/targets" | python3 -c "
import sys,json
ts=json.load(sys.stdin)['data']['activeTargets']
down=[t['labels'].get('job','?')+' '+t['scrapeUrl'] for t in ts if t['health']!='up']
print(f'{len(ts)} targets, down={len(down)}'); [print(' DOWN:',d) for d in down]"
```

down ターゲットが出たら即報告（15ターゲット全 up が 2026-07-11 復旧時の基準値）。

## 報告形式

層ごとに ✅/⚠️ と根拠（実コマンド出力）を示し、最後に「検出されたドリフト一覧 + 収束の推奨手順」をまとめる。
収束の原則: **動いている実態を正とし、コードへ昇格**（新挙動の導入と乖離の片付けを混ぜない）。
