import { queryRange } from '../prometheus-client.js';

export async function handleQueryRange(
  queryExpr: string,
  start: string,
  end: string = 'now',
  step: string = '60s',
) {
  try {
    const data = await queryRange(queryExpr, start, end, step);
    const dataPoints = data.result.reduce((sum, r) => sum + r.values.length, 0);
    const output = {
      query: queryExpr,
      data_points: dataPoints,
      results: data.result.map(r => ({
        metric: r.metric,
        values: r.values,
      })),
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
