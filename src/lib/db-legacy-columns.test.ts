/**
 * Fact-store split — the legacy raw_notes column-add must not run against a VIEW.
 *
 * db.ts startup ensures raw_notes has source_note_id + inbox_status via idempotent ALTERs. That is
 * only valid on a legacy SINGLE-FILE DB where raw_notes is a PHYSICAL table. Post-migration raw_notes
 * is a per-connection VIEW; `ALTER TABLE <view>` throws at module load → the server would fail to
 * start. `ensureLegacyRawNotesColumns` must therefore no-op whenever raw_notes is not a real table.
 *
 * Redirect the db.ts singleton to throwaway files before importing it (it opens a connection on
 * import); force production env so the import skips the dev/test _selene_metadata verification.
 */
import { tmpdir } from 'os';
import { mkdtempSync } from 'fs';
import { join } from 'path';
import Database from 'better-sqlite3';
import { makeTwoFileTestDb, redirectSeleneSingleton } from './test-two-file-db';

// Redirect the db.ts singleton to throwaway files BEFORE it is imported (db.ts opens a real
// connection on import); production env so the import skips the dev/test _selene_metadata check.
const { restore: restoreSingletonEnv } = redirectSeleneSingleton('selene-legacycols-singleton-');

import { ensureLegacyRawNotesColumns } from './db';

describe('ensureLegacyRawNotesColumns', () => {
  afterAll(() => {
    restoreSingletonEnv();
  });

  it('adds source_note_id + inbox_status to a legacy PHYSICAL raw_notes table that lacks them', () => {
    const dir = mkdtempSync(join(tmpdir(), 'selene-legacycols-phys-'));
    const conn = new Database(join(dir, 'x.db'));
    conn.exec(`CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT)`);

    ensureLegacyRawNotesColumns(conn);

    const cols = (conn.prepare(`PRAGMA table_info(raw_notes)`).all() as Array<{ name: string }>).map((c) => c.name);
    expect(cols).toContain('source_note_id');
    expect(cols).toContain('inbox_status');
    conn.close();
  });

  it('does NOT attempt ALTER when raw_notes is a VIEW missing those columns (ALTER on a view would throw)', () => {
    const two = makeTwoFileTestDb();
    // Replace the standard view with one that omits inbox_status + source_note_id, so the OLD
    // (unguarded) code would try to ALTER and throw. The guard must skip it entirely.
    two.db.exec('DROP VIEW raw_notes');
    two.db.exec(`CREATE TEMP VIEW raw_notes AS SELECT cn.id AS id, cn.title AS title FROM facts.captured_notes cn`);

    expect(() => ensureLegacyRawNotesColumns(two.db)).not.toThrow();

    // The view is untouched — still exactly id, title.
    const cols = (two.db.prepare(`PRAGMA table_info(raw_notes)`).all() as Array<{ name: string }>).map((c) => c.name);
    expect(cols).toEqual(['id', 'title']);
    two.db.close();
  });
});
