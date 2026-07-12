import { readFile, writeFile, mkdir } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';
import type { Proposal, ProposalIndex, ProposalIndexItem } from './types.js';

const DATA_DIR = process.env.MCP_DATA_DIR ?? join(process.cwd(), '.mcp-data');
const PROPOSALS_DIR = join(DATA_DIR, 'proposals');
const INDEX_FILE = join(PROPOSALS_DIR, 'index.json');

// ID は generate_proposal が randomUUID() で発行する。外部入力の ID をファイルパスへ
// 直結するため、UUID 形式以外は拒否する（2026-06 監査 M-1: パストラバーサル防止）
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function assertValidId(id: string): void {
  if (!UUID_PATTERN.test(id)) {
    throw new Error(`INVALID_ID: ID は UUID 形式である必要があります: ${id.slice(0, 64)}`);
  }
}

async function ensureDir(): Promise<void> {
  await mkdir(PROPOSALS_DIR, { recursive: true });
}

async function readIndex(): Promise<ProposalIndex> {
  if (!existsSync(INDEX_FILE)) {
    return { last_updated: new Date().toISOString(), total: 0, items: [] };
  }
  const raw = await readFile(INDEX_FILE, 'utf-8');
  return JSON.parse(raw) as ProposalIndex;
}

async function writeIndex(index: ProposalIndex): Promise<void> {
  index.last_updated = new Date().toISOString();
  await writeFile(INDEX_FILE, JSON.stringify(index, null, 2), 'utf-8');
}

export async function saveProposal(proposal: Proposal): Promise<void> {
  await ensureDir();
  const file = join(PROPOSALS_DIR, `${proposal.id}.json`);
  await writeFile(file, JSON.stringify(proposal, null, 2), 'utf-8');
  const index = await readIndex();
  const item: ProposalIndexItem = {
    id: proposal.id,
    urgency: proposal.urgency,
    target: proposal.target,
    status: proposal.status,
    created_at: proposal.created_at,
    content_preview: proposal.content.slice(0, 100),
  };
  index.items = index.items.filter(i => i.id !== proposal.id);
  index.items.push(item);
  index.total = index.items.length;
  await writeIndex(index);
}

export async function getProposal(id: string): Promise<Proposal | null> {
  assertValidId(id);
  const file = join(PROPOSALS_DIR, `${id}.json`);
  if (!existsSync(file)) return null;
  const raw = await readFile(file, 'utf-8');
  return JSON.parse(raw) as Proposal;
}

export async function updateProposalStatus(id: string, status: Proposal['status']): Promise<void> {
  const proposal = await getProposal(id);
  if (!proposal) throw new Error(`Proposal not found: ${id}`);
  proposal.status = status;
  await saveProposal(proposal);
}

export async function listProposals(): Promise<ProposalIndex> {
  await ensureDir();
  return readIndex();
}
