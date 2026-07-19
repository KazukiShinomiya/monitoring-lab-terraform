import { execSsh, validateServiceName } from '../ssh-client.js';
import { getApprovalLog, saveApprovalLog } from '../storage.js';
import type { ConfigSnapshot } from '../types.js';

export async function handleApplyService(service: string, approvalId: string) {
  try {
    const validService = validateServiceName(service);

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

    // 2026-06 監査 H-2: 承認ゲートの強化 3点
    // (1) サービス一致 — 別サービスの承認を流用させない
    if (approvalLog.service !== validService) {
      return {
        content: [{ type: 'text' as const, text: `エラー: この承認ログは service="${approvalLog.service ?? '(未記録・旧形式)'}" 向けです。"${validService}" への apply には使えません。create_approval で対象サービスを指定して承認を取り直してください。` }],
        isError: true,
      };
    }
    // (2) 単回使用 — 適用済みの承認は再利用不可
    if (approvalLog.applied_at) {
      return {
        content: [{ type: 'text' as const, text: `エラー: この承認ログは既に ${approvalLog.applied_at} に適用済みです。承認は1回限りです。再適用には新しい承認を作成してください。` }],
        isError: true,
      };
    }
    // (3) 有効期限 — 古い承認の実行を拒否（既定60分、APPROVAL_TTL_MINUTES で変更可）
    const ttlMinutes = Number(process.env.APPROVAL_TTL_MINUTES ?? 60);
    const ageMs = Date.now() - new Date(approvalLog.decided_at).getTime();
    if (!Number.isFinite(ageMs) || ageMs > ttlMinutes * 60 * 1000) {
      return {
        content: [{ type: 'text' as const, text: `エラー: この承認ログは期限切れです（decided_at: ${approvalLog.decided_at}、TTL: ${ttlMinutes}分）。承認を取り直してください。` }],
        isError: true,
      };
    }

    const filePath = `/workspace/terraform/envs/local/${validService}/terragrunt.hcl`;
    const contentBefore = await execSsh(`cat ${filePath}`);
    const snapshot: ConfigSnapshot = {
      service: validService,
      file_path: filePath,
      content_before: contentBefore,
      captured_at: new Date().toISOString(),
    };
    approvalLog.snapshot_before = snapshot;

    const applyOutput = await execSsh(
      `docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local/${validService} && terragrunt apply -auto-approve 2>&1'`,
      300000,
    );

    const success = !applyOutput.includes('Error:') && !applyOutput.includes('error:');
    const appliedAt = new Date().toISOString();
    approvalLog.applied_at = appliedAt;
    approvalLog.apply_result = applyOutput.slice(-500);
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
