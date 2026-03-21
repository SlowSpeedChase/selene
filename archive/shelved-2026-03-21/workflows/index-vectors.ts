import {
  createWorkflowLogger,
  db,
  embed,
  isAvailable,
  indexNotes,
  getIndexedNoteIds,
  type NoteVector,
  VECTOR_DIMENSIONS,
} from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('index-vectors');

interface NoteForIndexing {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string | null;
}

/**
 * Index vectors for processed notes not yet in LanceDB
 */
export async function indexVectors(limit = 50): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting vector indexing run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Get already indexed IDs from LanceDB
  const indexedIds = await getIndexedNoteIds();
  log.info({ indexedCount: indexedIds.size }, 'Found existing indexed notes');

  // Get processed notes from SQLite
  const notes = db.prepare(`
    SELECT
      rn.id,
      rn.title,
      rn.content,
      rn.created_at,
      pn.primary_theme
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.test_run IS NULL
      AND rn.status = 'processed'
    ORDER BY rn.created_at DESC
    LIMIT ?
  `).all(limit * 2) as NoteForIndexing[];

  // Filter out already indexed
  const needsIndexing = notes.filter(n => !indexedIds.has(n.id)).slice(0, limit);

  log.info({
    fetchedCount: notes.length,
    needsIndexing: needsIndexing.length
  }, 'Notes to index');

  if (needsIndexing.length === 0) {
    log.info('No notes need indexing');
    return { processed: 0, errors: 0, details: [] };
  }

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };
  const toIndex: NoteVector[] = [];

  for (const note of needsIndexing) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Computing embedding');

      const text = `${note.title}\n\n${note.content}`;
      const vector = await embed(text);

      if (vector.length !== VECTOR_DIMENSIONS) {
        throw new Error(`Unexpected embedding dimensions: ${vector.length}`);
      }

      toIndex.push({
        id: note.id,
        vector,
        title: note.title,
        primary_theme: note.primary_theme,
        note_type: null,      // Will be populated by facet extraction later
        actionability: null,
        time_horizon: null,
        context: null,
        created_at: note.created_at,
        indexed_at: new Date().toISOString(),
      });

      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to compute embedding');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  // Batch insert to LanceDB
  if (toIndex.length > 0) {
    try {
      await indexNotes(toIndex);
      log.info({ count: toIndex.length }, 'Batch indexed to LanceDB');
    } catch (err) {
      const error = err as Error;
      log.error({ err: error }, 'Failed to batch index to LanceDB');
      result.errors = toIndex.length;
      result.processed = 0;
    }
  }

  log.info(result, 'Vector indexing run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  const limit = process.argv[2] ? parseInt(process.argv[2], 10) : 50;

  indexVectors(limit)
    .then((result) => {
      console.log('Index-vectors complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Index-vectors failed:', err);
      process.exit(1);
    });
}
