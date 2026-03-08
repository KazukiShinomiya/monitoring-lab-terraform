import { execSsh, validateServiceName } from '../ssh-client.js';

export const planServiceTool = {
  name: 'plan_service',
  description: 'terragrunt planを実行して変更内容を確認する（読み取り専用、承認不要）。提案内容の差分確認に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      service: {
        type: 'string',
        enum: ['network', 'postgres', 'vault', 'prometheus', 'grafana', 'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'],
        description: 'planを実行するサービス名',
      },
    },
    required: ['service'],
  },
};

export async function handlePlanService(service: string) {
  try {
    const validService = validateServiceName(service);
    const planOutput = await execSsh(
      `docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local/${validService} && terragrunt plan 2>&1'`,
      120000,
    );

    const hasChanges = planOutput.includes('Plan:') && !planOutput.includes('No changes');
    const addMatch = planOutput.match(/(\d+) to add/);
    const changeMatch = planOutput.match(/(\d+) to change/);
    const destroyMatch = planOutput.match(/(\d+) to destroy/);

    const output = {
      service: validService,
      has_changes: hasChanges,
      plan_output: planOutput,
      resources_to_add: addMatch ? parseInt(addMatch[1]) : 0,
      resources_to_change: changeMatch ? parseInt(changeMatch[1]) : 0,
      resources_to_destroy: destroyMatch ? parseInt(destroyMatch[1]) : 0,
      executed_at: new Date().toISOString(),
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: terragrunt plan に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
