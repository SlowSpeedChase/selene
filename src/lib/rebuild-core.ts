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
