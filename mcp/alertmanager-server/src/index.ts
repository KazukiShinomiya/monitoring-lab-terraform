import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { handleGetAlerts } from './tools/get-alerts.js';
import { handleSilenceAlert } from './tools/silence-alert.js';
import { handleListSilences } from './tools/list-silences.js';
import { handleDeleteSilence } from './tools/delete-silence.js';

const server = new McpServer(
  { name: 'monitoring-lab-alertmanager-mcp', version: '1.0.0' },
);

// プロセスライフサイクルハンドラー
process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
process.on('uncaughtException', (err) => {
  process.stderr.write(`Uncaught exception: ${err.message}\n${err.stack}\n`);
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  process.stderr.write(`Unhandled rejection: ${String(reason)}\n`);
  process.exit(1);
});

// ツール登録

server.tool(
  'alertmanager_get_alerts',
  'アクティブなアラートを一覧で取得する。severity でフィルタ可能。',
  {
    severity: z.enum(['critical', 'warning']).optional().describe('フィルタ条件。省略時は全件返す'),
  },
  ({ severity }) => handleGetAlerts(severity),
);

server.tool(
  'alertmanager_silence_alert',
  'アラートをサイレンスする。confirmed=false でドライラン（操作内容の確認のみ）。',
  {
    alertname: z.string().describe('サイレンス対象のアラート名'),
    duration_hours: z.number().positive().default(2).describe('サイレンス持続時間（時間単位、デフォルト: 2）'),
    additional_matchers: z.array(z.object({
      name: z.string(),
      value: z.string(),
    })).optional().describe('追加ラベルマッチャー（例: [{name: "severity", value: "warning"}]）'),
    comment: z.string().default('claude-code によるサイレンス').describe('サイレンスの理由・説明'),
    confirmed: z.boolean().describe('false: 操作内容を表示して終了（ドライラン）。true: 実際にサイレンスを作成。'),
  },
  ({ alertname, duration_hours, additional_matchers, comment, confirmed }) =>
    handleSilenceAlert(alertname, duration_hours, additional_matchers ?? [], comment, confirmed),
);

server.tool(
  'alertmanager_list_silences',
  '有効なサイレンスを一覧で取得する。',
  {},
  () => handleListSilences(),
);

server.tool(
  'alertmanager_delete_silence',
  'サイレンスを削除する。confirmed=false でドライラン（操作内容の確認のみ）。',
  {
    silence_id: z.string().describe('削除する silence の UUID'),
    confirmed: z.boolean().describe('false: 操作内容を表示して終了（ドライラン）。true: 実際に削除を実行。'),
  },
  ({ silence_id, confirmed }) => handleDeleteSilence(silence_id, confirmed),
);

const transport = new StdioServerTransport();
await server.connect(transport);
