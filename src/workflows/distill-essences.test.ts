import assert from 'assert';
import Database from 'better-sqlite3';

interface ColumnInfo {
  name: string;
}

function columnNames(db: Database.Database): string[] {
  return (db.prepare('PRAGMA table_info(processed_notes)').all() as ColumnInfo[]).map((c) => c.name);
}

async function runTests() {
  const { getNotesNeedingEssence, ensureEssenceColumns } = await import('./distill-essences');

  // Test 1: public surface
  {
    assert.strictEqual(typeof getNotesNeedingEssence, 'function');
    assert.strictEqual(typeof ensureEssenceColumns, 'function', 'ensureEssenceColumns must be exported');
    console.log('  ✓ getNotesNeedingEssence + ensureEssenceColumns are exported');
  }

  // Test 2: distill-essences self-migrates the essence columns it depends on.
  // Regression for the fresh-DB ordering bug: essence/essence_at used to be
  // created only by export-obsidian (which runs LAST), so distill's own
  // `WHERE pn.essence IS NULL` query threw "no such column" on a fresh DB.
  {
    const db = new Database(':memory:');
    db.exec('CREATE TABLE processed_notes (id INTEGER PRIMARY KEY, raw_note_id INTEGER)');
    assert.ok(!columnNames(db).includes('essence'), 'precondition: essence column absent');

    ensureEssenceColumns(db);

    const cols = columnNames(db);
    assert.ok(cols.includes('essence'), 'essence column created');
    assert.ok(cols.includes('essence_at'), 'essence_at column created');
    console.log('  ✓ ensureEssenceColumns creates essence + essence_at on a table that lacks them');
  }

  // Test 3: idempotent — running again on a table that already has the columns is a no-op.
  {
    const db = new Database(':memory:');
    db.exec('CREATE TABLE processed_notes (id INTEGER PRIMARY KEY, raw_note_id INTEGER, essence TEXT, essence_at TEXT)');
    ensureEssenceColumns(db); // must not throw on duplicate column
    assert.ok(columnNames(db).includes('essence'));
    console.log('  ✓ ensureEssenceColumns is idempotent');
  }

  console.log('\nAll distill-essences tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
