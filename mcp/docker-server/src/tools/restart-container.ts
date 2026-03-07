import type { Tool } from '@modelcontextprotocol/sdk/types.js';
import { DockerClient } from '../docker-client.js';

export const restartContainerTool: Tool = {
  name: 'docker_restart_container',
  description: 'コンテナを再起動する。confirmed=false でドライラン（操作内容の確認のみ）。',
  inputSchema: {
    type: 'object',
    properties: {
      container_name: {
        type: 'string',
        description: '再起動するコンテナ名（部分一致可）',
      },
      confirmed: {
        type: 'boolean',
        description: 'false: 操作内容を表示して終了（ドライラン）。true: 実際に再起動を実行。',
      },
    },
    required: ['container_name', 'confirmed'],
  },
};

const client = new DockerClient();

export async function handleRestartContainer(container_name: string, confirmed: boolean) {
  try {
    const fullName = await client.findContainer(container_name);
    const currentStatus = await client.getContainerStatus(fullName);

    if (!confirmed) {
      const result = {
        dry_run: true as const,
        container_name: fullName,
        current_status: currentStatus,
        action: 'restart',
        message: `${fullName} を再起動します。実行するには confirmed=true で再度呼び出してください。`,
      };
      return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
    }

    await client.restartContainer(fullName);
    const newStatus = await client.getContainerStatus(fullName);
    const result = {
      success: true,
      container_name: fullName,
      action: 'restarted',
      new_status: newStatus,
      message: `${fullName} を再起動しました。現在の状態: ${newStatus}`,
    };
    return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
