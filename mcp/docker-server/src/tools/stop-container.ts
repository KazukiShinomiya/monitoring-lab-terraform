import { DockerClient } from '../docker-client.js';

const client = new DockerClient();

export async function handleStopContainer(container_name: string, confirmed: boolean) {
  try {
    const fullName = await client.findContainer(container_name);
    const currentStatus = await client.getContainerStatus(fullName);

    if (!confirmed) {
      const result = {
        dry_run: true as const,
        container_name: fullName,
        current_status: currentStatus,
        action: 'stop',
        message: `${fullName} を停止します。実行するには confirmed=true で再度呼び出してください。`,
      };
      return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
    }

    if (currentStatus !== 'running' && currentStatus !== 'restarting' && currentStatus !== 'paused') {
      const msg = `Error: ${fullName} は既に ${currentStatus} 状態です。`;
      return { content: [{ type: 'text' as const, text: msg }], isError: true };
    }

    await client.stopContainer(fullName);
    const newStatus = await client.getContainerStatus(fullName);
    const result = {
      success: true,
      container_name: fullName,
      action: 'stopped',
      new_status: newStatus,
      message: `${fullName} を停止しました。現在の状態: ${newStatus}`,
    };
    return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { content: [{ type: 'text' as const, text: message }], isError: true };
  }
}
