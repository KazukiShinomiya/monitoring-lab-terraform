export interface MetricSnapshot {
  query: string;
  value: number;
  unit: string;
  timestamp: string;
}

export interface ConfigSnapshot {
  service: string;
  file_path: string;
  content_before: string;
  terragrunt_state?: string;
  captured_at: string;
}

export interface ApprovalLog {
  id: string;
  proposal_id: string;
  // 2026-06 監査 H-2: 承認は特定サービスに紐づく。apply 時に一致を検証する。
  // 旧フォーマットのログには存在しないため optional（apply 側で欠落を拒否）
  service?: string;
  decision: 'approved' | 'rejected';
  decided_at: string;
  decided_by: string;
  snapshot_before?: ConfigSnapshot;
  applied_at?: string;
  apply_result?: string;
}

export interface EffectReport {
  id: string;
  proposal_id: string;
  approval_id: string;
  measured_at: string;
  metrics_before: MetricSnapshot[];
  metrics_after: MetricSnapshot[];
  delta_summary: string;
  success: boolean;
}
