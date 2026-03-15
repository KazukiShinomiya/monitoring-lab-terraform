import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleListSilences } from '../list-silences.js';
import { handleDeleteSilence } from '../delete-silence.js';

vi.mock('../../alertmanager-client.js', () => ({
  alertmanagerClient: {
    getSilences: vi.fn(),
    getSilence: vi.fn(),
    deleteSilence: vi.fn(),
  },
}));

import { alertmanagerClient } from '../../alertmanager-client.js';

const mockActiveSilence = {
  id: 'silence-uuid-001',
  matchers: [{ name: 'alertname', value: 'TestAlert', isRegex: false, isEqual: true }],
  startsAt: '2026-01-01T00:00:00.000Z',
  endsAt: '2026-01-01T02:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
  createdBy: 'claude-code',
  comment: 'test silence',
  status: { state: 'active' as const },
};

describe('handleListSilences', () => {
  beforeEach(() => vi.clearAllMocks());

  it('アクティブなサイレンスを一覧表示する', async () => {
    vi.mocked(alertmanagerClient.getSilences).mockResolvedValue([mockActiveSilence]);
    const result = await handleListSilences();
    expect(result.content[0].text).toContain('silence-uuid-001');
    expect(result.content[0].text).toContain('TestAlert');
  });

  it('有効なサイレンスがない場合は空メッセージを返す', async () => {
    vi.mocked(alertmanagerClient.getSilences).mockResolvedValue([
      { ...mockActiveSilence, status: { state: 'expired' as const } },
    ]);
    const result = await handleListSilences();
    expect(result.content[0].text).toContain('有効なサイレンスはありません');
  });

  it('接続エラー時はエラーメッセージを返す', async () => {
    vi.mocked(alertmanagerClient.getSilences).mockRejectedValue(new Error('connection refused'));
    const result = await handleListSilences();
    expect(result.content[0].text).toContain('❌');
  });
});

describe('handleDeleteSilence', () => {
  beforeEach(() => vi.clearAllMocks());

  it('confirmed=false のときドライランメッセージを返す', async () => {
    vi.mocked(alertmanagerClient.getSilence).mockResolvedValue(mockActiveSilence);
    const result = await handleDeleteSilence('silence-uuid-001', false);
    expect(result.content[0].text).toContain('ドライラン');
    expect(alertmanagerClient.deleteSilence).not.toHaveBeenCalled();
  });

  it('confirmed=true のときサイレンスを削除する', async () => {
    vi.mocked(alertmanagerClient.getSilence).mockResolvedValue(mockActiveSilence);
    vi.mocked(alertmanagerClient.deleteSilence).mockResolvedValue(undefined);
    const result = await handleDeleteSilence('silence-uuid-001', true);
    expect(result.content[0].text).toContain('✅');
    expect(alertmanagerClient.deleteSilence).toHaveBeenCalledWith('silence-uuid-001');
  });

  it('存在しないサイレンスIDはエラーメッセージを返す', async () => {
    vi.mocked(alertmanagerClient.getSilence).mockRejectedValue(
      new Error('SILENCE_NOT_FOUND:nonexistent-id'),
    );
    const result = await handleDeleteSilence('nonexistent-id', false);
    expect(result.content[0].text).toContain('見つかりません');
  });
});
