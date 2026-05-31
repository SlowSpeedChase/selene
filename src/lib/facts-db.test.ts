import Database from 'better-sqlite3';
import { initFactsSchema } from './facts-db';

describe('initFactsSchema', () => {
  it('creates captured_notes + review_state, idempotently', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    initFactsSchema(db); // second call must NOT throw (IF NOT EXISTS)

    const capCols = (db.prepare(`PRAGMA table_info(captured_notes)`).all() as { name: string }[]).map(c => c.name);
    expect(capCols).toEqual(expect.arrayContaining([
      'id','title','content','content_hash','source_type','word_count','character_count',
      'tags','created_at','imported_at','source_uuid','calendar_event','capture_type',
      'source_note_id','test_run',
    ]));

    const rsCols = (db.prepare(`PRAGMA table_info(review_state)`).all() as { name: string }[]).map(c => c.name);
    expect(rsCols).toEqual(expect.arrayContaining([
      'entity_type','entity_id','last_surfaced_at','surface_count',
    ]));
    db.close();
  });

  it('enforces NOT NULL on title/content/content_hash/created_at', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    expect(() =>
      db.prepare(`INSERT INTO captured_notes (title) VALUES ('x')`).run()
    ).toThrow(); // content/content_hash/created_at are NOT NULL
    db.close();
  });
});
