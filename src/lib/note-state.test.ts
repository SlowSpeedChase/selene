/**
 * Fact-store split — `setNoteState` partial-UPSERT of the disposable `note_state` row.
 *
 * `note_state` is the derived pipeline bookkeeping keyed to `captured_notes.id`. Multiple
 * writers (markProcessed → status, folio-feedback → status_folio, obsidian-render → export
 * columns) touch DIFFERENT columns of the SAME row at DIFFERENT times, so the UPSERT must set
 * ONLY the provided columns and never clobber the others. We assert that property directly and
 * confirm the read-back through the backward-compatible `raw_notes` view reflects both writes.
 */
import { makeTwoFileTestDb } from './test-two-file-db';
import type { Database as DatabaseType } from 'better-sqlite3';
import { setNoteState } from './note-state';

describe('setNoteState (partial note_state UPSERT)', () => {
  let db: DatabaseType;

  beforeEach(() => {
    ({ db } = makeTwoFileTestDb());
  });

  afterEach(() => db.close());

  it('a second patch sets only its columns and does NOT clobber columns from the first', () => {
    // A captured note (id 7) so the view's LEFT JOIN has a fact row to read back through.
    db.prepare(
      `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at)
       VALUES (?,?,?,?,?)`
    ).run(7, 'Note Seven', 'body', 'hash-7', '2026-05-01T08:00:00.000Z');

    setNoteState(db, 7, { status: 'processed', processed_at: 't1' });
    setNoteState(db, 7, { status_folio: 'written' });

    // Direct read of the bookkeeping row: status survived the second (folio-only) write.
    const row = db
      .prepare('SELECT status, processed_at, status_folio FROM note_state WHERE raw_note_id = 7')
      .get() as { status: string; processed_at: string | null; status_folio: string | null };
    expect(row.status).toBe('processed');
    expect(row.processed_at).toBe('t1');
    expect(row.status_folio).toBe('written');

    // Read-back through the view reflects BOTH writes (status + status_folio).
    const viewRow = db
      .prepare('SELECT status, status_folio FROM raw_notes WHERE id = 7')
      .get() as { status: string; status_folio: string | null };
    expect(viewRow.status).toBe('processed');
    expect(viewRow.status_folio).toBe('written');
  });

  it('an empty patch is a no-op — it creates no note_state row', () => {
    setNoteState(db, 99, {});
    const count = db
      .prepare('SELECT COUNT(*) AS n FROM note_state WHERE raw_note_id = 99')
      .get() as { n: number };
    expect(count.n).toBe(0);
  });

  it('a patch whose only keys are undefined is a no-op — it creates no note_state row', () => {
    setNoteState(db, 99, { status: undefined, exported_at: undefined });
    const count = db
      .prepare('SELECT COUNT(*) AS n FROM note_state WHERE raw_note_id = 99')
      .get() as { n: number };
    expect(count.n).toBe(0);
  });
});
