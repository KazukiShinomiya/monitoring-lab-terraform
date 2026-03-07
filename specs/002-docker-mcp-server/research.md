# Research: Docker MCP Server

**Date**: 2026-03-07 | **Branch**: `002-docker-mcp-server`

---

## R-001: Claude CodeとDockerコンテナMCPサーバーの接続方式

**Decision**: `docker run --rm -i` + stdio トランスポート

**Rationale**:
Claude Code の MCP設定（`.claude/settings.json` または `claude_desktop_config.json`）で以下のように定義する:
```json
{
  "mcpServers": {
    "docker": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "--mount", "type=bind,src=${HOME}/.ssh/id_rsa,dst=/root/.ssh/id_rsa,readonly",
        "monitoring-lab-docker-mcp"
      ]
    }
  }
}
```
- `--rm`: セッション終了時に自動削除
- `-i`: stdin を維持（MCP stdio通信に必須）
- SSH鍵はread-onlyマウントで渡す

**Alternatives considered**:
- HTTP/SSE transport: 常時起動サーバーが必要で複雑。stdio で十分。
- `docker exec` で既存コンテナに接続: コンテナが常時起動している前提が必要。

---

## R-002: Node.jsからDocker SSH接続の実装方式

**Decision**: `child_process.execFile` で `docker` CLI を直接呼び出す（`-H ssh://ubuntu@YOUR_SERVER_IP`）

**Rationale**:
```typescript
import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

async function dockerExec(args: string[]): Promise<string> {
  const { stdout } = await execFileAsync('docker', [
    '-H', 'ssh://ubuntu@YOUR_SERVER_IP',
    ...args
  ]);
  return stdout;
}
```
- 追加のNPMパッケージ不要（`dockerode`等）
- `docker` CLI が既にコンテナ内に存在する前提（Dockerfileでインストール）
- SSH鍵がマウントされていれば認証は自動

**Alternatives considered**:
- `dockerode`: Node.js Docker SDK。SSH接続はDockerContextの設定が複雑。
- `ssh2` npm パッケージ直接: 低レベルすぎる。docker CLI ラッパーが最もシンプル。

---

## R-003: MCP ツールの承認フロー実装

**Decision**: 操作系ツールに `confirmed: boolean` パラメーターを必須化。`false` または未指定時はドライランとして操作内容を返すのみ。

**Rationale**:
```typescript
// ツールスキーマ例
{
  name: "docker_restart_container",
  inputSchema: {
    type: "object",
    properties: {
      container_name: { type: "string", description: "コンテナ名（部分一致可）" },
      confirmed: {
        type: "boolean",
        description: "true の場合のみ実際に再起動を実行。false の場合は操作内容を表示して終了。"
      }
    },
    required: ["container_name", "confirmed"]
  }
}
```

Claude Code は以下のフローで操作する:
1. `confirmed: false` でツールを呼び出す → 「monitoring-lab-grafana を再起動します。よろしいですか？」を返す
2. ユーザーに確認を取る
3. 同意を得たら `confirmed: true` で再度呼び出す → 実行

これにより FR-007, FR-008 を技術的に強制できる。

**Alternatives considered**:
- Claude の指示レベルで「必ず確認を取れ」と定義する: 実装の強制力がなく、プロンプト変更で迂回できる。
- ツール名を `docker_restart_container_dry_run` と `docker_restart_container_execute` に分ける: 冗長。

---

## R-004: 既存状態チェック（FR-011相当）

**Decision**: 操作系ツールは実行前にコンテナの現在の状態を確認し、既に目的の状態にある場合はエラーを返す。

**Rationale**:
```typescript
// start_container の例
const status = await getContainerStatus(containerName);
if (status === 'running') {
  return { error: `${containerName} は既に running 状態です。操作は不要です。` };
}
```
Edge Case 仕様（「既に目的の状態にあるコンテナへの操作は事前キャンセル」）に対応。

---

## R-005: Dockerfile 設計

**Decision**: `node:22-alpine` ベースイメージ + Docker CLI インストール

```dockerfile
FROM node:22-alpine

# Docker CLI インストール（SSH接続用）
RUN apk add --no-cache docker-cli openssh-client

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY dist/ ./dist/

# SSHホスト検証をスキップ（自宅ラボ環境）
RUN mkdir -p /root/.ssh && echo "StrictHostKeyChecking no" > /root/.ssh/config

CMD ["node", "dist/index.js"]
```

**Alternatives considered**:
- `node:22-slim`: docker-cli, openssh-client のインストールが apt で若干重い。Alpine が軽量。
- `docker:latest` ベース: Node.js の追加インストールが逆に重くなる。

---

## R-006: MCPツール一覧（確定）

| ツール名 | 機能 | 承認必須 |
|---------|------|---------|
| `docker_list_containers` | 全コンテナの名前・状態・起動経過時間を取得 | 不要 |
| `docker_get_logs` | 指定コンテナの直近ログ取得（デフォルト100行） | 不要 |
| `docker_get_stats` | 全コンテナのCPU・メモリ使用量を取得 | 不要 |
| `docker_restart_container` | コンテナを再起動（confirmed=true で実行） | 必要 |
| `docker_stop_container` | コンテナを停止（confirmed=true で実行） | 必要 |
| `docker_start_container` | コンテナを起動（confirmed=true で実行） | 必要 |
