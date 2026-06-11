// scripts/backfill-connections.ts
// One-shot: populate note_connections over the EXISTING corpus, using cosine similarity.
//
// Why: connection detection in process-llm only fires for NEW notes (and only against
// notes >7 days old), so the pre-existing corpus has no edges. This backfill computes
// all-pairs cosine similarity over stored embeddings and writes every pair >= threshold.
// Idempotent (writeConnection uses INSERT OR IGNORE on a UNIQUE(source,target) constraint).
//
// Content-free: prints only counts, never note text — safe for an operator to run on prod.
// Run (dev/copy):  SELENE_ENV=development npx ts-node scripts/backfill-connections.ts
//   --dry-run        compute + report, write nothing
//   --threshold=0.7  override the cosine-similarity floor (default 0.75)
import type { Database as DatabaseType } from 'better-sqlite3';
import { db, createWorkflowLogger } from '../src/lib';
import { initSynthesisSchema, writeConnection } from '../src/lib/synthesis-db';
import { computeConnections, EmbeddedNote } from '../src/lib/vector-similarity';

const log = createWorkflowLogger('backfill-connections');

export const DEFAULT_CONNECTION_THRESHOLD = 0.75;

export interface BackfillConnectionsResult {
  notesScanned: number;
  candidates: number;
  written: number;
}

export function backfillConnections(
  conn: DatabaseType = db,
  opts: { threshold?: number; dryRun?: boolean } = {}
): BackfillConnectionsResult {
  const threshold = opts.threshold ?? DEFAULT_CONNECTION_THRESHOLD;
  initSynthesisSchema(conn); // ensure note_connections exists

  const rows = conn
    .prepare(
      `SELECT e.raw_note_id AS id, e.embedding AS embedding, r.created_at AS createdAt
       FROM note_embeddings e
       JOIN raw_notes r ON r.id = e.raw_note_id`
    )
    .all() as Array<{ id: number; embedding: string; createdAt: string }>;

  const notes: EmbeddedNote[] = rows.map(r => ({
    id: r.id,
    vector: JSON.parse(r.embedding) as number[],
    createdAt: r.createdAt,
  }));

  const candidates = computeConnections(notes, threshold);

  const countRow = () =>
    (conn.prepare('SELECT COUNT(*) AS c FROM note_connections').get() as { c: number }).c;
  const before = countRow();

  if (!opts.dryRun) {
    for (const c of candidates) writeConnection(conn, c.sourceId, c.targetId, c.similarity);
  }

  const written = opts.dryRun ? 0 : countRow() - before;
  return { notesScanned: notes.length, candidates: candidates.length, written };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const thresholdArg = args.find(a => a.startsWith('--threshold='));
  const threshold = thresholdArg ? Number(thresholdArg.split('=')[1]) : DEFAULT_CONNECTION_THRESHOLD;

  try {
    const res = backfillConnections(db, { threshold, dryRun });
    log.info({ ...res, threshold, dryRun }, 'backfill-connections complete');
    console.log('backfill-connections:', { ...res, threshold, dryRun });
    process.exit(0);
  } catch (err) {
    console.error('backfill-connections failed:', err);
    process.exit(1);
  }
}
