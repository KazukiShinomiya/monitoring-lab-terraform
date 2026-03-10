import { listProposals } from '../storage.js';

export async function handleListProposals(args: { status?: string }) {
  try {
    const filter = args.status ?? 'all';
    const index = await listProposals();
    const items = filter === 'all'
      ? index.items
      : index.items.filter(i => i.status === filter);

    if (items.length === 0) {
      return {
        content: [{ type: 'text' as const, text: `提案が見つかりません（フィルター: ${filter}）` }],
      };
    }

    const urgencyLabel = { high: '🔴', medium: '🟡', low: '🟢' };
    const statusLabel: Record<string, string> = {
      pending: '⏳ pending',
      approved: '✅ approved',
      applied: '✔️ applied',
      rejected: '❌ rejected',
      rolled_back: '↩️ rolled_back',
    };

    const lines = items.map(item => {
      const u = urgencyLabel[item.urgency] ?? '⚪';
      const s = statusLabel[item.status] ?? item.status;
      const date = item.created_at.slice(0, 10);
      return `${u} [${item.id.slice(0, 8)}] ${s} | ${date} | ${item.target}\n   ${item.content_preview.replace(/\n/g, ' ').slice(0, 80)}`;
    });

    const text = `改善提案一覧（${items.length}件 / フィルター: ${filter}）\n\n${lines.join('\n\n')}`;
    return {
      content: [{ type: 'text' as const, text }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: 提案一覧の取得に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
