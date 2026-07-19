import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

const SSH_HOST = process.env.SSH_HOST ?? 'ubuntu@YOUR_SERVER_IP';
const SSH_KEY_PATH = process.env.SSH_KEY_PATH ?? '/root/.ssh/id_rsa';

export const VALID_SERVICES = [
  'network', 'postgres', 'vault', 'vault-secrets',
  'prometheus', 'grafana',
  'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic',
  'alertmanager', 'tempo', 'otel-collector',
  'loki', 'promtail', 'victoriametrics',
  'github-runner', 'pyroscope', 'wow-exporter',
] as const;

export type ServiceName = typeof VALID_SERVICES[number];

export function validateServiceName(service: string): ServiceName {
  if (!(VALID_SERVICES as readonly string[]).includes(service)) {
    throw new Error(`Invalid service name: "${service}". Must be one of: ${VALID_SERVICES.join(', ')}`);
  }
  return service as ServiceName;
}

export async function execSsh(command: string, timeoutMs = 60000): Promise<string> {
  const { stdout } = await execFileAsync(
    'ssh',
    // 2026-06 監査 M-4: accept-new + known_hosts(readonly マウント) でホスト鍵の変化を検出する。
    // コンテナは --rm で毎回新規のため、検証の実効性はホスト側 known_hosts のマウントが担う
    ['-o', 'StrictHostKeyChecking=accept-new', '-o', `ConnectTimeout=10`, '-i', SSH_KEY_PATH, SSH_HOST, command],
    { encoding: 'utf-8', timeout: timeoutMs }
  );
  return stdout;
}
