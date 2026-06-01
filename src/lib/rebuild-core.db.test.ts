import Database from 'better-sqlite3';
import { listDerivedTables } from './rebuild-core';
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
