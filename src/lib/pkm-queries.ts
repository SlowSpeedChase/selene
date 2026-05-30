/**
 * PKM Browse — read-only query layer (Track 2).
 *
 * Every query gates on `baseNoteFilter()` so test/pending notes never leak into the browse
 * surface (design risk #3 — centralized to avoid drift). Concept/cross-ref membership uses
 * json_each, wrapped in a json_valid CASE so a single malformed JSON row can't crash a page.
 *
 * Functions take an explicit `db` (no singleton) -> unit-testable in-memory.
 */
import type { Database as DB } from 'better-sqlite3';

export interface ConceptCount {
  concept: string;
  n: number;
}
export interface NoteSummary {
  id: number;
  title: string;
  created_at: string;
  essence: string | null;
  primary_theme: string | null;
  category: string | null;
}
export interface EssenceRow {
  id: number;
  title: string;
  essence: string | null;
}
export interface CategoryCount {
  category: string;
  n: number;
}

/** The one place the "real, processed notes only" rule lives. */
export function baseNoteFilter(alias = 'rn'): string {
  return `${alias}.test_run IS NULL AND ${alias}.status = 'processed'`;
}

// json_each over a column, guarded so invalid JSON degrades to empty instead of throwing.
const safeJson = (col: string): string =>
  `json_each(CASE WHEN json_valid(${col}) THEN ${col} ELSE '[]' END)`;

export function getTopConcepts(db: DB, limit: number): ConceptCount[] {
  return db
    .prepare(
      `SELECT je.value AS concept, COUNT(*) AS n
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       , ${safeJson('pn.concepts')} je
       WHERE ${baseNoteFilter()}
       GROUP BY je.value
       ORDER BY n DESC, je.value ASC
       LIMIT ?`
    )
    .all(limit) as ConceptCount[];
}

export function getNotesForConcept(db: DB, concept: string, limit: number): NoteSummary[] {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.created_at, pn.essence, pn.primary_theme, pn.category
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       , ${safeJson('pn.concepts')} je
       WHERE je.value = ? AND ${baseNoteFilter()}
       ORDER BY rn.created_at DESC
       LIMIT ?`
    )
    .all(concept, limit) as NoteSummary[];
}

export function getCooccurringConcepts(db: DB, concept: string, limit: number): ConceptCount[] {
  return db
    .prepare(
      `SELECT jb.value AS concept, COUNT(*) AS n
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       , ${safeJson('pn.concepts')} ja
       , ${safeJson('pn.concepts')} jb
       WHERE ja.value = ? AND jb.value != ? AND ${baseNoteFilter()}
       GROUP BY jb.value
       ORDER BY n DESC, jb.value ASC
       LIMIT ?`
    )
    .all(concept, concept, limit) as ConceptCount[];
}

export function getNotesForCategory(db: DB, name: string, limit: number): NoteSummary[] {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.created_at, pn.essence, pn.primary_theme, pn.category
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       WHERE (pn.category = ?
              OR EXISTS (SELECT 1 FROM ${safeJson('pn.cross_ref_categories')} x WHERE x.value = ?))
         AND ${baseNoteFilter()}
       ORDER BY rn.created_at DESC
       LIMIT ?`
    )
    .all(name, name, limit) as NoteSummary[];
}

export function getCategoryCounts(db: DB): CategoryCount[] {
  return db
    .prepare(
      `SELECT pn.category AS category, COUNT(*) AS n
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       WHERE ${baseNoteFilter()} AND pn.category IS NOT NULL AND pn.category != ''
       GROUP BY pn.category
       ORDER BY n DESC, pn.category ASC`
    )
    .all() as CategoryCount[];
}

export function getOnThisDay(db: DB): NoteSummary[] {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.created_at, pn.essence, pn.primary_theme, pn.category
       FROM raw_notes rn
       JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE strftime('%m-%d', rn.created_at) = strftime('%m-%d', 'now')
         AND date(rn.created_at) < date('now')
         AND ${baseNoteFilter()}
       ORDER BY rn.created_at DESC`
    )
    .all() as NoteSummary[];
}

export function getRandomEssence(db: DB): EssenceRow | undefined {
  return db
    .prepare(
      `SELECT rn.id, rn.title, pn.essence
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       WHERE pn.essence IS NOT NULL AND ${baseNoteFilter()}
       ORDER BY RANDOM() LIMIT 1`
    )
    .get() as EssenceRow | undefined;
}

export interface NoteDetailRow {
  id: number;
  title: string;
  content: string;
  essence: string | null;
  concepts: string | null;
  category: string | null;
  primary_theme: string | null;
}

export function getNoteDetail(db: DB, id: number): NoteDetailRow | undefined {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, pn.essence, pn.concepts, pn.category, pn.primary_theme
       FROM raw_notes rn
       JOIN processed_notes pn ON pn.raw_note_id = rn.id
       WHERE rn.id = ? AND ${baseNoteFilter()}`
    )
    .get(id) as NoteDetailRow | undefined;
}

export function getRandomNoteId(db: DB): number | undefined {
  const row = db
    .prepare(
      `SELECT rn.id FROM raw_notes rn
       JOIN processed_notes pn ON pn.raw_note_id = rn.id
       WHERE ${baseNoteFilter()} ORDER BY RANDOM() LIMIT 1`
    )
    .get() as { id: number } | undefined;
  return row?.id;
}

export function getNoteSummariesByIds(db: DB, ids: number[]): NoteSummary[] {
  if (ids.length === 0) return [];
  const placeholders = ids.map(() => '?').join(',');
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.created_at, pn.essence, pn.primary_theme, pn.category
       FROM raw_notes rn
       JOIN processed_notes pn ON pn.raw_note_id = rn.id
       WHERE rn.id IN (${placeholders}) AND ${baseNoteFilter()}
       ORDER BY rn.created_at DESC`
    )
    .all(...ids) as NoteSummary[];
}

export function getEssences(db: DB, limit: number, offset: number): EssenceRow[] {
  return db
    .prepare(
      `SELECT rn.id, rn.title, pn.essence
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       WHERE pn.essence IS NOT NULL AND ${baseNoteFilter()}
       ORDER BY rn.created_at DESC
       LIMIT ? OFFSET ?`
    )
    .all(limit, offset) as EssenceRow[];
}
