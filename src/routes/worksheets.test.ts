import assert from 'assert';
import Database from 'better-sqlite3';
import { mkdtempSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

// CRITICAL: point the app's db singleton at a throwaway temp DB BEFORE importing
// anything that pulls in src/lib/config -> src/lib/db. SELENE_DB_PATH wins over
// every environment branch in config.ts, so this can never touch the real prod DB.
const TEST_DB_DIR = mkdtempSync(join(tmpdir(), 'selene-worksheets-test-'));
const TEST_DB_PATH = join(TEST_DB_DIR, 'selene.db');
process.env.SELENE_DB_PATH = TEST_DB_PATH;
// Force production env so db.ts skips its dev/test _selene_metadata fail-safe.
// SELENE_DB_PATH still wins over path resolution, so this points at the throwaway
// temp DB above — it can NEVER touch the real prod DB (~/selene-data/selene.db).
// Setting before config/db import; override:true in config only applies to .env.development
// which is skipped when SELENE_ENV === 'production'.
process.env.SELENE_ENV = 'production';

// Seed the throwaway DB with the minimal raw_notes schema the route + ingest need.
function seedSchema(): void {
  const db = new Database(TEST_DB_PATH);
  db.exec(`
    CREATE TABLE raw_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      content_hash TEXT UNIQUE NOT NULL,
      tags TEXT,
      word_count INTEGER DEFAULT 0,
      character_count INTEGER DEFAULT 0,
      created_at DATETIME NOT NULL,
      status TEXT DEFAULT 'pending',
      inbox_status TEXT DEFAULT 'pending',
      test_run TEXT,
      calendar_event TEXT,
      capture_type TEXT DEFAULT 'drafts',
      source_uuid TEXT,
      source_note_id INTEGER REFERENCES raw_notes(id)
    );
  `);
  db.close();
}

seedSchema();

const TEST_RUN = `test-worksheets-${Date.now()}`;

async function runTests() {
  console.log('Testing worksheet routes...\n');
  console.log(`Using throwaway DB: ${TEST_DB_PATH}\n`);

  // Lazy import AFTER SELENE_DB_PATH is set so the db singleton resolves correctly.
  const Fastify = (await import('fastify')).default;
  const { worksheetRoutes } = await import('./worksheets');

  console.log('Test 1: GET /api/worksheets/today returns a free_capture worksheet');
  {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({ method: 'GET', url: '/api/worksheets/today' });
    assert.strictEqual(res.statusCode, 200, `expected 200, got ${res.statusCode}`);
    assert.strictEqual(res.json().fields[0].kind, 'free_capture');
    await app.close();
    console.log('  ✓ PASS');
  }

  console.log('Test 2: POST answers creates a note for non-blank text and skips blanks');
  {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({
      method: 'POST',
      url: '/api/worksheets/ws_test/answers',
      payload: {
        worksheetId: 'ws_test',
        test_run: TEST_RUN,
        answers: [
          { fieldId: 'f1', chosenAction: 'new_note', text: `dentist ${TEST_RUN}` },
          { fieldId: 'f2', chosenAction: 'new_note', text: '   ' },
        ],
      },
    });
    assert.strictEqual(res.statusCode, 200, `expected 200, got ${res.statusCode}`);
    const body = res.json();
    assert.strictEqual(body.results[0].outcome, 'applied');
    assert.strictEqual(typeof body.results[0].noteId, 'number');
    assert.strictEqual(body.results[1].outcome, 'skipped');
    await app.close();
    console.log('  ✓ PASS');
  }

  console.log('Test 3: POST with missing answers array returns 400');
  {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({
      method: 'POST',
      url: '/api/worksheets/ws_test/answers',
      payload: { worksheetId: 'ws_test' },
    });
    assert.strictEqual(res.statusCode, 400, `expected 400, got ${res.statusCode}`);
    await app.close();
    console.log('  ✓ PASS');
  }

  console.log('\nAll worksheet route tests passed ✓');
}

runTests().catch((err) => {
  console.error('\nTEST FAILED:', err);
  process.exit(1);
});
