import { vi, describe, it, expect, beforeEach } from 'vitest';
import type { ApprovalLog } from '../../types.js';

// __tests__/ から見た正しい相対パス（../../ = src/ 直下）
vi.mock('../../storage.js', () => ({
  getApprovalLog: vi.fn().mockResolvedValue(null),
  saveApprovalLog: vi.fn().mockResolvedValue(undefined),
}));

// vi.mock はファイル先頭へ巻き上げられるため、外側の変数を参照できない — 配列はファクトリ内に置く
vi.mock('../../ssh-client.js', () => {
  const services = ['network', 'postgres', 'vault', 'prometheus', 'grafana',
    'zabbix', 'zabbix-agent', 'cadvisor', 'snmp-exporter', 'newrelic'] as const;
  return {
    execSsh: vi.fn().mockResolvedValue(''),
    validateServiceName: vi.fn((s: string) => {
      if (!(services as readonly string[]).includes(s)) throw new Error(`Invalid service name: "${s}"`);
      return s;
    }),
    VALID_SERVICES: services,
  };
});

import { handleRollbackService } from '../rollback-service.js';
import { handleApplyService } from '../apply-service.js';
import { handleCreateApproval } from '../create-approval.js';
import * as storage from '../../storage.js';
import * as ssh from '../../ssh-client.js';

beforeEach(() => vi.clearAllMocks());

// 承認済み・prometheus 向け・いま決裁されたばかりのログ（各テストで上書きして崩す）
function freshLog(overrides: Partial<ApprovalLog> = {}): ApprovalLog {
  return {
    id: 'log-id',
    proposal_id: 'prop-id',
    service: 'prometheus',
    decision: 'approved',
    decided_at: new Date().toISOString(),
    decided_by: 'operator',
    ...overrides,
  };
}

describe('rollback_service: ガード', () => {
  it('confirmed=false → 即座にエラー（外部アクセスなし）', async () => {
    const result = await handleRollbackService('any-id', false);
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('confirmed=true');
    expect(vi.mocked(storage.getApprovalLog)).not.toHaveBeenCalled();
  });

  it('decision=rejected のログ → エラー（H-2）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({
      decision: 'rejected',
      snapshot_before: {
        service: 'prometheus',
        file_path: '/workspace/terraform/envs/local/prometheus/terragrunt.hcl',
        content_before: 'x',
        captured_at: '2026-01-01',
      },
    }));
    const result = await handleRollbackService('log-id', true);
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('承認されていません');
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('file_path が期待値と不一致（改竄） → エラー・SSH実行なし（M-2）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({
      snapshot_before: {
        service: 'prometheus',
        file_path: '/etc/passwd; rm -rf /',
        content_before: 'x',
        captured_at: '2026-01-01',
      },
    }));
    const result = await handleRollbackService('log-id', true);
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('改竄');
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('snapshot の service が許可リスト外 → エラー・SSH実行なし（M-2）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({
      snapshot_before: {
        service: 'evil$(reboot)',
        file_path: '/workspace/terraform/envs/local/evil$(reboot)/terragrunt.hcl',
        content_before: 'x',
        captured_at: '2026-01-01',
      },
    }));
    const result = await handleRollbackService('log-id', true);
    expect(result.isError).toBe(true);
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('正当なスナップショット → ロールバック実行', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({
      snapshot_before: {
        service: 'prometheus',
        file_path: '/workspace/terraform/envs/local/prometheus/terragrunt.hcl',
        content_before: 'inputs = {}',
        captured_at: '2026-01-01',
      },
    }));
    const result = await handleRollbackService('log-id', true);
    expect(result.isError).toBeUndefined();
    expect(vi.mocked(ssh.execSsh)).toHaveBeenCalledTimes(2);
  });
});

describe('apply_service: 承認ゲート', () => {
  it('承認ログが存在しない → エラー', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(null);
    const result = await handleApplyService('prometheus', 'fake-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('承認ログが見つかりません');
  });

  it('decision=rejected の承認ログ → エラー', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({ decision: 'rejected' }));
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('承認されていません');
  });

  it('別サービス向けの承認 → エラー（H-2: 流用防止）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({ service: 'grafana' }));
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('使えません');
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('service 未記録の旧形式ログ → エラー（H-2）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({ service: undefined }));
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBe(true);
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('適用済み（applied_at あり） → エラー（H-2: 再利用防止）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({ applied_at: '2026-07-01T00:00:00Z' }));
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('適用済み');
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('TTL 超過（decided_at が古い） → エラー（H-2: 期限）', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog({ decided_at: '2026-01-01T00:00:00Z' }));
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain('期限切れ');
    expect(vi.mocked(ssh.execSsh)).not.toHaveBeenCalled();
  });

  it('承認済み・一致・未使用・期限内 → apply 実行', async () => {
    vi.mocked(storage.getApprovalLog).mockResolvedValueOnce(freshLog());
    const result = await handleApplyService('prometheus', 'log-id');
    expect(result.isError).toBeUndefined();
    expect(vi.mocked(ssh.execSsh)).toHaveBeenCalledTimes(2); // snapshot cat + apply
    expect(vi.mocked(storage.saveApprovalLog)).toHaveBeenCalledOnce();
  });
});

describe('create_approval: ログ作成', () => {
  it('approved → service を記録し次のステップを案内', async () => {
    const result = await handleCreateApproval('prop-123', 'prometheus', 'approved', 'operator');
    expect(result.isError).toBeUndefined();
    expect(result.content[0].text).toContain('承認');
    expect(result.content[0].text).toContain('次のステップ');
    expect(vi.mocked(storage.saveApprovalLog)).toHaveBeenCalledOnce();
    const saved = vi.mocked(storage.saveApprovalLog).mock.calls[0][0];
    expect(saved.service).toBe('prometheus');
  });

  it('rejected → 次のステップ案内なし', async () => {
    const result = await handleCreateApproval('prop-456', 'prometheus', 'rejected');
    expect(result.content[0].text).not.toContain('次のステップ');
    expect(result.content[0].text).toContain('却下');
    expect(vi.mocked(storage.saveApprovalLog)).toHaveBeenCalledOnce();
  });

  it('許可リスト外の service → エラー・保存なし', async () => {
    const result = await handleCreateApproval('prop-789', '../evil', 'approved');
    expect(result.isError).toBe(true);
    expect(vi.mocked(storage.saveApprovalLog)).not.toHaveBeenCalled();
  });
});
