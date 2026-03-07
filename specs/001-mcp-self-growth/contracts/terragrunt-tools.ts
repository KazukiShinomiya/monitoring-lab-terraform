/**
 * Terragrunt MCP Server — ツールスキーマ定義
 * 実装: mcp-servers/terragrunt-mcp/src/tools/
 */

import { z } from "zod";

// 有効なサービス名ホワイトリスト（コマンドインジェクション防止）
export const VALID_SERVICES = [
  'network', 'postgres', 'vault', 'prometheus', 'grafana',
  'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'
] as const;

export type ServiceName = typeof VALID_SERVICES[number];

// =====================================================
// Tool: plan_service
// 指定サービスの terragrunt plan を実行する（読み取り専用）
// =====================================================
export const PlanServiceInput = z.object({
  service: z.enum(VALID_SERVICES)
    .describe("planを実行するサービス名"),
});

export interface PlanServiceOutput {
  service: string;
  has_changes: boolean;
  plan_output: string;       // terragrunt plan の完全な出力
  resources_to_add: number;
  resources_to_change: number;
  resources_to_destroy: number;
  executed_at: string;
}

// =====================================================
// Tool: apply_service
// 指定サービスの terragrunt apply を実行する（承認必須）
// =====================================================
export const ApplyServiceInput = z.object({
  service: z.enum(VALID_SERVICES)
    .describe("applyを実行するサービス名"),
  approval_id: z.string().uuid()
    .describe("対応する承認ログのID（承認なしでは実行不可）"),
});

export interface ApplyServiceOutput {
  service: string;
  success: boolean;
  apply_output: string;
  resources_added: number;
  resources_changed: number;
  resources_destroyed: number;
  applied_at: string;
}

// =====================================================
// Tool: list_workspaces
// HCP Terraform Workspaceの状態を確認する
// =====================================================
export const ListWorkspacesInput = z.object({});

export interface ListWorkspacesOutput {
  organization: string;
  workspaces: Array<{
    name: string;
    execution_mode: 'local' | 'remote' | 'agent';
    resource_count: number;
    last_applied: string | null;
    status: 'no_changes' | 'has_changes' | 'unknown';
  }>;
}

// =====================================================
// Tool: rollback_service
// ApprovalLogのスナップショットからサービスをロールバックする
// =====================================================
export const RollbackServiceInput = z.object({
  approval_id: z.string().uuid()
    .describe("ロールバック対象の承認ログID。このIDのsnapshot_beforeが復元される。"),
});

export interface RollbackServiceOutput {
  service: string;
  success: boolean;
  restored_from: string;      // 復元元のスナップショット取得時刻
  rollback_applied_at: string;
  apply_output: string;
}

// =====================================================
// Tool: get_service_config
// サービスのTerragrunt設定ファイルを読み取る（読み取り専用）
// =====================================================
export const GetServiceConfigInput = z.object({
  service: z.enum(VALID_SERVICES)
    .describe("設定を読み取るサービス名"),
});

export interface GetServiceConfigOutput {
  service: string;
  file_path: string;
  content: string;           // terragrunt.hclの内容
  last_modified: string;
}

// =====================================================
// MCP Tool Registration Schema
// =====================================================
export const TERRAGRUNT_TOOLS = [
  {
    name: "plan_service",
    description: "terragrunt planを実行して変更内容を確認する（読み取り専用、承認不要）。提案内容の差分確認に使用する。",
    inputSchema: PlanServiceInput,
  },
  {
    name: "apply_service",
    description: "terragrunt applyを実行してインフラ変更を適用する。【承認必須】approval_idが必要。",
    inputSchema: ApplyServiceInput,
  },
  {
    name: "list_workspaces",
    description: "HCP TerraformのWorkspace一覧と状態を取得する。インフラ全体の管理状況を確認する。",
    inputSchema: ListWorkspacesInput,
  },
  {
    name: "rollback_service",
    description: "承認ログのスナップショットからサービスをロールバックする。問題発生時の復元に使用する。",
    inputSchema: RollbackServiceInput,
  },
  {
    name: "get_service_config",
    description: "サービスのTerragrunt設定ファイルを読み取る（読み取り専用）。変更提案の基礎情報収集に使用する。",
    inputSchema: GetServiceConfigInput,
  },
] as const;
