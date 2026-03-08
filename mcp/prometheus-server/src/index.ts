import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { queryMetricsTool, handleQueryMetrics } from './tools/query-metrics.js';
import { queryRangeTool, handleQueryRange } from './tools/query-range.js';
import { getActiveAlertsTool, handleGetActiveAlerts } from './tools/get-active-alerts.js';
import { compareMetricsTool, handleCompareMetrics } from './tools/compare-metrics.js';
import { generateProposalTool, handleGenerateProposal } from './tools/generate-proposal.js';
import { listProposalsTool, handleListProposals } from './tools/list-proposals.js';

const server = new Server(
  { name: 'monitoring-lab-prometheus-mcp', version: '1.1.0' },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    queryMetricsTool,
    queryRangeTool,
    getActiveAlertsTool,
    compareMetricsTool,
    generateProposalTool,
    listProposalsTool,
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const a = (args ?? {}) as Record<string, unknown>;
  switch (name) {
    case 'query_metrics':
      return handleQueryMetrics(a['query'] as string, a['time'] as string | undefined);
    case 'query_range':
      return handleQueryRange(
        a['query'] as string,
        a['start'] as string,
        a['end'] as string | undefined,
        a['step'] as string | undefined,
      );
    case 'get_active_alerts':
      return handleGetActiveAlerts(a['severity'] as string | undefined);
    case 'compare_metrics':
      return handleCompareMetrics(
        a['query'] as string,
        a['baseline_time'] as string,
        a['current_time'] as string | undefined,
      );
    case 'generate_proposal':
      return handleGenerateProposal();
    case 'list_proposals':
      return handleListProposals(a as { status?: string });
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
