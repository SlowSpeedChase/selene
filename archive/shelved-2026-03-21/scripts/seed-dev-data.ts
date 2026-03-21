/**
 * Seed Development Database
 *
 * Reads a JSON fixture file and populates the dev database with notes,
 * then runs all processing workflows to fully hydrate the data.
 *
 * Prerequisites:
 *   - Dev database created via: ./scripts/create-dev-db.sh
 *   - Fixture generated via: copy prompt from scripts/dev-data-prompt.md into an LLM
 *   - Fixture saved to: fixtures/dev-seed-notes.json
 *   - Ollama running with mistral:7b and nomic-embed-text models
 *
 * Usage:
 *   SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts
 *
 * Options:
 *   --skip-workflows   Insert notes only, skip processing workflows
 */

import { createHash } from 'crypto';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { execSync } from 'child_process';

// ── Safety check: must be running in development environment ──────────────

if (process.env.SELENE_ENV !== 'development') {
  console.error('ERROR: This script must run with SELENE_ENV=development');
  console.error('Usage: SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts');
  process.exit(1);
}

// ── Imports that trigger DB connection (after env check) ──────────────────

import { db, insertNote } from '../src/lib/db';

// ── Constants ─────────────────────────────────────────────────────────────

const PROJECT_ROOT = join(__dirname, '..');
const FIXTURE_PATH = join(PROJECT_ROOT, 'fixtures', 'dev-seed-notes.json');
const SKIP_WORKFLOWS = process.argv.includes('--skip-workflows');

// ── Types ─────────────────────────────────────────────────────────────────

interface FixtureNote {
  title: string;
  content: string;
  created_at: string;
  tags: string[];
}

// ── Helpers ───────────────────────────────────────────────────────────────

function sha256(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

function getNoteCount(): number {
  const row = db.prepare('SELECT COUNT(*) as count FROM raw_notes').get() as { count: number };
  return row.count;
}

function getPendingCount(): number {
  const row = db.prepare("SELECT COUNT(*) as count FROM raw_notes WHERE status = 'pending'").get() as { count: number };
  return row.count;
}

function getTableCount(table: string): number {
  try {
    const row = db.prepare(`SELECT COUNT(*) as count FROM ${table}`).get() as { count: number };
    return row.count;
  } catch {
    return 0;
  }
}

function runWorkflow(name: string, scriptPath: string): void {
  console.log(`\n  Running ${name}...`);
  try {
    execSync(`SELENE_ENV=development npx ts-node ${scriptPath}`, {
      stdio: 'inherit',
      cwd: PROJECT_ROOT,
      timeout: 600_000, // 10 minutes per workflow run
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error(`  WARNING: ${name} exited with error: ${error.message}`);
    console.error(`  Continuing with remaining workflows...`);
  }
}

function runWorkflowUntilDone(name: string, scriptPath: string): void {
  console.log(`\n  Running ${name} (looping until all notes processed)...`);
  let pending = getPendingCount();
  let iteration = 0;

  while (pending > 0) {
    iteration++;
    console.log(`    Iteration ${iteration}: ${pending} notes pending...`);
    try {
      execSync(`SELENE_ENV=development npx ts-node ${scriptPath}`, {
        stdio: 'inherit',
        cwd: PROJECT_ROOT,
        timeout: 600_000,
      });
    } catch (err: unknown) {
      const error = err as Error;
      console.error(`  WARNING: ${name} iteration ${iteration} error: ${error.message}`);
    }

    const newPending = getPendingCount();
    if (newPending === pending) {
      console.log(`    No progress made (still ${pending} pending). Breaking loop.`);
      break;
    }
    pending = newPending;
  }

  if (pending === 0) {
    console.log(`    All notes processed.`);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────

function main(): void {
  console.log('=== Seed Development Database ===\n');

  // 1. Check fixture file exists
  if (!existsSync(FIXTURE_PATH)) {
    console.error(`ERROR: Fixture file not found: ${FIXTURE_PATH}`);
    console.error('');
    console.error('To generate fixture data:');
    console.error('  1. Copy the prompt from scripts/dev-data-prompt.md');
    console.error('  2. Paste it into an LLM (Claude or ChatGPT)');
    console.error('  3. Save the JSON output to fixtures/dev-seed-notes.json');
    process.exit(1);
  }

  // 2. Check database is empty
  const existingCount = getNoteCount();
  if (existingCount > 0) {
    console.error(`ERROR: Database already contains ${existingCount} notes.`);
    console.error('To start fresh, reset the dev database first:');
    console.error('  ./scripts/create-dev-db.sh');
    process.exit(1);
  }

  // 3. Load and validate fixture data
  console.log(`Loading fixture: ${FIXTURE_PATH}`);
  let notes: FixtureNote[];
  try {
    const raw = readFileSync(FIXTURE_PATH, 'utf-8');
    notes = JSON.parse(raw) as FixtureNote[];
  } catch (err: unknown) {
    const error = err as Error;
    console.error(`ERROR: Failed to parse fixture JSON: ${error.message}`);
    process.exit(1);
  }

  if (!Array.isArray(notes) || notes.length === 0) {
    console.error('ERROR: Fixture must be a non-empty JSON array of note objects.');
    process.exit(1);
  }

  // Validate shape of first note
  const sample = notes[0];
  if (!sample.title || !sample.content || !sample.created_at || !Array.isArray(sample.tags)) {
    console.error('ERROR: Fixture notes must have { title, content, created_at, tags } fields.');
    console.error('Got:', JSON.stringify(sample, null, 2));
    process.exit(1);
  }

  console.log(`Found ${notes.length} notes in fixture.\n`);

  // 4. Insert notes in a transaction
  console.log('Inserting notes...');
  const startTime = Date.now();

  const insertAll = db.transaction(() => {
    for (let i = 0; i < notes.length; i++) {
      const note = notes[i];
      const contentHash = sha256(note.title + note.content + note.created_at);

      insertNote({
        title: note.title,
        content: note.content,
        contentHash,
        tags: note.tags,
        createdAt: note.created_at,
      });

      // Progress every 100 notes
      if ((i + 1) % 100 === 0) {
        console.log(`  Inserted ${i + 1}/${notes.length} notes...`);
      }
    }
  });

  insertAll();

  const insertDuration = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\nInserted ${notes.length} notes in ${insertDuration}s.\n`);

  // 5. Run processing workflows
  if (SKIP_WORKFLOWS) {
    console.log('--skip-workflows flag set. Skipping processing.\n');
  } else {
    console.log('=== Running Processing Workflows ===');

    // process-llm needs to loop since it processes in batches
    runWorkflowUntilDone('process-llm', 'src/workflows/process-llm.ts');

    // extract-tasks also processes pending notes
    runWorkflow('extract-tasks', 'src/workflows/extract-tasks.ts');

    // index-vectors builds embeddings
    runWorkflow('index-vectors', 'src/workflows/index-vectors.ts');

    // compute-relationships finds associations
    runWorkflow('compute-relationships', 'src/workflows/compute-relationships.ts');

    // detect-threads clusters notes into threads
    runWorkflow('detect-threads', 'src/workflows/detect-threads.ts');

    // reconsolidate-threads generates summaries
    runWorkflow('reconsolidate-threads', 'src/workflows/reconsolidate-threads.ts');

    // export-obsidian syncs to vault
    runWorkflow('export-obsidian', 'src/workflows/export-obsidian.ts');

    console.log('\n=== Workflows Complete ===\n');
  }

  // 6. Print summary
  console.log('=== Database Summary ===\n');
  console.log(`  raw_notes:         ${getTableCount('raw_notes')}`);
  console.log(`  processed_notes:   ${getTableCount('processed_notes')}`);
  console.log(`  threads:           ${getTableCount('threads')}`);
  console.log(`  note_associations: ${getTableCount('note_associations')}`);
  console.log(`  note_embeddings:   ${getTableCount('note_embeddings')}`);
  console.log(`  thread_notes:      ${getTableCount('thread_notes')}`);
  console.log('');
  console.log('Dev database seeded successfully.');
}

main();
