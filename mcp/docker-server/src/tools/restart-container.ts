import { DockerClient } from '../docker-client.js';

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
