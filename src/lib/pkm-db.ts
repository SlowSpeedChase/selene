/**
 * PKM Browse — review-state layer (Track 1).
 *
 * A tiny `review_state` table that records when an entity (note / category / concept) was
 * last surfaced and how many times, so the browse layer can do spaced resurfacing ("haven't
 * seen this in 7+ days, here it is again") and least-recently-surfaced ordering.
 *
 * Fact-store split (Task 9): review flags are PRECIOUS — they'd be lost on a Phase-2 rebuild of
 * the disposable selene.db. So `review_state` now lives in facts.db (created by initFactsSchema)
 * and resolves here via the `facts` ATTACH alias: selene.db's main has no `review_state` table, so
 * an UNQUALIFIED `review_state` binds to `facts.review_state`. Every connection that calls these
 * must therefore have facts ATTACHed (the db.ts singleton + test two-file DBs do). `initPkmSchema`
 * no longer CREATEs the table; it only seeds any selene.db-side PKM schema. The legacy
 * `pkm_review_state` table is left untouched as a migration backup.
 */
import type { Database as DB } from 'better-sqlite3';
import { baseNoteFilter } from './pkm-queries';

export const REVIEW_WINDOW_DAYS = 7;

export interface ReviewItem {
  entityType: string;
  entityId: string;
  lastSurfacedAt: string | null;
  surfaceCount: number;
}

/**
 * Idempotent PKM-side schema init. `review_state` is NO LONGER created here — it lives in facts.db
 * (initFactsSchema) and is reached via the `facts` attach alias. Kept as a hook for any future
 * selene.db-side PKM tables; currently a no-op so callers don't need to change.
 */
export function initPkmSchema(_db: DB): void {
  /* review_state moved to facts.db (precious). Nothing to create in selene.db (disposable). */
}

/** UPSERT: first surface -> count 1; thereafter increment and refresh the timestamp. */
export function markSurfaced(db: DB, entityType: string, entityId: string): void {
  db.prepare(
    `INSERT INTO review_state (entity_type, entity_id, last_surfaced_at, surface_count)
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
       LEFT JOIN review_state prs
         ON prs.entity_type = 'note' AND prs.entity_id = CAST(rn.id AS TEXT)
       WHERE ${baseNoteFilter('rn')}
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
       FROM review_state
       WHERE entity_type = ?
       ORDER BY last_surfaced_at ASC
       LIMIT ?`
    )
    .all(entityType, limit) as ReviewItem[];
}
