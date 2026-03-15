import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleSilenceAlert } from '../silence-alert.js';

vi.mock('../../alertmanager-client.js', () => ({
  alertmanagerClient: {
    createSilence: vi.fn(),
  },
}));

import { alertmanagerClient } from '../../alertmanager-client.js';

describe('handleSilenceAlert', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('confirmed=false のときドライランメッセージを返す', async () => {
    const result = await handleSilenceAlert('TestAlert', 2, [], 'test comment', false);
    expect(result.content[0].text).toContain('ドライラン');
    expect(result.content[0].text).toContain('TestAlert');
    expect(alertmanagerClient.createSilence).not.toHaveBeenCalled();
  });

  it('confirmed=true のときサイレンスを作成する', async () => {
    vi.mocked(alertmanagerClient.createSilence).mockResolvedValue({ silenceID: 'abc-123' });
    const result = await handleSilenceAlert('TestAlert', 2, [], 'test comment', true);
    expect(result.content[0].text).toContain('✅');
    expect(result.content[0].text).toContain('abc-123');
    expect(alertmanagerClient.createSilence).toHaveBeenCalledOnce();
  });

  it('追加マッチャーが正しく含まれる', async () => {
    const result = await handleSilenceAlert(
      'TestAlert',
      2,
      [{ name: 'severity', value: 'warning' }],
      'test',
      false,
    );
    expect(result.content[0].text).toContain('severity="warning"');
  });

  it('createSilence失敗時はエラーメッセージを返す', async () => {
    vi.mocked(alertmanagerClient.createSilence).mockRejectedValue(new Error('connection refused'));
    const result = await handleSilenceAlert('TestAlert', 2, [], 'test', true);
    expect(result.content[0].text).toContain('❌');
    expect(result.content[0].text).toContain('connection refused');
  });
});
