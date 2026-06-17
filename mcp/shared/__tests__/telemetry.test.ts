import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  initTelemetry,
  instrumentTool,
  shutdownTelemetry,
  __resetForTest,
} from '../telemetry.js';

describe('instrumentTool', () => {
  beforeEach(() => {
    __resetForTest();
    delete process.env.MCP_TELEMETRY_DISABLED;
  });

  afterEach(async () => {
    await shutdownTelemetry(100);
    __resetForTest();
  });

  it('成功時はハンドラの戻り値を透過する', async () => {
    initTelemetry('test');
    const wrapped = instrumentTool('echo', async (x: number) => x * 2);
    await expect(wrapped(21)).resolves.toBe(42);
  });

  it('throw した例外を再 throw する（透過）', async () => {
    initTelemetry('test');
    const boom = new Error('boom');
    const wrapped = instrumentTool('fail', async () => {
      throw boom;
    });
    await expect(wrapped()).rejects.toBe(boom);
  });

  it('同期ハンドラもラップできる', async () => {
    initTelemetry('test');
    const wrapped = instrumentTool('sync', (a: number, b: number) => a + b);
    await expect(wrapped(2, 3)).resolves.toBe(5);
  });
});

describe('MCP_TELEMETRY_DISABLED', () => {
  beforeEach(() => __resetForTest());
  afterEach(() => {
    delete process.env.MCP_TELEMETRY_DISABLED;
    __resetForTest();
  });

  it('=1 のとき計測は素通しし、ハンドラは正常動作する', async () => {
    process.env.MCP_TELEMETRY_DISABLED = '1';
    initTelemetry('test');
    const wrapped = instrumentTool('echo', async (x: string) => `hi ${x}`);
    await expect(wrapped('jint')).resolves.toBe('hi jint');
    // 無効時の shutdown も即 resolve する
    await expect(shutdownTelemetry(50)).resolves.toBeUndefined();
  });
});

describe('shutdownTelemetry', () => {
  beforeEach(() => {
    __resetForTest();
    delete process.env.MCP_TELEMETRY_DISABLED;
  });
  afterEach(() => __resetForTest());

  it('収集先が到達不能でも timeout 内に resolve する', async () => {
    // 到達不能なエンドポイントを指定
    process.env.OTEL_EXPORTER_OTLP_ENDPOINT = 'http://192.0.2.1:4317'; // TEST-NET-1
    initTelemetry('test');
    instrumentTool('x', async () => 1)();
    const start = Date.now();
    await shutdownTelemetry(300);
    expect(Date.now() - start).toBeLessThan(2000);
    delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  });

  it('二重呼び出ししても安全（冪等）', async () => {
    initTelemetry('test');
    await shutdownTelemetry(100);
    await expect(shutdownTelemetry(100)).resolves.toBeUndefined();
  });
});

describe('best-effort（計測がツールを阻害しない）', () => {
  beforeEach(() => {
    __resetForTest();
    delete process.env.MCP_TELEMETRY_DISABLED;
  });
  afterEach(async () => {
    await shutdownTelemetry(100);
    __resetForTest();
  });

  it('未初期化でも instrumentTool は機能する（素通し）', async () => {
    // initTelemetry を呼ばない
    const wrapped = instrumentTool('echo', async (x: number) => x + 1);
    await expect(wrapped(9)).resolves.toBe(10);
  });
});
