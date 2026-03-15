import { alertmanagerClient } from '../alertmanager-client.js';

interface AdditionalMatcher {
  name: string;
  value: string;
}

function formatIso(date: Date): string {
  return date.toISOString();
}

export async function handleSilenceAlert(
  alertname: string,
  durationHours: number,
  additionalMatchers: AdditionalMatcher[],
  comment: string,
  confirmed: boolean,
): Promise<{ content: Array<{ type: 'text'; text: string }> }> {
  const now = new Date();
  const endsAt = new Date(now.getTime() + durationHours * 60 * 60 * 1000);

  if (endsAt <= now) {
    return { content: [{ type: 'text', text: `❌ 終了時刻が過去の時刻です: ${formatIso(endsAt)}` }] };
  }

  const matchers = [
    { name: 'alertname', value: alertname, isRegex: false, isEqual: true },
    ...additionalMatchers.map(m => ({ name: m.name, value: m.value, isRegex: false, isEqual: true })),
  ];

  const matcherDesc = matchers.map(m => `${m.name}="${m.value}"`).join(', ');

  if (!confirmed) {
    const dryRun = [
      '🔍 ドライラン: 以下のサイレンスを作成します',
      '',
      `  対象: ${matcherDesc}`,
      `  期間: ${formatIso(now)} 〜 ${formatIso(endsAt)} (${durationHours}時間)`,
      `  作成者: claude-code`,
      `  コメント: ${comment}`,
      '',
      '実際に作成するには confirmed=true で再実行してください',
    ].join('\n');
    return { content: [{ type: 'text', text: dryRun }] };
  }

  try {
    const result = await alertmanagerClient.createSilence({
      matchers,
      startsAt: formatIso(now),
      endsAt: formatIso(endsAt),
      createdBy: 'claude-code',
      comment,
    });

    const success = [
      '✅ サイレンスを作成しました',
      '',
      `  Silence ID: ${result.silenceID}`,
      `  対象: ${matcherDesc}`,
      `  有効期限: ${formatIso(endsAt)}`,
    ].join('\n');
    return { content: [{ type: 'text', text: success }] };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { content: [{ type: 'text', text: `❌ サイレンス作成に失敗しました: ${message}` }] };
  }
}
