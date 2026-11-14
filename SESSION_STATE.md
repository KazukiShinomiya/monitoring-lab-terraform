# SESSION_STATE

最終更新: 2026-11-14

## 現在の状況

作業の場は WSL の `~/repos/labo`。Windows 側（`/mnt/e/work/labo`）の作業ツリーにはもう触らない。`.env` は Windows 側から写したもので、その後 `WOW_VPS_HOST` と `TF_TOKEN_app_terraform_io` を書き換えた。

2026-10-28 の停電からは復旧済み。残る firing は `SynologyDiskHighUsage` 2 件（warning、停電前から）だけ。

wow-exporter とハニーポットのダッシュボードは、2026-11-01 に PR #172〜#176 で改修・配備した（下記）。いまの exporter のイメージは `d1b9c4e59c80`（#174）。VPS のホスト鍵を固定して同期している（`StrictHostKeyChecking=yes`）。

**「次のローテーションは 2026-11-02 0:00 JST 頃」という以前の記述は誤りだった。取り消す。** 実際は 2026-11-01 0:00 JST（10-31 15:00Z）に起きていた。日付を数え違えたまま、ファイルの時刻を見ずに書いていた。週次の基準は「土曜 → 日曜に替わる 0:00 JST」。11-07 15:00Z（11-08 0:00 JST）にも同じ時刻に起きたことを、同期ログで確かめた。次は 11-14 15:00Z。

**Zabbix 8.0 への移行を準備中。** ブランチ `feat/zabbix-8-prep` に commit して push した。PR はまだ作っていない。`.env.example` の追記（`ZBX_MCP_ALLOWEDIP`、`ZABBIX_MCP_TOKEN`）は guardrails の git 層に止められるので、`--no-verify` を含めユーザーが `!` で commit する。本番は 7.4.3 のまま。2026-11-06 に `alpine-8.0.0` が 4 リポジトリすべてに載ったのを確認し、本番のダンプでのリハーサルも失敗 0 件で通った。いまは本番用に `alpine-8.0.1` を待っている（2026-11-14 時点でも 4 リポジトリとも 404。8.0 系は `alpine-8.0.0` と `alpine-8.0-latest` だけ）。手順は `docs/zabbix-8-upgrade.md`。

## 前回の戦果（2026-11-14: 細かい残タスクの片付け）

- **#197**（945d5b0）`scripts/build-wow-exporter.sh` の ssh を `build-zabbix-server.sh` に揃えた。鍵パスの決め打ちと `StrictHostKeyChecking=no` をやめ、実行権限を付けた（100755）。確かめたのは `bash -n` だけ。本番でのビルドは未検証
- **#198**（9aa7dac）Grafana の `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`（初期コミットから存在しない `home.json` を指していた）を外した。ユーザーの決定で、標準のホームに戻す案を採った。PR の plan で置き換わるのが `docker_container.service["grafana"]` だけ（理由は env）と確かめてからマージした。本番への反映は success（grafana は 1 件作り直し、他の 19 モジュールは変更 0）。ホームに「Welcome to Grafana」が出て、ダッシュボード 10 枚が残っていることを、ユーザーが画面で確かめた
- Dependabot 用のラベル `dependencies`・`mcp` を `gh label create` で作った（一覧で 2 件あるのを確認）
- 11-08 0:00 JST のローテーション（チェックポイント導入後で初めて）を、ユーザーが `!` で打ったコマンドの出力で確かめた。私が打つと `.env` を読むので infra-guard に止められる
  - 同期側: 4 本とも検知し、WARN・ERROR は 0 行。2 本で中身のある継ぎ足しが初めて起きた（https の access_log が 506 バイト、http の access_log が 504 バイト）。手元の `.1` の大きさは 4 本とも VPS 側の値と一致した
  - exporter 側: 4 本とも `read 0 remaining lines from .1`。継ぎ足し分の 4 行は、UA がすべて blackbox のプローブ（`PROBE_USER_AGENT`）で、`stats["lines"]` に入らないのが正しい。同じ周期に `skipped 2 probe lines`（https）と `skipped 4 probe lines`（http。`.1` の 2 行と新しいファイルの 2 行と読むが、内訳は未確認）が出ていた。取りこぼしは無い
  - exporter は 11-01 09:46:30Z に起動してから、再起動していない

## 前々回の戦果（2026-11-06: Zabbix 8.0.0 のリハーサル）

- `alpine-8.0.0` と `alpine-8.0-latest` が server / web / agent2 / mcp-server のすべてにあることを、Docker Hub の API と `docker manifest inspect` で確認した（pull はしていない）
- 本番のダンプ（80MB、取得 19 秒）で `scripts/zabbix-upgrade-rehearsal.sh` を手元で実行し、失敗 0 件。`dbversion` 7040000 → 8000000、移行を含む server の起動は 6 秒（手元の環境での値で、本番の見積もりにはそのまま使わない）。web と agent2 は 8.0.0 で応答。MCP は TLS・許可外 IP の 403・読み取りツール 7 個のみ・`maintenance_delete` の拒否を確認。本番の Admin のパスワードで API トークンも発行できた
- ダンプは本番・手元とも消し、リハーサルのコンテナ・ネットワーク・ボリュームも残っていないことを確認した
- 未確認: `alpine-8.0.1` での動作、`terragrunt plan` と本番への適用、SwitchBot の実取得、Claude Code からの MCP 接続

## それ以前の戦果（2026-11-01: ハニーポットの表示を「何を狙われているか」が読める形にした）

- **#172**（c285924）exporter に `insights.py` を足した。ログの時刻で 1 時間ごとに数え、直近の種類別・上位（パス・IP・UA・ASN・国）を `wowhoneypot_recent_*` で出す。新規パス: 初見の時刻を `/data/wow-state/first_seen.json`（ボリューム `monitoring-lab-wow_state`）に残し、直近 7 日の新規を `wowhoneypot_new_path_*` で出す。分類を 7 種足した（ai-agent=/mcp・/sse、config-leak、backup、app-exploit、vpn-appliance、cms、proxy）。2 世代・13,114 件で `other` が 13.9% → 5.8%。上位ゲージが落ちた系列を残す不具合も直した。pytest を初めて導入した
- **#173**（be21b6b）ダッシュボードの文言を平坦にした。問いかけの見出しや比喩をやめ、新規パス・前期間比・上位・初回観測などの用語にした（ユーザーから「AI がすぎる」と指摘があった）
- **#174**（59850f9）チェックポイント（`checkpoint.py` → `/data/wow-state/checkpoint.json`）を入れた。ファイルごとの読み終えた位置・先頭のハッシュと、カウンタの値を残す。起動時にカウンタを戻し、記録した位置より後の行だけを足す。ファイルの入れ替わりは先頭のハッシュで見分け、運転中・停止中のどちらのローテーションでも `.1` の未読の末尾を数える。SIGTERM は処理の切れ目まで待つ。最初の 1 周は HTTP サーバーを立てる前に済ませる。直近の窓は 1h・24h・7d で、`window` ラベルを付けた（`RECENT_WINDOWS`）
  - ダッシュボード: リクエスト数・種類別・前期間比・推移は `increase(...[$__range])` で表示期間に連動する。送信元 IP 数と上位の一覧は、変数「IP 数・上位の集計期間」（`window`）で選ぶ
  - 確認: pytest 69 件 pass。修正をわざと戻した写しで該当テストが落ちることも確認した。本番ログの写しで、初回起動 → チェックポイントからの再起動でカウンタが 444 → 444（二重計上なし）。本番では起動ログに `no checkpoint: counting all lines`、`checkpoint.json` ができ、IP 数は 1h=3・24h=123・7d=805、`up`=1
- **#175**（8de7e31）内訳の 5 枚のバーゲージを `sizing: manual`・高さ 14〜18px・文字 12px に固定した。マージ前に本番へ配り、ユーザーが画面で確認した（「めちゃめちゃいい感じ」）
- **#176**（148a880）上段の「種類別リクエスト数」も同じ設定にそろえた（`version` 9）。マージ前に本番へ配り、ユーザーが画面で確認した
- Grafana への配布は 3 回とも、配ったファイルの sha が手元と一致し、起動後の `provisioning.dashboard` にエラーは無かった。画面はユーザーが確認した
- ローテーション（11-01 0:00 JST）: 4 本とも検知し、VPS の `.1` の大きさは手元と一致（取りこぼしなし）。継ぎ足しは今回も 0 バイト

## 次の行動

1. Zabbix 8.0: 4 リポジトリに `alpine-8.0.1` が載るのを待つ。載ったらタグの既定値（`terraform/envs/local/zabbix/terragrunt.hcl`、`terraform/envs/local/zabbix-agent/terragrunt.hcl`、`config/zabbix/server/Dockerfile`）を上げ、`docs/zabbix-8-upgrade.md` の 2 のリハーサルをそのタグで撃ち直してから、3 以降へ進む。ユーザーの決定（2026-11-05、11-06 に再確認）: 本番は 8.0.1 を待つ。理由: `.0` は動かし続けて初めて出る不具合の修正前で、DB の移行は戻せず切り戻すと移行後のデータを失う。MCP も、運用する版とセットで使い始める（手元の写しで先に試す案は見送った）。公式の予定は無く、過去の `.0` → `.1` は 21〜48 日なので、11 月下旬〜12 月下旬と推定。11 月の最終週から覗く。MCP は読み取り専用のまま。`ZBX_MCP_ALLOWEDIP` は、RTX の DHCP レンジを含む `/26` に決めた（2026-11-06 のユーザーの決定。VPN の接続先も同じプールなので許可に入るのは想定内。公開リポジトリなので値は書かない）。secret は 2026-11-06 に登録した。RTX の設定では、8443 は IPv4 でも IPv6 でも外から通していない（2026-11-06 に `show config` で確認）。MCP の起動後に、実際に外からも叩いて確かめる。PR は 8.0.1 まで作らない（マージすると本番に適用される）
2. 本番での再起動の確認（未実施。やるかはユーザーの判断。数分、ハニーポットの監視が止まる）: `docker restart monitoring-lab-wow-exporter` の前後で `sum(wowhoneypot_http_requests_total)` が減らないこと、ログに `checkpoint restored` が出ること、`increase()` が跳ねないことを見る。2026-11-01 08:17Z と 09:46Z の再起動による跳ねは記録されていて消せず、その時刻を含む表示期間では件数が多めに出る。11-14 時点で 09:46Z 以降の再起動は 0 回なので、再起動しても跳ねないことはまだ確かめられていない。自然な再起動が起きたときに見てもよい
3. 数日後: 新規パスの表に何が出ているかを見る。`other` ばかりなら分類（`parser.py`）を足す。11-01 の夕方の時点で、新規パスは 2 件あった
4. 次に wow-exporter のイメージを作り直すとき、#197 で直した `scripts/build-wow-exporter.sh` がそのまま通るかを確かめる（未検証。ホスト鍵は known_hosts で検査するようになった）
5. NAS の容量: `/volume1` が 99.5%、`/volumeUSB1/usbshare` が 100%（`SynologyDiskHighUsage`）。何を消すか移すかはユーザーの判断
6. 自宅サーバーごと落ちると Alertmanager も止まり、誰も気づけない。外から生存を見る仕組みを検討する（未着手）
7. ランナーのイメージタグを 30 日以内に追従させる仕組み（自動アップデートを止めたため）。次の版が出たら上げる
8. HCP トークンの期限を週 1 で見るワークフロー（未着手。GitHub 側ランナーか自宅ランナーかが未決）
9. CVE-2026-98432: https://ubuntu.com/security/CVE-2026-98432 で 24.04 の `linux` に修正版が出たら、このサーバーのカーネルを更新して再起動する（未適用の 78 件も合わせて当てるかは、その時に決める）。カーネルが上がったのを確かめてから、`~/repos/pi-ops` で `ansible-playbook playbooks/mitigate-cve-2026-98432.yml -K --limit monitoring-lab -e cve_mode=absent` を打つ。sudo のパスワードが要るので、本物の端末で打つ

## 決定事項・メモ

- **`master` のまま `scripts/setup-remote-config.sh` を実行しない**（`feat/zabbix-8-prep` のマージまで）。本番の `init-zabbix-server.sh` は `docker-entrypoint.sh` を経由するが、master の版は経由しない。上書きして再起動すると `ZBX_DB_*` が渡らず、server は DB に繋がらないはず（実際に動かしては確かめていない）。ブランチではこのスクリプトを廃止した。本番ホストのファイルは、切り戻しに要るので移行後もしばらく残す
- **`.env` の `DOCKER_HOST=npipe:...` は 2026-11-06 にコメントにした**（Windows 側から写した名残。`grep -c '^DOCKER_HOST=' .env` は 0）。この値があると手元の `docker` が `Failed to initialize: protocol not available` で止まる。別のマシンに写した `.env` やスキルの注意書きには同じ罠が残りうる。Terraform は `TF_DOCKER_HOST` を見るので、この値を使わない
- `ZBX_ALLOWEDIP` は CIDR とカンマ区切りが効く（2026-11-06 に手元の使い捨て環境で確認。範囲内は 401、範囲外は 403）。`.1-.50` のような範囲指定は効かず、起動時のエラーも無いまま全部 403 になる。LAN から公開ポート経由で繋いだときに送信元 IP がそのまま届くかは未確認で、移行後に見る。403 になればまずここを疑う
- 8.0 のイメージは entrypoint が Go のバイナリで、`docker-entrypoint.sh` は無い。既定のユーザーは 1997。`/var/lib/zabbix` のボリュームは既に 1997 の所有
- MCP の `ZBX_ALLOWEDIP` は GitHub secret `ZBX_MCP_ALLOWEDIP` から渡す（未設定なら loopback のみ）。ツールのルールを書くと既定の拒否リストは置き換わるので、許可リストで書いている
- 本番で `docker run` すると、読み取りの確認でもイメージの pull が起きる（2026-11-05 に `alpine:3.20` を入れてしまい削除した）。確認は動いているコンテナへの `docker exec` で行う
- `check_switchbot.py` のタイムアウトが、移行前からログに出ている（2026-11-05 に確認）。移行後の確認では頻度を比べる

- **応答の中で英字だけの行が「（英語の行を伏せた。日本語での書き直しを待て）」に置き換わり、ユーザーに届かないことがある**（2026-11-01、`!` で打つコマンドを 2 回取りこぼした）。どこで伏せているかは未調査。コマンドを渡すときは「打つコマンド → ! …」のように、日本語と同じ行に入れる
- **PR のマージは Claude からは止められることがある**（2026-11-01、auto mode の判定が `Merge Without Review` で拒否した）。ユーザーがその PR のマージをはっきり指示したときは通った。予告に対してユーザーが別の操作で応じただけでは、マージの許可と読まない
- **`docker logs` が当てにならないことがある**（2026-11-01、Grafana コンテナ）。`--since` が 0 行を返した（2 回）。`--tail 2000` は今日の行を 1 行も返さず、10/27〜10/28 の古い 175 行だけを返した（log driver は `json-file`、ローテーション設定なし。理由は未調査）。`--tail 300` は正しかった。件数を小さくして取り、`t=` の最小・最大を確かめてから数える。ssh の中で awk や grep を何重にも引用すると崩れるので、ログは手元に持ってきて Python で数える
- **wow-exporter のカウンタは、再起動をまたいで続く**（#174 以降）。件数を期間で見るなら `increase(wowhoneypot_http_requests_total[$__range])` を使う。重複を除いた IP 数と上位の一覧は、任意の期間では出せないので `wowhoneypot_recent_*{window="1h|24h|7d"}` を使う。折りたたみ行の累計は「#174 導入以後の通算」になった
- `checkpoint.json` を消すと、次の起動で全部を数え直し、`increase()` が 1 回跳ねる。`first_seen.json` を消すと、手元のログにあるパスがすべて既知として記録し直される
- wow-exporter のテストは `uv venv` で作った venv で動かす（`python3 -m venv` は ensurepip が無く失敗する）。`config/wow-exporter` で `python -m pytest tests`
- wow-exporter のログはホストの `/data/wow-logs` には無い。名前付きボリューム `monitoring-lab-wow_logs` なので、`docker exec monitoring-lab-wow-exporter …` で読む
- Grafana の API（`/api/search` 等）は認証が要る。パスワードは `.env` の `GRAFANA_ADMIN_PASSWORD`。Claude から見られるのは health とコンテナのログまで
- 見た目の調整は、マージの前に手元のファイルをそのまま配り（`! bash scripts/sync-config.sh grafana`）、ユーザーに画面で見てもらってから commit する。配り直せば戻るので、取り返しはつく
- ローテーションの検知は、同期側は「VPS 側が手元より小さい」こと、exporter 側は先頭のハッシュに頼る。同期が 1 周期（週）以上止まると、`.1` も上書きされて取りこぼす
- WOW_VPS_HOST の注入経路: GitHub secret → apply workflow の env → `terragrunt.hcl` の `get_env` → コンテナの env
- イメージは `wow-exporter:latest` 固定なので、作り直しただけではコンテナは入れ替わらない。env かマウントの変更で作り直させる。ビルドはマージの前に行う（`! ( set -a; . ./.env; set +a; bash scripts/build-wow-exporter.sh )`）
- VPS のホスト鍵が変わったら、同期は `Host key verification failed` で止まる。指紋を独立の経路で確かめてから `/home/ubuntu/.ssh/wow-exporter-known_hosts` を差し替える。**指紋やホスト名は、このリポジトリのファイルにも commit メッセージにも書かない**（公開リポジトリ。値は honeypot-vps の SESSION_STATE にある）
- 定期実行のワークフローは、GitHub が自動で止めることがある（`disabled_inactivity`）。止まっても通知は来ない。`gh workflow list --all` で時々見る
- 手元で terragrunt を回すときは CI と同じ版を使う: `mise exec terraform@1.10.5 terragrunt@0.68.0 -- terragrunt …`。plan は env を平文で出すので、値を伏せて表示する
- HCP Terraform のトークン `monitoring-lab-cli` は 2027-10-25 に期限切れ。差し替えは GitHub secret `TF_API_TOKEN` と `.env` の `TF_TOKEN_app_terraform_io` の 2 か所
- Vault はサーバーを再起動すると sealed に戻る（5 本中 3 本で開く）。開け方: リポジトリ直下で `! ( set -a; . ./.env; set +a; for i in 1 2 3; do eval "k=\$VAULT_UNSEAL_KEY_$i"; printf '{"key":"%s"}' "$k" | ssh "${TARGET_USER:-ubuntu}@${TARGET_HOST}" 'curl -sk -X PUT --data @- https://127.0.0.1:8200/v1/sys/unseal' | python3 -c 'import sys,json; s=json.load(sys.stdin); print("sealed", s["sealed"], "progress", s["progress"], "/", s["t"])'; done )`。3 行目が `sealed False` なら開いた
- infra-guard フックは `.env` や `.ssh` を含むコマンドと、terraform/terragrunt の apply を含む文字列（commit メッセージも）を止める。ユーザーが `!` で打つか、メッセージをファイルに書いて `git commit -F` を使う
- infra-guard は、heredoc で書くファイルの中身に `.env`・`.ssh` の文字列があるだけでも止める（2026-11-14）。そういうファイルは Write ツールで書く
- `terragrunt hclfmt --terragrunt-check` は `terraform/envs/local/grafana/terragrunt.hcl` で失敗する。master でも同じなので、変更を確かめるときは master と比べる（2026-11-14）。zabbix のブランチでも整形チェックは通らず、`hclvalidate` は通る
