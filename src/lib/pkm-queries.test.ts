import Database from 'better-sqlite3';
import {
  getTopConcepts,
  getNotesForConcept,
  getCooccurringConcepts,
  getNotesForCategory,
  getCategoryCounts,
  getRandomEssence,
} from './pkm-queries';

type DB = InstanceType<typeof Database>;

function seed(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, content TEXT, created_at TEXT,
      status TEXT, test_run TEXT);
    CREATE TABLE processed_notes (raw_note_id INTEGER, concepts TEXT, essence TEXT,
      primary_theme TEXT, category TEXT, cross_ref_categories TEXT);
  `);
  const rn = db.prepare('INSERT INTO raw_notes VALUES (?,?,?,?,?,?)');
  const pn = db.prepare('INSERT INTO processed_notes VALUES (?,?,?,?,?,?)');
  // note 1: focus+sleep, Health & Body, cross-ref Daily Systems
  rn.run(1, 'Sleep note', 'c', '2026-05-01', 'processed', null);
  pn.run(1, '["focus","sleep"]', 'rest matters', 'theme-a', 'Health & Body', '["Daily Systems"]');
  // note 2: focus+work, Career & Work
  rn.run(2, 'Work note', 'c', '2026-05-02', 'processed', null);
  pn.run(2, '["focus","work"]', 'ship it', 'theme-b', 'Career & Work', '[]');
  // note 3: sleep, Health & Body — EXCLUDED (test_run)
  rn.run(3, 'Test note', 'c', '2026-05-03', 'processed', 'dev-seed');
  pn.run(3, '["sleep"]', 'should not appear', 'theme-c', 'Health & Body', '[]');
  // note 4: EXCLUDED (pending)
  rn.run(4, 'Pending note', 'c', '2026-05-04', 'pending', null);
  pn.run(4, '["focus"]', null, 'theme-d', 'Career & Work', '[]');
  return db;
}

describe('getTopConcepts', () => {
  it('counts concepts across processed, non-test notes only', () => {
    const top = getTopConcepts(seed(), 10);
    const map = Object.fromEntries(top.map((c) => [c.concept, c.n]));
    expect(map.focus).toBe(2); // notes 1,2 (note 4 pending excluded)
    expect(map.sleep).toBe(1); // note 1 (note 3 test_run excluded)
    expect(map.work).toBe(1);
    expect(top[0].concept).toBe('focus'); // highest first
  });
});

describe('getNotesForConcept', () => {
  it('returns notes whose concepts JSON contains the term', () => {
    const notes = getNotesForConcept(seed(), 'focus', 10);
    expect(notes.map((n) => n.id).sort()).toEqual([1, 2]);
  });
});

describe('getCooccurringConcepts', () => {
  it('returns other concepts appearing alongside the term', () => {
    const co = getCooccurringConcepts(seed(), 'focus', 10);
    const map = Object.fromEntries(co.map((c) => [c.concept, c.n]));
    expect(map.sleep).toBe(1); // with focus in note 1
    expect(map.work).toBe(1);  // with focus in note 2
    expect(map.focus).toBeUndefined(); // never co-occurs with itself
  });
});

describe('getNotesForCategory', () => {
  it('matches primary category AND cross_ref_categories', () => {
    expect(getNotesForCategory(seed(), 'Health & Body', 10).map((n) => n.id)).toEqual([1]);
    // note 1 reaches "Daily Systems" only via cross_ref
    expect(getNotesForCategory(seed(), 'Daily Systems', 10).map((n) => n.id)).toEqual([1]);
  });
});

describe('getCategoryCounts', () => {
  it('counts notes per primary category (excludes test/pending)', () => {
    const counts = Object.fromEntries(getCategoryCounts(seed()).map((c) => [c.category, c.n]));
    expect(counts['Health & Body']).toBe(1); // note 3 excluded
    expect(counts['Career & Work']).toBe(1); // note 4 excluded
  });
});

describe('getRandomEssence', () => {
  it('returns a note with a non-null essence from the eligible set', () => {
    const e = getRandomEssence(seed());
    expect(e).toBeDefined();
    expect([1, 2]).toContain(e!.id); // not 3 (test_run) or 4 (null essence/pending)
    expect(e!.essence).toBeTruthy();
  });
});
