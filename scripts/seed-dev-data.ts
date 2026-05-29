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
import Database from 'better-sqlite3';

import { config } from '../src/lib/config';

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
 * Open the dev database directly and refuse unless it is marked development.
 * This is an independent guard — it does not rely on SELENE_ENV being set.
 */
function openGuardedDevDb(dbPath: string): Database.Database {
  const database = new Database(dbPath);
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

  console.log(`Seeding dev database: ${dbPath}`);
  const database = openGuardedDevDb(dbPath);
  database.pragma('journal_mode = WAL');

  const notes = loadFixture(options);
  console.log(`Loaded ${notes.length} fictional notes from fixture.`);

  const insert = database.prepare(
    `INSERT OR IGNORE INTO raw_notes
       (title, content, content_hash, tags, word_count, character_count,
        created_at, status, test_run, capture_type)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
  );

  let inserted = 0;
  let skipped = 0;
  const insertAll = database.transaction((items: FixtureNote[]) => {
    for (const note of items) {
      const contentHash = createHash('sha256')
        .update(note.title + note.content)
        .digest('hex');
      const tags = note.content.match(/#\w+/g) || [];
      const wordCount = note.content.split(/\s+/).filter(Boolean).length;
      const characterCount = note.content.length;
      const result = insert.run(
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
      if (result.changes > 0) {
        inserted += 1;
      } else {
        skipped += 1;
      }
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
