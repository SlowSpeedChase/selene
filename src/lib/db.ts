import type { Database as DatabaseType } from 'better-sqlite3';
import { config } from './config';
import { logger } from './logger';
import { openSeleneConnection } from './open-selene-connection';
import { setNoteState } from './note-state';
import { ensureMigrated } from './ensure-migrated';
import type { CalendarEvent } from '../types';

// Self-heal an un-migrated dev DB / fail loud on un-migrated prod, BEFORE opening the long-lived
// connection (so the migration's journal_mode=DELETE has no competing handle). Skipped under jest:
// tests import db.ts against the real dev DB, and config.env is 'development' under jest, so an
// unguarded call here would auto-migrate the real dev DB. jest sets JEST_WORKER_ID (see
// db-guard.test.ts, which pins that contract).
if (!process.env.JEST_WORKER_ID) {
  ensureMigrated(config.dbPath, config.factsDbPath, config.env);
}

// Initialize database connection via the canonical opener — the ONE true way to build a
// raw_notes-view-capable connection (applyConnectionPragmas → ensureFactsDbInitialized →
// attachFacts → ensureNoteStateTable → ensureRawNotesView, in that load-bearing order: the
// view DDL hard-codes the `facts.` alias, so ATTACH must precede it). This replaces the inline
// re-implementation of that exact sequence.
export const db: DatabaseType = openSeleneConnection(config.dbPath, config.factsDbPath);

logger.info({ dbPath: config.dbPath, env: config.env }, 'Database connected');

// Fail-safe: Verify non-production environment is using correct database
if (config.isTestEnv || config.isDevEnv) {
  const expectedEnv = config.env; // 'test' or 'development'
  try {
    const result = db.prepare(
      "SELECT value FROM _selene_metadata WHERE key = 'environment'"
    ).get() as { value: string } | undefined;

    if (!result || result.value !== expectedEnv) {
      logger.error(
        { dbPath: config.dbPath, expected: expectedEnv, actual: result?.value },
        `SELENE_ENV=${expectedEnv} but database environment mismatch. Run scripts/create-dev-db.sh first.`
      );
      throw new Error(
        `SELENE_ENV=${expectedEnv} but database is not marked as ${expectedEnv} environment.\n` +
        `Expected _selene_metadata.environment = '${expectedEnv}'.\n` +
        `Run scripts/create-dev-db.sh to create the database.`
      );
    }

    logger.info({ env: expectedEnv }, 'Environment verified');
  } catch (err: unknown) {
    if (err instanceof Error && err.message.includes('no such table')) {
      logger.error(
        { dbPath: config.dbPath },
        `SELENE_ENV=${expectedEnv} but _selene_metadata table not found. Run scripts/create-dev-db.sh first.`
      );
      throw new Error(
        `SELENE_ENV=${expectedEnv} but _selene_metadata table not found.\n` +
        `Run scripts/create-dev-db.sh to create the database.`
      );
    }
    throw err;
  }
}

// Type for raw_notes table
export interface RawNote {
  id: number;
  title: string;
  content: string;
  content_hash: string;
  source_type: string;
  word_count: number;
  character_count: number;
  tags: string | null;
  created_at: string;
  imported_at: string;
  processed_at: string | null;
  exported_at: string | null;
  status: string;
  exported_to_obsidian: number;
  test_run: string | null;
  calendar_event: string | null;
  capture_type: string;
  source_note_id: number | null;
}

// Helper: Get pending notes for processing
// Fact-store split: the SQL is unchanged, but through the `raw_notes` view `status` is
// COALESCE(ns.status,'pending') — so a captured note with no note_state row is automatically
// 'pending' (derivation-absence). `conn` is a DI param (mirroring insertNote/markProcessed)
// so tests can drive an explicit two-file connection.
export function getPendingNotes(limit = 10, conn: DatabaseType = db): RawNote[] {
  return conn
    .prepare('SELECT * FROM raw_notes WHERE status = ? ORDER BY created_at ASC LIMIT ?')
    .all('pending', limit) as RawNote[];
}

// Helper: Mark note as processed
// Fact-store split: `status`/`processed_at` are derived bookkeeping → write the disposable
// note_state row (NOT the read-only raw_notes view). The view's COALESCE(ns.status,...) reads
// it back. setNoteState's partial UPSERT leaves any other note_state columns intact.
export function markProcessed(id: number, conn: DatabaseType = db): void {
  setNoteState(conn, id, { status: 'processed', processed_at: new Date().toISOString() });
}

// Helper: Check for duplicate by content hash
export function findByContentHash(hash: string): RawNote | undefined {
  return db.prepare('SELECT * FROM raw_notes WHERE content_hash = ?').get(hash) as
    | RawNote
    | undefined;
}

// Helper: Insert new note
export function insertNote(
  note: {
    title: string;
    content: string;
    contentHash: string;
    tags: string[];
    createdAt: string;
    testRun?: string;
    captureType?: string;
    sourceUuid?: string;
    sourceNoteId?: number;
  },
  conn: DatabaseType = db
): number {
  const wordCount = note.content.split(/\s+/).filter(Boolean).length;
  const characterCount = note.content.length;

  // Fact-store split: a captured note is a FACT — write it to facts.captured_notes (the
  // real table), NOT the read-only raw_notes view. We set NO `status`; the note has no
  // note_state row, and the view's COALESCE(ns.status,'pending') reads it back as 'pending'.
  const result = conn
    .prepare(
      `INSERT INTO facts.captured_notes
       (title, content, content_hash, tags, word_count, character_count, created_at, test_run, capture_type, source_uuid, source_note_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(
      note.title,
      note.content,
      note.contentHash,
      JSON.stringify(note.tags),
      wordCount,
      characterCount,
      note.createdAt,
      note.testRun || null,
      note.captureType || 'drafts',
      note.sourceUuid || null,
      note.sourceNoteId || null
    );

  return result.lastInsertRowid as number;
}

// Helper: Update calendar event metadata on a note
// Fact-store split: `calendar_event` is part of the immutable note FACT → write the real
// facts.captured_notes table (NOT the read-only raw_notes view). The note id comes from
// insertNote's captured_notes rowid, so it addresses the same row.
export function updateCalendarEvent(
  noteId: number,
  calendarEvent: CalendarEvent,
  conn: DatabaseType = db
): void {
  conn.prepare('UPDATE facts.captured_notes SET calendar_event = ? WHERE id = ?')
    .run(JSON.stringify(calendarEvent), noteId);
}

// Helper: Keyword search across notes
export function searchNotesKeyword(query: string, limit = 50): RawNote[] {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM raw_notes r
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE r.test_run IS NULL
      AND (r.content LIKE ? OR r.title LIKE ?)
    ORDER BY r.created_at DESC
    LIMIT ?
  `);
  const pattern = '%' + query + '%';
  return stmt.all(pattern, pattern, limit) as RawNote[];
}

// Ensure device_tokens table exists
db.exec(`
  CREATE TABLE IF NOT EXISTS device_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'ios',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

/**
 * Idempotent column-add for the LEGACY single-file shape, where raw_notes is a PHYSICAL table:
 * ensure source_note_id (annotation linking, 2026-05-28) + inbox_status (worksheet triage state)
 * exist so a fresh clone / rebuilt DB gets them without a manual ALTER.
 *
 * Post fact-store split, raw_notes is a per-connection VIEW that already exposes both columns, and
 * `ALTER TABLE <view>` THROWS — which at module load would crash the whole process. So this no-ops
 * whenever raw_notes is not a real table (it lives in sqlite_master with type='table' only when
 * physical; a TEMP view is in sqlite_temp_master, so this probe returns nothing for the view).
 */
export function ensureLegacyRawNotesColumns(conn: DatabaseType): void {
  const isPhysicalTable = conn
    .prepare(`SELECT 1 FROM sqlite_master WHERE name = 'raw_notes' AND type = 'table'`)
    .get();
  if (!isPhysicalTable) return;
  const cols = conn.prepare(`PRAGMA table_info(raw_notes)`).all() as Array<{ name: string }>;
  if (!cols.some((c) => c.name === 'source_note_id')) {
    conn.exec(`ALTER TABLE raw_notes ADD COLUMN source_note_id INTEGER REFERENCES raw_notes(id)`);
    logger.info('Migrated raw_notes: added source_note_id column');
  }
  if (!cols.some((c) => c.name === 'inbox_status')) {
    conn.exec(`ALTER TABLE raw_notes ADD COLUMN inbox_status TEXT DEFAULT 'pending'`);
    logger.info('Migrated raw_notes: added inbox_status column');
  }
}
ensureLegacyRawNotesColumns(db);

// Helper: Get all device tokens, optionally filtered by platform
export function getDeviceTokens(platform?: string): string[] {
  if (platform) {
    const rows = db.prepare('SELECT token FROM device_tokens WHERE platform = ?')
      .all(platform) as Array<{ token: string }>;
    return rows.map(r => r.token);
  }
  const rows = db.prepare('SELECT token FROM device_tokens')
    .all() as Array<{ token: string }>;
  return rows.map(r => r.token);
}

// Cleanup on process exit
process.on('exit', () => {
  db.close();
});
