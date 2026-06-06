/**
 * openSeleneConnection — the ONE true way to get a `raw_notes`-view-capable connection OUTSIDE
 * the db.ts singleton.
 *
 * The fact-store split made `raw_notes` a per-connection TEMP VIEW over `facts.captured_notes`
 * LEFT JOIN `note_state`. Any connection that wants to read `raw_notes` must therefore: apply the
 * pragmas, ATTACH facts.db AS `facts`, ensure `note_state` exists, and (re)create the temp view —
 * in that exact order (the view DDL hard-codes the `facts.` alias, so ATTACH must come first). The
 * db.ts singleton does this at import; this helper does the same for the three readers that bypass
 * it (folio-feedback, selene-inspect, seed-dev-data).
 *
 * It lives in its own module (not facts-db.ts) to keep facts-db.ts a pure-schema, singleton-free
 * unit, and to avoid any chance of an import cycle: this imports the facts-db helpers; nothing in
 * facts-db imports back.
 *
 * READONLY (verified empirically against real files): a readonly main connection CAN still ATTACH
 * facts (the attached file inherits readonly) and CREATE a TEMP VIEW that references the attached
 * facts db (TEMP objects live in the separate per-connection temp db, exempt from the readonly
 * main). So a readonly caller reads `raw_notes` through the same view as everyone else. Two
 * readonly nuances we handle explicitly:
 *   - `journal_mode = WAL` THROWS on a readonly handle when the file isn't already WAL (switching
 *     journal mode is a write). A real migrated selene.db is left in rollback-journal mode by the
 *     migration, so we MUST skip the WAL pragma on readonly and set only `busy_timeout` (which
 *     never writes). `applyConnectionPragmas` is used as-is for the read-write path.
 *   - We deliberately DO NOT run `ensureFactsDbInitialized` or `ensureNoteStateTable` on a readonly
 *     open — both would try to write (facts.db schema / the note_state CREATE), failing on a
 *     readonly handle and mutating the PRECIOUS facts file. The facts file is never touched by a
 *     readonly open (a readonly main makes the attached facts file readonly too).
 */
import Database from 'better-sqlite3';
import type { Database as DatabaseType } from 'better-sqlite3';
import { applyConnectionPragmas } from './db-config';
import {
  ensureFactsDbInitialized,
  attachFacts,
  ensureNoteStateTable,
  ensureRawNotesView,
} from './facts-db';

export interface OpenOpts {
  readonly?: boolean;
  fileMustExist?: boolean;
}

/**
 * Shared /tmp-isolation safety gate for the fact-store probe scripts.
 *
 * Refuses to run unless BOTH the main and facts DB paths are under `/tmp` — so a probe can never
 * touch the real prod/dev store even if its env is misconfigured. Throws on a missing or non-/tmp
 * path; callers let the throw propagate (it exits the probe non-zero before any DB is opened).
 *
 * Homed here because this module is a verified db.ts-free leaf (it imports only ./db-config +
 * ./facts-db). cutover-probe DEFERS importing db.ts until AFTER this guard runs — eagerly importing
 * db.ts opens the singleton against whatever path is set, so the guard must be reachable without
 * pulling in db.ts.
 */
export function assertTmpIsolated(dbPath: string, factsPath: string): void {
  for (const [name, p] of [
    ['SELENE_DB_PATH', dbPath],
    ['SELENE_FACTS_DB_PATH', factsPath],
  ] as const) {
    if (!p) throw new Error(`${name} must be set (this probe is /tmp-only).`);
    if (!p.startsWith('/tmp/')) {
      throw new Error(`${name}=${p} is not under /tmp — refusing (real-store guard).`);
    }
  }
}

/**
 * Open a selene.db connection fully wired for the two-file layout: pragmas + facts ATTACHed
 * + note_state + the raw_notes TEMP view. The one true way to get a view-capable connection
 * outside the db.ts singleton.
 *
 * On a readonly open, facts.db and note_state are assumed to already exist (we never write the
 * precious facts file from a reader); the temp view is still created so readers query `raw_notes`
 * uniformly.
 */
export function openSeleneConnection(
  dbPath: string,
  factsPath: string,
  opts: OpenOpts = {}
): DatabaseType {
  const readonly = opts.readonly ?? false;
  const db = new Database(dbPath, {
    readonly,
    fileMustExist: opts.fileMustExist ?? false,
  });

  if (readonly) {
    // Skip the WAL pragma: it throws on a readonly handle unless the file is already WAL, and a
    // migrated selene.db is left in rollback-journal mode. busy_timeout never writes, so it's safe.
    db.pragma('busy_timeout = 30000');
  } else {
    applyConnectionPragmas(db); // WAL + busy_timeout
  }

  if (!readonly) {
    // Never write facts on a readonly open: only stand up its schema when we can write.
    ensureFactsDbInitialized(factsPath);
  }
  attachFacts(db, factsPath); // ATTACH ... AS facts (view DDL depends on this alias)
  if (!readonly) {
    ensureNoteStateTable(db); // a CREATE — readonly callers rely on it already existing
  }
  ensureRawNotesView(db); // TEMP view: works on a readonly main (separate temp db)

  return db;
}
