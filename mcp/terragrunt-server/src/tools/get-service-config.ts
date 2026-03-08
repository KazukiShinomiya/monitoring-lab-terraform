import { execSsh, validateServiceName, VALID_SERVICES } from '../ssh-client.js';

export const getServiceConfigTool = {
  name: 'get_service_config',
  description: 'サービスのTerragrunt設定ファイルを読み取る（読み取り専用）。変更提案の基礎情報収集に使用する。',
  inputSchema: {
    type: 'object' as const,
    properties: {
      service: {
        type: 'string',
        enum: [...VALID_SERVICES],
        description: '設定を読み取るサービス名',
      },
    },
    required: ['service'],
  },
};

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
