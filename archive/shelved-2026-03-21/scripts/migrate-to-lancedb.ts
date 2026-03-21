/**
 * Migration script: Populate LanceDB from existing processed notes
 *
 * Run once to backfill vectors for all existing notes.
 * Safe to run multiple times (skips already indexed).
 */

import {
  db,
  embed,
  isAvailable,
  indexNotes,
  getIndexedNoteIds,
  type NoteVector,
  VECTOR_DIMENSIONS,
} from '../src/lib';

interface NoteRow {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string | null;
}

async function migrate() {
  console.log('=== LanceDB Migration ===\n');

  // Check Ollama
  if (!(await isAvailable())) {
    console.error('ERROR: Ollama is not available. Start Ollama first.');
    process.exit(1);
  }
  console.log('Ollama: OK\n');

  // Get existing indexed IDs
  const indexedIds = await getIndexedNoteIds();
  console.log(`Already indexed: ${indexedIds.size} notes\n`);

  // Get all processed notes
  const notes = db.prepare(`
    SELECT
      rn.id, rn.title, rn.content, rn.created_at,
      pn.primary_theme
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.test_run IS NULL
    ORDER BY rn.created_at
  `).all() as NoteRow[];

  // Filter to unindexed
  const toMigrate = notes.filter(n => !indexedIds.has(n.id));

  console.log(`Total processed notes: ${notes.length}`);
  console.log(`Need migration: ${toMigrate.length}\n`);

  if (toMigrate.length === 0) {
    console.log('Nothing to migrate. All notes already indexed.');
    process.exit(0);
  }

  // Process in batches
  const batchSize = 20;
  let success = 0;
  let errors = 0;

  for (let i = 0; i < toMigrate.length; i += batchSize) {
    const batch = toMigrate.slice(i, i + batchSize);
    const vectors: NoteVector[] = [];

    for (const note of batch) {
      const progress = `[${i + batch.indexOf(note) + 1}/${toMigrate.length}]`;
      process.stdout.write(`${progress} ${note.title.slice(0, 50)}...`);

      try {
        const text = `${note.title}\n\n${note.content}`;
        const vector = await embed(text);

        if (vector.length !== VECTOR_DIMENSIONS) {
          throw new Error(`Bad dimensions: ${vector.length}`);
        }

        vectors.push({
          id: note.id,
          vector,
          title: note.title,
          primary_theme: note.primary_theme,
          note_type: null,
          actionability: null,
          time_horizon: null,
          context: null,
          created_at: note.created_at,
          indexed_at: new Date().toISOString(),
        });

        console.log(' OK');
        success++;
      } catch (err) {
        console.log(' FAILED');
        console.error(`  Error: ${(err as Error).message}`);
        errors++;
      }
    }

    // Batch insert
    if (vectors.length > 0) {
      try {
        await indexNotes(vectors);
        console.log(`Batch ${Math.floor(i / batchSize) + 1} indexed (${vectors.length} notes)\n`);
      } catch (err) {
        console.error(`Batch insert failed: ${(err as Error).message}`);
        errors += vectors.length;
        success -= vectors.length;
      }
    }
  }

  console.log('\n=== Migration Complete ===');
  console.log(`Success: ${success}`);
  console.log(`Errors: ${errors}`);

  process.exit(errors > 0 ? 1 : 0);
}

migrate().catch(err => {
  console.error('Migration crashed:', err);
  process.exit(1);
});
