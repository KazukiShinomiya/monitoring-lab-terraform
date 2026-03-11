import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { handleListContainers } from './tools/list-containers.js';
import { handleGetLogs } from './tools/get-logs.js';
import { handleGetStats } from './tools/get-stats.js';
import { handleRestartContainer } from './tools/restart-container.js';
import { handleStopContainer } from './tools/stop-container.js';
import { handleStartContainer } from './tools/start-container.js';

const server = new McpServer(
  { name: 'monitoring-lab-docker-mcp', version: '2.0.0' },
);

server.tool(
  'docker_list_containers',
  '全コンテナの名前・状態・起動経過時間を取得する',
  {},
  () => handleListContainers(),
);

server.tool(
  'docker_get_logs',
  '指定コンテナの直近ログを取得する',
  {
    container_name: z.string().describe('コンテナ名（部分一致可。候補が複数ある場合は選択を促す）'),
    lines: z.number().int().positive().optional().default(100).describe('取得するログ行数（デフォルト: 100）'),
    since: z.string().optional().describe('指定時刻以降のログのみ取得（例: "1h", "30m", "2026-03-08T00:00:00"）'),
  },
  ({ container_name, lines, since }) => handleGetLogs(container_name, lines, since),
);

server.tool(
  'docker_get_stats',
  '全コンテナのCPU・メモリ使用量を取得する',
  {},
  () => handleGetStats(),
);

server.tool(
  'docker_restart_container',
  'コンテナを再起動する。confirmed=false でドライラン（操作内容の確認のみ）。',
  {
    container_name: z.string().describe('再起動するコンテナ名（部分一致可）'),
    confirmed: z.boolean().describe('false: 操作内容を表示して終了（ドライラン）。true: 実際に再起動を実行。'),
  },
  ({ container_name, confirmed }) => handleRestartContainer(container_name, confirmed),
);

server.tool(
  'docker_stop_container',
  'コンテナを停止する。confirmed=false でドライラン。',
  {
    container_name: z.string().describe('停止するコンテナ名（部分一致可）'),
    confirmed: z.boolean().describe('false: 操作内容を表示して終了。true: 実際に停止を実行。'),
  },
  ({ container_name, confirmed }) => handleStopContainer(container_name, confirmed),
);

server.tool(
  'docker_start_container',
  '停止中のコンテナを起動する。confirmed=false でドライラン。',
  {
    container_name: z.string().describe('起動するコンテナ名（部分一致可）'),
    confirmed: z.boolean().describe('false: 操作内容を表示して終了。true: 実際に起動を実行。'),
  },
  ({ container_name, confirmed }) => handleStartContainer(container_name, confirmed),
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
