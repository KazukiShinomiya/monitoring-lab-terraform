import { execSsh, validateServiceName } from '../ssh-client.js';
import { getApprovalLog, saveApprovalLog } from '../storage.js';

export async function handleRollbackService(approvalId: string, confirmed: boolean) {
  try {
    if (!confirmed) {
      return {
        content: [{ type: 'text' as const, text: 'ロールバックには confirmed=true の明示的な確認が必要です。実行してよい場合のみ true を指定してください。' }],
        isError: true,
      };
    }

    const approvalLog = await getApprovalLog(approvalId);
    if (!approvalLog) {
      return {
        content: [{ type: 'text' as const, text: `エラー: 承認ログが見つかりません（ID: ${approvalId}）。` }],
        isError: true,
      };
    }
    // H-2: 却下済み・未承認のログからはロールバックさせない
    if (approvalLog.decision !== 'approved') {
      return {
        content: [{ type: 'text' as const, text: `エラー: この承認ログは承認されていません（status: ${approvalLog.decision}）。ロールバックできません。` }],
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

    // 2026-06 監査 M-2: 保存済み JSON は改竄されうる外部入力として扱う。
    // service は許可リストで再検証し、file_path は信用せず期待値との一致のみ確認する
    const validService = validateServiceName(service);
    const expectedPath = `/workspace/terraform/envs/local/${validService}/terragrunt.hcl`;
    if (file_path !== expectedPath) {
      return {
        content: [{ type: 'text' as const, text: `エラー: スナップショットの file_path が期待値と一致しません（記録値: ${file_path.slice(0, 128)}）。改竄の疑いがあるためロールバックを中止します。` }],
        isError: true,
      };
    }

    // base64経由でファイルを書き戻す（シェルインジェクション対策）
    const base64Content = Buffer.from(content_before, 'utf-8').toString('base64');
    await execSsh(`echo '${base64Content}' | base64 -d > ${expectedPath}`, 30000);

    const applyOutput = await execSsh(
      `docker exec monitoring-lab-terragrunt sh -c 'cd /workspace/terraform/envs/local/${validService} && terragrunt apply -auto-approve 2>&1'`,
      300000,
    );

    const success = !applyOutput.includes('Error:');
    const rolledBackAt = new Date().toISOString();
    approvalLog.apply_result = `[ROLLBACK] ${applyOutput.slice(-500)}`;
    await saveApprovalLog(approvalLog);

    const output = {
      service,
      success,
      restored_from: captured_at,
      rollback_applied_at: rolledBackAt,
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
