import { vi, describe, it, expect, beforeEach } from 'vitest';

// __tests__/ から見た正しい相対パス（../../ = src/ 直下）
vi.mock('../../prometheus-client.js', () => ({
  getAlerts: vi.fn().mockResolvedValue([]),
  query: vi.fn().mockResolvedValue({ result: [] }),
}));

vi.mock('../../storage.js', () => ({
  saveProposal: vi.fn().mockResolvedValue(undefined),
  listProposals: vi.fn().mockResolvedValue({ items: [] }),
  updateProposalStatus: vi.fn().mockResolvedValue(undefined),
  getProposal: vi.fn().mockResolvedValue(null),
}));

import { handleGenerateProposal } from '../generate-proposal.js';
import { handleListProposals } from '../list-proposals.js';
import { handleGetActiveAlerts } from '../get-active-alerts.js';
import * as storage from '../../storage.js';
import * as promClient from '../../prometheus-client.js';

beforeEach(() => vi.clearAllMocks());

describe('generate_proposal: dry_run', () => {
  it('dry_run=true → saveProposal が呼ばれない', async () => {
    const result = await handleGenerateProposal(true, 'all');
    expect(vi.mocked(storage.saveProposal)).not.toHaveBeenCalled();
    expect(result.content[0].text).toContain('dry_run=true');
  });

  it('dry_run=false → saveProposal が呼ばれる', async () => {
    await handleGenerateProposal(false, 'all');
    expect(vi.mocked(storage.saveProposal)).toHaveBeenCalledOnce();
  });
});

describe('generate_proposal: focus による絞り込み', () => {
  it('focus=alerts → query (メモリ) は呼ばれない', async () => {
    await handleGenerateProposal(true, 'alerts');
    expect(vi.mocked(promClient.query)).not.toHaveBeenCalled();
  });

  it('focus=memory → getAlerts は呼ばれない', async () => {
    await handleGenerateProposal(true, 'memory');
    expect(vi.mocked(promClient.getAlerts)).not.toHaveBeenCalled();
  });
});

describe('list_proposals: status フィルタ', () => {
  const twoItems = [
    { id: 'aaa', urgency: 'low' as const, target: 'infra', status: 'pending' as const, created_at: '2026-01-01', content_preview: 'test' },
    { id: 'bbb', urgency: 'high' as const, target: 'infra', status: 'applied' as const, created_at: '2026-01-02', content_preview: 'test2' },
  ];

  it('status=all → 全件返す', async () => {
    vi.mocked(storage.listProposals).mockResolvedValueOnce({ items: twoItems });
    const result = await handleListProposals({ status: 'all' });
    expect(result.content[0].text).toContain('2件');
  });

  it('status=pending → pending のみ返す', async () => {
    vi.mocked(storage.listProposals).mockResolvedValueOnce({ items: twoItems });
    const result = await handleListProposals({ status: 'pending' });
    expect(result.content[0].text).toContain('1件');
    expect(result.content[0].text).not.toContain('applied');
  });
});

describe('get_active_alerts: severity フィルタ', () => {
  const twoAlerts = [
    { state: 'firing', labels: { alertname: 'A', severity: 'critical' }, annotations: {}, activeAt: '' },
    { state: 'firing', labels: { alertname: 'B', severity: 'warning' }, annotations: {}, activeAt: '' },
  ];

  it('severity=all → 全件返す', async () => {
    vi.mocked(promClient.getAlerts).mockResolvedValueOnce(twoAlerts);
    const result = await handleGetActiveAlerts('all');
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.count).toBe(2);
  });

  it('severity=critical → critical のみ返す', async () => {
    vi.mocked(promClient.getAlerts).mockResolvedValueOnce(twoAlerts);
    const result = await handleGetActiveAlerts('critical');
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.count).toBe(1);
    expect(parsed.alerts[0].name).toBe('A');
  });
});
