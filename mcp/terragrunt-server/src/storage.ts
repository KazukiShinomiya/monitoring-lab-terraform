import { readFile, writeFile, mkdir } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';
import type { ApprovalLog, EffectReport } from './types.js';

const DATA_DIR = process.env.MCP_DATA_DIR ?? join(process.cwd(), '.mcp-data');
const APPROVALS_DIR = join(DATA_DIR, 'approvals');
const REPORTS_DIR = join(DATA_DIR, 'reports');

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
