/**
 * Docker MCP Server — ツールスキーマ定義
 * 実装: mcp-servers/docker-mcp/src/tools/
 */

import { z } from "zod";

// =====================================================
// Tool: list_containers
// 全コンテナの状態一覧を取得する
// =====================================================
export const ListContainersInput = z.object({
  filter: z.enum(['all', 'running', 'stopped']).default('all')
    .describe("フィルター: all=全件, running=稼働中のみ, stopped=停止中のみ"),
});

export interface ListContainersOutput {
  containers: Array<{
    name: string;          // "monitoring-lab-prometheus"
    status: string;        // "Up 3 days"
    state: 'running' | 'stopped' | 'restarting' | 'exited';
    image: string;
    uptime_seconds?: number;
  }>;
}

// =====================================================
// Tool: get_container_logs
// 指定コンテナの最新ログを取得する
// =====================================================
export const GetContainerLogsInput = z.object({
  container: z.string().regex(/^[a-z0-9_-]+$/)
    .describe("コンテナ名 (例: monitoring-lab-prometheus)"),
  lines: z.number().int().min(1).max(1000).default(100)
    .describe("取得する行数（最大1000）"),
  since: z.string().optional()
    .describe("この時刻以降のログ (例: '1h', '2024-01-01T00:00:00Z')"),
});

export interface GetContainerLogsOutput {
  container: string;
  lines: string[];
  total_lines: number;
}

// =====================================================
// Tool: get_container_stats
// コンテナのリソース使用量（CPU・メモリ）を取得する
// =====================================================
export const GetContainerStatsInput = z.object({
  container: z.string().regex(/^[a-z0-9_-]+$/).optional()
    .describe("コンテナ名（省略時は全コンテナ）"),
});

export interface GetContainerStatsOutput {
  stats: Array<{
    name: string;
    cpu_percent: number;      // 0.00 〜 100.00
    memory_usage_bytes: number;
    memory_limit_bytes: number;
    memory_percent: number;   // 0.00 〜 100.00
    network_rx_bytes: number;
    network_tx_bytes: number;
  }>;
  measured_at: string;        // ISO 8601
}

// =====================================================
// Tool: restart_container
// コンテナを再起動する（承認必須）
// =====================================================
export const RestartContainerInput = z.object({
  container: z.string().regex(/^monitoring-lab-[a-z0-9_-]+$/)
    .describe("再起動するコンテナ名（monitoring-lab- プレフィックス必須）"),
  approval_id: z.string().uuid()
    .describe("対応する承認ログのID（承認なしでは実行不可）"),
});

export interface RestartContainerOutput {
  success: boolean;
  message: string;
  restarted_at: string;
}

// =====================================================
// MCP Tool Registration Schema (for reference)
// =====================================================
export const DOCKER_TOOLS = [
  {
    name: "list_containers",
    description: "全Dockerコンテナの状態一覧を取得する。稼働状況の確認に使用する。",
    inputSchema: ListContainersInput,
  },
  {
    name: "get_container_logs",
    description: "指定コンテナの最新ログを取得する。エラー診断に使用する。",
    inputSchema: GetContainerLogsInput,
  },
  {
    name: "get_container_stats",
    description: "コンテナのCPU・メモリ・ネットワーク使用量を取得する。リソース分析に使用する。",
    inputSchema: GetContainerStatsInput,
  },
  {
    name: "restart_container",
    description: "コンテナを再起動する。【承認必須】approval_idが必要。",
    inputSchema: RestartContainerInput,
  },
] as const;
