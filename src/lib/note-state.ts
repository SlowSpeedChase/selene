/**
 * Fact-store split — safe partial-UPSERT of the disposable `note_state` row.
 *
 * `note_state` (in selene.db `main`, keyed to `captured_notes.id`) holds the derivable pipeline
 * bookkeeping — `status`, `processed_at`, export flags, `status_folio`, `inbox_status`. Several
 * writers touch DIFFERENT columns of the SAME row at DIFFERENT times (markProcessed → status;
 * folio-feedback → status_folio; obsidian-render → export columns). A naïve `INSERT OR REPLACE`
 * would null out every column the caller didn't mention, so this UPSERT sets ONLY the provided
 * columns and leaves the rest intact.
 *
 * Injection-safe: column names come ONLY from the `ALLOWED` whitelist (never from caller-controlled
 * strings), and every value is bound as a parameter. Takes an explicit `db` (no module singleton)
 * so it works against any connection — the production one, a test two-file db, or folio-feedback's
 * own connection (`note_state` is a persistent table, visible without `attachFacts`).
 */
import type { Database as DB } from 'better-sqlite3';

export interface NoteStatePatch {
  status?: string;
  processed_at?: string | null;
  exported_at?: string | null;
  exported_to_obsidian?: number;
  obsidian_export_hash?: string | null;
  status_folio?: string;
  inbox_status?: string;
}

const ALLOWED = new Set([
  'status',
  'processed_at',
  'exported_at',
  'exported_to_obsidian',
  'obsidian_export_hash',
  'status_folio',
  'inbox_status',
]);

/** UPSERT only the provided columns of note_state for rawNoteId; leaves other columns intact. */
export function setNoteState(db: DB, rawNoteId: number, patch: NoteStatePatch): void {
  const cols = Object.keys(patch).filter(
    (k) => ALLOWED.has(k) && patch[k as keyof NoteStatePatch] !== undefined
  );
  if (cols.length === 0) return;
  const placeholders = cols.map(() => '?').join(', ');
  const updates = cols.map((c) => `${c} = excluded.${c}`).join(', ');
  const values = cols.map((c) => patch[c as keyof NoteStatePatch] as string | number | null);
  db.prepare(
    `INSERT INTO note_state (raw_note_id, ${cols.join(', ')}) VALUES (?, ${placeholders})
     ON CONFLICT(raw_note_id) DO UPDATE SET ${updates}`
  ).run(rawNoteId, ...values);
}
