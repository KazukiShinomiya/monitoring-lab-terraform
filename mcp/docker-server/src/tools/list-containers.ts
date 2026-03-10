import { DockerClient } from '../docker-client.js';

const client = new DockerClient();

export async function handleListContainers() {
  try {
    const containers = await client.listContainers();
    if (containers.length === 0) {
      return { content: [{ type: 'text' as const, text: 'コンテナが見つかりません。' }] };
    }
    const header = 'NAME                        STATUS     UPTIME';
    const separator = '-'.repeat(60);
    const rows = containers.map(c =>
      `${c.name.padEnd(28)}${c.status.padEnd(11)}${c.uptime}`
    );
    const text = [header, separator, ...rows].join('\n');
    return { content: [{ type: 'text' as const, text }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
