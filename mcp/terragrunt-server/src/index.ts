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
  ({ service }) => handlePlanService(service),
);

server.tool(
  'get_service_config',
  'サービスのTerragrunt設定ファイルを読み取る（読み取り専用）。変更提案の基礎情報収集に使用する。',
  {
    service: serviceEnum.describe('設定を読み取るサービス名'),
  },
  ({ service }) => handleGetServiceConfig(service),
);

server.tool(
  'list_workspaces',
  'HCP TerraformのWorkspace一覧と状態を取得する。インフラ全体の管理状況を確認する。',
  {},
  () => handleListWorkspaces(),
);

server.tool(
  'create_approval',
  '改善提案に対する承認ログを作成する。apply_service / rollback_service を実行するために必要。decision="approved" で承認、"rejected" で却下。',
  {
    proposal_id: z.string().describe('対象の提案ID（Prometheus MCP の generate_proposal で生成されたID）'),
    decision: z.enum(['approved', 'rejected']).describe('approved=承認して apply_service で実行可能にする / rejected=却下'),
    decided_by: z.string().optional().default('operator').describe('承認者名（例: "operator", "admin"）'),
  },
  ({ proposal_id, decision, decided_by }) => handleCreateApproval(proposal_id, decision, decided_by),
);

server.tool(
  'apply_service',
  'terragrunt applyを実行してインフラ変更を適用する。【承認必須】approval_idが必要。',
  {
    service: serviceEnum.describe('applyを実行するサービス名'),
    approval_id: z.string().describe('対応する承認ログのID（承認なしでは実行不可）'),
  },
  ({ service, approval_id }) => handleApplyService(service, approval_id),
);

server.tool(
  'rollback_service',
  '承認ログのスナップショットからサービスをロールバックする。問題発生時の復元に使用する。【確認必須】confirmed=true が必要。',
  {
    approval_id: z.string().describe('ロールバック対象の承認ログID。このIDのsnapshot_beforeが復元される。'),
    confirmed: z.boolean().describe('ロールバックを実行することを明示的に確認するフラグ。true を指定しないと実行されない。'),
  },
  ({ approval_id, confirmed }) => handleRollbackService(approval_id, confirmed),
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
