export type ContainerStatus =
  | 'running'
  | 'stopped'
  | 'paused'
  | 'restarting'
  | 'exited'
  | 'dead'
  | 'created';

export interface ContainerInfo {
  name: string;
  status: ContainerStatus;
  uptime: string;
}

export interface ContainerStats {
  name: string;
  cpu_percent: string;
  memory_usage: string;
  memory_percent: string;
}

export interface OperationResult {
  success: boolean;
  container_name: string;
  action: string;
  new_status: ContainerStatus;
  message: string;
}

export interface DryRunResult {
  dry_run: true;
  container_name: string;
  current_status: ContainerStatus;
  action: string;
  message: string;
}
