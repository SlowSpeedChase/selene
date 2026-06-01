import Database from 'better-sqlite3';
import { migrateToFactStore } from './migrate-to-fact-store';
import { logger } from './logger';

/** Detect a legacy single-file DB (a physical raw_notes table) and either auto-migrate (dev/clone)
 *  or fail loud (prod). MUST run before db.ts opens its long-lived connection so the migration's
 *  journal-mode change has no competing open handle. No-op once two-file. */
export function ensureMigrated(dbPath: string, factsPath: string, env: string): void {
  const probe = new Database(dbPath, { fileMustExist: false });
  let unmigrated = false;
  try {
    const row = probe.prepare(`SELECT type FROM sqlite_master WHERE name = 'raw_notes'`).get() as
      | { type: string } | undefined;
    unmigrated = row?.type === 'table'; // a physical raw_notes table == legacy single-file
  } finally {
    probe.close();
  }
  if (!unmigrated) return;                         // fresh or already two-file → nothing to do
  if (env === 'test') return;                      // tests manage their own DBs
  if (env === 'production') {
    throw new Error(
      `Prod DB at ${dbPath} is not migrated to the fact-store layout. ` +
      `Run scripts/cutover-prod.sh — refusing to serve in the incoherent split state.`
    );
  }
  logger.warn({ dbPath, factsPath }, 'Un-migrated DB detected — auto-migrating to fact-store layout');
  const r = migrateToFactStore(dbPath, factsPath);
  logger.info({ moved: r.notes, reviewRows: r.reviewRows }, 'Auto-migration complete');
}
