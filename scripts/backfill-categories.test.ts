/**
 * Fact-store split — backfill-categories' export-flag reset must NOT write the read-only
 * `raw_notes` view. Post-migration `raw_notes` is a per-connection view and `exported_to_obsidian`
 * lives in `note_state`; the old `UPDATE raw_notes SET exported_to_obsidian = 0` throws
 * ("cannot modify raw_notes because it is a view"). `resetExportFlagsForProcessed` must read the
 * target ids from the view and write the flag via `setNoteState` (the codebase's note_state writer).
 *
 * Redirect the db.ts singleton to throwaway files BEFORE importing the script (it opens a real
 * connection on import). Force production env so config.testRunFilter() yields `test_run IS NULL`
 * and the import skips the dev/test `_selene_metadata` verification. Assertions drive an EXPLICIT
 * two-file connection, never the singleton.
 */
import { makeTwoFileTestDb, redirectSeleneSingleton } from '../src/lib/test-two-file-db';

// Redirect the db.ts singleton to throwaway files BEFORE the script is imported (it opens a
// real connection on import); production env so config.testRunFilter() yields `test_run IS NULL`
// and the import skips the dev/test _selene_metadata verification.
const { restore: restoreSingletonEnv } = redirectSeleneSingleton('selene-backfill-singleton-');

import { insertNote } from '../src/lib/db';
import { setNoteState } from '../src/lib/note-state';
import { resetExportFlagsForProcessed } from './backfill-categories';

describe('backfill-categories resetExportFlagsForProcessed (writes note_state, not the read-only view)', () => {
  let two: ReturnType<typeof makeTwoFileTestDb>;

  beforeEach(() => {
    two = makeTwoFileTestDb();
  });
  afterEach(() => {
    two.db.close();
  });
  afterAll(() => {
    restoreSingletonEnv();
  });

  it('resets exported_to_obsidian=0 for processed notes via note_state, without writing the read-only raw_notes view', () => {
    // a, b are processed + already exported; c is left pending (no note_state row).
    const a = insertNote({ title: 'A', content: 'a', contentHash: 'h-a', tags: [], createdAt: '2026-05-31T00:00:00Z' }, two.db);
    const b = insertNote({ title: 'B', content: 'b', contentHash: 'h-b', tags: [], createdAt: '2026-05-31T00:00:00Z' }, two.db);
    const c = insertNote({ title: 'C', content: 'c', contentHash: 'h-c', tags: [], createdAt: '2026-05-31T00:00:00Z' }, two.db);
    setNoteState(two.db, a, { status: 'processed', exported_to_obsidian: 1 });
    setNoteState(two.db, b, { status: 'processed', exported_to_obsidian: 1 });

    // Must NOT throw (the old UPDATE raw_notes threw against the view).
    const count = resetExportFlagsForProcessed(two.db);

    expect(count).toBe(2);
    const flags = two.db
      .prepare('SELECT raw_note_id, exported_to_obsidian FROM note_state ORDER BY raw_note_id')
      .all() as Array<{ raw_note_id: number; exported_to_obsidian: number }>;
    expect(flags).toEqual([
      { raw_note_id: a, exported_to_obsidian: 0 },
      { raw_note_id: b, exported_to_obsidian: 0 },
    ]);

    // c stayed pending — the reset must not fabricate a note_state row for an unprocessed note.
    const cState = two.db.prepare('SELECT COUNT(*) AS n FROM note_state WHERE raw_note_id = ?').get(c) as { n: number };
    expect(cState.n).toBe(0);
  });
});
