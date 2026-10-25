# SESSION_STATE

最終更新: 2026-10-25

## 現在の状況

作業の場は WSL の `~/repos/labo`。Windows 側（`/mnt/e/work/labo`）の作業ツリーにはもう触らない。`.env` は Windows 側から写したもので、その後 `WOW_VPS_HOST` と `TF_TOKEN_app_terraform_io` を書き換えた。

wow-exporter はローテーション対応の `sync-logs.sh` を積み、`wowsync@` で VPS から同期している。Vault を unseal し、apply（run 40159712685 attempt 4）は全モジュール差分なしで緑。

honeypot-vps 側も片付いた（root 鍵 2 本の撤去・`PermitRootLogin no`・logrotate 有効化。詳細は honeypot-vps の SESSION_STATE）。VPS の logrotate を 2026-10-25 06:00Z に手で 1 回回し、labo 側が追従することを確かめた。

## 前回の戦果（2026-10-25）

- `sync-logs.sh` のローテーション対応（c25a623）。`--list-only` で VPS 側の大きさを読み、手元より小さければ `<名前>.1` を `--append` で引き切ってから手元を `<名前>.1` へ退避し、新ファイルを引く
  - 手元の `/usr/bin/rrsync -ro` に偽の ssh をかませて 9 通りを確認した（初回・追記・ローテーション・0 バイトの新ファイル・`.1` 不足時の WARN・HTTPS 無し・必須欠落で rc=1 など）
- `scripts/build-wow-exporter.sh` が `TARGET_USER`/`TARGET_HOST`/`TARGET_PORT` を読むように変更（468d07c）。ファイルは 100644 なので `bash` 経由で実行する
- `WOW_VPS_HOST` を `wowsync@` に切り替えた（GitHub secret と `.env`）。コンテナの env が `wowsync@` で始まること、初回同期の成功、exporter の 4 本のオフセットがファイルの大きさと一致することを、2026-10-25 04:30Z に実機で確認した
- HCP Terraform のユーザートークン（`monitoring-lab-cli`）が 2026-09-05 に期限切れになっていた。新しく発行し、`TF_API_TOKEN` と `.env` の両方を差し替えた（`account/details` が 200 を返すことを確認）

- 手動ローテーション（06:00Z）への追従を実機で確認: `/var/log/wow-sync.log` に 06:10Z、4 本とも `rotation detected`（WARN・ERROR なし）、手元の `.1` 4 本の大きさは VPS 側の `.1` と一致。exporter は 06:14:59Z に 4 本とも `has shrunk` でオフセットを戻し、09:00Z 時点のオフセットは 4 本とも新ファイルの大きさと一致
  - ただしこの回は手元 = VPS の `.1` で、`.1` からの継ぎ足しは 0 バイトだった。末尾がある場合の継ぎ足しは手元の試験でしか確かめていない（本番では未検証）

- Vault の sealed 検知を入れた（3acc4a4）: blackbox-exporter v0.28.0 が `/v1/sys/health` を 200 のみ成功として叩き、`VaultSealedOrDown`（`probe_success == 0` が 5 分で critical）。本番で targets 16 本すべて up、規則 ok/inactive、`probe_success` 1 を確認。503/501/名前解決失敗で 0 になることは一時コンテナで確認（Vault を実際に閉じての発火→Slack 到達は未検証）
- 新モジュールの workspace が HCP の既定でリモート実行になり apply が Docker に届かず失敗した。workspace と organization の Default Execution Mode を Local に変更（ユーザーが画面で実施）

## 次の行動

1. 自然なローテーション（2026-11-02 0:00 JST 頃）の後に、`docker exec monitoring-lab-wow-exporter grep -E "rotation detected|WARN|ERROR" /var/log/wow-sync.log` と exporter のログの `has shrunk` を見る。この回で初めて `.1` からの継ぎ足しが 0 バイトでなくなるはず。VPS 側では `.1` → `.2.gz` の圧縮も初めて起きる
2. `sync-logs.sh` の `StrictHostKeyChecking=no` をやめ、VPS のホスト鍵を固定する（honeypot-vps 側から挙がった宿題。未着手）
3. HCP トークンの期限を週 1 で見るワークフロー（未着手。GitHub 側ランナーか自宅ランナーかが未決）
4. ハニポの外形監視（VPS の 80/443）を blackbox に足す（honeypot-vps の次の行動 4。未着手）

## 決定事項・メモ

- ローテーション時、前の世代の末尾は exporter が読む前に入れ替わるので、メトリクスから最大 10 分/回落ちる。生ログは手元の `.1` と VPS の世代に残るため許容した（2 段化は途中状態が増えるので採らない）
- 検知は「VPS 側が手元より小さい」ことだけに頼る。同期が 1 周期（週）以上止まると見逃すが、そのときは `.1` も圧縮済みで、どの方式でも引き切れない
- `/data/wow-logs` を読むのは wow-exporter だけ（サーバー上で `docker ps --filter volume=` を使って確認）。promtail は docker_sd のみ
- WOW_VPS_HOST の注入経路: GitHub secret → apply workflow の env → `terragrunt.hcl` の `get_env` → コンテナの env。`.env` が効くのは手元で terragrunt を回すときだけ
- イメージは `wow-exporter:latest` 固定なので、イメージを作り直しただけでは再作成されない。env の変更で再作成させる。ビルドは push の前に行う
- exporter は起動のたびにログ全体を集計し直す（HTTP 側は約 1 分）
- HCP Terraform のユーザートークン `monitoring-lab-cli` は 2027-10-25 に期限切れ（1 年）。古い期限切れのトークンは 2026-10-25 に削除済み（ユーザー申告）。差し替えは GitHub secret `TF_API_TOKEN` と `.env` の `TF_TOKEN_app_terraform_io` の 2 か所
- Vault はサーバー再起動で sealed に戻る（5 本中 3 本で開く。鍵は `.env` の `VAULT_UNSEAL_KEY_1`〜`5`）。2026-07-24 頃の再起動以来 sealed だった（推測）。開け方: `.env` を読み込み、鍵を `{"key":"…"}` にしてサーバー上の `curl -sk -X PUT --data @- https://127.0.0.1:8200/v1/sys/unseal` へ ssh の標準入力で 3 回送る（鍵が画面とプロセス一覧に出ない）
- infra-guard フックは `.env` や `.ssh` を含むコマンドを止める。これらはユーザーが `!` で打つ。値を表示しない確かめ方（長さ・一致判定）を使うこと
