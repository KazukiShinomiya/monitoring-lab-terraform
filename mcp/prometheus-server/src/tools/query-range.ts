import { queryRange } from '../prometheus-client.js';

export const queryRangeTool = {
  name: 'query_range',
  description: 'PromQL範囲クエリで時系列データを取得する。トレンド分析・傾向把握に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      query: {
        type: 'string',
        description: 'PromQL式',
      },
      start: {
        type: 'string',
        description: "開始時刻 (例: 'now-1h', '2026-03-01T00:00:00Z')",
      },
      end: {
        type: 'string',
        description: '終了時刻 (省略時=現在)',
        default: 'now',
      },
      step: {
        type: 'string',
        description: "ステップ間隔 (例: '30s', '5m')",
        default: '60s',
      },
    },
    required: ['query', 'start'],
  },
};

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
