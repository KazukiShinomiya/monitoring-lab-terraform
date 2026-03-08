import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { listContainersTool, handleListContainers } from './tools/list-containers.js';
import { getLogsTool, handleGetLogs } from './tools/get-logs.js';
import { getStatsTool, handleGetStats } from './tools/get-stats.js';
import { restartContainerTool, handleRestartContainer } from './tools/restart-container.js';
import { stopContainerTool, handleStopContainer } from './tools/stop-container.js';
import { startContainerTool, handleStartContainer } from './tools/start-container.js';

const server = new Server(
  { name: 'monitoring-lab-docker-mcp', version: '1.1.0' },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    listContainersTool,
    getLogsTool,
    getStatsTool,
    restartContainerTool,
    stopContainerTool,
    startContainerTool,
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  switch (name) {
    case 'docker_list_containers':
      return await handleListContainers();
    case 'docker_get_logs':
      return await handleGetLogs(
        (args as { container_name: string; lines?: number; since?: string }).container_name,
        (args as { container_name: string; lines?: number; since?: string }).lines,
        (args as { container_name: string; lines?: number; since?: string }).since,
      );
    case 'docker_get_stats':
      return await handleGetStats();
    case 'docker_restart_container':
      return await handleRestartContainer(
        (args as { container_name: string; confirmed: boolean }).container_name,
        (args as { container_name: string; confirmed: boolean }).confirmed,
      );
    case 'docker_stop_container':
      return await handleStopContainer(
        (args as { container_name: string; confirmed: boolean }).container_name,
        (args as { container_name: string; confirmed: boolean }).confirmed,
      );
    case 'docker_start_container':
      return await handleStartContainer(
        (args as { container_name: string; confirmed: boolean }).container_name,
        (args as { container_name: string; confirmed: boolean }).confirmed,
      );
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
