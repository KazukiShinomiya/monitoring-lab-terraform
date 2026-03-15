import type { Alert, Silence, CreateSilenceParams } from './types.js';

export class AlertmanagerClient {
  private baseUrl: string;

  constructor() {
    this.baseUrl = (process.env.ALERTMANAGER_HOST ?? 'http://YOUR_SERVER_IP:9093').replace(/\/$/, '');
  }

  async getAlerts(filter?: { severity?: string }): Promise<Alert[]> {
    const url = new URL(`${this.baseUrl}/api/v2/alerts`);
    if (filter?.severity) {
      url.searchParams.set('filter', `severity="${filter.severity}"`);
    }
    const res = await fetch(url.toString());
    if (!res.ok) {
      throw new Error(`Alertmanager API error: ${res.status} ${res.statusText}`);
    }
    return res.json() as Promise<Alert[]>;
  }

  async createSilence(params: CreateSilenceParams): Promise<{ silenceID: string }> {
    const res = await fetch(`${this.baseUrl}/api/v2/silences`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(params),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Alertmanager API error: ${res.status} ${body}`);
    }
    return res.json() as Promise<{ silenceID: string }>;
  }

  async getSilences(): Promise<Silence[]> {
    const res = await fetch(`${this.baseUrl}/api/v2/silences`);
    if (!res.ok) {
      throw new Error(`Alertmanager API error: ${res.status} ${res.statusText}`);
    }
    return res.json() as Promise<Silence[]>;
  }

  async getSilence(silenceId: string): Promise<Silence> {
    const res = await fetch(`${this.baseUrl}/api/v2/silence/${silenceId}`);
    if (res.status === 404) {
      throw new Error(`SILENCE_NOT_FOUND:${silenceId}`);
    }
    if (!res.ok) {
      throw new Error(`Alertmanager API error: ${res.status} ${res.statusText}`);
    }
    return res.json() as Promise<Silence>;
  }

  async deleteSilence(silenceId: string): Promise<void> {
    const res = await fetch(`${this.baseUrl}/api/v2/silence/${silenceId}`, {
      method: 'DELETE',
    });
    if (res.status === 404) {
      throw new Error(`SILENCE_NOT_FOUND:${silenceId}`);
    }
    if (!res.ok) {
      throw new Error(`Alertmanager API error: ${res.status} ${res.statusText}`);
    }
  }
}

export const alertmanagerClient = new AlertmanagerClient();
