# 実行環境

## WSL2実行ルール（最重要）

DockerコマンドはWSL2経由で実行すること。Docker Desktop不使用。

```bash
# 基本パターン
wsl -d Ubuntu -- bash -c "docker ..."

# SSH経由でリモート操作
wsl -d Ubuntu -- bash -c "ssh ubuntu@10.0.0.220 'docker ps'"
```

## パス対応表

| 環境 | パス |
|------|------|
| Windows | `C:\work\repos\monitoring-lab-terraform` |
| WSL2 | `/mnt/c/work/repos/monitoring-lab-terraform` |
| WSL2ホーム | `/home/ubuntu/` |
| リモート監視基盤 | `ubuntu@10.0.0.220:/home/ubuntu/monitoring-lab/` |
| VPS (WOWHoneypot) | `root@ik1-427-45900.vs.sakura.ne.jp` |

## SSH鍵

- WSL2: `~/.ssh/id_ed25519`
- コンテナ内: `/root/.ssh/id_ed25519`（docker-compose.ymlで自動コピー）
- wow-exporter用: `/home/ubuntu/.ssh/wow-exporter-key`（リモートサーバー上）

## セッション開始時の確認コマンド

```bash
# WSL2のDocker起動確認
wsl -d Ubuntu -- bash -c "sudo service docker start 2>/dev/null; docker ps --format 'table {{.Names}}\t{{.Status}}'"

# リモートサーバーの状態確認
wsl -d Ubuntu -- bash -c "ssh ubuntu@10.0.0.220 'docker ps --format \"table {{.Names}}\t{{.Status}}\"'"
```

## よくある問題

- WSL2再起動後はDockerサービスが停止している → `sudo service docker start`
- リモートサーバーへのSSHは `~/.ssh/id_ed25519` を使用
- Terragruntキャッシュ肥大化時: `rm -rf terraform/envs/local/.terragrunt-cache`
