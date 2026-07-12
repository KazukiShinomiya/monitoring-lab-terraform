import { readFile, writeFile, mkdir } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';
import type { ApprovalLog, EffectReport } from './types.js';

const DATA_DIR = process.env.MCP_DATA_DIR ?? join(process.cwd(), '.mcp-data');
const APPROVALS_DIR = join(DATA_DIR, 'approvals');
const REPORTS_DIR = join(DATA_DIR, 'reports');

// ID は create_approval が randomUUID() で発行する。外部入力の ID をファイルパスへ
// 直結するため、UUID 形式以外は拒否する（2026-06 監査 M-1: パストラバーサル防止）
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function assertValidId(id: string): void {
  if (!UUID_PATTERN.test(id)) {
    throw new Error(`INVALID_ID: ID は UUID 形式である必要があります: ${id.slice(0, 64)}`);
  }
}

async function ensureDirs(): Promise<void> {
  await mkdir(APPROVALS_DIR, { recursive: true });
  await mkdir(REPORTS_DIR, { recursive: true });
}

export async function saveApprovalLog(log: ApprovalLog): Promise<void> {
  await ensureDirs();
  const file = join(APPROVALS_DIR, `${log.id}.json`);
  await writeFile(file, JSON.stringify(log, null, 2), 'utf-8');
}

export async function getApprovalLog(id: string): Promise<ApprovalLog | null> {
  assertValidId(id);
  const file = join(APPROVALS_DIR, `${id}.json`);
  if (!existsSync(file)) return null;
  const raw = await readFile(file, 'utf-8');
  return JSON.parse(raw) as ApprovalLog;
}

export async function saveEffectReport(report: EffectReport): Promise<void> {
  await ensureDirs();
  const file = join(REPORTS_DIR, `${report.id}.json`);
  await writeFile(file, JSON.stringify(report, null, 2), 'utf-8');
}
