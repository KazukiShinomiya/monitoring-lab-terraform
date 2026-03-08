import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { planServiceTool, handlePlanService } from './tools/plan-service.js';
import { getServiceConfigTool, handleGetServiceConfig } from './tools/get-service-config.js';
import { listWorkspacesTool, handleListWorkspaces } from './tools/list-workspaces.js';
import { applyServiceTool, handleApplyService } from './tools/apply-service.js';
import { rollbackServiceTool, handleRollbackService } from './tools/rollback-service.js';

const server = new Server(
  { name: 'monitoring-lab-terragrunt-mcp', version: '1.0.0' },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    planServiceTool,
    getServiceConfigTool,
    listWorkspacesTool,
    applyServiceTool,
    rollbackServiceTool,
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const a = (args ?? {}) as Record<string, unknown>;
  switch (name) {
    case 'plan_service':
      return handlePlanService(a['service'] as string);
    case 'get_service_config':
      return handleGetServiceConfig(a['service'] as string);
    case 'list_workspaces':
      return handleListWorkspaces();
    case 'apply_service':
      return handleApplyService(a['service'] as string, a['approval_id'] as string);
    case 'rollback_service':
      return handleRollbackService(a['approval_id'] as string);
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
