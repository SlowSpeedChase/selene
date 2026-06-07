import Database from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { inspectSchema, inspectCounts, inspectCoverage } from './inspect';
import { makeTwoFileTestDb } from './test-two-file-db';

type DB = InstanceType<typeof Database>;

// A value (not a column name) that must NEVER appear in any inspector output —
// it stands in for real note text. The whole point of selene-inspect is that
// schema/counts/coverage surface structure, never content.
const SENTINEL = 'ZZZ_NOTE_BODY_DO_NOT_LEAK_ZZZ';
const SENTINEL2 = 'ZZZ_ESSENCE_DO_NOT_LEAK_ZZZ';

function seed(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (
      id INTEGER PRIMARY KEY,
      title TEXT,
      content TEXT,
      status TEXT,
      test_run TEXT,
      created_at TEXT
    );
    CREATE TABLE processed_notes (
      id INTEGER PRIMARY KEY,
      raw_note_id INTEGER,
      category TEXT,
      essence TEXT
    );
    CREATE TABLE topic_clusters (id TEXT PRIMARY KEY, name TEXT);
    -- Real schema: links use topic_id + note_id (NOT cluster_id/raw_note_id).
    CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER, added_at TEXT);
  `);
  // 3 raw notes; note 1 carries a test_run marker (leakage); content holds the sentinel.
  const insR = db.prepare('INSERT INTO raw_notes (id,title,content,status,test_run,created_at) VALUES (?,?,?,?,?,?)');
  insR.run(1, SENTINEL, SENTINEL, 'processed', 't1', '2026-05-01');
  insR.run(2, 'note two', SENTINEL, 'processed', null, '2026-05-02');
  insR.run(3, 'note three', SENTINEL, 'pending', null, '2026-05-03');
  // 2 processed rows -> note 3 is unprocessed. pn1 missing category, pn2 missing essence.
  const insP = db.prepare('INSERT INTO processed_notes (id,raw_note_id,category,essence) VALUES (?,?,?,?)');
  insP.run(1, 1, null, SENTINEL2);
  insP.run(2, 2, 'Projects', null);
  // 2 clusters; note 1 is multi-membership (A+B), note 2 in A, note 3 in none.
  db.prepare('INSERT INTO topic_clusters (id,name) VALUES (?,?)').run('A', 'Alpha');
  db.prepare('INSERT INTO topic_clusters (id,name) VALUES (?,?)').run('B', 'Beta');
  const insL = db.prepare('INSERT INTO topic_note_links (topic_id,note_id,added_at) VALUES (?,?,?)');
  insL.run('A', 1, '2026-05-01'); // note 1 -> A
  insL.run('B', 1, '2026-05-01'); // note 1 -> B (multi-membership)
  insL.run('A', 2, '2026-05-01'); // note 2 -> A; note 3 -> none
  return db;
}

describe('inspectCounts', () => {
  it('reports row counts and test_run leakage without note text', () => {
    const db = seed();
    const r = inspectCounts(db);
    expect(r.tables.raw_notes).toBe(3);
    expect(r.tables.processed_notes).toBe(2);
    expect(r.testRunRows).toBe(1);
    expect(r.rawNotesByStatus.processed).toBe(2);
    expect(r.rawNotesByStatus.pending).toBe(1);
    expect(JSON.stringify(r)).not.toContain(SENTINEL);
    db.close();
  });
});

describe('inspectCoverage', () => {
  it('reports completeness and multi-membership without note text', () => {
    const db = seed();
    const r = inspectCoverage(db);
    expect(r.rawNotes).toBe(3);
    expect(r.processedNotes).toBe(2);
    expect(r.unprocessed).toBe(1);
    expect(r.missingCategory).toBe(1);
    expect(r.missingEssence).toBe(1);
    expect(r.missingEmbedding).toBeNull(); // note_embeddings table absent -> graceful null
    expect(r.clusters).toBe(2);
    expect(r.noteLinks).toBe(3);
    expect(r.avgClustersPerNote).toBeCloseTo(1.5);
    expect(r.notesWithNoCluster).toBe(1);
    expect(JSON.stringify(r)).not.toContain(SENTINEL);
    expect(JSON.stringify(r)).not.toContain(SENTINEL2);
    db.close();
  });
});

describe('inspectSchema', () => {
  it('lists tables when no table given', () => {
    const db = seed();
    const r = inspectSchema(db);
    expect(r.tables).toEqual(expect.arrayContaining(['raw_notes', 'processed_notes', 'topic_clusters']));
    expect(r.columns).toBeUndefined();
    db.close();
  });

  it('lists column names/types for a table but never row values', () => {
    const db = seed();
    const r = inspectSchema(db, 'raw_notes');
    expect(r.table).toBe('raw_notes');
    const names = (r.columns ?? []).map((c) => c.name);
    expect(names).toEqual(expect.arrayContaining(['content', 'title', 'status']));
    // Column NAMES are fine; the sentinel is a row VALUE and must not appear.
    expect(JSON.stringify(r)).not.toContain(SENTINEL);
    db.close();
  });
});

// ── Two-file (migrated) layout: raw_notes is a TEMP view over facts.captured_notes + note_state ──
//
// selene-inspect opens a migrated prod DB and must report the SAME rawNotes count / status
// breakdown it did pre-split. Through the view, raw_notes is a TEMP view (NOT a physical table in
// main.sqlite_master), so the inspector's relation-detection has to recognize it. status comes
// from COALESCE(note_state.status, 'pending').
describe('inspectCounts/inspectCoverage on a migrated two-file DB (raw_notes is the view)', () => {
  let db: DB;
  let dir: string;

  beforeEach(() => {
    ({ db, dir } = makeTwoFileTestDb());
    // processed_notes is a derived table the coverage report joins.
    db.exec(`CREATE TABLE processed_notes (id INTEGER PRIMARY KEY, raw_note_id INTEGER, category TEXT, essence TEXT);`);

    const ins = db.prepare(
      `INSERT INTO facts.captured_notes (title, content, content_hash, created_at, test_run)
       VALUES (?, ?, ?, ?, ?)`
    );
    // note 1: processed (explicit note_state), test_run marker, missing category
    const id1 = Number(ins.run('n1', SENTINEL, 'h1', '2026-05-01', 't1').lastInsertRowid);
    db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (?, 'processed')`).run(id1);
    db.prepare(`INSERT INTO processed_notes (raw_note_id, category, essence) VALUES (?, NULL, ?)`).run(id1, SENTINEL2);
    // note 2: processed (explicit note_state), missing essence
    const id2 = Number(ins.run('n2', SENTINEL, 'h2', '2026-05-02', null).lastInsertRowid);
    db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (?, 'processed')`).run(id2);
    db.prepare(`INSERT INTO processed_notes (raw_note_id, category, essence) VALUES (?, 'Projects', NULL)`).run(id2);
    // note 3: NO note_state row -> status COALESCE -> 'pending'; unprocessed
    Number(ins.run('n3', SENTINEL, 'h3', '2026-05-03', null).lastInsertRowid);
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('counts rawNotes from captured_notes (via the view) with the right status breakdown', () => {
    const r = inspectCounts(db);
    expect(r.tables.raw_notes).toBe(3);          // the 3 captured notes, surfaced through the view
    expect(r.tables.processed_notes).toBe(2);
    expect(r.testRunRows).toBe(1);               // note 1
    expect(r.rawNotesByStatus.processed).toBe(2); // notes 1,2 (explicit note_state)
    expect(r.rawNotesByStatus.pending).toBe(1);   // note 3 (COALESCE default)
    expect(JSON.stringify(r)).not.toContain(SENTINEL);
  });

  it('reports coverage (unprocessed / missing fields) through the view', () => {
    const r = inspectCoverage(db);
    expect(r.rawNotes).toBe(3);
    expect(r.processedNotes).toBe(2);
    expect(r.unprocessed).toBe(1);     // note 3 has no processed_notes row
    expect(r.missingCategory).toBe(1); // note 1
    expect(r.missingEssence).toBe(1);  // note 2
    expect(JSON.stringify(r)).not.toContain(SENTINEL);
    expect(JSON.stringify(r)).not.toContain(SENTINEL2);
  });

  it('lists raw_notes (the TEMP view) in the schema relation listing', () => {
    // inspectCounts/coverage already recognize the view via relationExists; the `schema` listing
    // must too, or `selene-inspect schema` would omit raw_notes on a migrated DB while `counts`
    // still reports a row count for it — an inconsistent picture for an operator.
    const r = inspectSchema(db);
    expect(r.tables).toContain('raw_notes');
    expect(r.tables).toContain('processed_notes');
  });
});

describe('inspectCoverage subCategoryCoverage', () => {
  function seedSubs(): DB {
    const db = new Database(':memory:');
    db.exec(`
      CREATE TABLE processed_notes (
        id INTEGER PRIMARY KEY,
        raw_note_id INTEGER,
        category TEXT,
        cross_ref_categories TEXT,
        sub_categories TEXT,
        essence TEXT
      );
    `);
    const ins = db.prepare(
      'INSERT INTO processed_notes (id,raw_note_id,category,cross_ref_categories,sub_categories,essence) VALUES (?,?,?,?,?,?)'
    );
    // 1: Health note with sub Running
    ins.run(1, 1, 'Health & Body', '[]', JSON.stringify({ 'Health & Body': 'Running' }), SENTINEL2);
    // 2: Health note with empty sub_categories -> none bucket
    ins.run(2, 2, 'Health & Body', '[]', '{}', SENTINEL2);
    // 3: Health & Body + cross_ref Projects & Tech, subs Running + Selene
    ins.run(
      3, 3, 'Health & Body', JSON.stringify(['Projects & Tech']),
      JSON.stringify({ 'Health & Body': 'Running', 'Projects & Tech': 'Selene' }), SENTINEL2
    );
    return db;
  }

  it('reports per-category sub-category counts incl a none bucket (counts only)', () => {
    const db = seedSubs();
    const cov = inspectCoverage(db).subCategoryCoverage;
    expect(cov?.['Health & Body']).toEqual({ Running: 2, none: 1 });
    expect(cov?.['Projects & Tech']).toEqual({ Selene: 1 });
    db.close();
  });

  it('is null when the sub_categories column is absent (old DB)', () => {
    const db = new Database(':memory:');
    // processed_notes WITHOUT a sub_categories column (legacy shape).
    db.exec('CREATE TABLE processed_notes (id INTEGER PRIMARY KEY, raw_note_id INTEGER, category TEXT, essence TEXT);');
    db.prepare('INSERT INTO processed_notes (id,raw_note_id,category,essence) VALUES (?,?,?,?)')
      .run(1, 1, 'Health & Body', SENTINEL2);
    expect(inspectCoverage(db).subCategoryCoverage).toBeNull();
    db.close();
  });

  it('emits only taxonomy labels + numbers (no note content)', () => {
    const db = new Database(':memory:');
    // A processed_notes row whose essence (a content-bearing column) holds the sentinel.
    db.exec(`
      CREATE TABLE processed_notes (
        id INTEGER PRIMARY KEY,
        raw_note_id INTEGER,
        category TEXT,
        cross_ref_categories TEXT,
        sub_categories TEXT,
        essence TEXT
      );
    `);
    db.prepare(
      'INSERT INTO processed_notes (id,raw_note_id,category,cross_ref_categories,sub_categories,essence) VALUES (?,?,?,?,?,?)'
    ).run(1, 1, 'Health & Body', '[]', JSON.stringify({ 'Health & Body': 'Running' }), SENTINEL);
    const cov = inspectCoverage(db).subCategoryCoverage;
    const json = JSON.stringify(cov);
    expect(json).not.toContain(SENTINEL); // essence text must not leak
    expect(json).toContain('Running');    // taxonomy labels are fine
    db.close();
  });
});

describe('content-leak invariant', () => {
  it('no inspector report serializes any real note text', () => {
    const db = seed();
    const blob = JSON.stringify([
      inspectCounts(db),
      inspectCoverage(db),
      inspectSchema(db),
      inspectSchema(db, 'raw_notes'),
      inspectSchema(db, 'processed_notes'),
    ]);
    expect(blob).not.toContain(SENTINEL);
    expect(blob).not.toContain(SENTINEL2);
    db.close();
  });
});
