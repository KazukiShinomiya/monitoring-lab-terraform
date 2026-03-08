import { execSsh, validateServiceName } from '../ssh-client.js';
import { getApprovalLog, saveApprovalLog } from '../storage.js';
import type { ConfigSnapshot } from '../types.js';

export const applyServiceTool = {
  name: 'apply_service',
  description: 'terragrunt applyを実行してインフラ変更を適用する。【承認必須】approval_idが必要。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      service: {
        type: 'string',
        enum: ['network', 'postgres', 'vault', 'prometheus', 'grafana', 'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'],
        description: 'applyを実行するサービス名',
      },
      approval_id: {
        type: 'string',
        description: '対応する承認ログのID（承認なしでは実行不可）',
      },
    },
    required: ['service', 'approval_id'],
  },
};

export async function handleApplyService(service: string, approvalId: string) {
  try {
    const validService = validateServiceName(service);

    // FR-006: 承認ログの存在確認
    const approvalLog = await getApprovalLog(approvalId);
    if (!approvalLog) {
      return {
        content: [{ type: 'text' as const, text: `エラー: 承認ログが見つかりません（ID: ${approvalId}）。ユーザーの承認なしにapplyは実行できません。` }],
        isError: true,
      };
    }
    if (approvalLog.decision !== 'approved') {
      return {
        content: [{ type: 'text' as const, text: `エラー: この承認ログは承認されていません（status: ${approvalLog.decision}）。` }],
        isError: true,
      };
    }

    // 変更前スナップショット取得
    const filePath = `/workspace/terraform/envs/local/${validService}/terragrunt.hcl`;
    const contentBefore = await execSsh(`cat ${filePath}`);
    const snapshot: ConfigSnapshot = {
      service: validService,
      file_path: filePath,
      content_before: contentBefore,
      captured_at: new Date().toISOString(),
    };
    approvalLog.snapshot_before = snapshot;

    // terragrunt apply 実行
    const applyOutput = await execSsh(
      `docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local/${validService} && terragrunt apply -auto-approve 2>&1'`,
      300000,
    );

    const success = !applyOutput.includes('Error:') && !applyOutput.includes('error:');
    const appliedAt = new Date().toISOString();
    approvalLog.applied_at = appliedAt;
    approvalLog.apply_result = applyOutput.slice(-500); // 末尾500文字を保存
    await saveApprovalLog(approvalLog);

    const addMatch = applyOutput.match(/(\d+) added/);
    const changeMatch = applyOutput.match(/(\d+) changed/);
    const destroyMatch = applyOutput.match(/(\d+) destroyed/);

    const output = {
      service: validService,
      success,
      apply_output: applyOutput,
      resources_added: addMatch ? parseInt(addMatch[1]) : 0,
      resources_changed: changeMatch ? parseInt(changeMatch[1]) : 0,
      resources_destroyed: destroyMatch ? parseInt(destroyMatch[1]) : 0,
      applied_at: appliedAt,
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: terragrunt apply に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
