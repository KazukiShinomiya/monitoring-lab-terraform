const PROMETHEUS_URL = process.env.PROMETHEUS_URL ?? 'http://YOUR_SERVER_IP:9090';

export interface PrometheusResult {
  metric: Record<string, string>;
  value: [number, string];
}

export interface PrometheusRangeResult {
  metric: Record<string, string>;
  values: Array<[number, string]>;
}

export async function query(expr: string, time?: string): Promise<{ resultType: string; result: PrometheusResult[] }> {
  const params = new URLSearchParams({ query: expr });
  if (time) params.set('time', time);
  const res = await fetch(`${PROMETHEUS_URL}/api/v1/query?${params}`);
  if (!res.ok) throw new Error(`Prometheus query failed: ${res.status} ${res.statusText}`);
  const json = await res.json() as { status: string; data: { resultType: string; result: PrometheusResult[] } };
  if (json.status !== 'success') throw new Error(`Prometheus error: ${JSON.stringify(json)}`);
  return json.data;
}

export async function queryRange(expr: string, start: string, end: string, step: string): Promise<{ result: PrometheusRangeResult[] }> {
  const resolvedStart = resolveTime(start);
  const resolvedEnd = resolveTime(end);
  const params = new URLSearchParams({ query: expr, start: resolvedStart, end: resolvedEnd, step });
  const res = await fetch(`${PROMETHEUS_URL}/api/v1/query_range?${params}`);
  if (!res.ok) throw new Error(`Prometheus query_range failed: ${res.status} ${res.statusText}`);
  const json = await res.json() as { status: string; data: { result: PrometheusRangeResult[] } };
  if (json.status !== 'success') throw new Error(`Prometheus error: ${JSON.stringify(json)}`);
  return json.data;
}

export async function getAlerts(): Promise<Array<{
  labels: Record<string, string>;
  annotations: Record<string, string>;
  state: string;
  activeAt: string;
}>> {
  const res = await fetch(`${PROMETHEUS_URL}/api/v1/alerts`);
  if (!res.ok) throw new Error(`Prometheus alerts failed: ${res.status} ${res.statusText}`);
  const json = await res.json() as { status: string; data: { alerts: Array<{ labels: Record<string, string>; annotations: Record<string, string>; state: string; activeAt: string }> } };
  if (json.status !== 'success') throw new Error(`Prometheus error: ${JSON.stringify(json)}`);
  return json.data.alerts;
}

function resolveTime(t: string): string {
  if (t === 'now') return String(Math.floor(Date.now() / 1000));
  // "now-1h", "now-30m" 形式をパース
  const m = t.match(/^now-(\d+)(s|m|h|d)$/);
  if (m) {
    const units: Record<string, number> = { s: 1, m: 60, h: 3600, d: 86400 };
    return String(Math.floor(Date.now() / 1000) - Number(m[1]) * units[m[2]]);
  }
  return t;
}
