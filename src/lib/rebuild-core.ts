import type Database from 'better-sqlite3';
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
