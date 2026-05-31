/**
 * Tests for openSeleneConnection — the one true way to get a view-capable selene.db connection
 * OUTSIDE the db.ts singleton (folio-feedback, selene-inspect, seed-dev-data all use it).
 *
 * Against REAL temp files (not :memory:, because the two-file layout ATTACHes a second file and
 * the WAL pragma only applies to on-disk files). Proves:
 *   - rw open: INSERT INTO facts.captured_notes is readable through the raw_notes view with the
 *     COALESCE('pending') status default;
 *   - rw open against a fresh (non-existent) facts path stands up facts.db schema automatically;
 *   - readonly open against an already-built two-file DB opens without throwing, attaches facts,
 *     materializes the temp view, and reads through it — WITHOUT writing the precious facts file.
 */
import Database from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync, rmSync, existsSync, statSync } from 'fs';
import { join } from 'path';
import { openSeleneConnection } from './open-selene-connection';

function freshPaths(): { dir: string; dbPath: string; factsPath: string } {
  const dir = mkdtempSync(join(tmpdir(), 'open-conn-'));
  return { dir, dbPath: join(dir, 'selene.db'), factsPath: join(dir, 'facts.db') };
}

describe('openSeleneConnection (read-write)', () => {
  it('returns a view-capable connection: captured_notes insert reads back through raw_notes view', () => {
    const { dir, dbPath, factsPath } = freshPaths();
    const db = openSeleneConnection(dbPath, factsPath);

    db.prepare(
      `INSERT INTO facts.captured_notes (title, content, content_hash, created_at)
       VALUES ('t', 'c', 'h1', datetime('now'))`
    ).run();

    const row = db
      .prepare(`SELECT id, title, status, inbox_status FROM raw_notes WHERE content_hash = 'h1'`)
      .get() as { id: number; title: string; status: string; inbox_status: string };
    expect(row.title).toBe('t');
    expect(row.status).toBe('pending'); // COALESCE default (no note_state row)
    expect(row.inbox_status).toBe('pending');

    // note_state override is visible through the same connection.
    db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (?, 'processed')`).run(row.id);
    const after = db.prepare(`SELECT status FROM raw_notes WHERE id = ?`).get(row.id) as { status: string };
    expect(after.status).toBe('processed');

    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('stands up facts.db with its schema when the facts file does not yet exist', () => {
    const { dir, dbPath, factsPath } = freshPaths();
    expect(existsSync(factsPath)).toBe(false);
    const db = openSeleneConnection(dbPath, factsPath);
    expect(existsSync(factsPath)).toBe(true);
    // review_state (precious) exists in facts.db via initFactsSchema.
    const rs = db.prepare(`SELECT COUNT(*) AS n FROM facts.review_state`).get() as { n: number };
    expect(rs.n).toBe(0);
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });
});

describe('openSeleneConnection (read-only)', () => {
  it('opens an already-built two-file DB readonly, reads through the view, and never writes facts', () => {
    const { dir, dbPath, factsPath } = freshPaths();

    // Build the two-file DB read-write and seed one fact.
    const rw = openSeleneConnection(dbPath, factsPath);
    rw.prepare(
      `INSERT INTO facts.captured_notes (title, content, content_hash, created_at)
       VALUES ('t', 'c', 'hro', datetime('now'))`
    ).run();
    // Leave selene.db in ROLLBACK-journal (DELETE) mode, like a freshly migrated DB. This is the
    // regression that crashed selene-inspect: `journal_mode = WAL` THROWS on a readonly handle when
    // the file isn't already WAL. The readonly open must skip that pragma. (Build in WAL would have
    // hidden the bug — the pragma is a no-op when the file is already WAL.)
    rw.pragma('journal_mode = DELETE');
    rw.close();

    const factsMtimeBefore = statSync(factsPath).mtimeMs;

    const ro = openSeleneConnection(dbPath, factsPath, { readonly: true, fileMustExist: true });
    const row = ro.prepare(`SELECT id, title, status FROM raw_notes WHERE content_hash = 'hro'`).get() as
      | { id: number; title: string; status: string }
      | undefined;
    expect(row).toBeDefined();
    expect(row!.status).toBe('pending');

    // The precious facts file must not be written by a readonly open.
    expect(() =>
      ro.prepare(`INSERT INTO facts.captured_notes (title, content, content_hash, created_at)
                  VALUES ('x','y','z',datetime('now'))`).run()
    ).toThrow(/readonly/);
    ro.close();

    expect(statSync(factsPath).mtimeMs).toBe(factsMtimeBefore);
    rmSync(dir, { recursive: true, force: true });
  });
});
