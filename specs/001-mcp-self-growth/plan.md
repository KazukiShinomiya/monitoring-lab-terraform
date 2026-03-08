# Implementation Plan: MCP自己成長基盤

**Branch**: `001-mcp-self-growth` | **Date**: 2026-03-01 | **Spec**: [spec.md](./spec.md)
**Input**: MCP自己成長基盤 — Claude CodeがPrometheus/Docker/Terragruntを操作するカスタムMCPサーバー群を構築し、観測→AI分析→改善提案→人間承認→適用→効果測定のループを実現する

---

## Summary

3つのカスタムMCPサーバー（Docker MCP・Prometheus MCP・Terragrunt MCP）をTypeScript/Node.jsで実装し、Claude Codeのサブプロセスとしてstdio経由で接続する。各サーバーはSSH経由でリモートホスト（10.0.0.220）にアクセスし、操作結果をローカルJSONファイルに永続化する。人間の明示的な承認なしにインフラへの変更は行わない。

---

## Technical Context

**Language/Version**: TypeScript 5.x + Node.js v22.20.0（Windows Git Bash環境で利用可能）
**Primary Dependencies**:
- `@modelcontextprotocol/sdk` — MCP Server SDK（stdio transport）
- `node-fetch` または組み込み `fetch`（Node.js 22）— Prometheus HTTP API呼び出し
- `ssh2` または `child_process`（`ssh` コマンド経由）— リモートDocker/Terragrunt操作
- `tsx` — TypeScriptの直接実行（ts-nodeの代替、軽量）
- `zod` — ツール引数のバリデーション

**Storage**: ローカルJSON/Markdownファイル（`.specify/memory/proposals/`、`.specify/memory/approvals/`）
**Testing**: 手動テスト + 独立したIntegrationテスト（将来）
**Target Platform**: Windows 11（Git Bash経由でClaude Codeが起動）→ SSHでリモートDocker（10.0.0.220）
**Performance Goals**: 個人ホームラボ用途のため厳密なSLA不要。PromQL応答 <5s、Docker stats <10s
**Constraints**:
- 自動適用禁止（Constitution II・FR-006）
- 各MCP Serverは独立して動作可能（FR-010）
- stdioトランスポート必須（FR-011）
- Claude Code設定ファイルへの登録必須（FR-012）

**Scale/Scope**: シングルユーザー（ジント1名）、9コンテナ監視、3 MCPサーバー

---

## Constitution Check

*GATE: Phase 0研究開始前に評価。Phase 1設計後に再評価。*

| 原則 | 評価 | 判定 |
|------|------|------|
| **I. IaC** | MCPサーバーはローカルプロセス（stdio）として動作し、インフラ変更は既存Terragruntを通じて行う。MCPサーバー自体はNode.jsパッケージであり、Dockerコンテナではない（ローカル実行のため不要）。Terragrunt MCPはplan/applyを呼び出すが、変更の実体はHCP TerraformとTerragruntで管理される。 | ✅ PASS |
| **II. セキュリティ** | FR-006が自動適用を明示的に禁止。承認ログにシークレットを記録しない。SSH鍵は`~/.ssh/monitoring_lab_key`（.envで参照）。Prometheusエンドポイントは認証なし（ホームLAN内のみ）。 | ✅ PASS |
| **III. ドキュメント駆動** | 本planがspecの後に作成されている。全ツールの入出力スキーマをcontracts/に定義する（Phase 1）。 | ✅ PASS |
| **IV. DRY** | 3つのMCPサーバー間でSSH実行ヘルパー・ファイル永続化ヘルパー・TypeScript型定義を`mcp-servers/shared/`で共有する。 | ✅ PASS |
| **V. 自己監視** | MCPサーバーはローカルプロセスであるため、Prometheus/Zabbixの監視対象にはならない。代わりに起動ログをファイルに記録し、`/status` ツールで健全性を確認できるようにする。 | ✅ PASS（ホームラボ許容範囲内） |

**Constitution Check結果**: 全原則 PASS。Phase 0研究を開始する。

---

## Project Structure

### Documentation（このフィーチャー）

```text
specs/001-mcp-self-growth/
├── plan.md              ← このファイル
├── research.md          ← Phase 0 出力（本コマンドで生成）
├── data-model.md        ← Phase 1 出力（本コマンドで生成）
├── quickstart.md        ← Phase 1 出力（本コマンドで生成）
├── contracts/           ← Phase 1 出力（本コマンドで生成）
│   ├── docker-tools.ts
│   ├── prometheus-tools.ts
│   └── terragrunt-tools.ts
└── tasks.md             ← Phase 2 出力（/speckit.tasks コマンドで生成）
```

### Source Code（リポジトリルート）

```text
mcp-servers/
├── shared/                    # 共通ユーティリティ
│   ├── src/
│   │   ├── types.ts           # 共有型定義（Proposal, ApprovalLog, EffectReport）
│   │   ├── ssh.ts             # SSH実行ヘルパー
│   │   ├── storage.ts         # ファイル永続化ヘルパー
│   │   └── config.ts          # 環境変数読み込み（SSH_HOST, SSH_KEY_PATH等）
│   ├── package.json
│   └── tsconfig.json
│
├── docker-mcp/                # MCP Server 1: Docker操作
│   ├── src/
│   │   ├── index.ts           # エントリポイント（McpServer起動）
│   │   └── tools/
│   │       ├── listContainers.ts
│   │       ├── getContainerLogs.ts
│   │       ├── getContainerStats.ts
│   │       └── restartContainer.ts
│   ├── package.json
│   └── tsconfig.json
│
├── prometheus-mcp/            # MCP Server 2: Prometheusクエリ
│   ├── src/
│   │   ├── index.ts
│   │   └── tools/
│   │       ├── queryMetrics.ts
│   │       ├── getActiveAlerts.ts
│   │       ├── analyzeRange.ts
│   │       └── compareMetrics.ts
│   ├── package.json
│   └── tsconfig.json
│
├── terragrunt-mcp/            # MCP Server 3: Terragrunt操作
│   ├── src/
│   │   ├── index.ts
│   │   └── tools/
│   │       ├── planService.ts
│   │       ├── applyService.ts
│   │       ├── listWorkspaces.ts
│   │       └── rollbackService.ts
│   ├── package.json
│   └── tsconfig.json
│
└── .mcp-data/                 # ファイル永続化ストレージ（.gitignoreに追加）
    ├── proposals/             # AIが生成した改善提案（JSON）
    ├── approvals/             # 承認ログ（スナップショット含む）
    └── reports/               # 効果測定レポート
```

**Structure Decision**: Single-project相当だが、3つのMCPサーバーを独立したnpmパッケージとして分離（FR-010: 各サーバー独立動作）。`shared/` でコードを共有しDRY原則を守る。

---

## Complexity Tracking

| 項目 | 理由 | 代替案を却下した理由 |
|------|------|---------------------|
| 3つの独立npmパッケージ | FR-010: 各MCPサーバーは単独で価値を提供できること | モノリシックなMCPサーバー1つでは、1つのバグ/停止で全機能が失われる |
| TypeScript（Pythonではなく） | Node.js v22がWindows側で利用可能、MCP公式SDKがTypeScript優先 | WSL2のPythonはClaude CodeのWindowsプロセスから起動が複雑 |
| SSH経由Docker操作（Docker TCPではなく） | ホームラボの信頼済みネットワーク内でシンプルかつ安全 | Docker TCP（2375）はTLSなしでは危険、TLS設定は複雑すぎる |

---

## Phase 0: Research

*研究タスク（エージェント並列実行 + Web調査）*

### R-001: MCP Server TypeScript SDK — 構造と登録方法

**決定**: TypeScript（`@modelcontextprotocol/sdk`）を採用

**理由**:
- Node.js v22.20.0がWindows/Git Bash環境に存在（Claude Codeが動作する環境）
- `@modelcontextprotocol/sdk` はTypeScript-first、公式ドキュメントはTypeScriptで記述
- stdio transport（Claude Codeのサブプロセスモデル）との相性が最良
- WSL2上のPythonでも可能だが、Windows→WSL2のプロセス起動は設定が複雑

**最小構造**:
```typescript
// index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({ name: "docker-mcp", version: "1.0.0" });

server.tool("list_containers", {}, async () => ({
  content: [{ type: "text", text: await listContainers() }]
}));

const transport = new StdioServerTransport();
await server.connect(transport);
```

**Claude Code設定への登録** (プロジェクトルートの `.mcp.json`・プロジェクトスコープ):
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
      "env": { "PROMETHEUS_URL": "http://10.0.0.220:9090" }
    },
    "terragrunt-mcp": {
      "command": "node",
      "args": ["mcp-servers/terragrunt-mcp/dist/index.js"],
      "env": { "SSH_KEY_PATH": "${HOME}/.ssh/monitoring_lab_key" }
    }
  }
}
```

**⚠️ 重要: `console.log()` 禁止**:
stdioトランスポートではstdoutがJSON-RPC 2.0専用。`console.log()` でプロトコルが破壊される。必ず `console.error()` またはファイルロガーを使用。

**検討した代替案**: Python MCP SDK、`tsx`でのts直接実行（開発時）

---

### R-002: リモートDocker操作 — SSHコマンド実行方式

**決定**: `child_process.execSync`/`exec`でSSHコマンドを実行する方式を採用

**理由**:
- ホームLAN（信頼済みネットワーク）内でシンプルかつ安全
- `ssh ubuntu@10.0.0.220 docker ps` という形式で十分
- Docker TCP API（2375/2376）はTLS設定が必要で複雑
- `dockerode`のSSHサポートは `ssh2` ライブラリに依存し、追加設定が必要
- 読み取り操作のみ（コンテナ停止・再起動は承認後のみ）

**実装パターン**:
```typescript
// shared/src/ssh.ts
import { execSync } from "child_process";

export function sshExec(command: string): string {
  const sshOpts = "-o StrictHostKeyChecking=no -o ConnectTimeout=10";
  const sshKey = process.env.SSH_KEY_PATH ?? "~/.ssh/monitoring_lab_key";
  return execSync(
    `ssh ${sshOpts} -i ${sshKey} ubuntu@10.0.0.220 "${command}"`,
    { encoding: "utf-8", timeout: 30000 }
  );
}

// 使用例
sshExec("docker ps --format '{{json .}}'")
sshExec("docker logs monitoring-lab-prometheus --tail 50")
sshExec("docker stats --no-stream --format '{{json .}}'")
```

**セキュリティ考慮**:
- コマンドインジェクション防止: 引数はホワイトリスト検証（コンテナ名は`^[a-z0-9_-]+$`）
- 書き込み操作（restart/apply）は承認チェック関数を通す

---

### R-003: Terragrunt リモート実行

**決定**: SSH + `docker exec monitoring-lab-terragrunt` 方式

**理由**:
- 既存の作業手順（セッション記録）でこの方式が確立済み
- WSL2上のdockerコマンドをSSH経由でリモートサーバーに実行する必要はない
  （リモートサーバーにTerragruntコンテナがある）

**実装パターン**:
```typescript
// terragrunt-mcp/src/tools/planService.ts
export async function planService(serviceName: string): Promise<string> {
  validateServiceName(serviceName);  // ホワイトリスト検証
  return sshExec(
    `docker exec monitoring-lab-terragrunt sh -c ` +
    `'cd /workspace/terraform/envs/local/${serviceName} && terragrunt plan 2>&1'`
  );
}
```

---

### R-004: ファイル永続化スキーマ

**決定**: JSONファイル（1提案=1ファイル）+ インデックスファイル

**理由**:
- データベース不要でシンプル
- 人間が直接読める（Markdownレポート）
- セッションをまたいで保持できる（FR-009）

