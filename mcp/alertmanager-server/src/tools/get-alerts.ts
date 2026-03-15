import { alertmanagerClient } from '../alertmanager-client.js';
import type { Alert } from '../types.js';

function formatTimeDiff(isoString: string): string {
  const now = Date.now();
  const then = new Date(isoString).getTime();
  const diffMs = now - then;
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 60) return `${diffMin}分前`;
  const diffH = Math.floor(diffMin / 60);
  if (diffH < 24) return `${diffH}時間前`;
  return `${Math.floor(diffH / 24)}日前`;
}

function formatAlert(alert: Alert, index: number): string {
  const name = alert.labels['alertname'] ?? '(unknown)';
  const severity = (alert.labels['severity'] ?? 'unknown').toUpperCase();
  const emoji = severity === 'CRITICAL' ? '🚨' : '⚠️';
  const labelEntries = Object.entries(alert.labels)
    .filter(([k]) => k !== 'alertname' && k !== 'severity')
    .map(([k, v]) => `${k}=${v}`)
    .join(', ');
  const since = formatTimeDiff(alert.startsAt);

  let line = `${index}. [${severity}] ${emoji} ${name}\n`;
  if (labelEntries) line += `   ラベル: ${labelEntries}\n`;
  line += `   発生: ${alert.startsAt} (${since})\n`;
  line += `   状態: ${alert.status.state}`;
  if (alert.status.silencedBy.length > 0) {
    line += ` / silenced by: [${alert.status.silencedBy.join(', ')}]`;
  }
  if (alert.status.inhibitedBy.length > 0) {
    line += ` / inhibited by: [${alert.status.inhibitedBy.join(', ')}]`;
  }
  if (alert.annotations['description'] || alert.annotations['summary']) {
    const desc = alert.annotations['description'] ?? alert.annotations['summary'];
    line += `\n   説明: ${desc}`;
  }
  return line;
}

export async function handleGetAlerts(severity?: string): Promise<{ content: Array<{ type: 'text'; text: string }> }> {
  let alerts: Alert[];
  try {
    alerts = await alertmanagerClient.getAlerts(severity ? { severity } : undefined);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { content: [{ type: 'text', text: `❌ Alertmanager に接続できません: ${process.env.ALERTMANAGER_HOST ?? 'http://YOUR_SERVER_IP:9093'}\n${message}` }] };
  }

  // firing/pending のみ表示（resolved は除外）
  const active = alerts.filter(a => a.status.state !== 'resolved');

  if (active.length === 0) {
    const filterMsg = severity ? ` (severity=${severity})` : '';
    return { content: [{ type: 'text', text: `✅ 現在発火中のアラートはありません${filterMsg}` }] };
  }

  const lines = [`🔔 アクティブアラート: ${active.length}件\n`];
  active.forEach((alert, i) => lines.push(formatAlert(alert, i + 1)));
  return { content: [{ type: 'text', text: lines.join('\n') }] };
}
