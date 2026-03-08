import { getAlerts } from '../prometheus-client.js';

export const getActiveAlertsTool = {
  name: 'get_active_alerts',
  description: '現在発火中のPrometheusアラートを取得する。問題の緊急度判定に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      severity: {
        type: 'string',
        enum: ['all', 'critical', 'warning', 'info'],
        description: 'フィルター: allで全アラート取得',
        default: 'all',
      },
    },
    required: [],
  },
};

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
