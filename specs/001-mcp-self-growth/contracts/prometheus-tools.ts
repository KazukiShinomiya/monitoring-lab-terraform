/**
 * Prometheus MCP Server — ツールスキーマ定義
 * 実装: mcp-servers/prometheus-mcp/src/tools/
 */

import { z } from "zod";

// =====================================================
// Tool: query_metrics
// PromQLインスタントクエリを実行する
// =====================================================
export const QueryMetricsInput = z.object({
  query: z.string().min(1)
    .describe("PromQL式 (例: 'container_memory_usage_bytes{name=\"monitoring-lab-prometheus\"}')"),
  time: z.string().optional()
    .describe("クエリ時刻 (ISO 8601 or Unix timestamp, 省略時=現在)"),
});

export interface QueryMetricsOutput {
  query: string;
  result_type: 'vector' | 'scalar' | 'matrix' | 'string';
  results: Array<{
    metric: Record<string, string>;  // ラベルセット
    value: [number, string];         // [timestamp, value]
  }>;
  executed_at: string;
}

// =====================================================
// Tool: query_range
// PromQL範囲クエリを実行する（時系列データ）
// =====================================================
export const QueryRangeInput = z.object({
  query: z.string().min(1)
    .describe("PromQL式"),
  start: z.string()
    .describe("開始時刻 (例: 'now-1h', '2026-03-01T00:00:00Z')"),
  end: z.string().default('now')
    .describe("終了時刻 (省略時=現在)"),
  step: z.string().default('60s')
    .describe("ステップ間隔 (例: '30s', '5m')"),
});

export interface QueryRangeOutput {
  query: string;
  data_points: number;
  results: Array<{
    metric: Record<string, string>;
    values: Array<[number, string]>;   // [[timestamp, value], ...]
  }>;
}

// =====================================================
// Tool: get_active_alerts
// 現在発火中のアラートを取得する
// =====================================================
export const GetActiveAlertsInput = z.object({
  severity: z.enum(['all', 'critical', 'warning', 'info']).default('all')
    .describe("フィルター: allで全アラート取得"),
});

export interface GetActiveAlertsOutput {
  count: number;
  alerts: Array<{
    name: string;           // アラートルール名
    state: 'firing' | 'pending';
    severity: string;
    summary: string;
    description: string;
    started_at: string;     // ISO 8601
    labels: Record<string, string>;
    annotations: Record<string, string>;
  }>;
}

// =====================================================
// Tool: compare_metrics
// 変更前後のメトリクスを比較する（効果測定用）
// =====================================================
export const CompareMetricsInput = z.object({
  query: z.string()
    .describe("比較するPromQL式"),
  baseline_time: z.string()
    .describe("比較基準時刻（変更前）ISO 8601"),
  current_time: z.string().default('now')
    .describe("現在時刻（変更後）"),
});

export interface CompareMetricsOutput {
  query: string;
  baseline: { time: string; value: number; };
  current: { time: string; value: number; };
  delta_absolute: number;
  delta_percent: number;
  improved: boolean;
  summary: string;  // 日本語サマリー "メモリ使用量が1.2GB → 0.9GB（25%削減）"
}

// =====================================================
// MCP Tool Registration Schema
// =====================================================
export const PROMETHEUS_TOOLS = [
  {
    name: "query_metrics",
    description: "PromQLインスタントクエリでメトリクスを取得する。コンテナのCPU・メモリ・ネットワーク状態の確認に使用する。",
    inputSchema: QueryMetricsInput,
  },
  {
    name: "query_range",
    description: "PromQL範囲クエリで時系列データを取得する。トレンド分析・傾向把握に使用する。",
    inputSchema: QueryRangeInput,
  },
  {
    name: "get_active_alerts",
    description: "現在発火中のPrometheusアラートを取得する。問題の緊急度判定に使用する。",
    inputSchema: GetActiveAlertsInput,
  },
  {
    name: "compare_metrics",
    description: "変更前後のメトリクスを比較して効果を測定する。terragrunt apply後の効果確認に使用する。",
    inputSchema: CompareMetricsInput,
  },
] as const;
