import { query } from '../prometheus-client.js';

export const queryMetricsTool = {
  name: 'query_metrics',
  description: 'PromQLインスタントクエリでメトリクスを取得する。コンテナのCPU・メモリ・ネットワーク状態の確認に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      query: {
        type: 'string',
        description: "PromQL式 (例: 'container_memory_usage_bytes{name=\"monitoring-lab-prometheus\"}')",
      },
      time: {
        type: 'string',
        description: 'クエリ時刻 (ISO 8601 or Unix timestamp, 省略時=現在)',
      },
    },
    required: ['query'],
  },
};

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
