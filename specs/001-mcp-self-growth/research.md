# Research: MCP自己成長基盤

**Branch**: `001-mcp-self-growth` | **Date**: 2026-03-01
**Status**: 完了（全NEEDS CLARIFICATION解消済み）

---

## R-001: MCP Server SDK — 技術選択

### Decision: TypeScript + `@modelcontextprotocol/sdk` v1.x

**Rationale**:
- Node.js v22.20.0がWindows/Git Bash環境に存在（Claude Codeが動作する場所）
- `@modelcontextprotocol/sdk` はTypeScript-first、公式ドキュメントの主言語
- stdio transportはClaude Codeのサブプロセスモデルに最適
- stdioはJSON-RPC 2.0メッセージをstdin/stdoutでやり取りする
- Python SDKも選択可能だが、WSL2のPythonからWindowsのClaude Codeへのstdioプロセス起動が複雑

**Alternatives considered**:
- Python (`mcp` SDK + FastMCP): データサイエンスライブラリが必要な場合に有効だが今回は不要
- `tsx` での直接実行（開発時のみ有効、本番はビルド必須）

**Key packages**:
```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.2.0",
    "zod": "^3.22.0",
    "ssh2": "^1.15.0",
    "dockerode": "^4.0.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/ssh2": "^1.15.0",
    "@types/dockerode": "^3.3.0",
    "typescript": "^5.3.0"
  }
}
```

**Critical: Never use `console.log()`**:
stdioトランスポートではstdoutがJSON-RPC 2.0メッセージ専用チャンネル。`console.log()` を使うとプロトコルが破壊される。必ず `console.error()` またはファイルロガーを使用する。

**登録方式**: プロジェクトルートの `.mcp.json`（プロジェクトスコープ）:
```json
{
  "mcpServers": {
    "docker-mcp": {
      "command": "node",
      "args": ["mcp-servers/docker-mcp/dist/index.js"],
      "env": { "SSH_KEY_PATH": "${HOME}/.ssh/monitoring_lab_key" }
    },
    "prometheus-mcp": {
      "command": "node",
      "args": ["mcp-servers/prometheus-mcp/dist/index.js"],
      "env": { "PROMETHEUS_URL": "http://YOUR_SERVER_IP:9090" }
    },
    "terragrunt-mcp": {
      "command": "node",
      "args": ["mcp-servers/terragrunt-mcp/dist/index.js"],
      "env": { "SSH_KEY_PATH": "${HOME}/.ssh/monitoring_lab_key" }
    }
  }
}
```

---

## R-002: リモートDocker操作 — `dockerode` SSH接続

### Decision: `dockerode` + `ssh2` によるSSH経由Docker API接続

**Rationale**:
- ホームLAN（信頼済みネットワーク）で既存のSSH鍵インフラを活用できる
- Docker TCP API（2375/2376）はTLSなしでは危険、TLS設定は過剰な複雑さ
- `dockerode` のSSHサポートがDockerAPIを型安全に使える
- 生のSSHコマンド実行（`ssh ubuntu@YOUR_SERVER_IP docker ps`）は実装がシンプルだが出力解析が必要

**Implementation pattern**:
```typescript
import Docker from 'dockerode';
import fs from 'fs';

const docker = new Docker({
  protocol: 'ssh',
  host: 'YOUR_SERVER_IP',
  port: 22,
  username: 'ubuntu',
  sshOptions: {
    privateKey: fs.readFileSync(process.env.SSH_KEY_PATH!),
    readyTimeout: 30000,
  },
});
```

**セキュリティ考慮**:
- コマンドインジェクション防止: コンテナ名は `/^[a-z0-9_-]+$/` でホワイトリスト検証
- 書き込み操作（restart/stop）は承認チェック関数を経由
- SSH鍵パーミッション: `chmod 600 ~/.ssh/monitoring_lab_key`

**Alternatives considered**:
- Docker TCP 2375（No TLS）: セキュリティリスクが高く却下
- Docker TCP 2376（TLS）: 証明書管理が複雑すぎる、ホームラボ不要
- 生SSH exec: `dockerode` より型安全性が低い、出力パーサーが必要

---

## R-003: Terragrunt リモート実行

### Decision: SSH + `docker exec monitoring-lab-terragrunt`

**Rationale**:
- 既存の作業手順（SESSION_STATE.md）でこの方式が確立済みで動作確認済み
- リモートサーバー上にTerragruntコンテナ（`monitoring-lab-terragrunt`）が存在する
- 追加インフラ不要

**Implementation pattern** (ssh2 Client):
```typescript
async function execTerragrunt(service: string, command: 'plan' | 'apply'): Promise<string> {
  const validServices = ['prometheus', 'grafana', 'postgres', 'vault',
    'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'];
  if (!validServices.includes(service)) throw new Error(`Invalid service: ${service}`);

  const dockerCmd = `docker exec monitoring-lab-terragrunt sh -c ` +
    `'cd /workspace/terraform/envs/local/${service} && terragrunt ${command} 2>&1'`;
  return execViaSsh(dockerCmd);
}
```

---

## R-004: ファイル永続化スキーマ

### Decision: JSONファイル（1提案=1ファイル）+ インデックス

**Rationale**:
- データベース不要でシンプル
- `jq` や直接読み込みで人間が確認可能
- セッションをまたいで保持できる（FR-009 ロールバック要件）
- GitでバージョニングはしないがMarkdownとして読める

**Directory structure**:
```
mcp-servers/.mcp-data/
├── proposals/
│   ├── index.json           # 提案一覧（ID・緊急度・状態のみ）
│   └── <uuid>.json          # 個別提案詳細
├── approvals/
│   ├── index.json
│   └── <uuid>.json          # 承認ログ（スナップショット含む）
└── reports/
    └── <uuid>.json          # 効果測定レポート
```

**JSONスキーマは `data-model.md` に定義**

---

## 解消されたNEEDS CLARIFICATION

| 項目 | 決定 | 根拠 |
|------|------|------|
| MCP SDK言語 | TypeScript | Node.js v22 がWindows側で利用可能 |
| Docker接続方式 | dockerode + SSH | 既存鍵インフラ活用、シンプル |
| MCP登録ファイル | `.mcp.json` (project scope) | チームで共有可能、gitに含める |
| console.log禁止 | console.error + ファイル | stdioプロトコル保護 |
| Terragrunt実行 | SSH + docker exec | 既存確立済み手順 |
| 永続化方式 | JSONファイル | DB不要、人間が読める |
