export type Urgency = 'low' | 'medium' | 'high';

interface AlertInfo {
  name: string;
  state: 'firing' | 'pending';
}

/**
 * アラート状態とメモリ逼迫情報から緊急度を判定する。
 * - firing アラートあり → high
 * - メモリ80%超コンテナあり → medium
 * - それ以外 → low
 */
export function classifyUrgency(alerts: AlertInfo[], highMemContainers: string[]): Urgency {
  if (alerts.some(a => a.state === 'firing')) return 'high';
  if (highMemContainers.length > 0) return 'medium';
  return 'low';
}
