import { vi, describe, it, expect, beforeEach } from 'vitest';

// __tests__/ から見た正しい相対パス（../../ = src/ 直下）
vi.mock('../../storage.js', () => ({
  getApprovalLog: vi.fn().mockResolvedValue(null),
  saveApprovalLog: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../../ssh-client.js', () => ({
  execSsh: vi.fn().mockResolvedValue(''),
  validateServiceName: vi.fn((s: string) => s),
  VALID_SERVICES: ['network', 'postgres', 'vault', 'prometheus', 'grafana',
    'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'] as const,
}));

import { handleRollbackService } from '../rollback-service.js';
import { handleApplyService } from '../apply-service.js';
import { handleCreateApproval } from '../create-approval.js';
import * as storage from '../../storage.js';

beforeEach(() => vi.clearAllMocks());

describe('rollback_service: confirmed ガード', () => {
  it('confirmed=false → 即座にエラー（外部アクセスなし）', async () => {
    const result = await handleRollbackService('any-id', false);
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('confirmed=true');
    expect(vi.mocked(storage.getApprovalLog)).not.toHaveBeenCalled();
  });
});

describe('apply_service: 承認なし実行ガード', () => {
  it('承認ログが存在しない → エラー', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(null);
    const result = await handleApplyService('prometheus', 'fake-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('承認ログが見つかりません');
  });

  it('decision=rejected の承認ログ → エラー', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce({
      id: 'log-id',
      proposal_id: 'prop-id',
      decision: 'rejected',
      decided_at: '2026-01-01',
      decided_by: 'operator',
    });
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('承認されていません');
  });
});

describe('create_approval: ログ作成', () => {
  it('approved → saveApprovalLog が呼ばれ次のステップを案内', async () => {
    const result = await handleCreateApproval('prop-123', 'approved', 'operator');
    expect(result.isError).toBeUndefined();
    expect(result.content[0].text).toContain('承認');
    expect(result.content[0].text).toContain('次のステップ');
    expect(vi.mocked(storage.saveApprovalLog)).toHaveBeenCalledOnce();
  });

  it('rejected → 次のステップ案内なし', async () => {
    const result = await handleCreateApproval('prop-456', 'rejected');
    expect(result.content[0].text).not.toContain('次のステップ');
    expect(result.content[0].text).toContain('却下');
    expect(vi.mocked(storage.saveApprovalLog)).toHaveBeenCalledOnce();
  });
});
