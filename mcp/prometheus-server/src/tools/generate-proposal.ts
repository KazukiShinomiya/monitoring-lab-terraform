import { randomUUID } from 'crypto';
import { getAlerts, query } from '../prometheus-client.js';
import { classifyUrgency } from '../urgency.js';
import { saveProposal } from '../storage.js';
import type { Proposal, Evidence } from '../types.js';

export const generateProposalTool = {
  name: 'generate_proposal',
  description: '現在のインフラ状態を分析して改善提案を生成・保存する。緊急度（low/medium/high）を自動分類する。',
  inputSchema: {
    type: 'object' as const,
    properties: {},
    required: [],
  },
};

export async function handleGenerateProposal() {
  try {
    // アラートとメモリ使用率を並列取得
    const [alerts, memResult] = await Promise.all([
      getAlerts(),
      query('container_memory_usage_bytes / container_spec_memory_limit_bytes * 100 > 80').catch(() => ({ result: [] as { metric: Record<string, string>; value: [number, string] }[] })),
    ]);

    const firingAlerts = alerts.filter(a => a.state === 'firing');
    const highMemContainers = (memResult as { result: Array<{ metric: Record<string, string>; value: [number, string] }> }).result.map(
      r => r.metric['name'] ?? r.metric['container_name'] ?? 'unknown'
    );

    const urgency = classifyUrgency(
      firingAlerts.map(a => ({ name: a.labels['alertname'] ?? '', state: 'firing' as const })),
      highMemContainers,
    );

    // 根拠データ（evidence）の構築
    const evidence: Evidence[] = [];
    if (firingAlerts.length > 0) {
      evidence.push({
        type: 'alert',
        source: 'prometheus',
        data: firingAlerts.map(a => `${a.labels['alertname']}: ${a.annotations['summary'] ?? ''}`).join('\n'),
        timestamp: new Date().toISOString(),
      });
    }
    if (highMemContainers.length > 0) {
      evidence.push({
        type: 'metric',
        source: 'prometheus',
        data: `メモリ使用率80%超のコンテナ: ${highMemContainers.join(', ')}`,
        timestamp: new Date().toISOString(),
      });
    }
    if (evidence.length === 0) {
      evidence.push({
        type: 'metric',
        source: 'prometheus',
        data: '全コンテナのメモリ使用率は正常範囲内。アクティブアラートなし。',
        timestamp: new Date().toISOString(),
      });
    }

    // 提案内容の生成
    let content: string;
    let expectedEffect: string;
    let target: string;

    if (urgency === 'high' && firingAlerts.length > 0) {
      const alert = firingAlerts[0];
      target = alert.labels['instance'] ?? alert.labels['job'] ?? 'infrastructure';
      content = `## 緊急: アラート発火中\n\n**${alert.labels['alertname']}** が発火しています。\n\n${alert.annotations['description'] ?? alert.annotations['summary'] ?? ''}\n\n対象: ${target}\n\n### 推奨アクション\n1. 対象サービスのログを確認する（docker MCP の docker_get_logs を使用）\n2. リソース使用状況を確認する（docker MCP の docker_get_stats を使用）\n3. 必要に応じてサービスを再起動する`;
      expectedEffect = 'アラートの解消とサービスの正常化';
    } else if (urgency === 'medium' && highMemContainers.length > 0) {
      target = highMemContainers[0];
      content = `## 警告: メモリ使用率が高くなっています\n\n以下のコンテナのメモリ使用率が80%を超えています:\n${highMemContainers.map(c => `- ${c}`).join('\n')}\n\n### 推奨アクション\n1. Terragruntの設定でメモリ上限を引き上げることを検討してください\n2. または不要なプロセスを停止してメモリを解放してください`;
      expectedEffect = 'メモリ使用率の正常化（80%以下）によるパフォーマンス安定化';
    } else {
      target = 'infrastructure';
      content = `## 正常: インフラは安定稼働中\n\n現時点でアクティブなアラートはなく、全コンテナのリソース使用率は正常範囲内です。\n\n### 予防的最適化の提案\n- 定期的なバックアップの確認\n- ログローテーションの設定確認\n- 監視ダッシュボードの定期レビュー`;
      expectedEffect = 'インフラの継続的な安定稼働';
    }

    const proposal: Proposal = {
      id: randomUUID(),
      urgency,
      target,
      content,
      expected_effect: expectedEffect,
      evidence,
      created_at: new Date().toISOString(),
      status: 'pending',
    };

    await saveProposal(proposal);

    const urgencyLabel = { high: '🔴 高', medium: '🟡 中', low: '🟢 低' }[urgency];
    const summary = `改善提案を生成しました（緊急度: ${urgencyLabel}）\n\nID: ${proposal.id}\n対象: ${target}\n\n${content}`;

    return {
      content: [{ type: 'text' as const, text: summary }],
    };
  } catch (err) {
    return {
      content: [{ type: 'text' as const, text: `エラー: 改善提案の生成に失敗しました。\n${String(err)}` }],
      isError: true,
    };
  }
}
