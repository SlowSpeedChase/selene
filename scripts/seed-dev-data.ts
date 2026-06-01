/**
 * seed-dev-data.ts - Seed the Selene development database with fictional notes.
 *
 * Reads fixture notes from generate-dev-fixture.py (run on the fly, or from a
 * file via --fixture) and inserts them into the dev database's raw_notes table
 * in 'pending' status so the normal processing pipeline (dev-process-batch.sh)
 * can pick them up. Content is purely invented — see generate-dev-fixture.py.
 *
 * SAFETY: This script REFUSES to run unless the target database is explicitly
 * marked `_selene_metadata.environment = 'development'`. It re-checks the marker
 * itself rather than trusting SELENE_ENV, so it can never write to the
 * production database even if the environment variable is misconfigured.
 *
 * Usage:
 *   SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts
 *   SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts --count 300
 *   SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts --fixture out.json
 */

import { createHash } from 'crypto';
import { execFileSync } from 'child_process';
import { readFileSync } from 'fs';
import { join } from 'path';
import type { Database as DatabaseType } from 'better-sqlite3';

import { config } from '../src/lib/config';
import { openSeleneConnection } from '../src/lib/open-selene-connection';

const CAPTURE_TYPE = 'dev-fixture';
const TEST_RUN = 'dev-seed';

interface FixtureNote {
  title: string;
  content: string;
  created_at: string;
}

interface SeedOptions {
  count: number;
  fixturePath: string | null;
}

function parseArgs(argv: string[]): SeedOptions {
  let count = 500;
  let fixturePath: string | null = null;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--count') {
      count = parseInt(argv[i + 1] ?? '500', 10);
      i += 1;
    } else if (arg === '--fixture') {
      fixturePath = argv[i + 1] ?? null;
      i += 1;
    }
  }
  return { count, fixturePath };
}

function loadFixture(options: SeedOptions): FixtureNote[] {
  let raw: string;
  if (options.fixturePath) {
    raw = readFileSync(options.fixturePath, 'utf-8');
  } else {
    const script = join(config.projectRoot, 'scripts', 'generate-dev-fixture.py');
    raw = execFileSync(
      'python3',
      [script, '--count', String(options.count)],
      { encoding: 'utf-8', maxBuffer: 64 * 1024 * 1024 }
    );
  }
  const parsed: unknown = JSON.parse(raw);
  if (!Array.isArray(parsed)) {
    throw new Error('Fixture is not a JSON array of notes');
  }
  return parsed as FixtureNote[];
}

/**
 * Open the dev database (FULLY two-file wired) and refuse unless it is marked development.
 * This is an independent guard — it does not rely on SELENE_ENV being set.
 *
 * Fact-store split: a captured note is a FACT, so fixtures are inserted into
 * facts.captured_notes (not the read-only raw_notes view). We therefore open via
 * openSeleneConnection (ATTACHes facts + builds the temp view), then run the dev-marker guard
 * against selene.db's own `_selene_metadata` (it lives in main, not facts). The guard reads the
 * SELENE.DB marker on purpose: that file is the per-environment anchor and is what create-dev-db.sh
 * stamps.
 */
function openGuardedDevDb(dbPath: string, factsPath: string): DatabaseType {
  const database = openSeleneConnection(dbPath, factsPath);
  let marker: { value: string } | undefined;
  try {
    marker = database
      .prepare("SELECT value FROM _selene_metadata WHERE key = 'environment'")
      .get() as { value: string } | undefined;
  } catch {
    database.close();
    throw new Error(
      `Refusing to seed: ${dbPath} has no _selene_metadata table. ` +
        `This does not look like a Selene dev database. Run scripts/create-dev-db.sh first.`
    );
  }
  if (!marker || marker.value !== 'development') {
    database.close();
    throw new Error(
      `Refusing to seed: ${dbPath} is marked environment='${marker?.value ?? 'unknown'}', ` +
        `expected 'development'. This guard prevents ever writing fixtures into production.`
    );
  }
  return database;
}

function main(): void {
  const options = parseArgs(process.argv.slice(2));
  const dbPath = config.dbPath;
  const factsPath = config.factsDbPath;

  console.log(`Seeding dev database: ${dbPath}`);
  console.log(`Facts database:       ${factsPath}`);
  const database = openGuardedDevDb(dbPath, factsPath);
  // openSeleneConnection already applied WAL + busy_timeout pragmas.

  const notes = loadFixture(options);
  console.log(`Loaded ${notes.length} fictional notes from fixture.`);

  // Fact-store split: fixtures are immutable note FACTS → facts.captured_notes (NOT the read-only
  // raw_notes view, NOT a `status` column). With no note_state row, each note reads back as
  // status='pending' through the view's COALESCE default — exactly what dev-process-batch expects.
  const insert = database.prepare(
    `INSERT INTO facts.captured_notes
       (title, content, content_hash, tags, word_count, character_count,
        created_at, test_run, capture_type)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  // facts.captured_notes' content_hash index is NON-unique (the migration keeps it that way so it
  // can't fail on historical duplicate hashes), so `INSERT OR IGNORE` would no longer dedup — it'd
  // happily insert duplicate fixtures on a re-seed. Preserve the old UNIQUE-content_hash idempotency
  // with an explicit existence check inside the transaction.
  const exists = database.prepare(
    `SELECT 1 FROM facts.captured_notes WHERE content_hash = ? LIMIT 1`
  );

  let inserted = 0;
  let skipped = 0;
  const insertAll = database.transaction((items: FixtureNote[]) => {
    for (const note of items) {
      const contentHash = createHash('sha256')
        .update(note.title + note.content)
        .digest('hex');
      if (exists.get(contentHash)) {
        skipped += 1;
        continue;
      }
      const tags = note.content.match(/#\w+/g) || [];
      const wordCount = note.content.split(/\s+/).filter(Boolean).length;
      const characterCount = note.content.length;
      insert.run(
        note.title,
        note.content,
        contentHash,
        JSON.stringify(tags),
        wordCount,
        characterCount,
        note.created_at,
        TEST_RUN,
        CAPTURE_TYPE
      );
      inserted += 1;
    }
  });

  insertAll(notes);
  database.close();

  console.log('');
  console.log('=== Seed Summary ===');
  console.log(`  Inserted:  ${inserted}`);
  console.log(`  Skipped (duplicate hash): ${skipped}`);
  console.log(`  capture_type: ${CAPTURE_TYPE}`);
  console.log(`  test_run:     ${TEST_RUN}`);
  console.log(`  status:       pending`);
  console.log('');
  console.log('Next: SELENE_ENV=development ./scripts/dev-process-batch.sh');
}

main();
