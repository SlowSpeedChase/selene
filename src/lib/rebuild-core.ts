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

const count = (db: DB, sql: string): number =>
  (db.prepare(sql).get() as { n: number }).n;

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
  return {
    coverageMin: env.COVERAGE_MIN ? Number(env.COVERAGE_MIN) : 0.95,
    driftTolerance: env.DRIFT_TOLERANCE ? Number(env.DRIFT_TOLERANCE) : 0.20,
  };
}

export function backupPath(dir: string, stamp: string): string {
  return join(dir, `pre-rebuild-${stamp}.db`);
}

/** Empty every main-schema (selene.db) table in one transaction. FK enforcement is
 *  toggled off for the truncation, restored after. Never touches the attached `facts`
 *  schema (captured_notes / review_state). */
export function wipe(db: DB): void {
  const tables = listDerivedTables(db);
  db.pragma('foreign_keys = OFF');
  const tx = db.transaction(() => {
    for (const name of tables) db.exec(`DELETE FROM "${name}"`);
  });
  tx();
  db.pragma('foreign_keys = ON');
}
