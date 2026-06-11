import { mkdtempSync, readFileSync, readdirSync, rmSync, existsSync, writeFileSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import type { Database as DatabaseType } from 'better-sqlite3';
import { reconcileExportedNotes } from './obsidian-render';
import { makeTwoFileTestDb } from './test-two-file-db';

// Fact-store split: `raw_notes` is a TEMP VIEW over facts.captured_notes + note_state, so the
// note FACT goes in facts.captured_notes and the export bookkeeping (obsidian_export_hash,
// exported_to_obsidian, exported_at) lands in note_state — both read back through the view.
//
// The reconcile loop filters `WHERE rn.status = 'processed'`; through the view that is
// COALESCE(ns.status,'pending'), so each eligible note MUST have a note_state row with
// status='processed' — otherwise it reads back as 'pending' and the loop sees zero notes.
// The reconcile then writes the export columns via setNoteState's partial UPSERT, which must
// NOT clobber that status (or the note vanishes from the query on the second run).
//
// The reconcile also joins raw_notes -> processed_notes and resolves each note's clusters via
// topic_clusters / topic_note_links — those stay as plain physical tables layered onto selene.db.
function seed(): DatabaseType {
  const { db } = makeTwoFileTestDb();
  db.exec(`
    CREATE TABLE processed_notes (
      raw_note_id INTEGER,
      primary_theme TEXT,
      concepts TEXT,
      essence TEXT,
      category TEXT,
      cross_ref_categories TEXT
    );
    CREATE TABLE topic_clusters (id TEXT PRIMARY KEY, name TEXT, parent_id TEXT);
    CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER, added_at TEXT,
      PRIMARY KEY (topic_id, note_id));
  `);
  // content_hash is NOT NULL in captured_notes — supply it.
  db.prepare(
    `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at)
     VALUES (?,?,?,?,?)`
  ).run(10, 'Morning pages', 'A few lines.', 'hash-10', '2026-05-01T08:00:00.000Z');
  // Load-bearing: status='processed' so the note reads back as processed through the view.
  db.prepare('INSERT INTO note_state (raw_note_id, status) VALUES (?, ?)').run(10, 'processed');
  db.prepare(
    `INSERT INTO processed_notes (raw_note_id, primary_theme, concepts, essence, category, cross_ref_categories)
     VALUES (?,?,?,?,?,?)`
  ).run(10, 'reflection', JSON.stringify(['journaling']), 'Daily practice.', 'Daily Systems', '[]');
  db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)').run('c1', 'Daily Systems', null);
  db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)').run('c2', 'Creativity & Expression', null);
  db.prepare('INSERT INTO topic_note_links VALUES (?,?,?)').run('c1', 10, 'now');
  return db;
}

function vault(): string {
  return mkdtempSync(join(tmpdir(), 'vault-'));
}

describe('reconcileExportedNotes', () => {
  let db: DatabaseType;
  afterEach(() => db.close());

  it('first run (NULL hash) writes the note and stores its hash in note_state', () => {
    db = seed();
    const dir = vault();
    const result = reconcileExportedNotes(db, dir);
    expect(result.written).toBe(1);
    expect(result.skipped).toBe(0);
    expect(readdirSync(dir).length).toBe(1);
    // Read back through the view (surfaces ns.obsidian_export_hash) — the hash landed in note_state.
    const storedHash = db.prepare('SELECT obsidian_export_hash AS h FROM raw_notes WHERE id = 10').get() as { h: string | null };
    expect(storedHash.h).toBeTruthy();
    // The export columns are in note_state, and status was NOT clobbered by the export write.
    const state = db.prepare('SELECT status, exported_to_obsidian, obsidian_export_hash, exported_at FROM note_state WHERE raw_note_id = 10').get() as {
      status: string;
      exported_to_obsidian: number;
      obsidian_export_hash: string | null;
      exported_at: string | null;
    };
    expect(state.status).toBe('processed');
    expect(state.exported_to_obsidian).toBe(1);
    expect(state.obsidian_export_hash).toBeTruthy();
    expect(state.exported_at).toBeTruthy();
  });

  it('second run with no change skips the note (no rewrite)', () => {
    db = seed();
    const dir = vault();
    reconcileExportedNotes(db, dir);
    const second = reconcileExportedNotes(db, dir);
    // A rewrite would be byte-identical to a skip, so only the counts discriminate.
    expect(second.written).toBe(0);
    expect(second.skipped).toBe(1);
  });

  it('rewrites a note whose vault file was deleted out of band, even though its hash is unchanged', () => {
    db = seed();
    const dir = vault();
    reconcileExportedNotes(db, dir);
    const file = join(dir, readdirSync(dir)[0]);

    // Simulate an out-of-band delete (iCloud conflict, vault restore, accidental rm).
    rmSync(file);
    expect(existsSync(file)).toBe(false);

    // Self-healing: the DB hash still matches, but the file is gone, so it must be recreated.
    const after = reconcileExportedNotes(db, dir);
    expect(after.written).toBe(1);
    expect(existsSync(file)).toBe(true);
  });

  it('defers changed notes past the per-run write cap for the next run', () => {
    db = seed();
    // Second processed note so two notes are eligible at once.
    db.prepare(
      `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at)
       VALUES (?,?,?,?,?)`
    ).run(20, 'Evening notes', 'Other lines.', 'hash-20', '2026-05-02T08:00:00.000Z');
    db.prepare('INSERT INTO note_state (raw_note_id, status) VALUES (?, ?)').run(20, 'processed');
    db.prepare(
      `INSERT INTO processed_notes (raw_note_id, primary_theme, concepts, essence, category, cross_ref_categories)
       VALUES (?,?,?,?,?,?)`
    ).run(20, 'reflection', '[]', null, 'Daily Systems', '[]');

    const dir = vault();
    const result = reconcileExportedNotes(db, dir, '', 1); // writeCap = 1
    expect(result.written).toBe(1);
    expect(result.deferred).toBe(1);

    // Next run drains the deferred note.
    const next = reconcileExportedNotes(db, dir, '', 1);
    expect(next.written).toBe(1);
    expect(next.deferred).toBe(0);
  });

  it('rewrites only the changed note with updated parent:: when its cluster membership changes', () => {
    db = seed();
    const dir = vault();
    reconcileExportedNotes(db, dir);

    // Add note 10 to a second cluster (multi-membership) — body unchanged.
    db.prepare('INSERT INTO topic_note_links VALUES (?,?,?)').run('c2', 10, 'now');
    const after = reconcileExportedNotes(db, dir);

    expect(after.written).toBe(1);
    const file = join(dir, readdirSync(dir)[0]);
    const md = readFileSync(file, 'utf-8');
    expect(md).toContain('parent:: [[Daily Systems]]');
    expect(md).toContain('parent:: [[Creativity & Expression]]');
  });
});

describe('feedback preserve-on-render', () => {
  let db: DatabaseType;
  afterEach(() => db.close());

  it('a rewrite re-appends unprocessed user text from the existing file', () => {
    db = seed();
    const dir = vault();
    // seed one processed note; first reconcile writes the file
    reconcileExportedNotes(db, dir);
    const file = join(dir, readdirSync(dir)[0]);

    // user types feedback into the vault file
    writeFileSync(file, readFileSync(file, 'utf-8') + '\nmy new feedback\n', 'utf-8');

    // force a content change so the hash flips and the file rewrites
    db.prepare(`UPDATE processed_notes SET essence = 'new essence' WHERE raw_note_id = ?`).run(10);
    const result = reconcileExportedNotes(db, dir);
    expect(result.written).toBe(1);

    const after = readFileSync(file, 'utf-8');
    expect(after).toContain('new essence');
    expect(after.trimEnd().endsWith('my new feedback')).toBe(true); // user text survived the rewrite
  });

  it('renders applied feedback from facts.note_feedback', () => {
    db = seed();
    const dir = vault();
    db.prepare(
      `INSERT INTO facts.note_feedback (raw_note_id, feedback_text, created_at, applied_at)
       VALUES (?, 'a skill I enjoy', '2026-06-10', '2026-06-10T12:00:00.000Z')`
    ).run(10);
    reconcileExportedNotes(db, dir);
    const after = readFileSync(join(dir, readdirSync(dir)[0]), 'utf-8');
    expect(after).toContain('> a skill I enjoy');
    expect(after).toContain('— applied 2026-06-10 ✓');
  });

  it('does NOT rewrite an unchanged note even when the file holds new user feedback (no clobber)', () => {
    db = seed();
    const dir = vault();
    reconcileExportedNotes(db, dir);
    const file = join(dir, readdirSync(dir)[0]);

    writeFileSync(file, readFileSync(file, 'utf-8') + '\nmy new feedback\n', 'utf-8');
    const withFeedback = readFileSync(file, 'utf-8');

    // hash still matches + file exists → skip path; the user's text is untouched
    const result = reconcileExportedNotes(db, dir);
    expect(result.written).toBe(0);
    expect(result.skipped).toBe(1);
    expect(readFileSync(file, 'utf-8')).toBe(withFeedback);
  });
});
