/**
 * Task 8b — THE MIGRATION test.
 *
 * Drives `migrateToFactStore(dbPath, factsPath)` directly against throwaway temp DBs
 * (NEVER a real DB under ~/selene-data*). Builds an EXISTING single-file selene.db with a
 * PHYSICAL `raw_notes` table (the pre-split shape), seeds it, migrates, and asserts:
 *   - ids are PRESERVED into facts.captured_notes (id-explicit INSERT…SELECT),
 *   - per-id status survives into note_state and reads back through a fresh two-file view,
 *   - review_state migrated from pkm_review_state,
 *   - raw_notes becomes raw_notes_legacy_backup (no longer a physical raw_notes),
 *   - orphan/dangling asserts ROLLBACK on violation (negative test),
 *   - a fresh real insertNote gets id > max-migrated-id (sqlite_sequence continuity),
 *   - a 2nd run is a clean idempotent no-op.
 *
 * `insertNote` is imported from ../src/lib/db (item 6). db.ts opens its module singleton on
 * import, so — exactly as src/lib/db-capture.test.ts does — we redirect SELENE_DB_PATH /
 * SELENE_FACTS_DB_PATH to throwaway files and force SELENE_ENV=production BEFORE that import,
 * and restore the env in afterAll so this file can't pollute siblings in the same Jest worker.
 */
import Database from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';

// --- env redirect for the ../src/lib/db singleton (must precede its import) ---
const ENV_KEYS = ['SELENE_ENV', 'SELENE_DB_PATH', 'SELENE_FACTS_DB_PATH'] as const;
const savedEnv: Record<string, string | undefined> = {};
for (const k of ENV_KEYS) savedEnv[k] = process.env[k];

process.env.SELENE_ENV = 'production';
const singletonDir = mkdtempSync(join(tmpdir(), 'selene-migrate-singleton-'));
process.env.SELENE_DB_PATH = join(singletonDir, 'selene.db');
process.env.SELENE_FACTS_DB_PATH = join(singletonDir, 'facts.db');

import { insertNote } from '../src/lib/db';
import {
  attachFacts,
  ensureFactsDbInitialized,
  ensureNoteStateTable,
  ensureRawNotesView,
} from '../src/lib/facts-db';
import { migrateToFactStore, stripRawNotesFk } from './migrate-to-fact-store';

afterAll(() => {
  for (const k of ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
  rmSync(singletonDir, { recursive: true, force: true });
});

/**
 * Build a throwaway single-file selene.db with a PHYSICAL raw_notes table in the pre-split
 * shape. Seeds 3 fact columns + the 6 bookkeeping columns the migration intersects.
 * DELIBERATELY omits `exported_at` (a note_state DDL column) so the intersection logic is
 * exercised — it must be skipped, not break the SELECT.
 */
function buildLegacyDb(opts: { orphanProcessed?: boolean } = {}): { dir: string; dbPath: string; factsPath: string } {
  const dir = mkdtempSync(join(tmpdir(), 'selene-migrate-'));
  const dbPath = join(dir, 'selene.db');
  const factsPath = join(dir, 'facts.db');
  const db = new Database(dbPath);

  // PHYSICAL raw_notes: all 15 fact columns + 6 of the 7 bookkeeping columns (no exported_at).
  db.exec(`
    CREATE TABLE raw_notes (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      title            TEXT NOT NULL,
      content          TEXT NOT NULL,
      content_hash     TEXT NOT NULL,
      source_type      TEXT,
      word_count       INTEGER,
      character_count  INTEGER,
      tags             TEXT,
      created_at       DATETIME NOT NULL,
      imported_at      DATETIME,
      source_uuid      TEXT,
      calendar_event   TEXT,
      capture_type     TEXT,
      source_note_id   INTEGER,
      test_run         TEXT,
      -- bookkeeping (will move to note_state):
      status               TEXT,
      processed_at         DATETIME,
      exported_to_obsidian INTEGER,
      obsidian_export_hash TEXT,
      status_folio         TEXT,
      inbox_status         TEXT
    );
  `);

  const ins = db.prepare(`
    INSERT INTO raw_notes
      (id, title, content, content_hash, capture_type, created_at, source_note_id, test_run, status, exported_to_obsidian, obsidian_export_hash)
    VALUES (@id,@title,@content,@content_hash,@capture_type,@created_at,@source_note_id,@test_run,@status,@exported_to_obsidian,@obsidian_export_hash)
  `);
  // id=10: a root note (self-referenced by 20), pending
  ins.run({ id: 10, title: 'Root', content: 'root body', content_hash: 'h10', capture_type: 'drafts', created_at: '2026-01-01T00:00:00Z', source_note_id: null, test_run: null, status: 'pending', exported_to_obsidian: 0, obsidian_export_hash: null });
  // id=20: an annotation of 10 (source_note_id=10), processed, carries an export hash
  ins.run({ id: 20, title: 'Annotation', content: 'note about root', content_hash: 'h20', capture_type: 'eink', created_at: '2026-01-02T00:00:00Z', source_note_id: 10, test_run: null, status: 'processed', exported_to_obsidian: 1, obsidian_export_hash: 'export-hash-20' });
  // id=30: archived + a test_run marker
  ins.run({ id: 30, title: 'Archived', content: 'old', content_hash: 'h30', capture_type: 'drafts', created_at: '2026-01-03T00:00:00Z', source_note_id: null, test_run: 'x', status: 'archived', exported_to_obsidian: 0, obsidian_export_hash: null });

  // processed_notes referencing raw_note_id 20 and 30 (+ optional orphan for the negative test)
  db.exec(`CREATE TABLE processed_notes (raw_note_id INTEGER, concepts TEXT, primary_theme TEXT)`);
  db.prepare(`INSERT INTO processed_notes (raw_note_id, primary_theme) VALUES (?, ?)`).run(20, 'work');
  db.prepare(`INSERT INTO processed_notes (raw_note_id, primary_theme) VALUES (?, ?)`).run(30, 'life');
  if (opts.orphanProcessed) {
    db.prepare(`INSERT INTO processed_notes (raw_note_id, primary_theme) VALUES (?, ?)`).run(999, 'ghost');
  }

  // pkm_review_state with 2 rows → migrates to facts.review_state
  db.exec(`
    CREATE TABLE pkm_review_state (
      entity_type      TEXT NOT NULL,
      entity_id        TEXT NOT NULL,
      last_surfaced_at TEXT,
      surface_count    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (entity_type, entity_id)
    );
  `);
  db.prepare(`INSERT INTO pkm_review_state (entity_type, entity_id, last_surfaced_at, surface_count) VALUES (?,?,?,?)`).run('note', '20', '2026-01-05T00:00:00Z', 3);
  db.prepare(`INSERT INTO pkm_review_state (entity_type, entity_id, last_surfaced_at, surface_count) VALUES (?,?,?,?)`).run('category', 'work', null, 0);

  db.close();
  return { dir, dbPath, factsPath };
}

/** Open the migrated layout as a real two-file connection (attach + note_state + view). */
function openTwoFile(dbPath: string, factsPath: string): Database.Database {
  const db = new Database(dbPath);
  attachFacts(db, factsPath);
  ensureNoteStateTable(db);
  ensureRawNotesView(db);
  return db;
}

describe('migrateToFactStore — single file → two files (id-preserving, transactional)', () => {
  it('preserves ids into facts.captured_notes and preserves content_hash', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    const result = migrateToFactStore(dbPath, factsPath);
    expect(result.alreadyMigrated).toBe(false);
    expect(result.notes).toBe(3);

    const facts = new Database(factsPath);
    const ids = (facts.prepare(`SELECT id FROM captured_notes ORDER BY id`).all() as { id: number }[]).map(r => r.id);
    expect(ids).toEqual([10, 20, 30]); // IDS PRESERVED — not re-autoincremented

    const hashes = Object.fromEntries(
      (facts.prepare(`SELECT id, content_hash FROM captured_notes`).all() as { id: number; content_hash: string }[])
        .map(r => [r.id, r.content_hash])
    );
    expect(hashes).toEqual({ 10: 'h10', 20: 'h20', 30: 'h30' });
    facts.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('moves bookkeeping into note_state and reads back per-id status through a fresh view (self-ref + test_run survive)', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    migrateToFactStore(dbPath, factsPath);

    const db = openTwoFile(dbPath, factsPath);
    const stateRows = Object.fromEntries(
      (db.prepare(`SELECT raw_note_id, status FROM note_state`).all() as { raw_note_id: number; status: string }[])
        .map(r => [r.raw_note_id, r.status])
    );
    expect(stateRows).toEqual({ 10: 'pending', 20: 'processed', 30: 'archived' });

    // Read back through the raw_notes VIEW — status COALESCEs from note_state.
    const viewStatus = Object.fromEntries(
      (db.prepare(`SELECT id, status FROM raw_notes`).all() as { id: number; status: string }[])
        .map(r => [r.id, r.status])
    );
    expect(viewStatus).toEqual({ 10: 'pending', 20: 'processed', 30: 'archived' });

    // The self-ref (20→10) and the test_run marker survive into the facts.
    const ann = db.prepare(`SELECT source_note_id FROM raw_notes WHERE id = 20`).get() as { source_note_id: number };
    expect(ann.source_note_id).toBe(10);
    const archived = db.prepare(`SELECT test_run FROM raw_notes WHERE id = 30`).get() as { test_run: string };
    expect(archived.test_run).toBe('x');

    // The migrated obsidian_export_hash for id=20 reads back through the view.
    const exported = db.prepare(`SELECT obsidian_export_hash FROM raw_notes WHERE id = 20`).get() as { obsidian_export_hash: string };
    expect(exported.obsidian_export_hash).toBe('export-hash-20');

    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('migrates pkm_review_state into facts.review_state (count === 2)', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    const result = migrateToFactStore(dbPath, factsPath);
    expect(result.reviewRows).toBe(2);

    const facts = new Database(factsPath);
    const n = (facts.prepare(`SELECT COUNT(*) AS n FROM review_state`).get() as { n: number }).n;
    expect(n).toBe(2);
    const noteRow = facts.prepare(`SELECT surface_count FROM review_state WHERE entity_type='note' AND entity_id='20'`).get() as { surface_count: number };
    expect(noteRow.surface_count).toBe(3);
    facts.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('renames raw_notes → raw_notes_legacy_backup (3 rows); raw_notes is no longer a physical table', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    migrateToFactStore(dbPath, factsPath);

    const db = new Database(dbPath);
    const backup = db.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes_legacy_backup'`).get() as { type: string } | undefined;
    expect(backup?.type).toBe('table');
    const backupCount = (db.prepare(`SELECT COUNT(*) AS n FROM raw_notes_legacy_backup`).get() as { n: number }).n;
    expect(backupCount).toBe(3);

    // No physical raw_notes table remains (the per-connection TEMP view is created at runtime).
    const physical = db.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes'`).get() as { type: string } | undefined;
    expect(physical).toBeUndefined();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('NEGATIVE: an orphan processed_notes row makes the migration THROW and ROLLBACK (nothing moved, raw_notes still physical)', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb({ orphanProcessed: true });
    expect(() => migrateToFactStore(dbPath, factsPath)).toThrow();

    // Rollback proof: captured_notes empty, raw_notes still a physical table, no backup.
    const facts = new Database(factsPath);
    const factCount = (facts.prepare(`SELECT COUNT(*) AS n FROM captured_notes`).get() as { n: number }).n;
    expect(factCount).toBe(0);
    facts.close();

    const db = new Database(dbPath);
    const physical = db.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes'`).get() as { type: string } | undefined;
    expect(physical?.type).toBe('table'); // RENAME was inside the txn → rolled back
    const backup = db.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes_legacy_backup'`).get() as { type: string } | undefined;
    expect(backup).toBeUndefined();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('FRESH-INSERT id safety: a real insertNote after migration gets id > max-migrated-id (sqlite_sequence continuity)', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    migrateToFactStore(dbPath, factsPath);

    // facts.sqlite_sequence must carry captured_notes at >= max migrated id (30).
    const facts = new Database(factsPath);
    const seqRow = facts.prepare(`SELECT seq FROM sqlite_sequence WHERE name='captured_notes'`).get() as { seq: number } | undefined;
    expect(seqRow).toBeDefined();
    expect(seqRow!.seq).toBe(30);
    facts.close();

    const db = openTwoFile(dbPath, factsPath);
    const newId = insertNote(
      { title: 'After', content: 'fresh', contentHash: 'h-after', tags: [], createdAt: '2026-02-01T00:00:00Z' },
      db
    );
    expect(newId).toBeGreaterThan(30); // cannot collide with a migrated id
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('IDEMPOTENT: a 2nd run is a clean no-op ({alreadyMigrated:true}, no duplicates, no throw)', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    migrateToFactStore(dbPath, factsPath);
    const second = migrateToFactStore(dbPath, factsPath);
    expect(second.alreadyMigrated).toBe(true);

    const facts = new Database(factsPath);
    const n = (facts.prepare(`SELECT COUNT(*) AS n FROM captured_notes`).get() as { n: number }).n;
    expect(n).toBe(3); // not duplicated
    facts.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('CRASH-ATOMIC: after a successful migration both files re-open and read back equal counts (DELETE journal mode did not break the path)', () => {
    const { dir, dbPath, factsPath } = buildLegacyDb();
    const result = migrateToFactStore(dbPath, factsPath);
    expect(result.alreadyMigrated).toBe(false);
    expect(result.notes).toBe(3);

    // Re-open BOTH files fresh and confirm the backup ↔ facts counts agree (3 == 3).
    const main = new Database(dbPath);
    const backupCount = (main.prepare(`SELECT COUNT(*) AS n FROM raw_notes_legacy_backup`).get() as { n: number }).n;
    main.close();
    const facts = new Database(factsPath);
    const factCount = (facts.prepare(`SELECT COUNT(*) AS n FROM captured_notes`).get() as { n: number }).n;
    facts.close();
    expect(backupCount).toBe(3);
    expect(factCount).toBe(3);

    rmSync(dir, { recursive: true, force: true });
  });

  it('STALE-note_state: a pre-existing wrong-shaped note_state (missing inbox_status) is DROPPED + recreated, not merged — migration SUCCEEDS and rows carry correct status/inbox_status', () => {
    // Real-world pollution: a physical raw_notes (correct shape) PLUS a stale note_state left
    // by an earlier run with an older schema that predates the inbox_status column. The stale
    // table here has EVERY column ensureNoteStateTable creates EXCEPT inbox_status, so the
    // pre-fix INSERT fails precisely on "no column named inbox_status" (the reported bug).
    const dir = mkdtempSync(join(tmpdir(), 'selene-migrate-stale-'));
    const dbPath = join(dir, 'selene.db');
    const factsPath = join(dir, 'facts.db');
    const db = new Database(dbPath);

    db.exec(`
      CREATE TABLE raw_notes (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        title            TEXT NOT NULL,
        content          TEXT NOT NULL,
        content_hash     TEXT NOT NULL,
        source_type      TEXT,
        word_count       INTEGER,
        character_count  INTEGER,
        tags             TEXT,
        created_at       DATETIME NOT NULL,
        imported_at      DATETIME,
        source_uuid      TEXT,
        calendar_event   TEXT,
        capture_type     TEXT,
        source_note_id   INTEGER,
        test_run         TEXT,
        status               TEXT,
        processed_at         DATETIME,
        exported_at          DATETIME,
        exported_to_obsidian INTEGER,
        obsidian_export_hash TEXT,
        status_folio         TEXT,
        inbox_status         TEXT
      );
    `);
    db.prepare(`
      INSERT INTO raw_notes (id, title, content, content_hash, capture_type, created_at, status, inbox_status)
      VALUES (?,?,?,?,?,?,?,?)
    `).run(10, 'Polluted', 'body', 'h10', 'drafts', '2026-01-01T00:00:00Z', 'processed', 'reviewed');

    // STALE note_state: same shape ensureNoteStateTable makes MINUS inbox_status. Seed a BOGUS
    // status so that if it were merged (kept) instead of dropped, the migrated status would be
    // wrong — proving "replaced, not merged", not merely "didn't throw".
    db.exec(`
      CREATE TABLE note_state (
        raw_note_id INTEGER PRIMARY KEY,
        status TEXT,
        processed_at DATETIME,
        exported_at DATETIME,
        exported_to_obsidian INTEGER,
        obsidian_export_hash TEXT,
        status_folio TEXT
      );
    `);
    db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (?, ?)`).run(10, 'STALE-WRONG');
    db.close();

    // Pre-fix this THROWS "no column named inbox_status"; post-fix it must SUCCEED.
    const result = migrateToFactStore(dbPath, factsPath);
    expect(result.alreadyMigrated).toBe(false);
    expect(result.notes).toBe(1);

    // The recreated note_state must HAVE the inbox_status column (PRAGMA table_info).
    const main = new Database(dbPath);
    const cols = (main.prepare(`PRAGMA table_info(note_state)`).all() as { name: string }[]).map(r => r.name);
    expect(cols).toContain('inbox_status');
    main.close();

    // Migrated rows carry the status/inbox_status from raw_notes (NOT the bogus stale status).
    const two = openTwoFile(dbPath, factsPath);
    const row = two.prepare(`SELECT status, inbox_status FROM raw_notes WHERE id = 10`).get() as { status: string; inbox_status: string };
    expect(row.status).toBe('processed');     // from raw_notes, not 'STALE-WRONG'
    expect(row.inbox_status).toBe('reviewed'); // flowed through the recreated table (not NULL→'pending')
    two.close();

    rmSync(dir, { recursive: true, force: true });
  });

  it('INCOMPLETE-STATE: backup table exists but facts.captured_notes is EMPTY → THROWS "Incomplete prior migration" (not a silent no-op)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'selene-migrate-partial-'));
    const dbPath = join(dir, 'selene.db');
    const factsPath = join(dir, 'facts.db');

    // Simulate a crash that committed the RENAME but not the facts inserts: a populated
    // raw_notes_legacy_backup (3 rows) in main, and a facts.db whose captured_notes is EMPTY.
    const main = new Database(dbPath);
    main.exec(`
      CREATE TABLE raw_notes_legacy_backup (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        created_at DATETIME NOT NULL
      );
    `);
    const ins = main.prepare(
      `INSERT INTO raw_notes_legacy_backup (id, title, content, content_hash, created_at) VALUES (?,?,?,?,?)`
    );
    ins.run(10, 'Root', 'root body', 'h10', '2026-01-01T00:00:00Z');
    ins.run(20, 'Annotation', 'note about root', 'h20', '2026-01-02T00:00:00Z');
    ins.run(30, 'Archived', 'old', 'h30', '2026-01-03T00:00:00Z');
    main.close();
    // facts.db exists with the schema but captured_notes is empty (inserts never ran).
    ensureFactsDbInitialized(factsPath);

    expect(() => migrateToFactStore(dbPath, factsPath)).toThrow(/Incomplete prior migration/);
    // And it must NOT report success in any form.
    let threw = false;
    try {
      migrateToFactStore(dbPath, factsPath);
    } catch {
      threw = true;
    }
    expect(threw).toBe(true);

    rmSync(dir, { recursive: true, force: true });
  });
});

// =============================================================================
// stripRawNotesFk — pure DDL surgery, unit-tested against the REAL forms.
//
// The migration RENAMEs raw_notes → raw_notes_legacy_backup; SQLite (>=3.25,
// legacy_alter_table OFF) AUTO-REWRITES every child FK that referenced raw_notes to
// point at the FROZEN backup. So the live derived tables (processed_notes,
// note_embeddings) must be rebuilt WITHOUT their raw_notes FK before the rename. This
// pure helper does the DDL transform; assert it strips ONLY the raw_notes FK and keeps
// every other column/constraint/index intent intact.
// =============================================================================
describe('stripRawNotesFk — removes ONLY the raw_notes FK, both DDL forms', () => {
  it('TABLE-LEVEL, no ON DELETE (real processed_notes shape): drops the FK + its trailing comma, keeps the CHECK', () => {
    const sql = `CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    things_integration_status TEXT
        CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))
        DEFAULT 'pending', category TEXT, essence TEXT,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
)`;
    const out = stripRawNotesFk(sql);
    // raw_notes is gone entirely.
    expect(out).not.toMatch(/raw_notes\s*\(/i);
    expect(out.toLowerCase()).not.toContain('foreign key');
    // The unrelated CHECK / columns survive verbatim.
    expect(out).toContain("CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))");
    expect(out).toContain('category TEXT');
    expect(out).toContain('essence TEXT');
    expect(out).toContain('raw_note_id INTEGER NOT NULL');
    // No dangling comma left immediately before the closing paren.
    expect(out).not.toMatch(/,\s*\)\s*$/);
    // Result is still valid DDL: SQLite accepts it.
    const db = new Database(':memory:');
    expect(() => db.exec(out)).not.toThrow();
    db.close();
  });

  it('TABLE-LEVEL with ON DELETE CASCADE (real note_embeddings shape): drops FK incl. ON DELETE, keeps UNIQUE column', () => {
    const sql = `CREATE TABLE note_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,
    model_version TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
)`;
    const out = stripRawNotesFk(sql);
    expect(out).not.toMatch(/raw_notes\s*\(/i);
    expect(out.toLowerCase()).not.toContain('foreign key');
    expect(out.toLowerCase()).not.toContain('on delete');
    // The inline UNIQUE on raw_note_id (a column constraint, NOT the FK) is preserved.
    expect(out).toContain('raw_note_id INTEGER NOT NULL UNIQUE');
    expect(out).toContain('embedding BLOB NOT NULL');
    expect(out).not.toMatch(/,\s*\)\s*$/);
    const db = new Database(':memory:');
    expect(() => db.exec(out)).not.toThrow();
    db.close();
  });

  it('INLINE column form: keeps the column type, drops the REFERENCES clause (and ON DELETE)', () => {
    const sql = `CREATE TABLE t (
    id INTEGER PRIMARY KEY,
    raw_note_id INTEGER REFERENCES raw_notes(id) ON DELETE CASCADE,
    note TEXT
)`;
    const out = stripRawNotesFk(sql);
    expect(out).not.toMatch(/raw_notes\s*\(/i);
    expect(out.toLowerCase()).not.toContain('references');
    expect(out.toLowerCase()).not.toContain('on delete');
    // The column itself stays, just without the REFERENCES tail.
    expect(out).toMatch(/raw_note_id\s+INTEGER/i);
    expect(out).toContain('note TEXT');
    const db = new Database(':memory:');
    expect(() => db.exec(out)).not.toThrow();
    db.close();
  });

  it('preserves a foreign key to a NON-raw_notes table (must not over-strip)', () => {
    const sql = `CREATE TABLE thing (
    id INTEGER PRIMARY KEY,
    raw_note_id INTEGER NOT NULL,
    thread_id INTEGER NOT NULL,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
)`;
    const out = stripRawNotesFk(sql);
    // raw_notes FK gone…
    expect(out).not.toMatch(/raw_notes\s*\(/i);
    // …but the threads FK kept intact.
    expect(out).toContain('FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE');
    const db = new Database(':memory:');
    db.exec(`CREATE TABLE threads (id INTEGER PRIMARY KEY)`);
    expect(() => db.exec(out)).not.toThrow();
    db.close();
  });

  it('is a no-op on DDL that has no raw_notes FK', () => {
    const sql = `CREATE TABLE plain (id INTEGER PRIMARY KEY, x TEXT)`;
    expect(stripRawNotesFk(sql)).toBe(sql);
  });
});

// =============================================================================
// THE COVERAGE-GAP TEST that would have caught the ship-blocker: after migrating,
// inserting a derived row (processed_notes / note_embeddings) for a FRESH captured_notes
// id — one NOT in the frozen raw_notes_legacy_backup — must SUCCEED with foreign_keys=ON.
// Pre-fix the rewritten FK→backup throws SQLITE_CONSTRAINT_FOREIGNKEY; post-fix it passes.
// The seeded legacy DB carries the REAL FK so the strip is genuinely exercised.
// =============================================================================
describe('post-migration fresh derived insert (FK-strip regression)', () => {
  /**
   * Build a legacy single-file DB whose processed_notes + note_embeddings carry the SAME
   * raw_notes FK as production (so the migration's strip must remove it). Seeds raw_notes
   * with ids 10,20 and a processed_notes/note_embeddings row referencing 20.
   */
  function buildLegacyWithFkDerived(): { dir: string; dbPath: string; factsPath: string } {
    const dir = mkdtempSync(join(tmpdir(), 'selene-migrate-fk-'));
    const dbPath = join(dir, 'selene.db');
    const factsPath = join(dir, 'facts.db');
    const db = new Database(dbPath);
    db.exec(`
      CREATE TABLE raw_notes (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        title            TEXT NOT NULL,
        content          TEXT NOT NULL,
        content_hash     TEXT NOT NULL,
        source_type      TEXT,
        word_count       INTEGER,
        character_count  INTEGER,
        tags             TEXT,
        created_at       DATETIME NOT NULL,
        imported_at      DATETIME,
        source_uuid      TEXT,
        calendar_event   TEXT,
        capture_type     TEXT,
        source_note_id   INTEGER,
        test_run         TEXT,
        status               TEXT,
        processed_at         DATETIME,
        exported_at          DATETIME,
        exported_to_obsidian INTEGER,
        obsidian_export_hash TEXT,
        status_folio         TEXT,
        inbox_status         TEXT
      );
    `);
    const ins = db.prepare(
      `INSERT INTO raw_notes (id, title, content, content_hash, created_at, status) VALUES (?,?,?,?,?,?)`
    );
    ins.run(10, 'Root', 'root body', 'h10', '2026-01-01T00:00:00Z', 'pending');
    ins.run(20, 'Proc', 'processed body', 'h20', '2026-01-02T00:00:00Z', 'processed');

    // processed_notes — REAL production shape (table-level FK, no ON DELETE, CHECK + indexes).
    db.exec(`
      CREATE TABLE processed_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_note_id INTEGER NOT NULL,
        concepts TEXT,
        primary_theme TEXT,
        processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        things_integration_status TEXT
            CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))
            DEFAULT 'pending',
        category TEXT, essence TEXT, essence_at TEXT,
        FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
      );
      CREATE INDEX idx_processed_notes_raw_id ON processed_notes(raw_note_id);
    `);
    db.prepare(`INSERT INTO processed_notes (raw_note_id, primary_theme) VALUES (?, ?)`).run(20, 'work');

    // note_embeddings — REAL production shape (table-level FK ON DELETE CASCADE, UNIQUE col, index).
    db.exec(`
      CREATE TABLE note_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_note_id INTEGER NOT NULL UNIQUE,
        embedding BLOB NOT NULL,
        model_version TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
      );
      CREATE INDEX idx_embeddings_note ON note_embeddings(raw_note_id);
    `);
    db.prepare(`INSERT INTO note_embeddings (raw_note_id, embedding, model_version) VALUES (?, ?, ?)`)
      .run(20, Buffer.from([1, 2, 3]), 'nomic-embed-text');

    db.close();
    return { dir, dbPath, factsPath };
  }

  it('processed_notes + note_embeddings rows for a FRESH (post-migration) note id insert cleanly with foreign_keys=ON', () => {
    const { dir, dbPath, factsPath } = buildLegacyWithFkDerived();
    const result = migrateToFactStore(dbPath, factsPath);
    expect(result.alreadyMigrated).toBe(false);
    expect(result.notes).toBe(2);

    // Fresh two-file connection with foreign_keys=ON (better-sqlite3 default), attach + view.
    const db = openTwoFile(dbPath, factsPath);
    expect((db.pragma('foreign_keys', { simple: true }) as number)).toBe(1);

    // A genuinely NEW note: insert it as a FACT (id NOT in raw_notes_legacy_backup).
    const freshId = insertNote(
      { title: 'Fresh', content: 'brand new', contentHash: 'h-fresh', tags: [], createdAt: '2026-03-01T00:00:00Z' },
      db
    );
    expect(freshId).toBeGreaterThan(20);
    // Sanity: that id is absent from the frozen backup.
    const inBackup = (db.prepare(`SELECT COUNT(*) AS n FROM raw_notes_legacy_backup WHERE id = ?`).get(freshId) as { n: number }).n;
    expect(inBackup).toBe(0);

    // THE ASSERTIONS: both derived inserts for the fresh id must NOT throw a FK error.
    expect(() =>
      db.prepare(`INSERT INTO processed_notes (raw_note_id, primary_theme) VALUES (?, ?)`).run(freshId, 'fresh-theme')
    ).not.toThrow();
    expect(() =>
      db
        .prepare(`INSERT OR REPLACE INTO note_embeddings (raw_note_id, embedding, model_version) VALUES (?, ?, ?)`)
        .run(freshId, Buffer.from([9, 9, 9]), 'nomic-embed-text')
    ).not.toThrow();

    // And they actually landed.
    expect((db.prepare(`SELECT COUNT(*) AS n FROM processed_notes WHERE raw_note_id = ?`).get(freshId) as { n: number }).n).toBe(1);
    expect((db.prepare(`SELECT COUNT(*) AS n FROM note_embeddings WHERE raw_note_id = ?`).get(freshId) as { n: number }).n).toBe(1);

    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('the migrated derived tables retain their pre-migration columns, indexes, CHECK, and pre-existing rows', () => {
    const { dir, dbPath, factsPath } = buildLegacyWithFkDerived();
    migrateToFactStore(dbPath, factsPath);

    const db = new Database(dbPath);
    // Columns preserved (processed_notes).
    const pcols = (db.prepare(`PRAGMA table_info(processed_notes)`).all() as { name: string }[]).map(r => r.name);
    expect(pcols).toEqual(
      expect.arrayContaining(['id', 'raw_note_id', 'concepts', 'primary_theme', 'processed_at', 'things_integration_status', 'category', 'essence', 'essence_at'])
    );
    // The index survives the rebuild.
    const pidx = (db.prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='processed_notes'`).all() as { name: string }[]).map(r => r.name);
    expect(pidx).toContain('idx_processed_notes_raw_id');
    // The CHECK constraint is still enforced (bad value rejected).
    expect(() =>
      db.prepare(`INSERT INTO processed_notes (raw_note_id, things_integration_status) VALUES (?, ?)`).run(20, 'BOGUS')
    ).toThrow();
    // Pre-existing row preserved.
    expect((db.prepare(`SELECT COUNT(*) AS n FROM processed_notes WHERE raw_note_id = 20`).get() as { n: number }).n).toBe(1);

    // note_embeddings: columns + UNIQUE + index preserved, original row intact.
    const ecols = (db.prepare(`PRAGMA table_info(note_embeddings)`).all() as { name: string }[]).map(r => r.name);
    expect(ecols).toEqual(expect.arrayContaining(['id', 'raw_note_id', 'embedding', 'model_version', 'created_at']));
    const eidx = (db.prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='note_embeddings'`).all() as { name: string }[]).map(r => r.name);
    expect(eidx).toContain('idx_embeddings_note');
    expect((db.prepare(`SELECT COUNT(*) AS n FROM note_embeddings WHERE raw_note_id = 20`).get() as { n: number }).n).toBe(1);
    // Neither rebuilt table references raw_notes anymore.
    const psql = (db.prepare(`SELECT sql FROM sqlite_master WHERE name='processed_notes'`).get() as { sql: string }).sql;
    const esql = (db.prepare(`SELECT sql FROM sqlite_master WHERE name='note_embeddings'`).get() as { sql: string }).sql;
    expect(psql.toLowerCase()).not.toContain('raw_notes');
    expect(esql.toLowerCase()).not.toContain('raw_notes');
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });
});
