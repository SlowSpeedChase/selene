import { createWorkflowLogger, db } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compute-relationships');

// Thresholds
const TEMPORAL_WINDOW_HOURS = 24;

interface TemporalNote {
  id: number;
  created_at: string;
}

/**
 * Compute TEMPORAL relationships between notes created close in time
 */
function computeTemporalRelationships(): number {
  log.info('Computing temporal relationships');

  // Get all notes ordered by creation time
  const notes = db.prepare(`
    SELECT id, created_at FROM raw_notes
    WHERE test_run IS NULL AND status = 'processed'
    ORDER BY created_at
  `).all() as TemporalNote[];

  const insert = db.prepare(`
    INSERT OR IGNORE INTO note_relationships
    (note_a_id, note_b_id, relationship_type, strength, source)
    VALUES (?, ?, 'TEMPORAL', NULL, 'temporal')
  `);

  let count = 0;

  for (let i = 0; i < notes.length; i++) {
    const noteA = notes[i];
    const timeA = new Date(noteA.created_at).getTime();

    // Look at subsequent notes within the window
    for (let j = i + 1; j < notes.length; j++) {
      const noteB = notes[j];
      const timeB = new Date(noteB.created_at).getTime();
      const diffHours = (timeB - timeA) / (1000 * 60 * 60);

      if (diffHours > TEMPORAL_WINDOW_HOURS) break;

      // Ensure note_a_id < note_b_id for consistency
      const [smallerId, largerId] = noteA.id < noteB.id
        ? [noteA.id, noteB.id]
        : [noteB.id, noteA.id];

      try {
        insert.run(smallerId, largerId);
        count++;
      } catch {
        // Ignore duplicates
      }
    }
  }

  log.info({ count }, 'Temporal relationships computed');
  return count;
}

/**
 * Compute SAME_THREAD relationships from threads table
 */
function computeThreadRelationships(): number {
  log.info('Computing thread relationships');

  // Check if thread_notes table has data
  const threadCount = db.prepare(`SELECT COUNT(*) as count FROM thread_notes`).get() as { count: number };
  if (threadCount.count === 0) {
    log.info('No thread notes found, skipping');
    return 0;
  }

  const result = db.prepare(`
    INSERT OR IGNORE INTO note_relationships
    (note_a_id, note_b_id, relationship_type, strength, source)
    SELECT
      MIN(tn1.raw_note_id, tn2.raw_note_id),
      MAX(tn1.raw_note_id, tn2.raw_note_id),
      'SAME_THREAD',
      NULL,
      'structural'
    FROM thread_notes tn1
    JOIN thread_notes tn2 ON tn1.thread_id = tn2.thread_id
    WHERE tn1.raw_note_id < tn2.raw_note_id
  `).run();

  const count = result.changes;
  log.info({ count }, 'Thread relationships computed');
  return count;
}

/**
 * Compute SAME_PROJECT relationships from project_notes table
 */
function computeProjectRelationships(): number {
  log.info('Computing project relationships');

  // Check if project_notes table has data
  const projectCount = db.prepare(`SELECT COUNT(*) as count FROM project_notes`).get() as { count: number };
  if (projectCount.count === 0) {
    log.info('No project notes found, skipping');
    return 0;
  }

  const result = db.prepare(`
    INSERT OR IGNORE INTO note_relationships
    (note_a_id, note_b_id, relationship_type, strength, source)
    SELECT
      MIN(pn1.raw_note_id, pn2.raw_note_id),
      MAX(pn1.raw_note_id, pn2.raw_note_id),
      'SAME_PROJECT',
      NULL,
      'structural'
    FROM project_notes pn1
    JOIN project_notes pn2 ON pn1.project_id = pn2.project_id
    WHERE pn1.raw_note_id < pn2.raw_note_id
  `).run();

  const count = result.changes;
  log.info({ count }, 'Project relationships computed');
  return count;
}

/**
 * Main workflow: compute all relationship types
 */
export async function computeRelationships(): Promise<WorkflowResult> {
  log.info('Starting relationship computation');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  try {
    const temporal = computeTemporalRelationships();
    result.processed += temporal;
    result.details.push({ id: 0, success: true, error: `temporal: ${temporal}` });
  } catch (err) {
    log.error({ err }, 'Failed temporal relationships');
    result.errors++;
  }

  try {
    const thread = computeThreadRelationships();
    result.processed += thread;
    result.details.push({ id: 0, success: true, error: `thread: ${thread}` });
  } catch (err) {
    log.error({ err }, 'Failed thread relationships');
    result.errors++;
  }

  try {
    const project = computeProjectRelationships();
    result.processed += project;
    result.details.push({ id: 0, success: true, error: `project: ${project}` });
  } catch (err) {
    log.error({ err }, 'Failed project relationships');
    result.errors++;
  }

  log.info(result, 'Relationship computation complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  computeRelationships()
    .then((result) => {
      console.log('Compute-relationships complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compute-relationships failed:', err);
      process.exit(1);
    });
}
