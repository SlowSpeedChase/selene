import assert from 'assert';
import Database from 'better-sqlite3';
import { redirectSeleneSingleton } from '../lib/test-two-file-db';

// distill-essences imports `db` from '../lib', which opens a real connection on import
// (keyed on SELENE_ENV / SELENE_DB_PATH / SELENE_FACTS_DB_PATH). Redirect that singleton to
// throwaway temp files BEFORE importing the module-under-test so the import is harmless.
const { restore } = redirectSeleneSingleton('selene-distill-essences-test-');

import { getNotesNeedingEssence, ensureEssenceColumns } from './distill-essences';

interface ColumnInfo {
  name: string;
}

function columnNames(db: Database.Database): string[] {
  return (db.prepare('PRAGMA table_info(processed_notes)').all() as ColumnInfo[]).map((c) => c.name);
}

describe('distill-essences', () => {
  afterAll(() => restore());

  it('getNotesNeedingEssence + ensureEssenceColumns are exported', () => {
    assert.strictEqual(typeof getNotesNeedingEssence, 'function');
    assert.strictEqual(typeof ensureEssenceColumns, 'function', 'ensureEssenceColumns must be exported');
  });

  // distill-essences self-migrates the essence columns it depends on.
  // Regression for the fresh-DB ordering bug: essence/essence_at used to be
  // created only by export-obsidian (which runs LAST), so distill's own
  // `WHERE pn.essence IS NULL` query threw "no such column" on a fresh DB.
  it('ensureEssenceColumns creates essence + essence_at on a table that lacks them', () => {
    const db = new Database(':memory:');
    db.exec('CREATE TABLE processed_notes (id INTEGER PRIMARY KEY, raw_note_id INTEGER)');
    assert.ok(!columnNames(db).includes('essence'), 'precondition: essence column absent');

    ensureEssenceColumns(db);

    const cols = columnNames(db);
    assert.ok(cols.includes('essence'), 'essence column created');
    assert.ok(cols.includes('essence_at'), 'essence_at column created');
  });

  // idempotent — running again on a table that already has the columns is a no-op.
  it('ensureEssenceColumns is idempotent', () => {
    const db = new Database(':memory:');
    db.exec('CREATE TABLE processed_notes (id INTEGER PRIMARY KEY, raw_note_id INTEGER, essence TEXT, essence_at TEXT)');
    ensureEssenceColumns(db); // must not throw on duplicate column
    assert.ok(columnNames(db).includes('essence'));
  });
});
