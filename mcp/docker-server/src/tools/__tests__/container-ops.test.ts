import { vi, describe, it, expect, beforeEach } from 'vitest';

// __tests__/ から見た正しい相対パス（../../ = src/ 直下）
vi.mock('../../docker-client.js', () => ({
  DockerClient: vi.fn(function() {
    return {
      findContainer: vi.fn().mockResolvedValue('monitoring-lab-prometheus'),
      getContainerStatus: vi.fn().mockResolvedValue('running'),
      restartContainer: vi.fn().mockResolvedValue(undefined),
      stopContainer: vi.fn().mockResolvedValue(undefined),
      startContainer: vi.fn().mockResolvedValue(undefined),
      getLogs: vi.fn().mockResolvedValue('2026-01-01 INFO server started\n2026-01-01 INFO ready'),
      listContainers: vi.fn().mockResolvedValue([]),
      getStats: vi.fn().mockResolvedValue([]),
    };
  }),
}));

import { handleRestartContainer } from '../restart-container.js';
import { handleStopContainer } from '../stop-container.js';
import { handleStartContainer } from '../start-container.js';
import { handleGetLogs } from '../get-logs.js';

beforeEach(() => vi.clearAllMocks());

describe('dry-run: confirmed=false は実行しない', () => {
  it('restart → dry_run フラグが返る', async () => {
    const result = await handleRestartContainer('prometheus', false);
    expect(result.isError).toBeUndefined();
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.dry_run).toBe(true);
    expect(parsed.action).toBe('restart');
    expect(parsed.container_name).toBe('monitoring-lab-prometheus');
  });

  it('stop → dry_run フラグが返る', async () => {
    const result = await handleStopContainer('prometheus', false);
    expect(result.isError).toBeUndefined();
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.dry_run).toBe(true);
    expect(parsed.action).toBe('stop');
  });

  it('start → dry_run フラグが返る', async () => {
    const result = await handleStartContainer('prometheus', false);
    expect(result.isError).toBeUndefined();
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed.dry_run).toBe(true);
    expect(parsed.action).toBe('start');
  });
});

describe('getLogs: ログ取得', () => {
  it('ログ内容が返る', async () => {
    const result = await handleGetLogs('prometheus', 50);
    expect(result.isError).toBeUndefined();
    expect(result.content[0].text).toContain('INFO');
  });

  it('lines デフォルト値100で動作する', async () => {
    const result = await handleGetLogs('prometheus');
    expect(result.content[0].text).toBeTruthy();
  });
});
