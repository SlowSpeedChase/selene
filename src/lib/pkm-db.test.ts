/**
 * pkm-db tests — review-state layer, now on the two-file fact-store layout.
 *
 * Fact-store split (Task 9): `review_state` moved into facts.db (precious). It resolves via the
 * `facts` attach alias, so these tests build a real two-file DB with makeTwoFileTestDb() rather
 * than a bare :memory: handle. getDueForReview reads the `raw_notes` TEMP view
 * (facts.captured_notes LEFT JOIN note_state), so processed/test_run fixtures are seeded into
 * facts.captured_notes + note_state — matching how the live app stores them.
 */
import type { Database as DB } from 'better-sqlite3';
import { rmSync } from 'fs';
import { makeTwoFileTestDb } from './test-two-file-db';
import {
  initPkmSchema,
  markSurfaced,
  getDueForReview,
  getLeastRecentlySurfaced,
  ReviewItem,
} from './pkm-db';

/** A two-file DB seeded with the minimal captured_notes + note_state for getDueForReview. */
function freshDb(): { db: DB; dir: string } {
  const { db, dir } = makeTwoFileTestDb();
  initPkmSchema(db); // no-op now (review_state lives in facts), but the contract still holds
  const cap = db.prepare(
    `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at, test_run)
     VALUES (?, 't', 'c', ?, ?, ?)`
  );
  const state = db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (?, ?)`);
  // note 1: processed, never surfaced -> due
  cap.run(1, 'h1', '2026-05-01', null);
  state.run(1, 'processed');
  // note 2: processed, will be surfaced now -> not due
  cap.run(2, 'h2', '2026-05-02', null);
  state.run(2, 'processed');
  // note 3: processed BUT test_run -> excluded entirely by baseNoteFilter's test_run guard
  cap.run(3, 'h3', '2026-05-03', 'dev-seed');
  state.run(3, 'processed');
  return { db, dir };
}

describe('initPkmSchema', () => {
  it('is idempotent and does NOT create review_state in selene.db main (it lives in facts.db)', () => {
    const { db, dir } = makeTwoFileTestDb();
    expect(() => { initPkmSchema(db); initPkmSchema(db); }).not.toThrow();
    // review_state must NOT exist as a selene.db main table — only in the attached facts db.
    const mainTbl = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='review_state'")
      .get();
    expect(mainTbl).toBeUndefined();
    const factsTbl = db
      .prepare("SELECT name FROM facts.sqlite_master WHERE type='table' AND name='review_state'")
      .get();
    expect(factsTbl).toBeDefined();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });
});

describe('markSurfaced', () => {
  it('upserts into facts.review_state: first call count 1 + timestamp, second increments to 2', () => {
    const { db, dir } = freshDb();
    markSurfaced(db, 'note', '1');
    let r = db
      .prepare("SELECT surface_count AS c, last_surfaced_at AS t FROM review_state WHERE entity_type='note' AND entity_id='1'")
      .get() as { c: number; t: string };
    expect(r.c).toBe(1);
    expect(r.t).toBeTruthy();
    // The row really lives in facts.db (precious), reachable via the qualified name too.
    const viaFacts = db
      .prepare("SELECT surface_count AS c FROM facts.review_state WHERE entity_type='note' AND entity_id='1'")
      .get() as { c: number };
    expect(viaFacts.c).toBe(1);

    markSurfaced(db, 'note', '1');
    r = db
      .prepare("SELECT surface_count AS c FROM review_state WHERE entity_type='note' AND entity_id='1'")
      .get() as { c: number; t: string };
    expect(r.c).toBe(2);
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });
});

describe('getDueForReview', () => {
  it('includes a never-surfaced note and excludes one surfaced just now', () => {
    const { db, dir } = freshDb();
    markSurfaced(db, 'note', '2'); // note 2 surfaced now -> not due
    const due: ReviewItem[] = getDueForReview(db, 10);
    const ids = due.map((d) => d.entityId);
    expect(ids).toContain('1');     // never surfaced
    expect(ids).not.toContain('2'); // surfaced now
    expect(ids).not.toContain('3'); // test_run note excluded
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('orders never-surfaced (count 0) first', () => {
    const { db, dir } = freshDb();
    // surface note 1 long ago so it is due but has a count; note 2 never surfaced.
    db.prepare("INSERT INTO review_state VALUES ('note','1',datetime('now','-30 days'),3)").run();
    const due = getDueForReview(db, 10);
    expect(due[0].entityId).toBe('2'); // count 0, never surfaced -> first
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });
});

describe('getLeastRecentlySurfaced', () => {
  it('returns rows of a type, NULL/oldest last_surfaced_at first', () => {
    const { db, dir } = freshDb();
    db.prepare("INSERT INTO review_state VALUES ('concept','focus',datetime('now','-2 days'),5)").run();
    db.prepare("INSERT INTO review_state VALUES ('concept','sleep',datetime('now','-9 days'),2)").run();
    const items = getLeastRecentlySurfaced(db, 'concept', 10);
    expect(items.map((i) => i.entityId)).toEqual(['sleep', 'focus']); // older first
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });
});
