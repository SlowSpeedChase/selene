import Database from 'better-sqlite3';
import { mkdtempSync, rmSync, existsSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import {
  listDerivedTables, snapshot, backupPath, wipe, pendingCount,
  vacuumBackup, restoreFromBackup,
} from './rebuild-core';
type DB = InstanceType<typeof Database>;

it('lists only main-schema user tables, excluding sqlite_* and views', () => {
  const db: DB = new Database(':memory:');
  // AUTOINCREMENT forces SQLite to create the internal sqlite_sequence table,
  // which must be excluded by the NOT LIKE 'sqlite_%' clause.
  db.exec(`
    CREATE TABLE processed_notes (id INTEGER PRIMARY KEY AUTOINCREMENT);
    CREATE TABLE note_embeddings (raw_note_id INTEGER);
    CREATE VIEW v AS SELECT 1;
  `);
  const tables = listDerivedTables(db);
  expect(tables.sort()).toEqual(['note_embeddings', 'processed_notes']);
  expect(tables).not.toContain('sqlite_sequence');
});

it('counts captured + each derived metric', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes_t (id INTEGER PRIMARY KEY, exported INTEGER);
    CREATE VIEW raw_notes AS SELECT id, exported AS exported_to_obsidian FROM raw_notes_t;
    CREATE TABLE processed_notes (raw_note_id INTEGER, essence TEXT);
    CREATE TABLE note_embeddings (raw_note_id INTEGER);
    CREATE TABLE topic_clusters (id TEXT PRIMARY KEY);
    CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER);
  `);
  // 3 captured, but only 2 exported — a mixed flag so a dropped WHERE clause is caught.
  db.exec(`INSERT INTO raw_notes_t VALUES (1,1),(2,1),(3,0)`);
  db.exec(`INSERT INTO processed_notes VALUES (1,'e'),(2,NULL)`);
  db.exec(`INSERT INTO note_embeddings VALUES (1)`);
  db.exec(`INSERT INTO topic_clusters VALUES ('c1')`);
  db.exec(`INSERT INTO topic_note_links VALUES ('c1',1)`);
  const snap = snapshot(db);
  expect(snap).toEqual({
    captured: 3, processed: 2, essences: 1, embeddings: 1,
    clusters: 1, clusterLinks: 1, exported: 2,
  });
  // The WHERE exported_to_obsidian = 1 clause is load-bearing: not every row is exported.
  expect(snap.exported).toBeLessThan(snap.captured);
});

it('snapshot tolerates a never-derived schema (missing essence column / derived tables = 0)', () => {
  // A PRE-snapshot of a DB that has never been through the pipeline: processed_notes
  // exists but has NO essence column (distill-essences.ensureEssenceColumns adds it
  // lazily), and the embeddings/clusters tables are entirely absent. The raw_notes
  // view is present (it's a per-connection temp view, not a derived table).
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes_t (id INTEGER PRIMARY KEY);
    CREATE VIEW raw_notes AS SELECT id, 0 AS exported_to_obsidian FROM raw_notes_t;
    CREATE TABLE processed_notes (raw_note_id INTEGER);  -- NOTE: no essence column, no other derived tables
  `);
  db.exec(`INSERT INTO raw_notes_t VALUES (1),(2)`);
  db.exec(`INSERT INTO processed_notes VALUES (1),(2)`);
  expect(snapshot(db)).toEqual({
    captured: 2, processed: 2, essences: 0, embeddings: 0,
    clusters: 0, clusterLinks: 0, exported: 0,
  });
});

it('pendingCount sums pending notes + processed rows missing an essence', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes_t (id INTEGER PRIMARY KEY, status TEXT);
    CREATE VIEW raw_notes AS SELECT id, status FROM raw_notes_t;
    CREATE TABLE processed_notes (raw_note_id INTEGER, essence TEXT);
  `);
  db.exec(`INSERT INTO raw_notes_t VALUES (1,'pending'),(2,'pending'),(3,'processed')`);
  db.exec(`INSERT INTO processed_notes VALUES (3,NULL)`);
  // 2 pending notes + 1 processed row still missing an essence = 3 outstanding.
  expect(pendingCount(db)).toBe(3);
});

it('pendingCount tolerates a never-distilled schema (missing essence column = no outstanding distill work)', () => {
  // The bug this guards: on a never-distilled DB the essence column does not yet
  // exist (distill-essences adds it lazily). A raw .get() throws "no such column:
  // essence" at the top of the drain loop, which main()'s catch mistakes for a
  // mid-rebuild crash and triggers a spurious rollback. pendingCount must instead
  // treat the absent column as 0 (the pending raw_notes count drives the loop).
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes_t (id INTEGER PRIMARY KEY, status TEXT);
    CREATE VIEW raw_notes AS SELECT id, status FROM raw_notes_t;
    CREATE TABLE processed_notes (raw_note_id INTEGER);  -- NOTE: no essence column yet
  `);
  db.exec(`INSERT INTO raw_notes_t VALUES (1,'pending'),(2,'processed')`);
  db.exec(`INSERT INTO processed_notes VALUES (2)`);
  // 1 pending + 0 (essence column absent => 0 outstanding distill work), and no throw.
  expect(pendingCount(db)).toBe(1);
});

it('backupPath names a timestamped file under the backup dir', () => {
  expect(backupPath('/b', '20260601-120000')).toBe('/b/pre-rebuild-20260601-120000.db');
});

describe('vacuumBackup + restoreFromBackup (WAL-safe, no file swap)', () => {
  // These need real files on disk: VACUUM INTO writes a file, and restore ATTACHes
  // one. We build a WAL DB with an ATTACHed facts schema + derived tables, exactly
  // like a live selene.db, so the tests prove the precious facts are never copied
  // into the backup and never touched by the restore.
  let dir: string;
  const open = (): { db: DB; mainPath: string; factsPath: string } => {
    const mainPath = join(dir, 'selene.db');
    const factsPath = join(dir, 'facts.db');
    const db: DB = new Database(mainPath);
    db.pragma('journal_mode = WAL');
    db.prepare('ATTACH ? AS facts').run(factsPath);
    db.exec(`
      CREATE TABLE facts.captured_notes (id INTEGER PRIMARY KEY);
      INSERT INTO facts.captured_notes VALUES (1),(2),(3);
      CREATE TEMP VIEW raw_notes AS SELECT id, 'pending' AS status FROM facts.captured_notes;
      CREATE TABLE processed_notes (raw_note_id INTEGER, essence TEXT);
      INSERT INTO processed_notes VALUES (1,'a'),(2,'b');
      CREATE TABLE note_embeddings (raw_note_id INTEGER);
      INSERT INTO note_embeddings VALUES (1);
    `);
    return { db, mainPath, factsPath };
  };

  beforeEach(() => { dir = mkdtempSync(join(tmpdir(), 'rebuild-core-')); });
  afterEach(() => { rmSync(dir, { recursive: true, force: true }); });

  it('vacuumBackup writes a standalone copy of the main schema, excluding attached facts', () => {
    const { db } = open();
    const dest = join(dir, 'backup.db');
    vacuumBackup(db, dest);
    db.close();
    expect(existsSync(dest)).toBe(true);
    const bak: DB = new Database(dest, { readonly: true });
    const tables = listDerivedTables(bak).sort();
    expect(tables).toEqual(['note_embeddings', 'processed_notes']); // facts.captured_notes NOT copied
    expect((bak.prepare('SELECT COUNT(*) n FROM processed_notes').get() as { n: number }).n).toBe(2);
    bak.close();
  });

  it('restoreFromBackup rolls derived tables back via attach+row-copy, leaving facts untouched', () => {
    const { db } = open();
    const dest = join(dir, 'backup.db');
    vacuumBackup(db, dest);
    // Simulate a rebuild that lazily added a column (drift) then wiped everything.
    db.exec(`ALTER TABLE note_embeddings ADD COLUMN model TEXT`);
    db.exec(`DELETE FROM processed_notes; DELETE FROM note_embeddings;`);
    expect((db.prepare('SELECT COUNT(*) n FROM processed_notes').get() as { n: number }).n).toBe(0);

    restoreFromBackup(db, dest);

    expect((db.prepare('SELECT COUNT(*) n FROM processed_notes').get() as { n: number }).n).toBe(2);
    expect((db.prepare('SELECT COUNT(*) n FROM note_embeddings').get() as { n: number }).n).toBe(1);
    // The drift column the backup never had defaults to NULL (column-explicit insert).
    expect((db.prepare('SELECT model FROM note_embeddings').get() as { model: string | null }).model).toBeNull();
    // The precious attached facts schema is never written by restore.
    expect((db.prepare('SELECT COUNT(*) n FROM facts.captured_notes').get() as { n: number }).n).toBe(3);
    db.close();
  });

  it('restoreFromBackup empties a derived table that did not exist at backup time', () => {
    const { db } = open();
    const dest = join(dir, 'backup.db');
    vacuumBackup(db, dest);
    // rederive created a brand-new derived table after the backup was taken.
    db.exec(`CREATE TABLE topic_clusters (id TEXT PRIMARY KEY); INSERT INTO topic_clusters VALUES ('c1');`);

    restoreFromBackup(db, dest);

    // PRE had no such table, so rollback must leave it empty (not carry the post-backup row).
    expect((db.prepare('SELECT COUNT(*) n FROM topic_clusters').get() as { n: number }).n).toBe(0);
    db.close();
  });
});

it('wipe empties every main-schema table but leaves attached facts untouched', () => {
  const db: DB = new Database(':memory:');
  db.exec(`ATTACH ':memory:' AS facts;
    CREATE TABLE facts.captured_notes (id INTEGER PRIMARY KEY);
    INSERT INTO facts.captured_notes VALUES (1),(2);
    CREATE TABLE processed_notes (raw_note_id INTEGER);
    INSERT INTO processed_notes VALUES (1),(2),(3);`);
  wipe(db);
  expect(listDerivedTables(db)).toContain('processed_notes');
  expect((db.prepare('SELECT COUNT(*) n FROM processed_notes').get() as { n: number }).n).toBe(0);
  expect((db.prepare('SELECT COUNT(*) n FROM facts.captured_notes').get() as { n: number }).n).toBe(2);
});

// REGRESSION (verify-rebuild scenario A): wipe() must NOT truncate non-derived tables.
// _selene_metadata is the env-identity marker db.ts reads on every dev/test connection
// (db.ts:44-61) — truncating it crashed re-derivation's process-llm with
// "database is not marked as development environment". PROD has NO such guard, so the
// same wipe would SILENTLY drop the marker, device push tokens, and the migration
// safety-net. wipe must touch ONLY the known-derived allowlist.
it('wipe truncates derived tables but preserves identity / device tokens / legacy backup', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE _selene_metadata (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO _selene_metadata VALUES ('environment','development');
    CREATE TABLE device_tokens (token TEXT);
    INSERT INTO device_tokens VALUES ('apns-abc');
    CREATE TABLE raw_notes_legacy_backup (id INTEGER);
    INSERT INTO raw_notes_legacy_backup VALUES (1),(2);
    CREATE TABLE processed_notes (raw_note_id INTEGER);
    INSERT INTO processed_notes VALUES (1),(2),(3);
  `);
  wipe(db);
  // derived data is gone
  expect((db.prepare('SELECT COUNT(*) n FROM processed_notes').get() as { n: number }).n).toBe(0);
  // identity marker survives — the dev-env guard depends on it (prod has no guard)
  expect((db.prepare(`SELECT value FROM _selene_metadata WHERE key='environment'`).get() as { value: string }).value).toBe('development');
  // non-derived operational state survives
  expect((db.prepare('SELECT COUNT(*) n FROM device_tokens').get() as { n: number }).n).toBe(1);
  expect((db.prepare('SELECT COUNT(*) n FROM raw_notes_legacy_backup').get() as { n: number }).n).toBe(2);
  // listDerivedTables itself excludes the non-derived tables
  expect(listDerivedTables(db)).toEqual(['processed_notes']);
});
