import { execSsh, validateServiceName } from '../ssh-client.js';

export async function handleGetServiceConfig(service: string) {
  try {
    const validService = validateServiceName(service);
    const filePath = `/workspace/terraform/envs/local/${validService}/terragrunt.hcl`;
    const [content, lastModified] = await Promise.all([
      execSsh(`cat ${filePath}`),
      execSsh(`stat -c '%y' ${filePath} 2>/dev/null || echo 'unknown'`),
    ]);

    const output = {
      service: validService,
      file_path: filePath,
      content: content.trim(),
      last_modified: lastModified.trim(),
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: 設定ファイルの読み取りに失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
