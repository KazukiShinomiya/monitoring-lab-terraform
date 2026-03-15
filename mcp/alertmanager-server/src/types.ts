// Alertmanager API v2 型定義

export interface Matcher {
  name: string;
  value: string;
  isRegex: boolean;
  isEqual: boolean;
}

export interface AlertStatus {
  state: 'firing' | 'pending' | 'resolved';
  silencedBy: string[];
  inhibitedBy: string[];
}

export interface Alert {
  labels: Record<string, string>;
  annotations: Record<string, string>;
  startsAt: string;
  endsAt: string;
  updatedAt: string;
  fingerprint: string;
  status: AlertStatus;
  receivers: Array<{ name: string }>;
  generatorURL: string;
}

export interface SilenceStatus {
  state: 'active' | 'pending' | 'expired';
}

export interface Silence {
  id: string;
  matchers: Matcher[];
  startsAt: string;
  endsAt: string;
  updatedAt: string;
  createdBy: string;
  comment: string;
  status: SilenceStatus;
}

export interface CreateSilenceParams {
  matchers: Matcher[];
  startsAt: string;
  endsAt: string;
  createdBy: string;
  comment: string;
}
