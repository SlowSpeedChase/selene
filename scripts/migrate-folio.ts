// scripts/migrate-folio.ts
import Database from 'better-sqlite3';
import { join } from 'path';
import { homedir } from 'os';

const dbPath = process.env.SELENE_DB_PATH || join(homedir(), 'selene-data/selene.db');
const db = new Database(dbPath);

const hasColumn = db
  .prepare("SELECT COUNT(*) as count FROM pragma_table_info('raw_notes') WHERE name = 'status_folio'")
  .get() as { count: number };

if (hasColumn.count === 0) {
  db.prepare("ALTER TABLE raw_notes ADD COLUMN status_folio TEXT DEFAULT NULL").run();
  console.log('Migration complete: added status_folio column to raw_notes');
} else {
  console.log('Column status_folio already exists — skipping');
}

db.close();
