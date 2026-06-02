import type Database from 'better-sqlite3';
import { join } from 'path';
type DB = InstanceType<typeof Database>;

/** Tables in the `main` schema (selene.db) only — NOT the attached `facts` schema,
 *  NOT views (raw_notes), NOT sqlite internal tables. These are what wipe() truncates.
 *  An unqualified `sqlite_master` reads the `main` schema only, so attached
 *  `facts.*` tables are never returned here. */
export function listDerivedTables(db: DB): string[] {
  return (db.prepare(
    `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`
  ).all() as Array<{ name: string }>).map((r) => r.name);
}

export interface Snapshot {
  captured: number; processed: number; essences: number; embeddings: number;
  clusters: number; clusterLinks: number; exported: number;
}

// Absent derived table/column = 0 (the "pending = derivation-absence" model): a
// never-derived DB may lack processed_notes.essence (added lazily by
// distill-essences) or whole derived tables (note_embeddings, topic_clusters).
// We can't probe sqlite_master for existence — raw_notes is a per-connection TEMP
// view, so it would read as "absent" — hence the try/catch on the specific error.
// The rethrow keeps genuine typos/bugs from being masked; the full-schema snapshot
// test guards exact counts.
const count = (db: DB, sql: string): number => {
  try {
    return (db.prepare(sql).get() as { n: number }).n;
  } catch (err) {
    if (err instanceof Error && /no such (column|table)/i.test(err.message)) return 0;
    throw err;
  }
};

/** Read derived counts from selene.db (facts via the raw_notes view). Content-free. */
export function snapshot(db: DB): Snapshot {
  return {
    captured: count(db, `SELECT COUNT(*) n FROM raw_notes`),
    processed: count(db, `SELECT COUNT(*) n FROM processed_notes`),
    essences: count(db, `SELECT COUNT(*) n FROM processed_notes WHERE essence IS NOT NULL`),
    embeddings: count(db, `SELECT COUNT(*) n FROM note_embeddings`),
    clusters: count(db, `SELECT COUNT(*) n FROM topic_clusters`),
    clusterLinks: count(db, `SELECT COUNT(*) n FROM topic_note_links`),
    exported: count(db, `SELECT COUNT(*) n FROM raw_notes WHERE exported_to_obsidian = 1`),
  };
}

/** Outstanding re-derivation work: pending notes awaiting LLM extraction + processed
 *  rows still missing an essence. The drain loop in rebuild.ts gates on this combined
 *  total (mirrors dev-process-batch.sh draining both stages to zero). Routed through
 *  the SAME absent-tolerant `count()` as snapshot(): on a never-distilled DB the
 *  essence column does not exist yet (distill-essences adds it lazily), so a raw read
 *  would throw "no such column: essence" at the top of the loop — which main()'s catch
 *  would mistake for a mid-rebuild crash and roll back. Treating the absent column as
 *  0 is safe in the wipe-then-rederive flow: processed_notes is empty post-wipe, so the
 *  pending raw_notes count drives the loop and distill-essences creates the column on
 *  the first pass. */
export function pendingCount(db: DB): number {
  return (
    count(db, `SELECT COUNT(*) n FROM raw_notes WHERE status='pending'`) +
    count(db, `SELECT COUNT(*) n FROM processed_notes WHERE essence IS NULL`)
  );
}

export type DrainOutcome = 'continue' | 'drained' | 'stalled' | 'capped';

/** Pure decision for the re-derivation drain loop, called once per pass with the
 *  work remaining AFTER that pass, the count BEFORE it (previous), the iteration
 *  index, and the ceiling. Extracted from the loop so the termination logic is
 *  unit-testable in isolation.
 *    - drained: nothing left (remaining === 0) — the clean finish; takes precedence
 *      over the cap so a final-pass completion isn't misreported as truncation.
 *    - capped:  hit the iteration ceiling with work still outstanding (defensive
 *      backstop against an unforeseen non-converging case).
 *    - stalled: a pass made no progress (remaining === previous) but work remains —
 *      a permanently-stuck note; stop and let the coverage gate judge the shortfall.
 *    - continue: still making progress.
 *  Pass previous = Infinity (or any value > remaining) on the first pass so it can
 *  never false-read as stalled. */
export function drainDecision(
  remaining: number, previous: number, iteration: number, cap: number,
): DrainOutcome {
  if (remaining === 0) return 'drained';
  if (iteration >= cap) return 'capped';
  if (remaining === previous) return 'stalled';
  return 'continue';
}

export interface Thresholds { coverageMin: number; driftTolerance: number; }
export interface Verdict { pass: boolean; coverage: number; reasons: string[]; }

const DRIFT_METRICS: Array<keyof Snapshot> = [
  'processed', 'essences', 'embeddings', 'clusters', 'clusterLinks', 'exported',
];

export function verdict(pre: Snapshot, post: Snapshot, t: Thresholds): Verdict {
  const reasons: string[] = [];
  const coverage = post.captured === 0 ? 1 : post.processed / post.captured;
  if (coverage < t.coverageMin) {
    reasons.push(`coverage ${(coverage * 100).toFixed(1)}% < floor ${(t.coverageMin * 100).toFixed(0)}%`);
  }
  for (const m of DRIFT_METRICS) {
    if (pre[m] === 0) continue;
    const drift = (post[m] - pre[m]) / pre[m];
    if (drift < -t.driftTolerance) {
      reasons.push(`${m} drift ${(drift * 100).toFixed(1)}% < -${(t.driftTolerance * 100).toFixed(0)}%`);
    }
  }
  return { pass: reasons.length === 0, coverage, reasons };
}

/** Thresholds from env, with the agreed defaults. */
export function thresholdsFromEnv(env: NodeJS.ProcessEnv = process.env): Thresholds {
  const num = (v: string | undefined, d: number): number => {
    const n = Number(v);
    return v !== undefined && v !== '' && Number.isFinite(n) ? n : d;
  };
  return {
    coverageMin: num(env.COVERAGE_MIN, 0.95),
    driftTolerance: num(env.DRIFT_TOLERANCE, 0.20),
  };
}

export function backupPath(dir: string, stamp: string): string {
  return join(dir, `pre-rebuild-${stamp}.db`);
}

/** Empty every main-schema (selene.db) table in one transaction. FK enforcement is
 *  toggled off for the truncation, then restored to the caller's PRIOR state.
 *  Never touches the attached `facts` schema (captured_notes / review_state).
 *
 *  Note: the foreign_keys pragma is toggled OUTSIDE the transaction deliberately —
 *  toggling foreign_keys mid-transaction is a no-op in better-sqlite3, so this
 *  ordering is required for the OFF to actually take effect. */
export function wipe(db: DB): void {
  const tables = listDerivedTables(db);
  const prevFk = db.pragma('foreign_keys', { simple: true });
  db.pragma('foreign_keys = OFF');
  try {
    const tx = db.transaction(() => {
      for (const name of tables) db.exec(`DELETE FROM "${name}"`);
    });
    tx();
  } finally {
    db.pragma(`foreign_keys = ${prevFk ? 'ON' : 'OFF'}`);
  }
}
