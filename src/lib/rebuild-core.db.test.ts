import Database from 'better-sqlite3';
import { listDerivedTables, snapshot } from './rebuild-core';
type DB = InstanceType<typeof Database>;

it('lists only main-schema user tables, excluding sqlite_* and views', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE processed_notes (id INTEGER PRIMARY KEY);
    CREATE TABLE note_embeddings (raw_note_id INTEGER);
    CREATE VIEW v AS SELECT 1;
  `);
  expect(listDerivedTables(db).sort()).toEqual(['note_embeddings', 'processed_notes']);
});

it('counts captured + each derived metric', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes_t (id INTEGER PRIMARY KEY);
    CREATE VIEW raw_notes AS SELECT id, 1 AS exported_to_obsidian FROM raw_notes_t;
    CREATE TABLE processed_notes (raw_note_id INTEGER, essence TEXT);
    CREATE TABLE note_embeddings (raw_note_id INTEGER);
    CREATE TABLE topic_clusters (id TEXT PRIMARY KEY);
    CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER);
  `);
  db.exec(`INSERT INTO raw_notes_t VALUES (1),(2),(3)`);
  db.exec(`INSERT INTO processed_notes VALUES (1,'e'),(2,NULL)`);
  db.exec(`INSERT INTO note_embeddings VALUES (1)`);
  db.exec(`INSERT INTO topic_clusters VALUES ('c1')`);
  db.exec(`INSERT INTO topic_note_links VALUES ('c1',1)`);
  expect(snapshot(db)).toEqual({
    captured: 3, processed: 2, essences: 1, embeddings: 1,
    clusters: 1, clusterLinks: 1, exported: 3,
  });
});
