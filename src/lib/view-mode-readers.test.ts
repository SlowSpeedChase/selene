/**
 * MIGRATION GATE (Task 8a) — view-mode reader sweep.
 *
 * The split moved note facts into facts.captured_notes and pipeline bookkeeping into
 * note_state; `raw_notes` is now a per-connection TEMP VIEW
 * (facts.captured_notes LEFT JOIN note_state, status/inbox_status COALESCE'd to 'pending').
 *
 * The pre-existing test suite never exercises that view path — every other fixture builds a
 * PHYSICAL raw_notes table (and our view-guard no-ops when a physical table exists). So before
 * any real DB is migrated, this file PROVES every real reader still works when raw_notes is the
 * view. If it is green, the migration is safe; if a reader were structurally view-incompatible,
 * we'd see it here.
 *
 * Each reader is exercised through `makeTwoFileTestDb()` (a selene.db with facts.db attached +
 * note_state + the raw_notes TEMP view — production wiring). Two value-add mechanisms are proven,
 * matching how each reader actually queries the view:
 *
 *   A) status-COALESCE distinction (pkm-queries, folio-feedback, worksheets): a note with NO
 *      note_state row (status/inbox_status default to 'pending' via COALESCE) is distinguished
 *      from a note with an explicit note_state row, and the reader's status/inbox_status filter
 *      includes/excludes each correctly.
 *
 *   B) LEFT-JOIN row preservation (daily-summary, synthesis-digest): these readers don't filter
 *      on status, but the view is a LEFT JOIN — a note with NO note_state row must STILL surface.
 *      That's the dominant migration risk for them: after migration every fresh/unprocessed note
 *      is note_state-less, and an INNER-join regression would silently drop recent notes. Each of
 *      these two readers returns a note_state-less note and we assert it is present.
 *
 * SELENE_ENV is forced to 'production' at module top (BEFORE importing config/test-run), so
 * `testRunFilter()` produces the real guard. Under jest the repo's .env.development otherwise
 * sets SELENE_ENV=development, which makes testRunFilter() a no-op — that would silently disable
 * the test_run-exclusion checks below. Mirrors src/routes/worksheets.test.ts. No DB path is set,
 * so this can never touch a real DB: every reader is driven against the throwaway two-file fixture.
 *
 * `process.env` is shared across a jest worker (workers run files sequentially in one process, and
 * dotenv never overrides an already-set var), so we capture and restore SELENE_ENV in afterAll to
 * avoid flipping config.env for any test file that loads after this one in the same worker.
 */
const ORIGINAL_SELENE_ENV = process.env.SELENE_ENV;
process.env.SELENE_ENV = 'production';

import type { Database as DB } from 'better-sqlite3';
import { rmSync } from 'fs';
import { makeTwoFileTestDb } from './test-two-file-db';
import { testRunFilter } from './test-run';
import { initSynthesisSchema } from './synthesis-db';
import {
  getTopConcepts,
  getNotesForConcept,
  getCategoryCounts,
  getRandomEssence,
} from './pkm-queries';
import { buildSynthesisSections } from './synthesis-digest';

// Restore the worker-shared SELENE_ENV so later test files keep their normal config.env default.
afterAll(() => {
  if (ORIGINAL_SELENE_ENV === undefined) {
    delete process.env.SELENE_ENV;
  } else {
    process.env.SELENE_ENV = ORIGINAL_SELENE_ENV;
  }
});

// ── Fixture helpers ──────────────────────────────────────────────────────────────

/** Insert a fact row into facts.captured_notes; returns the new id. */
function insertCapturedNote(
  db: DB,
  fields: {
    title: string;
    content?: string;
    content_hash: string;
    created_at: string;
    capture_type?: string | null;
    test_run?: string | null;
  }
): number {
  const info = db
    .prepare(
      `INSERT INTO facts.captured_notes (title, content, content_hash, created_at, capture_type, test_run)
       VALUES (@title, @content, @content_hash, @created_at, @capture_type, @test_run)`
    )
    .run({
      title: fields.title,
      content: fields.content ?? 'body',
      content_hash: fields.content_hash,
      created_at: fields.created_at,
      capture_type: fields.capture_type ?? null,
      test_run: fields.test_run ?? null,
    });
  return Number(info.lastInsertRowid);
}

/** Insert a note_state bookkeeping row (the COALESCE override). */
function insertNoteState(
  db: DB,
  raw_note_id: number,
  state: { status?: string | null; inbox_status?: string | null; status_folio?: string | null }
): void {
  db.prepare(
    `INSERT INTO note_state (raw_note_id, status, inbox_status, status_folio)
     VALUES (?, ?, ?, ?)`
  ).run(
    raw_note_id,
    state.status ?? null,
    state.inbox_status ?? null,
    state.status_folio ?? null
  );
}

/** processed_notes is a derived table the readers JOIN; create it physically on the same conn. */
function createProcessedNotes(db: DB): void {
  db.exec(`
    CREATE TABLE processed_notes (
      raw_note_id INTEGER,
      concepts TEXT,
      essence TEXT,
      primary_theme TEXT,
      secondary_themes TEXT,
      category TEXT,
      cross_ref_categories TEXT
    );
  `);
}

function insertProcessed(
  db: DB,
  raw_note_id: number,
  p: {
    concepts?: string | null;
    essence?: string | null;
    primary_theme?: string | null;
    secondary_themes?: string | null;
    category?: string | null;
    cross_ref_categories?: string | null;
  }
): void {
  db.prepare(
    `INSERT INTO processed_notes
       (raw_note_id, concepts, essence, primary_theme, secondary_themes, category, cross_ref_categories)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(
    raw_note_id,
    p.concepts ?? null,
    p.essence ?? null,
    p.primary_theme ?? null,
    p.secondary_themes ?? null,
    p.category ?? null,
    p.cross_ref_categories ?? '[]'
  );
}

// ── 1. pkm-queries.ts — real functions, status-COALESCE distinction ───────────────
//
// Every pkm-queries function gates on baseNoteFilter() => `test_run IS NULL AND status = 'processed'`.
// We seed processed notes with an EXPLICIT note_state.status='processed' and one note with NO
// note_state row (status COALESCE -> 'pending'), and assert the pending note is excluded — i.e. the
// view's COALESCE default is what keeps an un-migrated/fresh note out of the browse surface.

describe('pkm-queries through the raw_notes view', () => {
  let db: DB;
  let dir: string;

  beforeEach(() => {
    ({ db, dir } = makeTwoFileTestDb());
    createProcessedNotes(db);

    // note 1: processed (explicit note_state), Health & Body, cross-ref Daily Systems
    const id1 = insertCapturedNote(db, { title: 'Sleep note', content: 'c', content_hash: 'h1', created_at: '2026-05-01' });
    insertNoteState(db, id1, { status: 'processed' });
    insertProcessed(db, id1, { concepts: '["focus","sleep"]', essence: 'rest matters', primary_theme: 'theme-a', category: 'Health & Body', cross_ref_categories: '["Daily Systems"]' });

    // note 2: processed (explicit note_state), Career & Work
    const id2 = insertCapturedNote(db, { title: 'Work note', content: 'c', content_hash: 'h2', created_at: '2026-05-02' });
    insertNoteState(db, id2, { status: 'processed' });
    insertProcessed(db, id2, { concepts: '["focus","work"]', essence: 'ship it', primary_theme: 'theme-b', category: 'Career & Work' });

    // note 3: processed BUT test_run -> excluded by baseNoteFilter's test_run guard
    const id3 = insertCapturedNote(db, { title: 'Test note', content: 'c', content_hash: 'h3', created_at: '2026-05-03', test_run: 'dev-seed' });
    insertNoteState(db, id3, { status: 'processed' });
    insertProcessed(db, id3, { concepts: '["sleep"]', essence: 'should not appear', primary_theme: 'theme-c', category: 'Health & Body' });

    // note 4: NO note_state row -> status COALESCE -> 'pending' -> excluded (the value-add proof)
    const id4 = insertCapturedNote(db, { title: 'Fresh capture', content: 'c', content_hash: 'h4', created_at: '2026-05-04' });
    insertProcessed(db, id4, { concepts: '["focus"]', essence: null, primary_theme: 'theme-d', category: 'Career & Work' });
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('getTopConcepts counts only processed, non-test notes (pending note_state-less note excluded)', () => {
    const map = Object.fromEntries(getTopConcepts(db, 10).map((c) => [c.concept, c.n]));
    // focus appears in notes 1,2 (processed) but NOT note 4 (pending via COALESCE default).
    expect(map.focus).toBe(2);
    expect(map.sleep).toBe(1); // note 1 only (note 3 test_run excluded)
    expect(map.work).toBe(1);
  });

  it('getNotesForConcept returns only the explicit-processed notes for a concept', () => {
    // 'focus' is on notes 1,2 (processed) and note 4 (pending). The pending note_state-less note 4
    // must NOT come back — proves the view's COALESCE default gates it out.
    expect(getNotesForConcept(db, 'focus', 10).map((n) => n.id).sort((a, b) => a - b)).toEqual([1, 2]);
  });

  it('getCategoryCounts excludes the pending (note_state-less) note', () => {
    const counts = Object.fromEntries(getCategoryCounts(db).map((c) => [c.category, c.n]));
    expect(counts['Health & Body']).toBe(1);  // note 1 (note 3 test_run excluded)
    expect(counts['Career & Work']).toBe(1);  // note 2 only — note 4 pending excluded
  });

  it('getRandomEssence never returns the pending or test_run note', () => {
    const e = getRandomEssence(db);
    expect(e).toBeDefined();
    expect([1, 2]).toContain(e!.id); // not 3 (test_run) and not 4 (pending + null essence)
    expect(e!.essence).toBeTruthy();
  });
});

// ── 2. synthesis-digest.ts — real buildSynthesisSections(), LEFT-JOIN row preservation ─────────
//
// Its only raw_notes read is Section 3 (note_connections JOIN raw_notes src/tgt). It does not
// filter on status, so the view value-add to prove is LEFT-JOIN row preservation: the connection's
// SOURCE note has NO note_state row, and its title must still appear in "Unexpected connections".
// If the view dropped note_state-less rows, fresh-note connections would vanish post-migration.

describe('synthesis-digest buildSynthesisSections through the raw_notes view', () => {
  let db: DB;
  let dir: string;

  beforeEach(() => {
    ({ db, dir } = makeTwoFileTestDb());
    initSynthesisSchema(db); // topic_clusters, topic_note_links, note_connections, synthesis_meta

    // src note: NO note_state row (status COALESCE -> 'pending'); must still surface via the view.
    const srcId = insertCapturedNote(db, { title: 'Fresh source note', content: 'c', content_hash: 'hs', created_at: new Date().toISOString() });
    // tgt note: explicit note_state (processed). Older, for a believable "target".
    const tgtId = insertCapturedNote(db, { title: 'Older target note', content: 'c', content_hash: 'ht', created_at: '2026-04-01T00:00:00.000Z' });
    insertNoteState(db, tgtId, { status: 'processed' });

    const now = new Date().toISOString();
    db.prepare(
      `INSERT INTO note_connections (id, source_note_id, target_note_id, similarity_score, found_at)
       VALUES ('conn1', ?, ?, 0.88, ?)`
    ).run(srcId, tgtId, now);
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('surfaces a connection whose source note has no note_state row (LEFT-JOIN preservation)', () => {
    const result = buildSynthesisSections(db);
    expect(result).toContain('Unexpected connections');
    expect(result).toContain('Fresh source note');  // note_state-less src survived the view JOIN
    expect(result).toContain('Older target note');
  });
});

// ── 3. daily-summary.ts — query-mirror (workflow not unit-isolable), LEFT-JOIN preservation ────
//
// dailySummary() has file + Apple-Notes + LLM side effects, so we mirror ONLY its DB read.
// QUERY-MIRROR of src/workflows/daily-summary.ts:46-54 (verbatim SELECT + testRunFilter('rn'));
// kept in sync via the imported testRunFilter(). The value-add: an in-window note with NO
// note_state row must still appear (LEFT-JOIN preservation), and the test_run note must be
// excluded by the real guard (which is why SELENE_ENV is forced to production above).

function dailySummaryNotesMirror(
  db: DB,
  startISO: string,
  endISO: string
): Array<{ title: string; content: string; primary_theme: string | null }> {
  return db
    .prepare(
      `SELECT rn.title, rn.content, pn.primary_theme, pn.secondary_themes, pn.concepts, pn.essence
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.created_at BETWEEN ? AND ?
         ${testRunFilter('rn')}
       ORDER BY rn.created_at`
    )
    .all(startISO, endISO) as Array<{ title: string; content: string; primary_theme: string | null }>;
}

describe('daily-summary past-week read through the raw_notes view (query-mirror)', () => {
  let db: DB;
  let dir: string;
  const start = '2026-05-10T00:00:00.000Z';
  const end = '2026-05-17T23:59:59.999Z';

  beforeEach(() => {
    ({ db, dir } = makeTwoFileTestDb());
    createProcessedNotes(db);

    // in-window, NO note_state row -> must appear (LEFT-JOIN preservation = the value-add)
    const idFresh = insertCapturedNote(db, { title: 'Fresh in-window', content: 'aaa', content_hash: 'd1', created_at: '2026-05-12T09:00:00.000Z' });
    insertProcessed(db, idFresh, { primary_theme: 'p1' });

    // in-window, explicit note_state -> must appear
    const idProc = insertCapturedNote(db, { title: 'Processed in-window', content: 'bbb', content_hash: 'd2', created_at: '2026-05-13T09:00:00.000Z' });
    insertNoteState(db, idProc, { status: 'processed' });
    insertProcessed(db, idProc, { primary_theme: 'p2' });

    // OUT of window, NO note_state row -> must NOT appear (windowing works through the view)
    insertCapturedNote(db, { title: 'Old out-of-window', content: 'ccc', content_hash: 'd3', created_at: '2026-01-01T09:00:00.000Z' });

    // in-window, test_run set -> must NOT appear (testRunFilter guard active under production env)
    insertCapturedNote(db, { title: 'Test-run in-window', content: 'ddd', content_hash: 'd4', created_at: '2026-05-14T09:00:00.000Z', test_run: 'dev-seed' });
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('windows correctly and preserves the note_state-less in-window note', () => {
    const rows = dailySummaryNotesMirror(db, start, end);
    const titles = rows.map((r) => r.title).sort();
    expect(titles).toEqual(['Fresh in-window', 'Processed in-window']);
    // The note_state-less note survived the LEFT JOIN (would be dropped by an INNER-join regression).
    expect(titles).toContain('Fresh in-window');
  });
});

// ── 4. folio-feedback.ts — query-mirror of candidate SELECT, status-COALESCE distinction ───────
//
// runFolioFeedback() opens its own connection and writes files + setNoteState (Task-9 scope).
// We mirror ONLY its candidate-selection READ to prove view-compatibility.
// QUERY-MIRROR of src/workflows/folio-feedback.ts:79-87 (verbatim).
// Value-add: a folio note with NO note_state row (status COALESCE -> 'pending') must be EXCLUDED
// (pending is not in ('processed','archived')); one with explicit status='processed' is included.

function folioCandidatesMirror(
  db: DB
): Array<{ id: number; title: string; content: string; created_at: string; concepts: string | null; primary_theme: string | null }> {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, rn.created_at,
              pn.concepts, pn.primary_theme
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON pn.raw_note_id = rn.id
       WHERE rn.capture_type = 'folio'
         AND rn.status_folio IS NULL
         AND rn.status IN ('processed', 'archived')`
    )
    .all() as Array<{ id: number; title: string; content: string; created_at: string; concepts: string | null; primary_theme: string | null }>;
}

describe('folio-feedback candidate selection through the raw_notes view (query-mirror)', () => {
  let db: DB;
  let dir: string;

  beforeEach(() => {
    ({ db, dir } = makeTwoFileTestDb());
    createProcessedNotes(db);

    // included: folio + explicit status='processed' + status_folio NULL
    const idProc = insertCapturedNote(db, { title: 'Folio: /x :: a.ts', content: 'c', content_hash: 'f1', created_at: '2026-05-01', capture_type: 'folio' });
    insertNoteState(db, idProc, { status: 'processed' }); // status_folio left NULL
    insertProcessed(db, idProc, { concepts: '["x"]', primary_theme: 'pt' });

    // included: folio + explicit status='archived'
    const idArch = insertCapturedNote(db, { title: 'Folio: /x :: b.ts', content: 'c', content_hash: 'f2', created_at: '2026-05-02', capture_type: 'folio' });
    insertNoteState(db, idArch, { status: 'archived' });

    // EXCLUDED: folio but NO note_state row -> status COALESCE -> 'pending' (the value-add proof)
    insertCapturedNote(db, { title: 'Folio: /x :: c.ts', content: 'c', content_hash: 'f3', created_at: '2026-05-03', capture_type: 'folio' });

    // EXCLUDED: folio + processed BUT status_folio already 'written'
    const idDone = insertCapturedNote(db, { title: 'Folio: /x :: d.ts', content: 'c', content_hash: 'f4', created_at: '2026-05-04', capture_type: 'folio' });
    insertNoteState(db, idDone, { status: 'processed', status_folio: 'written' });

    // EXCLUDED: processed + status_folio NULL but NOT capture_type 'folio'
    const idNonFolio = insertCapturedNote(db, { title: 'Ordinary note', content: 'c', content_hash: 'f5', created_at: '2026-05-05', capture_type: 'drafts' });
    insertNoteState(db, idNonFolio, { status: 'processed' });
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('selects only folio notes with processed/archived status and unset status_folio', () => {
    const titles = folioCandidatesMirror(db).map((r) => r.title).sort();
    expect(titles).toEqual(['Folio: /x :: a.ts', 'Folio: /x :: b.ts']);
    // The note_state-less folio note (status COALESCE -> 'pending') is correctly excluded.
    expect(titles).not.toContain('Folio: /x :: c.ts');
  });
});

// ── 5. routes/worksheets.ts — query-mirror of fetchReviewNotes, inbox_status-COALESCE distinction ─
//
// fetchReviewNotes() is module-local and bound to the singleton `db`, so a faithful mirror is the
// correct way to drive it against the fixture connection.
// QUERY-MIRROR of src/routes/worksheets.ts:18-26 (verbatim SELECT + testRunFilter()).
// Value-add: a fresh capture with NO note_state row must count as pending (inbox_status COALESCE
// -> 'pending') and be returned; one with explicit inbox_status='processed' must be excluded.

function fetchReviewNotesMirror(
  db: DB
): Array<{ id: number; title: string; content: string; created_at: string }> {
  return db
    .prepare(
      `SELECT id, title, content, created_at
       FROM raw_notes
       WHERE inbox_status = 'pending'
         ${testRunFilter()}
         AND created_at < datetime('now', '-1 day')
       ORDER BY created_at ASC
       LIMIT 3`
    )
    .all() as Array<{ id: number; title: string; content: string; created_at: string }>;
}

describe('worksheets fetchReviewNotes through the raw_notes view (query-mirror)', () => {
  let db: DB;
  let dir: string;
  // All seed notes are dated well before now so the `created_at < now-1day` clause never gates them.
  const old = '2026-01-01T00:00:00.000Z';

  beforeEach(() => {
    ({ db, dir } = makeTwoFileTestDb());

    // included: NO note_state row -> inbox_status COALESCE -> 'pending' (a fresh capture). VALUE-ADD.
    insertCapturedNote(db, { title: 'Fresh pending capture', content: 'aaa', content_hash: 'w1', created_at: old });

    // included: explicit inbox_status='pending'
    const idExplicit = insertCapturedNote(db, { title: 'Explicit pending', content: 'bbb', content_hash: 'w2', created_at: '2026-01-02T00:00:00.000Z' });
    insertNoteState(db, idExplicit, { inbox_status: 'pending' });

    // EXCLUDED: explicit inbox_status='processed'
    const idProcessed = insertCapturedNote(db, { title: 'Already triaged', content: 'ccc', content_hash: 'w3', created_at: '2026-01-03T00:00:00.000Z' });
    insertNoteState(db, idProcessed, { inbox_status: 'processed' });

    // EXCLUDED: pending (no note_state) BUT test_run set -> testRunFilter guard (production env)
    insertCapturedNote(db, { title: 'Test-run pending', content: 'ddd', content_hash: 'w4', created_at: '2026-01-04T00:00:00.000Z', test_run: 'dev-seed' });
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('returns pending-inbox notes incl. note_state-less fresh captures, excludes triaged + test_run', () => {
    const titles = fetchReviewNotesMirror(db).map((r) => r.title).sort();
    expect(titles).toEqual(['Explicit pending', 'Fresh pending capture']);
    // A fresh capture with no note_state row counts as pending via COALESCE — the hard requirement.
    expect(titles).toContain('Fresh pending capture');
    expect(titles).not.toContain('Already triaged');
    expect(titles).not.toContain('Test-run pending');
  });
});
