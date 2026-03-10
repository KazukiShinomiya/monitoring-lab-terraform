import { query } from '../prometheus-client.js';

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
