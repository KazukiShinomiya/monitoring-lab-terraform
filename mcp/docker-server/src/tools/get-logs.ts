import { DockerClient } from '../docker-client.js';

const client = new DockerClient();

export async function handleGetLogs(container_name: string, lines: number = 100, since?: string) {
  try {
    const fullName = await client.findContainer(container_name);
    const logs = await client.getLogs(fullName, lines, since);
    const text = logs || '(ログが空です)';
    return { content: [{ type: 'text' as const, text }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
