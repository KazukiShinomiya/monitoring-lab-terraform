import { alertmanagerClient } from '../alertmanager-client.js';

export async function handleDeleteSilence(
  silenceId: string,
  confirmed: boolean,
): Promise<{ content: Array<{ type: 'text'; text: string }> }> {
  // まず silence の存在確認（dry-run でも情報表示のために取得）
  let silenceInfo: string;
  try {
    const silence = await alertmanagerClient.getSilence(silenceId);
    const matcherDesc = silence.matchers.map(m => `${m.name}="${m.value}"`).join(', ');
    silenceInfo = `  対象: ${matcherDesc}\n  有効期限: ${silence.endsAt}`;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.startsWith('SILENCE_NOT_FOUND:')) {
      return { content: [{ type: 'text', text: `❌ 指定されたサイレンスが見つかりません: ${silenceId}` }] };
    }
    return { content: [{ type: 'text', text: `❌ Alertmanager に接続できません: ${message}` }] };
  }

  if (!confirmed) {
    const dryRun = [
      '🔍 ドライラン: 以下のサイレンスを削除します',
      '',
      `  Silence ID: ${silenceId}`,
      silenceInfo,
      '',
      '実際に削除するには confirmed=true で再実行してください',
    ].join('\n');
    return { content: [{ type: 'text', text: dryRun }] };
  }

  try {
    await alertmanagerClient.deleteSilence(silenceId);
    return {
      content: [{
        type: 'text',
        text: `✅ サイレンスを削除しました\n\n  Silence ID: ${silenceId}\n${silenceInfo}`,
      }],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.startsWith('SILENCE_NOT_FOUND:')) {
      return { content: [{ type: 'text', text: `❌ 指定されたサイレンスが見つかりません: ${silenceId}` }] };
    }
    return { content: [{ type: 'text', text: `❌ サイレンス削除に失敗しました: ${message}` }] };
  }
}
