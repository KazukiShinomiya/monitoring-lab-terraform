import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { VALID_SERVICES } from './ssh-client.js';
import { handlePlanService } from './tools/plan-service.js';
import { handleGetServiceConfig } from './tools/get-service-config.js';
import { handleListWorkspaces } from './tools/list-workspaces.js';
import { handleCreateApproval } from './tools/create-approval.js';
import { handleApplyService } from './tools/apply-service.js';
import { handleRollbackService } from './tools/rollback-service.js';
import { initTelemetry, instrumentTool, shutdownTelemetry } from './telemetry.js';

// 016: 計装を初期化（OTLP メトリクスを otel-collector へ push）。冪等・起動を妨げない。
initTelemetry('terragrunt');

const server = new McpServer(
  { name: 'monitoring-lab-terragrunt-mcp', version: '2.0.0' },
);

const serviceEnum = z.enum(VALID_SERVICES);

server.tool(
  'plan_service',
  'terragrunt planを実行して変更内容を確認する（読み取り専用、承認不要）。提案内容の差分確認に使用する。',
  {
    service: serviceEnum.describe('planを実行するサービス名'),
  },
  instrumentTool('plan_service', ({ service }) => handlePlanService(service)),
);

server.tool(
  'get_service_config',
  'サービスのTerragrunt設定ファイルを読み取る（読み取り専用）。変更提案の基礎情報収集に使用する。',
  {
    service: serviceEnum.describe('設定を読み取るサービス名'),
  },
  instrumentTool('get_service_config', ({ service }) => handleGetServiceConfig(service)),
);

server.tool(
  'list_workspaces',
  'HCP TerraformのWorkspace一覧と状態を取得する。インフラ全体の管理状況を確認する。',
  {},
  instrumentTool('list_workspaces', () => handleListWorkspaces()),
);

server.tool(
  'create_approval',
  '改善提案に対する承認ログを作成する。apply_service / rollback_service を実行するために必要。decision="approved" で承認、"rejected" で却下。承認は指定サービス専用・1回限り・期限付き（既定60分）。',
  {
    proposal_id: z.string().describe('対象の提案ID（Prometheus MCP の generate_proposal で生成されたID）'),
    service: serviceEnum.describe('承認対象のサービス名。apply_service はこの一致を検証する'),
    decision: z.enum(['approved', 'rejected']).describe('approved=承認して apply_service で実行可能にする / rejected=却下'),
    decided_by: z.string().optional().default('operator').describe('承認者名（例: "operator", "admin"）'),
  },
  instrumentTool('create_approval', ({ proposal_id, service, decision, decided_by }) => handleCreateApproval(proposal_id, service, decision, decided_by)),
);

server.tool(
  'apply_service',
  'terragrunt applyを実行してインフラ変更を適用する。【承認必須】approval_idが必要。',
  {
    service: serviceEnum.describe('applyを実行するサービス名'),
    approval_id: z.string().describe('対応する承認ログのID（承認なしでは実行不可）'),
  },
  instrumentTool('apply_service', ({ service, approval_id }) => handleApplyService(service, approval_id)),
);

server.tool(
  'rollback_service',
  '承認ログのスナップショットからサービスをロールバックする。問題発生時の復元に使用する。【確認必須】confirmed=true が必要。',
  {
    approval_id: z.string().describe('ロールバック対象の承認ログID。このIDのsnapshot_beforeが復元される。'),
    confirmed: z.boolean().describe('ロールバックを実行することを明示的に確認するフラグ。true を指定しないと実行されない。'),
  },
  instrumentTool('rollback_service', ({ approval_id, confirmed }) => handleRollbackService(approval_id, confirmed)),
);

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
process.on('uncaughtException', (error) => {
  process.stderr.write(`Uncaught exception: ${error.message}\n${error.stack}\n`);
  void gracefulExit(1);
});
process.on('unhandledRejection', (reason) => {
  process.stderr.write(`Unhandled rejection: ${String(reason)}\n`);
  void gracefulExit(1);
});

const transport = new StdioServerTransport();
// stdio が閉じる（Claude が切断/EOF）時も flush してから終了
transport.onclose = () => { void gracefulExit(0); };
process.stdin.on('end', () => { void gracefulExit(0); });
process.stdin.on('close', () => { void gracefulExit(0); });
await server.connect(transport);
