/**
 * PKM Browse — review-state layer (Track 1).
 *
 * A tiny `pkm_review_state` table that records when an entity (note / category / concept) was
 * last surfaced and how many times, so the browse layer can do spaced resurfacing ("haven't
 * seen this in 7+ days, here it is again") and least-recently-surfaced ordering.
 *
 * Functions take an explicit `db` (no module singleton) so they're unit-testable in-memory,
 * matching src/lib/synthesis-db.ts. Track 2's routes call these with the shared connection
 * after calling initPkmSchema(db) once at server startup.
 */
import type { Database as DB } from 'better-sqlite3';

export const REVIEW_WINDOW_DAYS = 7;

export interface ReviewItem {
  entityType: string;
  entityId: string;
  lastSurfacedAt: string | null;
  surfaceCount: number;
}

/** Idempotent schema init (CREATE TABLE/INDEX IF NOT EXISTS). */
export function initPkmSchema(db: DB): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS pkm_review_state (
      entity_type      TEXT NOT NULL,
      entity_id        TEXT NOT NULL,
      last_surfaced_at TEXT,
      surface_count    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (entity_type, entity_id)
    );
    CREATE INDEX IF NOT EXISTS idx_pkm_review_last ON pkm_review_state(last_surfaced_at);
  `);
}

/** UPSERT: first surface -> count 1; thereafter increment and refresh the timestamp. */
export function markSurfaced(db: DB, entityType: string, entityId: string): void {
  db.prepare(
    `INSERT INTO pkm_review_state (entity_type, entity_id, last_surfaced_at, surface_count)
     VALUES (?, ?, datetime('now'), 1)
     ON CONFLICT(entity_type, entity_id) DO UPDATE SET
       surface_count = surface_count + 1,
       last_surfaced_at = datetime('now')`
  ).run(entityType, entityId);
}

/** Processed, non-test notes never surfaced or not surfaced in the last REVIEW_WINDOW_DAYS,
 *  least-surfaced and oldest first (never-surfaced notes lead). */
export function getDueForReview(db: DB, limit: number): ReviewItem[] {
  return db
    .prepare(
      `SELECT 'note' AS entityType, CAST(rn.id AS TEXT) AS entityId,
              prs.last_surfaced_at AS lastSurfacedAt,
              COALESCE(prs.surface_count, 0) AS surfaceCount
       FROM raw_notes rn
       LEFT JOIN pkm_review_state prs
         ON prs.entity_type = 'note' AND prs.entity_id = CAST(rn.id AS TEXT)
       WHERE rn.test_run IS NULL AND rn.status = 'processed'
         AND (prs.last_surfaced_at IS NULL
              OR prs.last_surfaced_at < datetime('now', '-' || ? || ' days'))
       ORDER BY surfaceCount ASC, prs.last_surfaced_at ASC
       LIMIT ?`
    )
    .all(REVIEW_WINDOW_DAYS, limit) as ReviewItem[];
}

/** Rows of a given entity type ordered by least-recently-surfaced (NULL/oldest first). */
export function getLeastRecentlySurfaced(db: DB, entityType: string, limit: number): ReviewItem[] {
  return db
    .prepare(
      `SELECT entity_type AS entityType, entity_id AS entityId,
              last_surfaced_at AS lastSurfacedAt, surface_count AS surfaceCount
       FROM pkm_review_state
       WHERE entity_type = ?
       ORDER BY last_surfaced_at ASC
       LIMIT ?`
    )
    .all(entityType, limit) as ReviewItem[];
}
