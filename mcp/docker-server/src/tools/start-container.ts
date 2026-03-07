import type { Tool } from '@modelcontextprotocol/sdk/types.js';
import { DockerClient } from '../docker-client.js';

export const startContainerTool: Tool = {
  name: 'docker_start_container',
  description: '停止中のコンテナを起動する。confirmed=false でドライラン。',
  inputSchema: {
    type: 'object',
    properties: {
      container_name: {
        type: 'string',
        description: '起動するコンテナ名（部分一致可）',
      },
      confirmed: {
        type: 'boolean',
        description: 'false: 操作内容を表示して終了。true: 実際に起動を実行。',
      },
    },
    required: ['container_name', 'confirmed'],
  },
};

const client = new DockerClient();

export async function handleStartContainer(container_name: string, confirmed: boolean) {
  try {
    const fullName = await client.findContainer(container_name);
    const currentStatus = await client.getContainerStatus(fullName);

    if (!confirmed) {
      const result = {
        dry_run: true as const,
        container_name: fullName,
        current_status: currentStatus,
        action: 'start',
        message: `${fullName} を起動します。実行するには confirmed=true で再度呼び出してください。`,
      };
      return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
    }

    if (currentStatus === 'running' || currentStatus === 'restarting' || currentStatus === 'paused') {
      const msg = `Error: ${fullName} は既に ${currentStatus} 状態です。`;
      return { content: [{ type: 'text' as const, text: msg }], isError: true };
    }

    await client.startContainer(fullName);
    const newStatus = await client.getContainerStatus(fullName);
    const result = {
      success: true,
      container_name: fullName,
      action: 'started',
      new_status: newStatus,
      message: `${fullName} を起動しました。現在の状態: ${newStatus}`,
    };
    return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
