/**
 * Seed Test Data Script
 *
 * Populates the database with curated fake notes for testing thread detection.
 * Notes are marked with test_run='seed-test' for easy cleanup.
 *
 * Usage: npx ts-node scripts/seed-test-data.ts [--clear-only]
 */

import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import Database from 'better-sqlite3';

// Use local database path (not production)
const DB_PATH = path.join(__dirname, '..', 'data', 'selene.db');
const TEST_NOTES_PATH = path.join(__dirname, 'test-notes.json');
const TEST_RUN_MARKER = 'seed-test';

interface TestNote {
  title: string;
  content: string;
  created_at: string;
  expected_cluster: string;
  tags?: string[];
  edge_case?: string;
}

interface TestNotesFile {
  metadata: {
    description: string;
    version: string;
    created: string;
    story: string;
    note_count: number;
  };
  clusters: Record<string, {
    expected_thread_name: string | null;
    description: string;
  }>;
  notes: TestNote[];
}

function generateContentHash(content: string): string {
  return crypto.createHash('sha256').update(content).digest('hex');
}

function clearTestData(db: Database.Database): void {
  console.log('Clearing existing test data...');

  // Delete test notes
  const deleteNotes = db.prepare('DELETE FROM raw_notes WHERE test_run = ?');
  const notesDeleted = deleteNotes.run(TEST_RUN_MARKER);
  console.log(`  Deleted ${notesDeleted.changes} test notes`);

  // Clear thread tables completely (for fresh detection)
  const tables = ['thread_notes', 'thread_history', 'threads'];
  for (const table of tables) {
    try {
      const result = db.prepare(`DELETE FROM ${table}`).run();
      console.log(`  Cleared ${result.changes} rows from ${table}`);
    } catch (err) {
      console.log(`  Table ${table} may not exist, skipping`);
    }
  }

  // Clear embeddings and associations for test notes
  // (We want to recompute these from scratch)
  try {
    db.prepare('DELETE FROM note_embeddings').run();
    db.prepare('DELETE FROM note_associations').run();
    console.log('  Cleared embeddings and associations');
  } catch (err) {
    console.log('  Embeddings/associations tables may not exist');
  }
}

function insertTestNotes(db: Database.Database, notes: TestNote[]): number {
  console.log(`\nInserting ${notes.length} test notes...`);

  const insertStmt = db.prepare(`
    INSERT INTO raw_notes
    (title, content, content_hash, tags, word_count, character_count, created_at, status, test_run)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)
  `);

  let inserted = 0;
  const insertAll = db.transaction(() => {
    for (const note of notes) {
      const wordCount = note.content.split(/\s+/).filter(Boolean).length;
      const characterCount = note.content.length;
      const hash = generateContentHash(note.content);
      const tags = JSON.stringify(note.tags || []);

      try {
        insertStmt.run(
          note.title,
          note.content,
          hash,
          tags,
          wordCount,
          characterCount,
          note.created_at,
          TEST_RUN_MARKER
        );
        inserted++;
      } catch (err) {
        const error = err as Error;
        if (error.message.includes('UNIQUE constraint')) {
          console.log(`  Skipping duplicate: ${note.title}`);
        } else {
          throw err;
        }
      }
    }
  });

  insertAll();
  return inserted;
}

function printSummary(db: Database.Database, notesFile: TestNotesFile): void {
  console.log('\n--- Summary ---');

  // Count notes by cluster
  const clusterCounts: Record<string, number> = {};
  for (const note of notesFile.notes) {
    const cluster = note.expected_cluster;
    clusterCounts[cluster] = (clusterCounts[cluster] || 0) + 1;
  }

  console.log('\nExpected clusters:');
  for (const [cluster, count] of Object.entries(clusterCounts).sort()) {
    const info = notesFile.clusters[cluster];
    const name = info?.expected_thread_name || '(orphan)';
    console.log(`  ${cluster}: ${count} notes -> "${name}"`);
  }

  // Count actual notes in database
  const dbCount = db.prepare(
    'SELECT COUNT(*) as count FROM raw_notes WHERE test_run = ?'
  ).get(TEST_RUN_MARKER) as { count: number };

  console.log(`\nDatabase state:`);
  console.log(`  Test notes: ${dbCount.count}`);
  console.log(`  Test marker: ${TEST_RUN_MARKER}`);
  console.log('\nReady for embedding generation.');
}

function main(): void {
  const clearOnly = process.argv.includes('--clear-only');

  console.log('=== Seed Test Data ===\n');
  console.log(`Database: ${DB_PATH}`);
  console.log(`Test notes: ${TEST_NOTES_PATH}`);

  // Check files exist
  if (!fs.existsSync(DB_PATH)) {
    console.error(`Database not found: ${DB_PATH}`);
    process.exit(1);
  }

  if (!clearOnly && !fs.existsSync(TEST_NOTES_PATH)) {
    console.error(`Test notes file not found: ${TEST_NOTES_PATH}`);
    process.exit(1);
  }

  // Open database
  const db = new Database(DB_PATH);
  db.pragma('journal_mode = WAL');

  try {
    // Clear existing test data
    clearTestData(db);

    if (clearOnly) {
      console.log('\n--clear-only flag set, skipping note insertion');
      return;
    }

    // Load and insert test notes
    const notesFile: TestNotesFile = JSON.parse(
      fs.readFileSync(TEST_NOTES_PATH, 'utf-8')
    );

    const inserted = insertTestNotes(db, notesFile.notes);
    console.log(`\nInserted ${inserted} notes`);

    // Print summary
    printSummary(db, notesFile);

  } finally {
    db.close();
  }
}

main();
