/**
 * Test-support: build a throwaway two-file DB matching production wiring.
 *
 * Returns a fresh `selene.db` connection with `facts.db` ATTACHed (as `facts`), the
 * disposable `note_state` bookkeeping table, and the backward-compatible `raw_notes` TEMP
 * view (facts.captured_notes LEFT JOIN note_state). Mirrors the module-level wiring in
 * src/lib/db.ts so tests exercise the real read/write split.
 *
 * Lives in src/lib (not a test dir) so production `tsc --noEmit` covers it; it imports only
 * the facts-db helpers — nothing test-only. Caller is responsible for `db.close()`.
 */
import Database, { Database as DatabaseType } from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync } from 'fs';
import { join } from 'path';
import {
  ensureFactsDbInitialized,
  attachFacts,
  ensureNoteStateTable,
  ensureRawNotesView,
} from './facts-db';

/** A throwaway selene.db with facts.db attached + note_state + raw_notes temp view. Caller closes. */
export function makeTwoFileTestDb(): { db: DatabaseType; dir: string } {
  const dir = mkdtempSync(join(tmpdir(), 'selene-2file-'));
  const factsPath = join(dir, 'facts.db');
  ensureFactsDbInitialized(factsPath);
  const db = new Database(join(dir, 'selene.db'));
  attachFacts(db, factsPath);
  ensureNoteStateTable(db);
  ensureRawNotesView(db);
  return { db, dir };
}
