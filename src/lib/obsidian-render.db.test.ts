import Database from 'better-sqlite3';
import { mkdtempSync, readFileSync, readdirSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { reconcileExportedNotes } from './obsidian-render';

type DB = InstanceType<typeof Database>;

// Heavier seed than the constellation test: the reconcile loop joins raw_notes -> processed_notes
// and resolves each note's clusters via topic_clusters / topic_note_links.
function seed(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (
      id INTEGER PRIMARY KEY,
      title TEXT,
      content TEXT,
      created_at TEXT,
      status TEXT,
      test_run TEXT,
      exported_to_obsidian INTEGER DEFAULT 0,
      exported_at TEXT,
      obsidian_export_hash TEXT
    );
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
  db.prepare(
    `INSERT INTO raw_notes (id, title, content, created_at, status, exported_to_obsidian, obsidian_export_hash)
     VALUES (?,?,?,?,?,?,?)`
  ).run(10, 'Morning pages', 'A few lines.', '2026-05-01T08:00:00.000Z', 'processed', 0, null);
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
  it('first run (NULL hash) writes the note and stores its hash', () => {
    const db = seed();
    const dir = vault();
    const result = reconcileExportedNotes(db, dir);
    expect(result.written).toBe(1);
    expect(result.skipped).toBe(0);
    expect(readdirSync(dir).length).toBe(1);
    const storedHash = db.prepare('SELECT obsidian_export_hash AS h FROM raw_notes WHERE id = 10').get() as { h: string | null };
    expect(storedHash.h).toBeTruthy();
  });

  it('second run with no change skips the note (no rewrite)', () => {
    const db = seed();
    const dir = vault();
    reconcileExportedNotes(db, dir);
    const second = reconcileExportedNotes(db, dir);
    // A rewrite would be byte-identical to a skip, so only the counts discriminate.
    expect(second.written).toBe(0);
    expect(second.skipped).toBe(1);
  });

  it('rewrites a note whose vault file was deleted out of band, even though its hash is unchanged', () => {
    const db = seed();
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
    const db = seed();
    // Second processed note so two notes are eligible at once.
    db.prepare(
      `INSERT INTO raw_notes (id, title, content, created_at, status, exported_to_obsidian, obsidian_export_hash)
       VALUES (?,?,?,?,?,?,?)`
    ).run(20, 'Evening notes', 'Other lines.', '2026-05-02T08:00:00.000Z', 'processed', 0, null);
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
    const db = seed();
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
