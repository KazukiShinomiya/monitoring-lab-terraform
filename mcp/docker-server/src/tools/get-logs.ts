import type { Tool } from '@modelcontextprotocol/sdk/types.js';
import { DockerClient } from '../docker-client.js';

export const getLogsTool: Tool = {
  name: 'docker_get_logs',
  description: '指定コンテナの直近ログを取得する',
  inputSchema: {
    type: 'object',
    properties: {
      container_name: {
        type: 'string',
        description: 'コンテナ名（部分一致可。候補が複数ある場合は選択を促す）',
      },
      lines: {
        type: 'number',
        description: '取得するログ行数（デフォルト: 100）',
        default: 100,
      },
    },
    required: ['container_name'],
  },
};

const client = new DockerClient();

export async function handleGetLogs(container_name: string, lines: number = 100) {
  try {
    const fullName = await client.findContainer(container_name);
    const logs = await client.getLogs(fullName, lines);
    const text = logs || '(ログが空です)';
    return { content: [{ type: 'text' as const, text }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
