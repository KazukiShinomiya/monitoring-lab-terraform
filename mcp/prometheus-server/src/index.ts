import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { handleQueryMetrics } from './tools/query-metrics.js';
import { handleQueryRange } from './tools/query-range.js';
import { handleGetActiveAlerts } from './tools/get-active-alerts.js';
import { handleCompareMetrics } from './tools/compare-metrics.js';
import { handleGenerateProposal } from './tools/generate-proposal.js';
import { handleListProposals } from './tools/list-proposals.js';

const server = new McpServer(
  { name: 'monitoring-lab-prometheus-mcp', version: '2.0.0' },
);

server.tool(
  'query_metrics',
  'PromQLインスタントクエリでメトリクスを取得する。コンテナのCPU・メモリ・ネットワーク状態の確認に使用する。',
  {
    query: z.string().describe("PromQL式 (例: 'container_memory_usage_bytes{name=\"monitoring-lab-prometheus\"}')"),
    time: z.string().optional().describe('クエリ時刻 (ISO 8601 or Unix timestamp, 省略時=現在)'),
  },
  ({ query, time }) => handleQueryMetrics(query, time),
);

server.tool(
  'query_range',
  'PromQL範囲クエリで時系列データを取得する。トレンド分析・傾向把握に使用する。',
  {
    query: z.string().describe('PromQL式'),
    start: z.string().describe("開始時刻 (例: 'now-1h', '2026-03-01T00:00:00Z')"),
    end: z.string().optional().default('now').describe('終了時刻 (省略時=現在)'),
    step: z.string().optional().default('60s').describe("ステップ間隔 (例: '30s', '5m')"),
  },
  ({ query, start, end, step }) => handleQueryRange(query, start, end, step),
);

server.tool(
  'get_active_alerts',
  '現在発火中のPrometheusアラートを取得する。問題の緊急度判定に使用する。',
  {
    severity: z.enum(['all', 'critical', 'warning', 'info']).optional().default('all').describe('フィルター: allで全アラート取得'),
  },
  ({ severity }) => handleGetActiveAlerts(severity),
);

server.tool(
  'compare_metrics',
  '変更前後のメトリクスを比較して効果を測定する。terragrunt apply後の効果確認に使用する。',
  {
    query: z.string().describe('比較するPromQL式'),
    baseline_time: z.string().describe('比較基準時刻（変更前）ISO 8601 または Unix timestamp'),
    current_time: z.string().optional().describe('現在時刻（変更後）省略時=現在'),
  },
  ({ query, baseline_time, current_time }) => handleCompareMetrics(query, baseline_time, current_time),
);

server.tool(
  'generate_proposal',
  '現在のインフラ状態を分析して改善提案を生成する。dry_run=true の場合は分析のみで保存しない（副作用なし）。',
  {
    dry_run: z.boolean().optional().default(false).describe('true の場合、分析結果を返すが提案ファイルを保存しない（副作用なし）'),
    focus: z.enum(['alerts', 'memory', 'all']).optional().default('all').describe('分析対象: alerts=アラートのみ, memory=メモリのみ, all=全体'),
  },
  ({ dry_run, focus }) => handleGenerateProposal(dry_run, focus),
);

server.tool(
  'list_proposals',
  '保存済みの改善提案一覧を取得する。status でフィルタ可能（pending/applied/rejected/all）。',
  {
    status: z.enum(['all', 'pending', 'approved', 'applied', 'rejected', 'rolled_back']).optional().default('all').describe('フィルター: pending=未処理, applied=解消済み, all=全件'),
  },
  ({ status }) => handleListProposals({ status }),
);

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
process.on('uncaughtException', (error) => {
  process.stderr.write(`Uncaught exception: ${error.message}\n${error.stack}\n`);
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  process.stderr.write(`Unhandled rejection: ${String(reason)}\n`);
  process.exit(1);
});

const transport = new StdioServerTransport();
await server.connect(transport);
