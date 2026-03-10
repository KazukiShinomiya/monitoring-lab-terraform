import { getAlerts } from '../prometheus-client.js';

export async function handleGetActiveAlerts(severity: string = 'all') {
  try {
    const alerts = await getAlerts();
    const filtered = severity === 'all'
      ? alerts
      : alerts.filter(a => a.labels['severity'] === severity);

    const output = {
      count: filtered.length,
      alerts: filtered.map(a => ({
        name: a.labels['alertname'] ?? 'unknown',
        state: a.state as 'firing' | 'pending',
        severity: a.labels['severity'] ?? 'unknown',
        summary: a.annotations['summary'] ?? '',
        description: a.annotations['description'] ?? '',
        started_at: a.activeAt,
        labels: a.labels,
        annotations: a.annotations,
      })),
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: Prometheusアラート取得に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
