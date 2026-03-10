import { DockerClient } from '../docker-client.js';

const client = new DockerClient();

export async function handleGetStats() {
  try {
    const stats = await client.getStats();
    if (stats.length === 0) {
      return { content: [{ type: 'text' as const, text: 'コンテナが見つかりません。' }] };
    }
    const header = 'NAME                        CPU%    MEM USAGE / LIMIT    MEM%';
    const separator = '-'.repeat(65);
    const rows = stats.map(s =>
      `${s.name.padEnd(28)}${s.cpu_percent.padEnd(8)}${s.memory_usage.padEnd(21)}${s.memory_percent}`
    );
    const text = [header, separator, ...rows].join('\n');
    return { content: [{ type: 'text' as const, text }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
