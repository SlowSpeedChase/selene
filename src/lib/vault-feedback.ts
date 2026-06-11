/**
 * Obsidian feedback loop ("Your note") — pure parsing + DI'd scan/ingest helpers.
 *
 * The vault's exported notes end with a `## ✍️ Your note` section. The PROTOCOL (mirrors
 * obsidian-render.ts, which renders the other side): blockquoted lines in the section are
 * Selene's applied-feedback history; any other non-whitespace text is NEW author feedback.
 * Feedback is precious (human words) → facts.note_feedback, keyed on captured_notes.id
 * (total + stable: facts.db is never rebuilt). Design:
 * docs/plans/2026-06-10-obsidian-feedback-loop-design.md
 *
 * Takes an explicit `db` (no module singleton) so it is unit-testable via makeTwoFileTestDb,
 * matching obsidian-render.ts / note-state.ts.
 */
import type { Database as DB } from 'better-sqlite3';
import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';
import { setNoteState } from './note-state';

export const YOUR_NOTE_HEADING = '## ✍️ Your note';

export interface ParsedSection {
  hasSection: boolean;
  newFeedback: string | null;
}

/** Apply the section protocol to a note file's markdown. */
export function parseYourNoteSection(markdown: string): ParsedSection {
  const lines = markdown.split(/\r?\n/); // CRLF-tolerant; feedback_text never carries \r
  const start = lines.findIndex((l) => l.trim() === YOUR_NOTE_HEADING);
  if (start === -1) return { hasSection: false, newFeedback: null };

  // Consume to EOF: the canonical render guarantees the Your-note section is the document TAIL,
  // so breaking at a `## ` line protected nothing — it silently dropped (and the next
  // preserve-on-render rewrite permanently lost) everything an author wrote below their own
  // markdown subheading inside their feedback.
  const section = lines.slice(start + 1);
  const fresh = section
    .filter((l) => !l.trimStart().startsWith('>'))
    .join('\n')
    .trim();
  return { hasSection: true, newFeedback: fresh.length > 0 ? fresh : null };
}

/**
 * The note's captured_notes.id from the `selene_id:` frontmatter line. Bounded to the LEADING
 * `---` fenced block only: body text mentioning "selene_id: N" in a hand-made file must never
 * mis-attribute feedback (and re-pend) note N.
 */
export function extractSeleneId(markdown: string): number | null {
  const lines = markdown.split(/\r?\n/);
  if (lines[0]?.trim() !== '---') return null;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === '---') break; // closing fence — id not found
    const m = lines[i].match(/^selene_id:\s*(\d+)\s*$/);
    if (m) return parseInt(m[1], 10);
  }
  return null;
}

export interface ScanResult {
  scanned: number;     // files inspected
  ingested: number;    // new feedback rows written (note re-pended)
  duplicates: number;  // identical (note, text) already ingested — awaiting re-export
  unmatched: number;   // no selene_id / id not in captured_notes — skipped, file untouched
  errors: number;      // per-file read/parse exceptions
  /** First few per-file failures (filename + exception message, NO note content) so an errors>0
   *  exit is diagnosable from logs — same precedent as obsidian-render's reconcile errorSamples. */
  errorSamples: Array<{ file: string; message: string }>;
}

/**
 * Scan every Notes/*.md for new "Your note" text and ingest it. Full scan each run, no
 * watermark: ~300 small files is trivially cheap and the (raw_note_id, feedback_text) dedupe
 * makes rescans idempotent. Never writes to any vault file.
 */
export function scanVaultFeedback(db: DB, notesDir: string, now: string): ScanResult {
  const result: ScanResult = {
    scanned: 0, ingested: 0, duplicates: 0, unmatched: 0, errors: 0, errorSamples: [],
  };

  let files: string[];
  try {
    files = readdirSync(notesDir).filter((f) => f.endsWith('.md'));
  } catch {
    return result; // vault dir missing (fresh dev sandbox) — nothing to scan
  }

  // One file's ingest (filing snapshot + INSERT + re-pend) as a single transaction, invoked
  // .immediate() so BEGIN IMMEDIATE takes the write lock up front: two concurrent scanners
  // (15-min agent + hourly export pre-scan) serialize instead of racing, and a crash can never
  // record feedback without its re-pend (which would dedupe-skip it forever). Returns false
  // when the UNIQUE dedupe index ignored the row — duplicate, must NOT re-pend.
  const ingestOne = db.transaction((noteId: number, text: string): boolean => {
    // Snapshot the filing being corrected BEFORE re-derivation replaces it (Phase 2's
    // few-shot raw material). NULL when the note was never processed.
    const filing = db
      .prepare(
        `SELECT category, cross_ref_categories, sub_categories, primary_theme, concepts, essence
         FROM processed_notes WHERE raw_note_id = ?`
      )
      .get(noteId) as Record<string, unknown> | undefined;

    // OR IGNORE against idx_note_feedback_dedupe is the authoritative concurrent-scanner
    // guard (the SELECT outside is just the cheap no-write-lock common path).
    const inserted = db.prepare(
      `INSERT OR IGNORE INTO facts.note_feedback (raw_note_id, feedback_text, original_filing, created_at)
       VALUES (?, ?, ?, ?)`
    ).run(noteId, text, filing ? JSON.stringify(filing) : null, now);
    if (inserted.changes === 0) return false;

    // Re-pend: derivation-absence machinery does the rest (process-llm INSERT OR REPLACEs).
    // Partial UPSERT preserves unrelated bookkeeping (status_folio, inbox_status, export hash).
    setNoteState(db, noteId, { status: 'pending', processed_at: null });
    return true;
  });

  for (const file of files) {
    result.scanned++;
    try {
      const markdown = readFileSync(join(notesDir, file), 'utf-8');
      const { newFeedback } = parseYourNoteSection(markdown);
      if (!newFeedback) continue;

      const noteId = extractSeleneId(markdown);
      const known = noteId !== null
        && db.prepare(`SELECT 1 FROM facts.captured_notes WHERE id = ?`).get(noteId);
      if (!known || noteId === null) {
        result.unmatched++;
        continue;
      }

      // Cheap dup check (belt): counts duplicates without burning a write lock. The
      // authoritative guard (suspenders) is the OR IGNORE inside ingestOne.
      const dup = db
        .prepare(`SELECT 1 FROM facts.note_feedback WHERE raw_note_id = ? AND feedback_text = ?`)
        .get(noteId, newFeedback);
      if (dup) {
        result.duplicates++;
        continue;
      }

      if (ingestOne.immediate(noteId, newFeedback)) result.ingested++;
      else result.duplicates++; // concurrent scanner won the race between belt and suspenders
    } catch (err) {
      result.errors++;
      if (result.errorSamples.length < 5) {
        result.errorSamples.push({ file, message: (err as Error).message });
      }
    }
  }
  return result;
}

/** ALL of a note's feedback texts, oldest first — every (re-)derivation carries full intent history. */
export function getIntentTexts(db: DB, rawNoteId: number): string[] {
  const rows = db
    .prepare(
      `SELECT feedback_text FROM facts.note_feedback
       WHERE raw_note_id = ? ORDER BY created_at ASC, id ASC`
    )
    .all(rawNoteId) as Array<{ feedback_text: string }>;
  return rows.map((r) => r.feedback_text);
}

/** Stamp this note's un-applied feedback as applied (called after a successful re-derivation). */
export function markFeedbackApplied(db: DB, rawNoteId: number, now: string): void {
  db.prepare(
    `UPDATE facts.note_feedback SET applied_at = ? WHERE raw_note_id = ? AND applied_at IS NULL`
  ).run(now, rawNoteId);
}
