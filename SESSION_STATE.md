# SESSION_STATE

最終更新: 2026-10-28

## 現在の状況

作業の場は WSL の `~/repos/labo`。Windows 側（`/mnt/e/work/labo`）の作業ツリーにはもう触らない。`.env` は Windows 側から写したもので、その後 `WOW_VPS_HOST` と `TF_TOKEN_app_terraform_io` を書き換えた。

2026-10-28 にブレーカーが落ち、自宅サーバー・NAS・10.0.0.250 が同時に止まった。サーバーは復帰し、Vault を unseal、CI ランナーを直し、apply（run 40693432147）は緑。NAS（10.0.0.200）と 10.0.0.250 は自然に復帰（NAS は up=1、10.0.0.250 は HDD 5 台ともマウント済み、`TargetDown`・`FilesystemMountDisappeared` は解消）。残る firing は `SynologyDiskHighUsage` 2 件（warning）だけで、これは停電前から 7 日以上続いているもの。

wow-exporter は VPS のホスト鍵を固定して同期している（`StrictHostKeyChecking=yes`）。

## 前回の戦果（2026-10-28）

- VPS のホスト鍵を固定した（41ad40c）。鍵 1 行をサーバーの `/home/ubuntu/.ssh/wow-exporter-known_hosts`（644・ubuntu・111 バイト）に置き、`/root/.ssh/known_hosts_wow` へ read-only でマウント。ホスト名を含むのでリポジトリには置かない
  - 41ad40c の commit メッセージに指紋を書いてしまい（公開リポジトリ）、VPS とこのリポジトリを結ぶ手がかりになったため、同日 VPS の ed25519 ホスト鍵を作り直し、known_hosts を差し替えた（13:39Z の同期で成功を確認）。**指紋やホスト名は、このリポジトリのファイルにも commit メッセージにも書かない**。値と経緯は honeypot-vps の SESSION_STATE にある
  - 最初の鍵の指紋は、サーバーからの `ssh-keyscan` と WSL の known_hosts（Ansible 接続時の記録）の 2 経路で照合。業者コンソールでの照合はしていない
  - 一時コンテナで、正しい鍵は rc=0、偽の鍵は rc=255 と `Host key verification failed` を確認。本番で起動時（13:07Z）と cron（13:10Z）の同期が成功し、4 本のオフセットがファイルの大きさと一致（13:12Z）
- CI ランナーを直した（e85bfd2）。停電で自動アップデート（2.336.0 → 2.338.0）が途中で止まり `bin` が欠け、終了コード 127 で再起動ループしていた。イメージを 2.338.2 に上げ、`DISABLE_AUTO_UPDATE=true` で自動アップデートを止めた
  - ランナー自身が壊れていたので、復旧の apply は手元から CI と同じ版（terraform 1.10.5 / terragrunt 0.68.0、mise で導入）で実施。手元の 1.16 で state を書くと CI が読めなくなるため
- `VaultSealedOrDown` が停電後に firing になることを本番で確認（12:17Z）。Alertmanager は起動後に Slack へ 9 件送り失敗 0（`alertmanager_notifications_total{integration="slack"}`）。どの 1 件が Vault のものかまでは記録に残らない

## 次の行動

1. 自然なローテーション（2026-11-02 0:00 JST 頃）の後に、`docker exec monitoring-lab-wow-exporter grep -E "rotation detected|WARN|ERROR" /var/log/wow-sync.log` と exporter のログの `has shrunk` を見る。この回で初めて `.1` からの継ぎ足しが 0 バイトでなくなるはず（本番では未検証）。VPS 側では `.1` → `.2.gz` の圧縮も初めて起きる。ホスト鍵固定後の初のローテーションでもある
2. NAS の容量: `/volume1` が 99.5%、`/volumeUSB1/usbshare` が 100%（`SynologyDiskHighUsage`、2026-10-21 以前から firing）。何を消すか移すかはユーザーの判断
3. 自宅サーバーごと落ちると Alertmanager も止まり、誰も気づけない。外から生存を見る仕組みを検討（未着手）
4. ランナーのイメージタグを 30 日以内に追従させる仕組み（自動アップデートを止めたため。期限を過ぎると GitHub がジョブを回さなくなる）。次の版が出たら上げる
5. HCP トークンの期限を週 1 で見るワークフロー（未着手。GitHub 側ランナーか自宅ランナーかが未決）

## 決定事項・メモ

- ローテーション時、前の世代の末尾は exporter が読む前に入れ替わるので、メトリクスから最大 10 分/回落ちる。生ログは手元の `.1` と VPS の世代に残るため許容した（2 段化は途中状態が増えるので採らない）
- 検知は「VPS 側が手元より小さい」ことだけに頼る。同期が 1 周期（週）以上止まると見逃すが、そのときは `.1` も圧縮済みで、どの方式でも引き切れない
- `/data/wow-logs` を読むのは wow-exporter だけ（サーバー上で `docker ps --filter volume=` を使って確認）。promtail は docker_sd のみ
- WOW_VPS_HOST の注入経路: GitHub secret → apply workflow の env → `terragrunt.hcl` の `get_env` → コンテナの env。`.env` が効くのは手元で terragrunt を回すときだけ
- イメージは `wow-exporter:latest` 固定なので、イメージを作り直しただけでは再作成されない。env かマウントの変更で再作成させる。ビルドは push の前に行う
- exporter は起動のたびにログ全体を集計し直す（HTTP 側は約 1 分）。オフセットは `wowhoneypot_processed_lines`（バイト）で見る。読み直しは 300 秒ごと
- VPS のホスト鍵が変わったら（OS 再インストール等）同期は `Host key verification failed` で止まる。そのときは指紋を独立の経路で確かめてから `/home/ubuntu/.ssh/wow-exporter-known_hosts` を差し替える
- 手元で terragrunt を回すときは CI と同じ版を使う: `mise exec terraform@1.10.5 terragrunt@0.68.0 -- terragrunt …`。plan は env を平文で出すので `ACCESS_TOKEN=` を伏せて表示する
- HCP Terraform のユーザートークン `monitoring-lab-cli` は 2027-10-25 に期限切れ（1 年）。古い期限切れのトークンは 2026-10-25 に削除済み（ユーザー申告）。差し替えは GitHub secret `TF_API_TOKEN` と `.env` の `TF_TOKEN_app_terraform_io` の 2 か所
- Vault はサーバー再起動で sealed に戻る（5 本中 3 本で開く。鍵は `.env` の `VAULT_UNSEAL_KEY_1`〜`5`）。開け方: リポジトリ直下で `! ( set -a; . ./.env; set +a; for i in 1 2 3; do eval "k=\$VAULT_UNSEAL_KEY_$i"; printf '{"key":"%s"}' "$k" | ssh "${TARGET_USER:-ubuntu}@${TARGET_HOST}" 'curl -sk -X PUT --data @- https://127.0.0.1:8200/v1/sys/unseal' | python3 -c 'import sys,json; s=json.load(sys.stdin); print("sealed", s["sealed"], "progress", s["progress"], "/", s["t"])'; done )`（鍵が画面とプロセス一覧に出ない。3 行目が `sealed False` なら開いた）。sealed のままだと apply の `vault-secrets` が 503 で落ちる
- infra-guard フックは `.env` や `.ssh` を含むコマンドと、terraform/terragrunt の apply を含む文字列（commit メッセージも）を止める。これらはユーザーが `!` で打つか、メッセージをファイルに書いて `git commit -F` を使う。値を表示しない確かめ方（長さ・一致判定）を使うこと
