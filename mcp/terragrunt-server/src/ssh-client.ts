import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

const SSH_HOST = process.env.SSH_HOST ?? 'ubuntu@10.0.0.220';
const SSH_KEY_PATH = process.env.SSH_KEY_PATH ?? '/root/.ssh/id_rsa';

export const VALID_SERVICES = [
  'network', 'postgres', 'vault', 'prometheus', 'grafana',
  'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'
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
    ['-o', 'StrictHostKeyChecking=no', '-o', `ConnectTimeout=10`, '-i', SSH_KEY_PATH, SSH_HOST, command],
    { encoding: 'utf-8', timeout: timeoutMs }
  );
  return stdout;
}
