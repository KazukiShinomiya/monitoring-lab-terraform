# Implementation Plan: Docker MCP Server

**Branch**: `002-docker-mcp-server` | **Date**: 2026-03-07 | **Spec**: [spec.md](./spec.md)

## Summary

Claude CodeがリモートDocker（10.0.0.220）をSSH経由で操作できるMCPサーバーをTypeScriptで実装する。
コンテナ一覧・ログ・リソース確認（読み取り系）と、承認フロー付きの再起動・停止・起動（操作系）を6つのMCPツールとして提供する。
MCPサーバーはDockerコンテナとして起動し、Claude Codeは `docker run` 経由でstdioで接続する。

## Technical Context

**Language/Version**: TypeScript 5.x + Node.js v22.20.0 (LTS)
**Primary Dependencies**: `@modelcontextprotocol/sdk` (MCP通信), `zod` (スキーマバリデーション)
**Docker接続**: `child_process` 経由で `docker -H ssh://ubuntu@10.0.0.220` CLI を実行
**Storage**: N/A（ステートレス設計）
**Testing**: Vitest（ユニットテスト）
**Target Platform**: Docker コンテナ（ローカル開発環境上で Claude Code が `docker run` で起動）
**Project Type**: Single project（`mcp/docker-server/`）
**Performance Goals**: 読み取り系ツール応答 < 10秒（SC-002準拠）
**Constraints**: SSH鍵を `/root/.ssh/id_rsa` にマウント、リモートホスト `10.0.0.220` のみ対象

## Constitution Check

### I. Infrastructure as Code (IaC) ✅

本MCPサーバーはリモート監視基盤（10.0.0.220）ではなく、ローカル開発環境上で動作する開発ツール。
既存の `docker-compose.yml`（Terragrunt/Terraform開発コンテナと同方式）でサービス定義する。
監視基盤コンテナ（Prometheus等）は引き続きTerragrunt管理。

### II. セキュリティファースト ✅

- SSH鍵はコンテナ起動時に `--mount type=bind,src=~/.ssh/id_rsa,dst=/root/.ssh/id_rsa,readonly` でマウント。コード内にシークレットなし。
- 操作系ツールはすべて `confirmed: true` パラメーターが必須。パラメーター未指定時はドライランとして扱う。
- コンテナ作成・削除・イメージ操作は実装しない（FR-009）。

### III. ドキュメント駆動開発 ✅

Speckit ADLC: specify → clarify → plan（本文書）→ tasks → implement の順序に従っている。

### IV. モジュール化とDRY原則 ✅

- Docker CLI実行ロジックを `DockerClient` クラスに集約（ツール間で共有）。
- 各ツールは `src/tools/` に単一責任で分離。

### V. 自己監視の可観測性 ⚠️（条件付き合格）

本MCPサーバーはローカル開発ツールとして `docker run --rm` で起動するため、常時稼働コンテナではない。
Prometheusスクレイプ対象としての監視は適用外。
ただし、接続エラー・操作エラーを stderr にログ出力し、問題追跡を可能とする。

## Project Structure

### Documentation (this feature)

```text
specs/002-docker-mcp-server/
├── plan.md              # このファイル
├── research.md          # Phase 0 調査結果
├── data-model.md        # Phase 1 データモデル・ツールスキーマ
├── quickstart.md        # Phase 1 セットアップガイド
├── contracts/           # Phase 1 MCPツール定義
└── tasks.md             # Phase 2 (/speckit.tasks で生成)
```

### Source Code (repository root)

```text
mcp/
└── docker-server/
    ├── src/
    │   ├── index.ts              # MCPサーバーエントリポイント
    │   ├── docker-client.ts      # Docker SSH接続クライアント
    │   └── tools/
    │       ├── list-containers.ts   # コンテナ一覧取得
    │       ├── get-logs.ts          # ログ取得
    │       ├── get-stats.ts         # リソース使用量取得
    │       ├── restart-container.ts # 再起動（承認フロー付き）
    │       ├── stop-container.ts    # 停止（承認フロー付き）
    │       └── start-container.ts   # 起動（承認フロー付き）
    ├── Dockerfile
    ├── package.json
    ├── tsconfig.json
    └── README.md
```

**Structure Decision**: Single project。全ツールが同一のDocker SSH接続クライアントを共有するため、monorepo内の単一パッケージ構成が最適。

## Complexity Tracking

Constitution Check はすべて合格または条件付き合格。追加の正当化不要。
