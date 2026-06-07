import Database from 'better-sqlite3';
import { backfillConnections } from './backfill-connections';

type DB = InstanceType<typeof Database>;

function setup(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, created_at TEXT);
    CREATE TABLE note_embeddings (raw_note_id INTEGER, embedding TEXT, model_version TEXT, created_at TEXT);
  `);
  return db;
}

function addNote(db: DB, id: number, createdAt: string, vector: number[]): void {
  db.prepare('INSERT INTO raw_notes (id, created_at) VALUES (?, ?)').run(id, createdAt);
  db.prepare(
    'INSERT INTO note_embeddings (raw_note_id, embedding, model_version, created_at) VALUES (?, ?, ?, ?)'
  ).run(id, JSON.stringify(vector), 'nomic-embed-text', createdAt);
}

function connectionCount(db: DB): number {
  return (db.prepare('SELECT COUNT(*) AS c FROM note_connections').get() as { c: number }).c;
}

describe('backfillConnections', () => {
  it('writes a connection for the similar pair and skips the unrelated note', () => {
    const db = setup();
    addNote(db, 1, '2026-01-01T00:00:00Z', [1, 0, 0]);
    addNote(db, 2, '2026-01-10T00:00:00Z', [0.9, 0.1, 0]); // ~ note 1
    addNote(db, 3, '2026-01-20T00:00:00Z', [0, 0, 1]); // orthogonal

    const res = backfillConnections(db, { threshold: 0.75 });

    expect(res.notesScanned).toBe(3);
    expect(res.candidates).toBe(1);
    expect(res.written).toBe(1);
    expect(connectionCount(db)).toBe(1);
    db.close();
  });

  it('orients the written connection newer -> older', () => {
    const db = setup();
    addNote(db, 1, '2026-01-01T00:00:00Z', [1, 0, 0]);
    addNote(db, 2, '2026-01-10T00:00:00Z', [0.9, 0.1, 0]);

    backfillConnections(db, { threshold: 0.75 });

    const row = db
      .prepare('SELECT source_note_id AS s, target_note_id AS t FROM note_connections')
      .get() as { s: number; t: number };
    expect(row.s).toBe(2); // newer
    expect(row.t).toBe(1); // older
    db.close();
  });

  it('dry-run writes nothing but still reports candidates', () => {
    const db = setup();
    addNote(db, 1, '2026-01-01T00:00:00Z', [1, 0, 0]);
    addNote(db, 2, '2026-01-10T00:00:00Z', [1, 0, 0]);

    const res = backfillConnections(db, { threshold: 0.75, dryRun: true });

    expect(res.candidates).toBe(1);
    expect(res.written).toBe(0);
    expect(connectionCount(db)).toBe(0);
    db.close();
  });

  it('is idempotent — a second run writes no new rows', () => {
    const db = setup();
    addNote(db, 1, '2026-01-01T00:00:00Z', [1, 0, 0]);
    addNote(db, 2, '2026-01-10T00:00:00Z', [1, 0, 0]);

    const first = backfillConnections(db, { threshold: 0.75 });
    const second = backfillConnections(db, { threshold: 0.75 });

    expect(first.written).toBe(1);
    expect(second.written).toBe(0);
    expect(connectionCount(db)).toBe(1);
    db.close();
  });
});
