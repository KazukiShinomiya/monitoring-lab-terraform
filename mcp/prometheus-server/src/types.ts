export type ProposalStatus = 'pending' | 'approved' | 'rejected' | 'applied' | 'rolled_back';

export interface Evidence {
  type: 'metric' | 'log' | 'alert';
  source: string;
  data: string;
  timestamp: string;
}

export interface Proposal {
  id: string;
  urgency: 'low' | 'medium' | 'high';
  target: string;
  content: string;
  expected_effect: string;
  evidence: Evidence[];
  created_at: string;
  status: ProposalStatus;
}

export interface ProposalIndexItem {
  id: string;
  urgency: 'low' | 'medium' | 'high';
  target: string;
  status: ProposalStatus;
  created_at: string;
  content_preview: string;
}

export interface ProposalIndex {
  last_updated: string;
  total: number;
  items: ProposalIndexItem[];
}

export interface MetricSnapshot {
  query: string;
  value: number;
  unit: string;
  timestamp: string;
}
