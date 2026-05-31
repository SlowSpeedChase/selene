/**
 * facts.db — schema for the precious, immutable fact store.
 *
 * `facts.db` owns two tables: `captured_notes` (the immutable note facts — the durable
 * subset of today's `raw_notes`) and `review_state` (human review flags, migrated later
 * from today's `pkm_review_state`). A later task ATTACHes `facts.db` and calls this once;
 * this module is pure schema with NO connection logic and touches NO real data.
 *
 * Takes an explicit `db` (no module singleton) so it's unit-testable in-memory, matching
 * src/lib/pkm-db.ts.
 */
import type { Database as DB } from 'better-sqlite3';

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
      imported_at      DATETIME,
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

    -- Non-unique lookup indexes (dedup/lookup parity). NON-unique on purpose so the later
    -- data migration can't fail on any historical duplicates.
    CREATE INDEX IF NOT EXISTS idx_captured_content_hash ON captured_notes(content_hash);
    CREATE INDEX IF NOT EXISTS idx_captured_source_uuid ON captured_notes(source_uuid);
  `);
}
