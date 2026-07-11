import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { handleGetAlerts } from './tools/get-alerts.js';
import { handleSilenceAlert } from './tools/silence-alert.js';
import { handleListSilences } from './tools/list-silences.js';
import { handleDeleteSilence } from './tools/delete-silence.js';
import { initTelemetry, instrumentTool, shutdownTelemetry } from './telemetry.js';

// 016: 計装を初期化（OTLP メトリクスを otel-collector へ push）。冪等・起動を妨げない。
initTelemetry('alertmanager');

const server = new McpServer(
  { name: 'monitoring-lab-alertmanager-mcp', version: '1.0.0' },
);

// プロセスライフサイクルハンドラー
// 016: 終了時に未送出メトリクスを flush してから終了する。
// 短命プロセスでは定期エクスポートが発火しないため、これが唯一の確実な送出経路。
// 冪等ガード必須: stdin 'end'/'close'/transport.onclose は連続発火しうるため、
// 2発目が process.exit を先に踏むと flush 中の送信が失われる（prometheus-server で実測）。
let exiting = false;
async function gracefulExit(code: number): Promise<void> {
  if (exiting) return;
  exiting = true;
  await shutdownTelemetry(8000);
  process.exit(code);
}

process.on('SIGINT', () => { void gracefulExit(0); });
process.on('SIGTERM', () => { void gracefulExit(0); });
process.on('uncaughtException', (err) => {
  process.stderr.write(`Uncaught exception: ${err.message}\n${err.stack}\n`);
  void gracefulExit(1);
});
process.on('unhandledRejection', (reason) => {
  process.stderr.write(`Unhandled rejection: ${String(reason)}\n`);
  void gracefulExit(1);
});

// ツール登録

server.tool(
  'alertmanager_get_alerts',
  'アクティブなアラートを一覧で取得する。severity でフィルタ可能。',
  {
    severity: z.enum(['critical', 'warning']).optional().describe('フィルタ条件。省略時は全件返す'),
  },
  instrumentTool('alertmanager_get_alerts', ({ severity }) => handleGetAlerts(severity)),
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
  instrumentTool('alertmanager_silence_alert', ({ alertname, duration_hours, additional_matchers, comment, confirmed }) =>
    handleSilenceAlert(alertname, duration_hours, additional_matchers ?? [], comment, confirmed)),
);

server.tool(
  'alertmanager_list_silences',
  '有効なサイレンスを一覧で取得する。',
  {},
  instrumentTool('alertmanager_list_silences', () => handleListSilences()),
);

server.tool(
  'alertmanager_delete_silence',
  'サイレンスを削除する。confirmed=false でドライラン（操作内容の確認のみ）。',
  {
    silence_id: z.string().describe('削除する silence の UUID'),
    confirmed: z.boolean().describe('false: 操作内容を表示して終了（ドライラン）。true: 実際に削除を実行。'),
  },
  instrumentTool('alertmanager_delete_silence', ({ silence_id, confirmed }) => handleDeleteSilence(silence_id, confirmed)),
);

const transport = new StdioServerTransport();
// stdio が閉じる（Claude が切断/EOF）時も flush してから終了
transport.onclose = () => { void gracefulExit(0); };
process.stdin.on('end', () => { void gracefulExit(0); });
process.stdin.on('close', () => { void gracefulExit(0); });
await server.connect(transport);
