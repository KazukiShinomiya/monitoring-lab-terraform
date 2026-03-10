import { query } from '../prometheus-client.js';

export async function handleQueryMetrics(queryExpr: string, time?: string) {
  try {
    const data = await query(queryExpr, time);
    const output = {
      query: queryExpr,
      result_type: data.resultType,
      results: data.result.map(r => ({
        metric: r.metric,
        value: r.value,
      })),
      executed_at: new Date().toISOString(),
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: Prometheusへの接続に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
