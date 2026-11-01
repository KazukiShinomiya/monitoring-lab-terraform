# SESSION_STATE

最終更新: 2026-11-01

## 現在の状況

作業の場は WSL の `~/repos/labo`。Windows 側（`/mnt/e/work/labo`）の作業ツリーにはもう触らない。`.env` は Windows 側から写したもので、その後 `WOW_VPS_HOST` と `TF_TOKEN_app_terraform_io` を書き換えた。

2026-10-28 の停電からは復旧済み。残る firing は `SynologyDiskHighUsage` 2 件（warning、停電前から）だけ。

wow-exporter は 2026-11-01 に PR #172 で改修・配備した（下記）。VPS のホスト鍵を固定して同期している（`StrictHostKeyChecking=yes`）。

**「次のローテーションは 2026-11-02 0:00 JST 頃」という前回の記述は誤りだった。取り消す。** 実際は 2026-11-01 0:00 JST（10-31 15:00Z）に起きていた。日付を数え違えたまま、ファイルの時刻を見ずに書いていた。週次の基準は「土曜 → 日曜に替わる 0:00 JST」と読むこと（未検証。次回の時刻で確かめる）。

## 前回の戦果（2026-11-01: ハニーポットの表示を「何を狙われているか」が読める形にした）

- PR #172 をマージ（c285924）。apply の run 41288201668 は success。新しいイメージ `8f9e9d19dffe` のコンテナが再起動 0 回で動いている
- exporter（`config/wow-exporter/exporter/`）
  - `insights.py`: ログに書かれた時刻で 1 時間ごとの箱に数え、直近 24 時間の種類別・上位（パス・IP・UA・ASN・国）を `wowhoneypot_recent_*` で出す。再起動しても値は跳ねない
  - 新顔のパス: 初見の時刻をボリューム `monitoring-lab-wow_state` の `/data/wow-state/first_seen.json` に残し、直近 7 日に初めて現れたパスを `wowhoneypot_new_path_*` で出す。記録が無い初回は、手元のログにあるパスを既知として扱う。180 日来なかったパスは記録から外す
  - 起動時に `.1` を読み、窓の集計と初見だけを埋める（累計には足さない）
  - 分類を 7 種足した（ai-agent=/mcp・/sse、config-leak、backup、app-exploit、vpn-appliance、cms、proxy）。2 世代・13,114 件で `other` が 13.9% → 5.8%
  - 上位ゲージが落ちた系列を残し続ける不具合を直した（20 のはずが 27 系列あった → 20）
  - pytest を初めて導入した（`config/wow-exporter/tests/`、61 件 pass）
- 本番での確認: 起動ログに `bootstrapped with 2469 known paths`。Prometheus で `wowhoneypot_known_paths`=2469、直近 24 時間 701 件・送信元 IP 122、`up`=1
- ダッシュボード `wow-honeypot.json` を 3 段に組み直した（いま何を狙われているか / いつもと違うか / 誰が来ているか）。既存の 31 枚は末尾の折りたたみ行に残した。`sync-config.sh grafana` で配り、配ったファイルの sha が手元と一致、プロビジョニングにエラーは無いことを確認した。**画面での見え方は未検証**（`/api/search` は認証が要り、Claude からは見られない）
- ローテーション（11-01 0:00 JST）の検証: 4 本とも `rotation detected`、VPS の `.1` の大きさは手元と一致（取りこぼしなし）、exporter は 4 本ともオフセットを戻した。ただし継ぎ足しは今回も 0 バイトで、**継ぎ足しの経路は本番では未検証のまま**。VPS 側の `.2.gz` 圧縮は見ていない

## 次の行動

1. （ユーザー）Grafana で `WOWHoneypot - Attack Dashboard` を開き、見え方を確かめる。解説表の高さ、種類の名前が日本語に置き換わっているか、表の列の並び。直す点があれば JSON を直接直す（生成に使ったスクリプトは 2026-11-01 のセッションのスクラッチパッドにしか無く、リポジトリには入れていない）
2. 数日後: `wowhoneypot_new_paths_24h` と新顔の表に何が出ているかを見る。新顔が `other` ばかりなら、分類（`parser.py`）を足す
3. 2026-11-08 以降: 「先週との比較」の先週の列が埋まっているかを見る（メトリクスを入れてから 7 日経つまでは空）
4. `scripts/build-wow-exporter.sh` の手直し: 実行権限が無い（git 上で 100644）、`StrictHostKeyChecking=no`、鍵のパスを `/home/ubuntu/.ssh/id_ed25519` に決め打ちしている（WSL には無く、警告が出て別の鍵で入っている）
5. 次のローテーション（2026-11-08 0:00 JST の見込み、未検証）の後に、`docker exec monitoring-lab-wow-exporter grep -E "rotation detected|WARN|ERROR" /var/log/wow-sync.log` と、exporter のログの `has shrunk` を見る。継ぎ足しが 0 バイトでなければ、そこで初めて経路が検証される。ローテーションの後で `wowhoneypot_recent_*` が欠けないことも見る
6. NAS の容量: `/volume1` が 99.5%、`/volumeUSB1/usbshare` が 100%（`SynologyDiskHighUsage`）。何を消すか移すかはユーザーの判断
7. 自宅サーバーごと落ちると Alertmanager も止まり、誰も気づけない。外から生存を見る仕組みを検討する（未着手）
8. ランナーのイメージタグを 30 日以内に追従させる仕組み（自動アップデートを止めたため）。次の版が出たら上げる
9. HCP トークンの期限を週 1 で見るワークフロー（未着手。GitHub 側ランナーか自宅ランナーかが未決）
10. CVE-2026-98432: https://ubuntu.com/security/CVE-2026-98432 で 24.04 の `linux` に修正版が出たら、このサーバーのカーネルを更新して再起動する（未適用の 78 件も合わせて当てるかは、その時に決める）。カーネルが上がったのを確かめてから、`~/repos/pi-ops` で `ansible-playbook playbooks/mitigate-cve-2026-98432.yml -K --limit monitoring-lab -e cve_mode=absent` を打つ。sudo のパスワードが要るので、本物の端末で打つ
11. （軽い）Dependabot のラベル `dependencies`・`mcp` がリポジトリに無い。作るか `dependabot.yml` から消す

## 決定事項・メモ

- **応答の中で英字だけの行が「（英語の行を伏せた。日本語での書き直しを待て）」に置き換わり、ユーザーに届かないことがある**（2026-11-01、`!` で打つコマンドを 2 回取りこぼした）。どこで伏せているかは未調査。コマンドを渡すときは「打つコマンド → ! …」のように、日本語と同じ行に入れる
- wow-exporter のテストは `uv venv` で作った venv で動かす（`python3 -m venv` は ensurepip が無く失敗する）。`config/wow-exporter` で `python -m pytest tests`
- wow-exporter のログはホストの `/data/wow-logs` には無い。名前付きボリューム `monitoring-lab-wow_logs` なので、`docker exec monitoring-lab-wow-exporter …` で読む
- Grafana の API（`/api/search` 等）は認証が要る。パスワードは `.env` の `GRAFANA_ADMIN_PASSWORD`。Claude から見られるのは health とコンテナのログまで
- `docker logs --since 10m` は、再起動の直後に 0 行を返したことがある（理由は未調査）。件数で判断するときは `--tail N` で取り直す
- ローテーション時、前の世代の末尾は exporter が読む前に入れ替わるので、累計のメトリクスから最大 10 分/回落ちる（許容済み）。直近 24 時間の集計は、起動時に `.1` を読み直すので影響を受けにくい
- 検知は「VPS 側が手元より小さい」ことだけに頼る。同期が 1 周期（週）以上止まると見逃す
- WOW_VPS_HOST の注入経路: GitHub secret → apply workflow の env → `terragrunt.hcl` の `get_env` → コンテナの env
- イメージは `wow-exporter:latest` 固定なので、作り直しただけではコンテナは入れ替わらない。env かマウントの変更で作り直させる。ビルドはマージの前に行う（`! ( set -a; . ./.env; set +a; bash scripts/build-wow-exporter.sh )`）
- exporter は起動のたびにログ全体を集計し直す。累計の Counter の `rate()` は再起動の直後に跳ねるので、傾向を見るなら `wowhoneypot_recent_*` を使う
- VPS のホスト鍵が変わったら、同期は `Host key verification failed` で止まる。指紋を独立の経路で確かめてから `/home/ubuntu/.ssh/wow-exporter-known_hosts` を差し替える。**指紋やホスト名は、このリポジトリのファイルにも commit メッセージにも書かない**（公開リポジトリ。値は honeypot-vps の SESSION_STATE にある）
- 定期実行のワークフローは、GitHub が自動で止めることがある（`disabled_inactivity`）。止まっても通知は来ない。`gh workflow list --all` で時々見る
- 手元で terragrunt を回すときは CI と同じ版を使う: `mise exec terraform@1.10.5 terragrunt@0.68.0 -- terragrunt …`。plan は env を平文で出すので、値を伏せて表示する
- HCP Terraform のトークン `monitoring-lab-cli` は 2027-10-25 に期限切れ。差し替えは GitHub secret `TF_API_TOKEN` と `.env` の `TF_TOKEN_app_terraform_io` の 2 か所
- Vault はサーバーを再起動すると sealed に戻る（5 本中 3 本で開く）。開け方: リポジトリ直下で `! ( set -a; . ./.env; set +a; for i in 1 2 3; do eval "k=\$VAULT_UNSEAL_KEY_$i"; printf '{"key":"%s"}' "$k" | ssh "${TARGET_USER:-ubuntu}@${TARGET_HOST}" 'curl -sk -X PUT --data @- https://127.0.0.1:8200/v1/sys/unseal' | python3 -c 'import sys,json; s=json.load(sys.stdin); print("sealed", s["sealed"], "progress", s["progress"], "/", s["t"])'; done )`。3 行目が `sealed False` なら開いた
- infra-guard フックは `.env` や `.ssh` を含むコマンドと、terraform/terragrunt の apply を含む文字列（commit メッセージも）を止める。ユーザーが `!` で打つか、メッセージをファイルに書いて `git commit -F` を使う
