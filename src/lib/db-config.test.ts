import Database from 'better-sqlite3';
import { applyConnectionPragmas } from './db-config';

describe('applyConnectionPragmas', () => {
  it('sets a busy_timeout so a workflow waits for a lock instead of throwing SQLITE_BUSY', () => {
    // Regression guard for the nightly synthesize-topics crash: with the default
    // busy_timeout of 0, any overlap with the every-5-min process-llm writer made
    // synthesize throw `SQLITE_BUSY: database is locked` and exit 1.
    const db = new Database(':memory:');
    applyConnectionPragmas(db);
    expect(db.pragma('busy_timeout', { simple: true })).toBe(30000);
    db.close();
  });
});
