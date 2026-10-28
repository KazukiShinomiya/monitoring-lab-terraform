---
name: sync
description: 設定ファイルをリモートへ同期する定型（引数: prometheus / alertmanager / grafana / snmp / tempo / otel-collector / blackbox / all）。配備後の検証まで一気通貫
---

`$ARGUMENTS` で指定されたサービスの設定をリモートへ同期し、**配備後の検証まで**行う。同期だけして検証を省くのは禁止
（プレースホルダ配備事件の教訓: 配備の成否は「リロードが通ったか」でなく「ターゲットが up か」で判定する）。

## 実行

```bash
task sync:<service>   # prometheus / alertmanager / grafana / snmp / tempo / otel-collector / all
```

内部は `scripts/sync-config.sh`。`render_config`（`.env` 実値へ置換）+ `assert_no_placeholder`
（コメント行以外に `YOUR_*` が残れば配備拒否）のガード付き。**ガードに拒否されたら `.env` の `PROM_*` 等の欠落を疑う**——ガードを迂回しない。

## 配備後検証（サービス別）

- **prometheus**: `curl -s http://$TARGET_HOST:9090/api/v1/targets` で全ターゲット health=up を確認（基準: 18ターゲット。2026-10-25 に vault_health・honeypot_probe×2 を追加）。
  ルール変更時は `/api/v1/rules` にも反映されているか見る
- **alertmanager**: `amtool check-config` はコンテナ内で。`curl -s http://$TARGET_HOST:9093/api/v2/status` で config 反映確認
- **grafana**: 再起動後 `/api/health` が ok、対象ダッシュボードが `/api/search` に出ること
- **snmp**: snmp-exporter 再起動後、Prometheus の SNMP ターゲット（RTX830・Synology）が up に戻ること
- **tempo / otel-collector**: コンテナが Restarts 増加なしで up、（otel-collector は）パイプライン起動ログにエラーなし
- **blackbox**: Prometheus の `vault_health` ターゲットが up、`probe_success{job="vault_health"}` が 1。
  初回はコンテナ未作成なので、apply より**先に**同期してファイルを置く（無いと Docker がディレクトリを作り起動に失敗する）

## 注意

- `.env` を source したら `unset DOCKER_HOST`（npipe 汚染で WSL docker が壊れる）
- WSL の clone（`~/repos/labo`）では `sync-config.sh` は LF なので `bash scripts/sync-config.sh <service>` で直接動く（2026-10-25 確認）。
  CRLF で WSL2 直実行不可だったのは Windows 側の作業ツリー。`.env` を読むため Claude からは打たず、ユーザーが `!` で打つ
- 同期対象にない設定（loki.yml / promtail.yml 等）は scp + apply の手動経路。その場合も配備後検証は同基準で行う
