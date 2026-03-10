const TF_ORG = process.env.TF_ORG ?? 'k1981-learning-lab';
const TF_TOKEN = process.env.TF_TOKEN_app_terraform_io ?? process.env.TF_TOKEN ?? '';

export async function handleListWorkspaces() {
  try {
    if (!TF_TOKEN) {
      return {
        content: [{ type: 'text' as const, text: 'エラー: TF_TOKEN_app_terraform_io 環境変数が設定されていません。' }],
        isError: true,
      };
    }

    const res = await fetch(
      `https://app.terraform.io/api/v2/organizations/${TF_ORG}/workspaces?page[size]=50`,
      {
        headers: {
          Authorization: `Bearer ${TF_TOKEN}`,
          'Content-Type': 'application/vnd.api+json',
        },
      },
    );
    if (!res.ok) throw new Error(`HCP Terraform API error: ${res.status} ${res.statusText}`);

    const json = await res.json() as {
      data: Array<{
        id: string;
        attributes: {
          name: string;
          'execution-mode': string;
          'resource-count': number;
          'latest-change-at': string | null;
        };
      }>;
    };

    const workspaces = json.data.map(w => ({
      name: w.attributes.name,
      execution_mode: w.attributes['execution-mode'] as 'local' | 'remote' | 'agent',
      resource_count: w.attributes['resource-count'],
      last_applied: w.attributes['latest-change-at'],
      status: 'unknown' as const,
    }));

    const output = {
      organization: TF_ORG,
      workspaces,
    };
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(output, null, 2) }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: HCP Terraform API への接続に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
