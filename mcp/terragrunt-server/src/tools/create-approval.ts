import { randomUUID } from 'crypto';
import { saveApprovalLog } from '../storage.js';
import type { ApprovalLog } from '../types.js';

export async function handleCreateApproval(
  proposalId: string,
  decision: 'approved' | 'rejected',
  decidedBy: string = 'operator',
) {
  try {
    const log: ApprovalLog = {
      id: randomUUID(),
      proposal_id: proposalId,
      decision,
      decided_at: new Date().toISOString(),
      decided_by: decidedBy,
    };

    await saveApprovalLog(log);

    const decisionLabel = decision === 'approved' ? '✅ 承認' : '❌ 却下';
    const nextStep = decision === 'approved'
      ? `\n\n次のステップ: apply_service を実行する際に approval_id="${log.id}" を指定してください。`
      : '';

    return {
      content: [{
        type: 'text' as const,
        text: `承認ログを作成しました（${decisionLabel}）\n\napproval_id: ${log.id}\nproposal_id: ${proposalId}\ndecided_by: ${decidedBy}\ndecided_at: ${log.decided_at}${nextStep}`,
      }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: 承認ログの作成に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
