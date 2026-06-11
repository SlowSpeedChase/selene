import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import type { Database as DB } from 'better-sqlite3';
import { makeTwoFileTestDb } from './test-two-file-db';
import {
  scanVaultFeedback,
  getIntentTexts,
  getIntentRows,
  markFeedbackApplied,
  rependIfUnappliedFeedback,
  YOUR_NOTE_HEADING,
} from './vault-feedback';

function seedNote(db: DB, id: number, title: string): void {
  db.prepare(
    `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at)
     VALUES (?, ?, 'content', ?, '2026-06-01T00:00:00.000Z')`
  ).run(id, title, `hash-${id}`);
  db.prepare(
    `CREATE TABLE IF NOT EXISTS processed_notes (
       raw_note_id INTEGER PRIMARY KEY, concepts TEXT, primary_theme TEXT,
       category TEXT, cross_ref_categories TEXT, sub_categories TEXT, essence TEXT)`
  ).run();
}

function noteFile(id: number, sectionBody: string): string {
  return [`---`, `title: "t"`, `selene_id: ${id}`, `---`, ``, `# t`, ``, YOUR_NOTE_HEADING, ``, sectionBody, ``].join('\n');
}

describe('scanVaultFeedback', () => {
  let db: DB;
  let dbDir: string;
  let vaultDir: string;

  beforeEach(() => {
    const t = makeTwoFileTestDb();
    db = t.db;
    dbDir = t.dir;
    vaultDir = mkdtempSync(join(tmpdir(), 'selene-vault-'));
  });

  afterEach(() => {
    db.close();
    rmSync(dbDir, { recursive: true, force: true });
    rmSync(vaultDir, { recursive: true, force: true });
  });

  it('ingests new feedback, snapshots the filing, and re-pends the note', () => {
    seedNote(db, 7, 'a note');
    db.prepare(`INSERT INTO processed_notes (raw_note_id, category, primary_theme) VALUES (7, 'Career & Work', 'old theme')`).run();
    db.prepare(`INSERT INTO note_state (raw_note_id, status, status_folio) VALUES (7, 'processed', 'sent')`).run();
    writeFileSync(join(vaultDir, 'n7.md'), noteFile(7, 'this is a skill I enjoy'));

    const r = scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    expect(r).toMatchObject({ scanned: 1, ingested: 1, duplicates: 0, unmatched: 0, errors: 0 });

    const row = db.prepare(`SELECT * FROM facts.note_feedback WHERE raw_note_id = 7`).get() as {
      feedback_text: string; original_filing: string; applied_at: string | null;
    };
    expect(row.feedback_text).toBe('this is a skill I enjoy');
    expect(JSON.parse(row.original_filing)).toMatchObject({ category: 'Career & Work', primary_theme: 'old theme' });
    expect(row.applied_at).toBeNull();

    // re-pended via the raw_notes view, and unrelated bookkeeping preserved
    const note = db.prepare(`SELECT status FROM raw_notes WHERE id = 7`).get() as { status: string };
    expect(note.status).toBe('pending');
    const state = db.prepare(`SELECT status_folio FROM note_state WHERE raw_note_id = 7`).get() as { status_folio: string };
    expect(state.status_folio).toBe('sent');
  });

  it('is idempotent: a second scan of the same text ingests nothing', () => {
    seedNote(db, 7, 'a note');
    writeFileSync(join(vaultDir, 'n7.md'), noteFile(7, 'same text'));
    scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    const r2 = scanVaultFeedback(db, vaultDir, '2026-06-10T12:05:00.000Z');
    expect(r2).toMatchObject({ ingested: 0, duplicates: 1 });
    expect(db.prepare(`SELECT COUNT(*) AS n FROM facts.note_feedback`).get()).toEqual({ n: 1 });
  });

  it('schema pins dedupe: raw duplicate INSERT throws; INSERT OR IGNORE reports changes 0', () => {
    seedNote(db, 7, 'a note');
    const raw = `INSERT INTO facts.note_feedback (raw_note_id, feedback_text, created_at) VALUES (7, 'twice', '2026-06-10')`;
    db.prepare(raw).run();
    // The UNIQUE index is the authoritative guard under concurrent scanners.
    expect(() => db.prepare(raw).run()).toThrow(/UNIQUE/i);
    const ignored = db
      .prepare(`INSERT OR IGNORE INTO facts.note_feedback (raw_note_id, feedback_text, created_at) VALUES (7, 'twice', '2026-06-10')`)
      .run();
    expect(ignored.changes).toBe(0);
    expect(db.prepare(`SELECT COUNT(*) AS n FROM facts.note_feedback`).get()).toEqual({ n: 1 });
  });

  it('already-ingested text (even applied) counts as duplicate and does NOT re-pend the note', () => {
    seedNote(db, 7, 'a note');
    db.prepare(
      `INSERT INTO facts.note_feedback (raw_note_id, feedback_text, created_at, applied_at)
       VALUES (7, 'old words', '2026-06-01', '2026-06-02')`
    ).run();
    db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (7, 'processed')`).run();
    writeFileSync(join(vaultDir, 'n7.md'), noteFile(7, 'old words'));

    const r = scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    expect(r).toMatchObject({ scanned: 1, ingested: 0, duplicates: 1, errors: 0 });
    expect(db.prepare(`SELECT COUNT(*) AS n FROM facts.note_feedback`).get()).toEqual({ n: 1 });
    const state = db.prepare(`SELECT status FROM note_state WHERE raw_note_id = 7`).get() as { status: string };
    expect(state.status).toBe('processed'); // duplicate must NOT re-pend
  });

  it('skips files with no selene_id or an unknown id (unmatched, untouched)', () => {
    writeFileSync(join(vaultDir, 'alien.md'), `# hand-made\n${YOUR_NOTE_HEADING}\nsome text\n`);
    writeFileSync(join(vaultDir, 'ghost.md'), noteFile(999, 'text'));
    const r = scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    expect(r).toMatchObject({ ingested: 0, unmatched: 2 });
  });

  it('unprocessed note (no processed_notes row) snapshots original_filing as NULL', () => {
    seedNote(db, 8, 'fresh');
    writeFileSync(join(vaultDir, 'n8.md'), noteFile(8, 'early feedback'));
    scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    const row = db.prepare(`SELECT original_filing FROM facts.note_feedback WHERE raw_note_id = 8`).get() as { original_filing: string | null };
    expect(row.original_filing).toBeNull();
  });

  it('missing vault dir -> zero result, no throw', () => {
    expect(scanVaultFeedback(db, join(vaultDir, 'nope'), '2026-06-10T12:00:00.000Z'))
      .toMatchObject({ scanned: 0, ingested: 0, errors: 0 });
  });

  it('per-file read failure is counted AND sampled (filename + message, no content)', () => {
    // A subdirectory named *.md makes readFileSync throw EISDIR — a reliable error trigger.
    mkdirSync(join(vaultDir, 'trap.md'));
    const r = scanVaultFeedback(db, vaultDir, '2026-06-10T12:00:00.000Z');
    expect(r).toMatchObject({ scanned: 1, errors: 1 });
    expect(r.errorSamples).toHaveLength(1);
    expect(r.errorSamples[0].file).toBe('trap.md');
    expect(r.errorSamples[0].message).toMatch(/EISDIR/);
  });
});

describe('intent helpers', () => {
  let db: DB;
  let dir: string;

  beforeEach(() => {
    const t = makeTwoFileTestDb();
    db = t.db;
    dir = t.dir;
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  function insertFeedback(rawNoteId: number, text: string, createdAt: string, appliedAt: string | null = null): number {
    const r = db
      .prepare(`INSERT INTO facts.note_feedback (raw_note_id, feedback_text, created_at, applied_at) VALUES (?, ?, ?, ?)`)
      .run(rawNoteId, text, createdAt, appliedAt);
    return Number(r.lastInsertRowid);
  }

  function appliedAtById(id: number): string | null {
    const row = db.prepare(`SELECT applied_at FROM facts.note_feedback WHERE id = ?`).get(id) as { applied_at: string | null };
    return row.applied_at;
  }

  it('getIntentRows returns ids + texts oldest-first; getIntentTexts is its text projection', () => {
    const a = insertFeedback(7, 'first', '2026-06-01', '2026-06-02');
    const b = insertFeedback(7, 'second', '2026-06-09');
    insertFeedback(8, 'other note', '2026-06-09');

    expect(getIntentRows(db, 7)).toEqual([
      { id: a, feedback_text: 'first' },
      { id: b, feedback_text: 'second' },
    ]);
    expect(getIntentTexts(db, 7)).toEqual(['first', 'second']);
  });

  it('markFeedbackApplied stamps ONLY the given ids — a row ingested mid-derivation stays un-applied', () => {
    const readAtPromptTime = insertFeedback(7, 'read at prompt time', '2026-06-01');
    const arrivedMidDerivation = insertFeedback(7, 'arrived mid-derivation', '2026-06-09');
    const otherNote = insertFeedback(8, 'other note', '2026-06-09');

    // Caller stamps exactly what it read; also try smuggling another note's id past the guard.
    markFeedbackApplied(db, 7, '2026-06-10T12:00:00.000Z', [readAtPromptTime, otherNote]);

    expect(appliedAtById(readAtPromptTime)).toBe('2026-06-10T12:00:00.000Z');
    expect(appliedAtById(arrivedMidDerivation)).toBeNull(); // no false ✓ for the straggler
    expect(appliedAtById(otherNote)).toBeNull();            // raw_note_id guard holds
  });

  it('markFeedbackApplied with empty ids is a no-op', () => {
    const a = insertFeedback(7, 'pending', '2026-06-01');
    markFeedbackApplied(db, 7, '2026-06-10T12:00:00.000Z', []);
    expect(appliedAtById(a)).toBeNull();
  });

  it('markFeedbackApplied never re-stamps an already-applied row', () => {
    const a = insertFeedback(7, 'already done', '2026-06-01', '2026-06-02');
    markFeedbackApplied(db, 7, '2026-06-10T12:00:00.000Z', [a]);
    expect(appliedAtById(a)).toBe('2026-06-02');
  });

  it('rependIfUnappliedFeedback re-pends the note and returns true when an un-applied row exists', () => {
    db.prepare(`INSERT INTO note_state (raw_note_id, status, processed_at, status_folio) VALUES (7, 'processed', '2026-06-10T11:00:00.000Z', 'sent')`).run();
    insertFeedback(7, 'straggler', '2026-06-10');

    expect(rependIfUnappliedFeedback(db, 7)).toBe(true);

    const state = db
      .prepare(`SELECT status, processed_at, status_folio FROM note_state WHERE raw_note_id = 7`)
      .get() as { status: string; processed_at: string | null; status_folio: string };
    expect(state.status).toBe('pending');
    expect(state.processed_at).toBeNull();
    expect(state.status_folio).toBe('sent'); // unrelated bookkeeping preserved
    expect(appliedAtById(getIntentRows(db, 7)[0].id)).toBeNull(); // it re-pends, never stamps
  });

  it('rependIfUnappliedFeedback is a no-op returning false when all feedback is applied', () => {
    db.prepare(`INSERT INTO note_state (raw_note_id, status, processed_at) VALUES (7, 'processed', '2026-06-10T11:00:00.000Z')`).run();
    insertFeedback(7, 'done', '2026-06-01', '2026-06-02');
    insertFeedback(8, 'someone else is pending', '2026-06-09'); // other note must not trigger 7

    expect(rependIfUnappliedFeedback(db, 7)).toBe(false);

    const state = db.prepare(`SELECT status, processed_at FROM note_state WHERE raw_note_id = 7`).get() as { status: string; processed_at: string | null };
    expect(state.status).toBe('processed');
    expect(state.processed_at).toBe('2026-06-10T11:00:00.000Z');
  });
});
