import { execSsh } from '../ssh-client.js';
import { getApprovalLog } from '../storage.js';

export const rollbackServiceTool = {
  name: 'rollback_service',
  description: '承認ログのスナップショットからサービスをロールバックする。問題発生時の復元に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      approval_id: {
        type: 'string',
        description: 'ロールバック対象の承認ログID。このIDのsnapshot_beforeが復元される。',
      },
    },
    required: ['approval_id'],
  },
};

export async function handleRollbackService(approvalId: string) {
  try {
    const approvalLog = await getApprovalLog(approvalId);
    if (!approvalLog) {
      return {
        content: [{ type: 'text' as const, text: `エラー: 承認ログが見つかりません（ID: ${approvalId}）。` }],
        isError: true,
      };
    }
    if (!approvalLog.snapshot_before) {
      return {
        content: [{ type: 'text' as const, text: `エラー: このログにはスナップショットがありません。ロールバックできません。` }],
        isError: true,
      };
    }

    const { service, file_path, content_before, captured_at } = approvalLog.snapshot_before;

    // ファイルを変更前の内容に書き戻す（シングルクォートをエスケープ）
    const escapedContent = content_before.replace(/'/g, "'\\''");
    await execSsh(`printf '%s' '${escapedContent}' > ${file_path}`, 30000);

    // terragrunt apply でロールバックを適用
    const applyOutput = await execSsh(
      `docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local/${service} && terragrunt apply -auto-approve 2>&1'`,
      300000,
    );

    const output = {
      service,
      success: !applyOutput.includes('Error:'),
      restored_from: captured_at,
      rollback_applied_at: new Date().toISOString(),
      apply_output: applyOutput,
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: ロールバックに失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
