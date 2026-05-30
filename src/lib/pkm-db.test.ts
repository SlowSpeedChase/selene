import Database from 'better-sqlite3';
import {
  initPkmSchema,
  markSurfaced,
  getDueForReview,
  getLeastRecentlySurfaced,
  ReviewItem,
} from './pkm-db';

type DB = InstanceType<typeof Database>;

function freshDb(): DB {
  const db = new Database(':memory:');
  initPkmSchema(db);
  // Minimal raw_notes for the note-aware getDueForReview.
  db.exec(`CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, status TEXT, test_run TEXT, created_at TEXT);`);
  const ins = db.prepare('INSERT INTO raw_notes (id,status,test_run,created_at) VALUES (?,?,?,?)');
  ins.run(1, 'processed', null, '2026-05-01'); // never surfaced -> due
  ins.run(2, 'processed', null, '2026-05-02'); // will surface now -> not due
  ins.run(3, 'processed', 'dev-seed', '2026-05-03'); // test_run -> excluded entirely
  return db;
}

describe('initPkmSchema', () => {
  it('creates the pkm_review_state table (idempotent)', () => {
    const db = new Database(':memory:');
    expect(() => { initPkmSchema(db); initPkmSchema(db); }).not.toThrow();
    const row = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='pkm_review_state'")
      .get();
    expect(row).toBeDefined();
    db.close();
  });
});

describe('markSurfaced', () => {
  it('upserts: first call sets count 1 + timestamp, second increments to 2', () => {
    const db = freshDb();
    markSurfaced(db, 'note', '1');
    let r = db.prepare("SELECT surface_count AS c, last_surfaced_at AS t FROM pkm_review_state WHERE entity_type='note' AND entity_id='1'").get() as { c: number; t: string };
    expect(r.c).toBe(1);
    expect(r.t).toBeTruthy();
    markSurfaced(db, 'note', '1');
    r = db.prepare("SELECT surface_count AS c FROM pkm_review_state WHERE entity_type='note' AND entity_id='1'").get() as { c: number; t: string };
    expect(r.c).toBe(2);
    db.close();
  });
});

describe('getDueForReview', () => {
  it('includes a never-surfaced note and excludes one surfaced just now', () => {
    const db = freshDb();
    markSurfaced(db, 'note', '2'); // note 2 surfaced now -> not due
    const due: ReviewItem[] = getDueForReview(db, 10);
    const ids = due.map((d) => d.entityId);
    expect(ids).toContain('1');     // never surfaced
    expect(ids).not.toContain('2'); // surfaced now
    expect(ids).not.toContain('3'); // test_run note excluded
    db.close();
  });

  it('orders never-surfaced (count 0) first', () => {
    const db = freshDb();
    // surface note 1 long ago so it is due but has a count; note 2 never surfaced.
    db.prepare("INSERT INTO pkm_review_state VALUES ('note','1',datetime('now','-30 days'),3)").run();
    const due = getDueForReview(db, 10);
    expect(due[0].entityId).toBe('2'); // count 0, never surfaced -> first
    db.close();
  });
});

describe('getLeastRecentlySurfaced', () => {
  it('returns rows of a type, NULL/oldest last_surfaced_at first', () => {
    const db = freshDb();
    db.prepare("INSERT INTO pkm_review_state VALUES ('concept','focus',datetime('now','-2 days'),5)").run();
    db.prepare("INSERT INTO pkm_review_state VALUES ('concept','sleep',datetime('now','-9 days'),2)").run();
    const items = getLeastRecentlySurfaced(db, 'concept', 10);
    expect(items.map((i) => i.entityId)).toEqual(['sleep', 'focus']); // older first
    db.close();
  });
});
