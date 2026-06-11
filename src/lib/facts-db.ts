/**
 * facts.db — schema for the precious, immutable fact store.
 *
 * `facts.db` owns three tables: `captured_notes` (the immutable note facts — the durable
 * subset of today's `raw_notes`), `review_state` (human review flags, migrated later
 * from today's `pkm_review_state`), and `note_feedback` (free-text author intent from the
 * Obsidian feedback loop). A later task ATTACHes `facts.db` and calls this once;
 * this module is pure schema with NO connection logic and touches NO real data.
 *
 * Takes an explicit `db` (no module singleton) so it's unit-testable in-memory, matching
 * src/lib/pkm-db.ts.
 */
import Database from 'better-sqlite3';
import type { Database as DB } from 'better-sqlite3';
import { applyConnectionPragmas } from './db-config';

/** Idempotent schema init (CREATE TABLE/INDEX IF NOT EXISTS). */
export function initFactsSchema(db: DB): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS captured_notes (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      title            TEXT NOT NULL,
      content          TEXT NOT NULL,
      content_hash     TEXT NOT NULL,
      source_type      TEXT,
      word_count       INTEGER,
      character_count  INTEGER,
      tags             TEXT,
      created_at       DATETIME NOT NULL,
      imported_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
      source_uuid      TEXT,
      calendar_event   TEXT,
      capture_type     TEXT,
      source_note_id   INTEGER,
      test_run         TEXT
    );

    CREATE TABLE IF NOT EXISTS review_state (
      entity_type      TEXT NOT NULL,
      entity_id        TEXT NOT NULL,
      last_surfaced_at TEXT,
      surface_count    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (entity_type, entity_id)
    );

    -- Obsidian feedback loop (2026-06-10 design): free-text author intent captured from the
    -- vault's "Your note" sections. PRECIOUS — human words; survives rebuild by living here.
    -- raw_note_id = captured_notes.id (facts.db is never rebuilt, so the id is stable).
    CREATE TABLE IF NOT EXISTS note_feedback (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      raw_note_id     INTEGER NOT NULL,
      feedback_text   TEXT NOT NULL,
      original_filing TEXT,
      created_at      DATETIME NOT NULL,
      applied_at      DATETIME
    );
    CREATE INDEX IF NOT EXISTS idx_note_feedback_note ON note_feedback(raw_note_id);
    -- UNIQUE dedupe guard: two scanners run scanVaultFeedback concurrently (15-min vault-feedback
    -- agent + hourly export's pre-render scan); a SELECT-then-INSERT check alone lets both pass
    -- and double-insert into this never-rebuilt store. The captured_notes indexes below are
    -- non-unique to tolerate historical duplicates in migrated data — that rationale does NOT
    -- apply here: note_feedback is brand-new with no prod rows, so adding UNIQUE via IF NOT
    -- EXISTS cannot hit existing dups (it would throw at init if a table somehow had them).
    CREATE UNIQUE INDEX IF NOT EXISTS idx_note_feedback_dedupe
      ON note_feedback(raw_note_id, feedback_text);

    -- Non-unique lookup indexes (dedup/lookup parity). NON-unique on purpose so the later
    -- data migration can't fail on any historical duplicates.
    CREATE INDEX IF NOT EXISTS idx_captured_content_hash ON captured_notes(content_hash);
    CREATE INDEX IF NOT EXISTS idx_captured_source_uuid ON captured_notes(source_uuid);

    -- review_state moved into facts.db (precious) in Task 9: the browse layer's
    -- least-recently-surfaced ordering scans last_surfaced_at, so mirror the old
    -- idx_pkm_review_last index here (Task 2 omitted it when seeding the schema).
    CREATE INDEX IF NOT EXISTS idx_review_state_last ON review_state(last_surfaced_at);
  `);
}

/**
 * `note_state` lives in selene.db (main) — the disposable, derivable pipeline bookkeeping
 * keyed to `captured_notes.id`. Separated from the precious facts so the whole row's
 * processing/export state can be rebuilt without touching the immutable note.
 */
export function ensureNoteStateTable(db: DB): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS note_state (
      raw_note_id INTEGER PRIMARY KEY,
      status TEXT,
      processed_at DATETIME,
      exported_at DATETIME,
      exported_to_obsidian INTEGER,
      obsidian_export_hash TEXT,
      status_folio TEXT,
      inbox_status TEXT
    );
  `);
}

/**
 * Backward-compatible `raw_notes` VIEW so the existing readers keep working unchanged once
 * the data lives in `facts.captured_notes` + `note_state`.
 *
 * GUARDED: if a physical `raw_notes` TABLE still exists (an un-migrated DB), this is a no-op —
 * we leave the table alone; the later data migration (Task 8) converts it. We only (re)create
 * the view when `raw_notes` is absent or already a view, so the app never crashes mid-migration.
 *
 * The DDL hard-codes the `facts.` attach alias, so the connection must `attachFacts` first.
 *
 * Per-connection TEMP view: SQLite forbids a PERSISTENT view in `main` from referencing an
 * attached database ("view ... cannot reference objects in database facts"), since a stored
 * view must stay valid even when nothing is attached. A TEMP view is exempt (it lives only for
 * the connection, created after ATTACH). So every connection that reads `raw_notes` must run
 * `attachFacts` + `ensureRawNotesView` together.
 */
export function ensureRawNotesView(db: DB): void {
  const existing = db.prepare(
    `SELECT type FROM sqlite_master WHERE name = 'raw_notes'`
  ).get() as { type: string } | undefined;
  if (existing && existing.type === 'table') return; // un-migrated; Task 8 converts it
  db.exec(`
    DROP VIEW IF EXISTS raw_notes;
    CREATE TEMP VIEW raw_notes AS
      SELECT cn.id, cn.title, cn.content, cn.content_hash, cn.source_type,
             cn.word_count, cn.character_count, cn.tags, cn.created_at, cn.imported_at,
             cn.source_uuid, cn.calendar_event, cn.capture_type, cn.source_note_id, cn.test_run,
             COALESCE(ns.status, 'pending') AS status,
             COALESCE(ns.inbox_status, 'pending') AS inbox_status,
             ns.processed_at, ns.exported_at,
             ns.exported_to_obsidian, ns.obsidian_export_hash, ns.status_folio
      FROM facts.captured_notes cn
      LEFT JOIN note_state ns ON ns.raw_note_id = cn.id;
  `);
}

/**
 * Ensure `facts.db` exists with its schema. Opens it as a STANDALONE connection so the
 * UNQUALIFIED `CREATE TABLE`s in `initFactsSchema` land in `facts.db`'s own `main` schema
 * (NOT in selene.db). Safe to call repeatedly — the schema is all IF NOT EXISTS.
 */
export function ensureFactsDbInitialized(factsPath: string): void {
  const f = new Database(factsPath);
  applyConnectionPragmas(f);
  initFactsSchema(f);
  f.close();
}

/**
 * Attach `facts.db` to an existing selene connection under the alias `facts` (the view DDL
 * depends on this exact alias). `busy_timeout` is per-connection (already covers the attached
 * db); `journal_mode = WAL` is per-file, so set it on the attached file too — best-effort,
 * since in-memory/test databases can't go WAL.
 */
export function attachFacts(db: DB, factsPath: string): void {
  db.prepare(`ATTACH DATABASE ? AS facts`).run(factsPath);
  try {
    db.pragma(`facts.journal_mode = WAL`);
  } catch {
    /* memory/test dbs: best-effort */
  }
}
