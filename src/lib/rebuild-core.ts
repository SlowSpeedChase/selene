import type Database from 'better-sqlite3';
import { join } from 'path';
type DB = InstanceType<typeof Database>;

/** The derived/disposable tables in selene.db's `main` schema — what a rebuild
 *  truncates and re-derives from facts.db. This is an explicit ALLOWLIST, not
 *  "every table in main", because selene.db also holds NON-derived state that
 *  MUST survive a wipe:
 *    - `_selene_metadata`        the env-identity marker db.ts reads on every
 *                                dev/test connection (db.ts:44-61). Truncating it
 *                                crashes re-derivation; PROD has no guard, so the
 *                                same wipe would silently corrupt the DB's identity.
 *    - `device_tokens`           live push registrations (not derivable from facts).
 *    - `raw_notes_legacy_backup` the one-time Ph1 migration safety-net.
 *    - chat / thread tables      archived (2026-03-21), preserved by omission.
 *  An allowlist fails SAFE: a table added to `main` later is preserved (at worst a
 *  stale/incomplete rebuild) rather than silently destroyed. */
export const DERIVED_TABLES = [
  'processed_notes',
  'processed_notes_apple',
  'note_embeddings',
  'note_chunks',
  'note_state',
  'note_associations',
  'note_relationships',
  'detected_patterns',
  'sentiment_history',
  'topic_clusters',
  'topic_note_links',
] as const;

/** The DERIVED_TABLES that actually EXIST in this db's `main` schema. Restricting to
 *  present tables keeps wipe()/restoreFromBackup() from erroring on a derived table a
 *  never-fully-derived DB hasn't created yet (e.g. topic_clusters before the first
 *  synthesize). An unqualified `sqlite_master` reads `main` only, so attached
 *  `facts.*` tables are never returned. */
export function listDerivedTables(db: DB): string[] {
  const present = new Set(
    (db.prepare(
      `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`
    ).all() as Array<{ name: string }>).map((r) => r.name)
  );
  return DERIVED_TABLES.filter((t) => present.has(t));
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

/** Snapshot selene.db's MAIN schema to a standalone file via `VACUUM INTO`.
 *  WAL-safe and concurrency-safe: it runs through a connection (so the webhook
 *  server's live handle keeps a consistent view) and never swaps a file. VACUUM
 *  targets only the `main` schema, so the ATTACHed `facts` (captured_notes /
 *  review_state) is NOT copied into the backup — the backup is disposable-only.
 *  Replaces a raw copyFileSync, which would miss uncheckpointed WAL pages. */
export function vacuumBackup(db: DB, dest: string): void {
  db.prepare('VACUUM INTO ?').run(dest);
}

/** Roll the derived (main-schema) tables back to a vacuumBackup, IN PLACE, by
 *  ATTACHing the backup and copying rows table-by-table inside one FK-off
 *  transaction. Crucially this NEVER overwrites the selene.db file, so a
 *  concurrent connection (the webhook server, which stays up during a prod
 *  rebuild) is never corrupted by a file swapped out from under it.
 *
 *  Column drift: rederive can lazily ADD COLUMNs (e.g. processed_notes.essence)
 *  after the backup was taken, so the live table may be a superset of the backup's
 *  columns. We build the insert column list from the BACKUP's PRAGMA table_info,
 *  so live-only columns simply default to NULL. A live table absent from the
 *  backup (created by rederive post-backup) is emptied — PRE never had it. Never
 *  touches the attached `facts` schema. */
export function restoreFromBackup(db: DB, backupFile: string): void {
  const tables = listDerivedTables(db);
  const prevFk = db.pragma('foreign_keys', { simple: true });
  db.pragma('foreign_keys = OFF');
  try {
    db.prepare('ATTACH ? AS bak').run(backupFile);
    try {
      const tx = db.transaction(() => {
        for (const name of tables) {
          const cols = (db.prepare(`PRAGMA bak.table_info("${name}")`).all() as Array<{ name: string }>)
            .map((c) => c.name);
          db.exec(`DELETE FROM main."${name}"`);
          if (cols.length === 0) continue; // table absent in backup (PRE lacked it) → leave empty
          const colList = cols.map((c) => `"${c}"`).join(', ');
          db.exec(`INSERT INTO main."${name}" (${colList}) SELECT ${colList} FROM bak."${name}"`);
        }
      });
      tx();
    } finally {
      db.prepare('DETACH bak').run();
    }
  } finally {
    db.pragma(`foreign_keys = ${prevFk ? 'ON' : 'OFF'}`);
  }
}
