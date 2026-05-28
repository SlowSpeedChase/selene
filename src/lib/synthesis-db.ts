import { randomUUID } from 'crypto';
import type { Database } from 'better-sqlite3';

export interface NoteConnection {
  id: string;
  source_note_id: number;
  target_note_id: number;
  similarity_score: number;
  found_at: string;
}

/**
 * Creates the 4 synthesis schema tables (idempotent — safe to call on every startup).
 *
 * Tables:
 *   topic_clusters       — LLM-named topic groups with optional hierarchy
 *   topic_note_links     — many-to-many join between topics and raw notes
 *   note_connections     — pairwise similarity scores between notes
 *   synthesis_meta       — key/value store for synthesis pipeline metadata
 */
export function initSynthesisSchema(db: Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS topic_clusters (
      id                    TEXT PRIMARY KEY,
      name                  TEXT NOT NULL,
      slug                  TEXT NOT NULL UNIQUE,
      parent_id             TEXT REFERENCES topic_clusters(id),
      synthesis_text        TEXT,
      prev_synthesis_text   TEXT,
      synthesis_updated_at  TEXT,
      evolution_detected_at TEXT,
      evolution_summary     TEXT,
      note_count            INTEGER NOT NULL DEFAULT 0,
      split_threshold       INTEGER NOT NULL DEFAULT 8,
      is_proto              INTEGER NOT NULL DEFAULT 0,
      created_at            TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS topic_note_links (
      topic_id  TEXT    NOT NULL REFERENCES topic_clusters(id),
      note_id   INTEGER NOT NULL,
      added_at  TEXT    NOT NULL,
      PRIMARY KEY (topic_id, note_id)
    );

    CREATE INDEX IF NOT EXISTS idx_tnl_topic ON topic_note_links(topic_id);
    CREATE INDEX IF NOT EXISTS idx_tnl_note  ON topic_note_links(note_id);

    CREATE TABLE IF NOT EXISTS note_connections (
      id               TEXT PRIMARY KEY,
      source_note_id   INTEGER NOT NULL,
      target_note_id   INTEGER NOT NULL,
      similarity_score REAL    NOT NULL,
      found_at         TEXT    NOT NULL,
      UNIQUE(source_note_id, target_note_id)
    );

    CREATE INDEX IF NOT EXISTS idx_nc_source ON note_connections(source_note_id);
    CREATE INDEX IF NOT EXISTS idx_nc_found  ON note_connections(found_at);

    CREATE TABLE IF NOT EXISTS synthesis_meta (
      key        TEXT PRIMARY KEY,
      value      TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  `);
}

/**
 * Inserts a similarity connection between two notes.
 * Uses INSERT OR IGNORE so that duplicate (source_note_id, target_note_id) pairs are
 * silently skipped — the UNIQUE constraint on those columns prevents double-counting
 * the same connection across multiple process-llm runs.
 */
export function writeConnection(
  db: Database,
  sourceNoteId: number,
  targetNoteId: number,
  similarityScore: number
): void {
  db.prepare(`
    INSERT OR IGNORE INTO note_connections (id, source_note_id, target_note_id, similarity_score, found_at)
    VALUES (?, ?, ?, ?, ?)
  `).run(
    randomUUID(),
    sourceNoteId,
    targetNoteId,
    similarityScore,
    new Date().toISOString()
  );
}
