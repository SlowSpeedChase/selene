import Database from 'better-sqlite3';
import { listDerivedTables, snapshot, backupPath, wipe, pendingCount } from './rebuild-core';
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
