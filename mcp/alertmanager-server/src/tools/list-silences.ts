import { alertmanagerClient } from '../alertmanager-client.js';
import type { Silence } from '../types.js';

function formatSilence(silence: Silence, index: number): string {
  const matcherDesc = silence.matchers.map(m => `${m.name}="${m.value}"`).join(', ');
  return [
    `${index}. ID: ${silence.id}`,
    `   対象: ${matcherDesc}`,
    `   有効期限: ${silence.endsAt}`,
    `   作成者: ${silence.createdBy}`,
    `   コメント: ${silence.comment}`,
    `   状態: ${silence.status.state}`,
  ].join('\n');
}

export async function handleListSilences(): Promise<{ content: Array<{ type: 'text'; text: string }> }> {
  let silences: Silence[];
  try {
    silences = await alertmanagerClient.getSilences();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { content: [{ type: 'text', text: `❌ Alertmanager に接続できません: ${message}` }] };
  }

  const active = silences.filter(s => s.status.state === 'active' || s.status.state === 'pending');

  if (active.length === 0) {
    return { content: [{ type: 'text', text: '✅ 有効なサイレンスはありません' }] };
  }

  const lines = [`🔇 有効なサイレンス: ${active.length}件\n`];
  active.forEach((s, i) => lines.push(formatSilence(s, i + 1)));
  return { content: [{ type: 'text', text: lines.join('\n') }] };
}
