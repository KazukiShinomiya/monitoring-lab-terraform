import { query } from '../prometheus-client.js';

export const compareMetricsTool = {
  name: 'compare_metrics',
  description: '変更前後のメトリクスを比較して効果を測定する。terragrunt apply後の効果確認に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      query: {
        type: 'string',
        description: '比較するPromQL式',
      },
      baseline_time: {
        type: 'string',
        description: '比較基準時刻（変更前）ISO 8601 または Unix timestamp',
      },
      current_time: {
        type: 'string',
        description: '現在時刻（変更後）省略時=現在',
      },
    },
    required: ['query', 'baseline_time'],
  },
};

export async function handleCompareMetrics(
  queryExpr: string,
  baselineTime: string,
  currentTime?: string,
) {
  try {
    const [baselineData, currentData] = await Promise.all([
      query(queryExpr, baselineTime),
      query(queryExpr, currentTime),
    ]);

    const baselineVal = baselineData.result[0] ? parseFloat(baselineData.result[0].value[1]) : 0;
    const currentVal = currentData.result[0] ? parseFloat(currentData.result[0].value[1]) : 0;
    const deltaAbsolute = currentVal - baselineVal;
    const deltaPercent = baselineVal !== 0 ? (deltaAbsolute / baselineVal) * 100 : 0;
    const improved = deltaAbsolute < 0; // メモリ・CPU等は減少が改善

    const summary = `${baselineVal.toFixed(2)} → ${currentVal.toFixed(2)}（${deltaPercent >= 0 ? '+' : ''}${deltaPercent.toFixed(1)}%${improved ? '、改善' : '、悪化'}）`;

    const output = {
      query: queryExpr,
      baseline: { time: baselineTime, value: baselineVal },
      current: { time: currentTime ?? 'now', value: currentVal },
      delta_absolute: deltaAbsolute,
      delta_percent: deltaPercent,
      improved,
      summary,
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: メトリクス比較に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
