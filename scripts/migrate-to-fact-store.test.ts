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
  ensureNoteStateTable,
  ensureRawNotesView,
} from '../src/lib/facts-db';
import { migrateToFactStore } from './migrate-to-fact-store';

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
});
