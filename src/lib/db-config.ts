import Database from 'better-sqlite3';

type DB = InstanceType<typeof Database>;

/**
 * Pragmas applied to every Selene SQLite connection.
 *
 * - `journal_mode = WAL`: concurrent readers + a single writer.
 * - `busy_timeout = 30000`: wait up to 30s for a lock instead of throwing
 *   `SQLITE_BUSY` immediately (the default timeout is 0). Each workflow runs as a
 *   separate process with its own connection to the same file, so the long nightly
 *   `synthesize-topics` run used to collide with the every-5-minute `process-llm`
 *   writer and crash (exit 1). Waiting for the lock fixes that systemically.
 */
export function applyConnectionPragmas(db: DB): void {
  db.pragma('journal_mode = WAL');
  db.pragma('busy_timeout = 30000');
}
