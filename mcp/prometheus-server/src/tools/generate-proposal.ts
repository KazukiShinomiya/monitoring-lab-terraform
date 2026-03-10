import { randomUUID } from 'crypto';
import { getAlerts, query } from '../prometheus-client.js';
import { classifyUrgency } from '../urgency.js';
import { saveProposal, listProposals, updateProposalStatus, getProposal } from '../storage.js';
import type { Proposal, Evidence } from '../types.js';

/** cAdvisorの id ラベル（/docker/abc123...）からコンテナ名を抽出する */
function parseContainerName(metric: Record<string, string>): string {
  if (metric['name']) return metric['name'];
  if (metric['container_name']) return metric['container_name'];
  if (metric['image']) {
    const img = metric['image'].split('/').pop() ?? metric['image'];
    return img.split(':')[0];
  }
  const id = metric['id'] ?? '';
  const m = id.match(/docker[/-]([a-f0-9]{12})/);
  if (m) return `container:${m[1]}`;
  return 'unknown';
}

export async function handleGenerateProposal(dryRun: boolean = false, focus: string = 'all') {
  try {
    // focus による取得対象の絞り込み
    const [alerts, memResult] = await Promise.all([
      focus !== 'memory' ? getAlerts() : Promise.resolve([]),
      focus !== 'alerts'
        ? query('(container_memory_usage_bytes{id=~"/system.slice/docker-.+\\.scope"} / container_spec_memory_limit_bytes{id=~"/system.slice/docker-.+\\.scope"} * 100 > 80) and container_spec_memory_limit_bytes{id=~"/system.slice/docker-.+\\.scope"} > 0').catch(() => ({ result: [] as { metric: Record<string, string>; value: [number, string] }[] }))
        : Promise.resolve({ result: [] as { metric: Record<string, string>; value: [number, string] }[] }),
    ]);

    const firingAlerts = alerts.filter(a => a.state === 'firing');
    const firingAlertNames = new Set(firingAlerts.map(a => a.labels['alertname'] ?? ''));

    const highMemContainers = (memResult as { result: Array<{ metric: Record<string, string>; value: [number, string] }> }).result.map(
      r => parseContainerName(r.metric)
    );

    // 既存のpending提案のうち、アラートが解消されたものをresolvedに更新
    const index = await listProposals();
    const pendingItems = index.items.filter(i => i.status === 'pending');
    const autoResolved: string[] = [];
    for (const item of pendingItems) {
      const proposal = await getProposal(item.id);
      if (!proposal) continue;
      const alertEvidence = proposal.evidence.find(e => e.type === 'alert');
      if (!alertEvidence) continue;
      const evidenceAlertNames = alertEvidence.data
        .split('\n')
        .map(line => line.split(':')[0].trim())
        .filter(Boolean);
      const allResolved = evidenceAlertNames.every(name => !firingAlertNames.has(name));
      if (allResolved && evidenceAlertNames.length > 0) {
        await updateProposalStatus(item.id, 'applied');
        autoResolved.push(item.id.slice(0, 8));
      }
    }

    // 同一アラート名でpendingな提案が既にあればスキップ
    const updatedIndex = await listProposals();
    const stillPendingItems = updatedIndex.items.filter(i => i.status === 'pending');
    if (firingAlerts.length > 0 && stillPendingItems.length > 0) {
      for (const item of stillPendingItems) {
        const proposal = await getProposal(item.id);
        if (!proposal) continue;
        const alertEvidence = proposal.evidence.find(e => e.type === 'alert');
        if (!alertEvidence) continue;
        const existingNames = alertEvidence.data
          .split('\n')
          .map(line => line.split(':')[0].trim())
          .filter(Boolean);
        const overlap = existingNames.some(name => firingAlertNames.has(name));
        if (overlap) {
          const resolvedMsg = autoResolved.length > 0
            ? `\n\n✅ 解消済みとしてresolvedに更新した提案: ${autoResolved.join(', ')}`
            : '';
          return {
            content: [{
              type: 'text' as const,
              text: `同じアラートに対するpending提案が既に存在します（ID: ${item.id.slice(0, 8)}...）。重複生成をスキップしました。${resolvedMsg}\n\n既存提案を確認するには list_proposals を使用してください。`,
            }],
          };
        }
      }
    }

    const urgency = classifyUrgency(
      firingAlerts.map(a => ({ name: a.labels['alertname'] ?? '', state: 'firing' as const })),
      highMemContainers,
    );

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

    let content: string;
    let expectedEffect: string;
    let target: string;

    if (urgency === 'high' && firingAlerts.length > 0) {
      const alert = firingAlerts[0];
      target = alert.labels['instance'] ?? alert.labels['job'] ?? 'infrastructure';
      const allAlertSummaries = firingAlerts
        .map(a => `- **${a.labels['alertname']}**: ${a.annotations['description'] ?? a.annotations['summary'] ?? ''}`)
        .join('\n');
      content = `## 緊急: アラート発火中（${firingAlerts.length}件）\n\n${allAlertSummaries}\n\n### 推奨アクション\n1. 対象サービスのログを確認する（docker MCP の docker_get_logs を使用）\n2. リソース使用状況を確認する（docker MCP の docker_get_stats を使用）\n3. 必要に応じてサービスを再起動する`;
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

    const dryRunNote = dryRun ? '\n\n⚠️ dry_run=true: 提案は保存されていません。' : '';

    if (!dryRun) {
      await saveProposal(proposal);
    }

    const urgencyLabel = { high: '🔴 高', medium: '🟡 中', low: '🟢 低' }[urgency];
    const resolvedMsg = autoResolved.length > 0
      ? `\n\n✅ 解消済みとしてresolvedに更新した提案: ${autoResolved.join(', ')}`
      : '';
    const summary = `改善提案を生成しました（緊急度: ${urgencyLabel}）${resolvedMsg}${dryRunNote}\n\nID: ${proposal.id}\n対象: ${target}\n分析対象: ${focus}\n\n${content}`;

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
