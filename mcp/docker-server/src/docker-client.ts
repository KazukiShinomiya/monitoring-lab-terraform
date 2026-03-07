import { execFile } from 'child_process';
import { promisify } from 'util';
import type { ContainerInfo, ContainerStats, ContainerStatus } from './types.js';

const execFileAsync = promisify(execFile);

const REMOTE_HOST = 'ssh://ubuntu@YOUR_SERVER_IP';

const ERR_SSH = 'Error: リモートサーバー (YOUR_SERVER_IP) に接続できません。SSH鍵とネットワーク接続を確認してください。';

export class DockerClient {
  private async execDocker(args: string[]): Promise<string> {
    try {
      const { stdout } = await execFileAsync('docker', ['-H', REMOTE_HOST, ...args]);
      return stdout.trim();
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : String(error);
      if (msg.includes('ssh') || msg.includes('connect') || msg.includes('dial')) {
        throw new Error(ERR_SSH);
      }
      throw error;
    }
  }

  private parseStatus(statusStr: string): ContainerStatus {
    const s = statusStr.toLowerCase();
    if (s.startsWith('up')) return 'running';
    if (s.startsWith('exited')) return 'exited';
    if (s.startsWith('created')) return 'created';
    if (s.startsWith('restarting')) return 'restarting';
    if (s.startsWith('paused')) return 'paused';
    if (s.startsWith('dead')) return 'dead';
    return 'stopped';
  }

  async listContainers(): Promise<ContainerInfo[]> {
    const output = await this.execDocker([
      'ps', '-a',
      '--format', '{{.Names}}\t{{.Status}}\t{{.RunningFor}}',
    ]);
    if (!output) return [];
    return output.split('\n').filter(Boolean).map(line => {
      const [name, status, uptime] = line.split('\t');
      return { name: name ?? '', status: this.parseStatus(status ?? ''), uptime: uptime ?? '' };
    });
  }

  async findContainer(name: string): Promise<string> {
    const containers = await this.listContainers();
    const matches = containers.filter(c => c.name.includes(name));
    if (matches.length === 0) {
      throw new Error(`Error: コンテナ '${name}' が見つかりません。docker_list_containers で一覧を確認してください。`);
    }
    if (matches.length > 1) {
      const names = matches.map(c => c.name).join('\n  ');
      throw new Error(`候補が複数あります。完全なコンテナ名で再指定してください:\n  ${names}`);
    }
    return matches[0]!.name;
  }

  async getContainerStatus(name: string): Promise<ContainerStatus> {
    const containers = await this.listContainers();
    const container = containers.find(c => c.name === name);
    return container?.status ?? 'stopped';
  }

  async getLogs(name: string, lines: number): Promise<string> {
    return await this.execDocker(['logs', '--tail', String(lines), name]);
  }

  async getStats(): Promise<ContainerStats[]> {
    const output = await this.execDocker([
      'stats', '--no-stream',
      '--format', '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}',
    ]);
    if (!output) return [];
    return output.split('\n').filter(Boolean).map(line => {
      const [name, cpu_percent, memory_usage, memory_percent] = line.split('\t');
      return {
        name: name ?? '',
        cpu_percent: cpu_percent ?? '',
        memory_usage: memory_usage ?? '',
        memory_percent: memory_percent ?? '',
      };
    });
  }

  async restartContainer(name: string): Promise<void> {
    await this.execDocker(['restart', name]);
  }

  async stopContainer(name: string): Promise<void> {
    await this.execDocker(['stop', name]);
  }

  async startContainer(name: string): Promise<void> {
    await this.execDocker(['start', name]);
  }
}
