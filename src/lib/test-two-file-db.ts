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
import { mkdtempSync, rmSync } from 'fs';
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

/** The three env vars that key db.ts's module singleton (config.ts reads them at import time). */
const SINGLETON_ENV_KEYS = ['SELENE_ENV', 'SELENE_DB_PATH', 'SELENE_FACTS_DB_PATH'] as const;

/**
 * Redirect db.ts's module SINGLETON to throwaway temp files BEFORE db.ts is imported.
 *
 * db.ts opens a real connection on import, keyed on SELENE_ENV / SELENE_DB_PATH /
 * SELENE_FACTS_DB_PATH. A test that imports db.ts (or anything that imports it) must call this
 * at top-of-module, in the SAME source position where the env redirect must run — i.e. BEFORE
 * the `import { ... } from './db'` line. (TS CommonJS emit keeps `require()` calls in source
 * order, so a call placed above the db import runs before db.ts loads.) Forcing
 * SELENE_ENV='production' makes that import skip the dev/test `_selene_metadata` verification
 * (which would throw on a fresh throwaway DB). The singleton is never used for assertions —
 * tests inject an explicit two-file connection (see `makeTwoFileTestDb`).
 *
 * Jest shares process.env across files in a worker without restoring it, so the snapshot is
 * taken here at call time and `restore()` (call from `afterAll`) resets the three keys to their
 * EXACT prior values (a previously-unset key is DELETED, not set to the string "undefined") AND
 * removes the temp dir — otherwise a later file in the same worker re-evaluates config.ts against
 * leaked env (order-dependent flakiness) and the temp dir leaks.
 */
export function redirectSeleneSingleton(prefix: string): { dir: string; restore: () => void } {
  const savedEnv: Record<string, string | undefined> = {};
  for (const k of SINGLETON_ENV_KEYS) savedEnv[k] = process.env[k];

  process.env.SELENE_ENV = 'production';
  const dir = mkdtempSync(join(tmpdir(), prefix));
  process.env.SELENE_DB_PATH = join(dir, 'selene.db');
  process.env.SELENE_FACTS_DB_PATH = join(dir, 'facts.db');

  const restore = (): void => {
    for (const k of SINGLETON_ENV_KEYS) {
      if (savedEnv[k] === undefined) delete process.env[k];
      else process.env[k] = savedEnv[k];
    }
    rmSync(dir, { recursive: true, force: true });
  };

  return { dir, restore };
}
