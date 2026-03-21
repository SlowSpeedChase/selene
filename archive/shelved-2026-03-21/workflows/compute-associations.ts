import {
  createWorkflowLogger,
  db,
  getIndexedNoteIds,
  searchSimilarNotes,
  embed,
} from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compute-associations');

// Top K neighbors to store per note
const TOP_K = 10;

// Maximum L2 distance to consider (lower = more similar)
// nomic-embed-text produces unnormalized embeddings, so L2 distances are large:
//   ~3-10    = near-duplicate content
//   ~240-280 = topically related
//   ~300+    = weakly related
// This matches detect-threads.ts MAX_ASSIGNMENT_DISTANCE = 350
const MAX_DISTANCE = 300;

// Convert L2 distance to 0-1 similarity score
// Uses exponential decay so close notes score much higher than distant ones
function distanceToSimilarity(distance: number): number {
  // Exponential decay: score = e^(-distance/scale)
  // At distance 0 → 1.0, distance 100 → ~0.85, distance 250 → ~0.60, distance 350 → ~0.44
  const scale = 600;
  return Math.exp(-distance / scale);
}

/**
 * Compute associations for notes that don't have them yet.
 * For each indexed note, finds top-K similar notes via LanceDB vector search
 * and stores pairwise similarity scores in note_associations.
 */
export async function computeAssociations(limit = 20): Promise<WorkflowResult> {
  log.info({ limit, topK: TOP_K, maxDistance: MAX_DISTANCE }, 'Starting association computation');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  // Get all indexed note IDs
  const indexedIds = await getIndexedNoteIds();
  log.info({ indexedCount: indexedIds.size }, 'Found indexed notes');

  if (indexedIds.size === 0) {
    log.info('No indexed notes found - run index-vectors first');
    return result;
  }

  // Find notes that need associations computed
  // A note "needs" associations if it appears in neither column of note_associations
  const existingNotes = db.prepare(`
    SELECT DISTINCT note_id FROM (
      SELECT note_a_id AS note_id FROM note_associations
      UNION
      SELECT note_b_id AS note_id FROM note_associations
    )
  `).all() as { note_id: number }[];

  const hasAssociations = new Set(existingNotes.map(r => r.note_id));

  const needsComputing = [...indexedIds]
    .filter(id => !hasAssociations.has(id))
    .slice(0, limit);

  log.info({
    withAssociations: hasAssociations.size,
    needsComputing: needsComputing.length,
  }, 'Notes needing association computation');

  if (needsComputing.length === 0) {
    log.info('All indexed notes already have associations');
    return result;
  }

  const insertStmt = db.prepare(`
    INSERT OR IGNORE INTO note_associations (note_a_id, note_b_id, similarity_score)
    VALUES (?, ?, ?)
  `);

  for (const noteId of needsComputing) {
    try {
      // Get the note's content and re-embed it
      const note = db.prepare('SELECT title, content FROM raw_notes WHERE id = ?').get(noteId) as
        | { title: string; content: string }
        | undefined;

      if (!note) {
        log.warn({ noteId }, 'Note not found in raw_notes');
        continue;
      }

      const vector = await embed(`${note.title}\n\n${note.content}`);

      // Search for similar notes
      const neighbors = await searchSimilarNotes(vector, {
        limit: TOP_K,
        maxDistance: MAX_DISTANCE,
        excludeIds: [noteId],
      });

      // Insert pairwise associations (enforce note_a_id < note_b_id)
      let insertedCount = 0;
      for (const neighbor of neighbors) {
        const aId = Math.min(noteId, neighbor.id);
        const bId = Math.max(noteId, neighbor.id);
        const similarity = distanceToSimilarity(neighbor.distance);

        const changes = insertStmt.run(aId, bId, similarity);
        if (changes.changes > 0) insertedCount++;
      }

      result.processed++;
      result.details.push({
        id: noteId,
        success: true,
        error: `${neighbors.length} neighbors, ${insertedCount} new associations`,
      });

      log.info({
        noteId,
        neighbors: neighbors.length,
        newAssociations: insertedCount,
      }, 'Computed associations for note');
    } catch (err) {
      const error = err as Error;
      log.error({ noteId, err: error }, 'Failed to compute associations');
      result.errors++;
      result.details.push({ id: noteId, success: false, error: error.message });
    }
  }

  const totalAssociations = (db.prepare('SELECT COUNT(*) as cnt FROM note_associations').get() as { cnt: number }).cnt;
  log.info({ ...result, totalAssociations }, 'Association computation complete');

  return result;
}

// CLI entry point
if (require.main === module) {
  const limit = process.argv[2] ? parseInt(process.argv[2], 10) : 20;

  computeAssociations(limit)
    .then((result) => {
      console.log('Compute-associations complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compute-associations failed:', err);
      process.exit(1);
    });
}
