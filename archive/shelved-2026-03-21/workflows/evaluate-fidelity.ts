import { createWorkflowLogger, db } from '../lib';
import type { FidelityTier } from '../lib/context-builder';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('evaluate-fidelity');

interface TierInput {
  ageDays: number;
  hasEssence: boolean;
  threadStatus: string | null;
}

/**
 * Pure function: compute the fidelity tier for a note based on age and activity.
 *
 * Rules:
 *   FULL:     age < 7 days
 *   HIGH:     age < 90 days OR in active thread (requires essence)
 *   SUMMARY:  age >= 90 days AND thread inactive/archived (requires essence)
 *   SKELETON: thread archived AND age >= 180 days (requires essence)
 *
 * Guard: cannot demote below 'full' without an essence.
 *
 * Note: access tracking (accessed_at) is not yet implemented. Skeleton demotion
 * uses note age as a proxy. When access tracking is added, the rule should use
 * days since last access instead of days since creation.
 */
export function computeTier(input: TierInput): FidelityTier {
  const { ageDays, hasEssence, threadStatus } = input;

  // Fresh notes are always full
  if (ageDays < 7) return 'full';

  // Guard: no demotion without essence
  if (!hasEssence) return 'full';

  // Active thread keeps notes at high regardless of age
  if (threadStatus === 'active') return 'high';

  // Warm period
  if (ageDays < 90) return 'high';

  // Cold: archived + 180+ days old
  if (threadStatus === 'archived' && ageDays >= 180) return 'skeleton';

  // Cool: 90+ days, inactive/archived
  return 'summary';
}

interface NoteForEvaluation {
  raw_note_id: number;
  fidelity_tier: string;
  essence: string | null;
  age_days: number;
  thread_status: string | null;
}

export async function evaluateFidelity(): Promise<WorkflowResult> {
  log.info('Starting fidelity evaluation');

  // Use CASE expression to deterministically resolve thread status when a note
  // belongs to multiple threads: active wins over archived wins over null.
  // Skeleton notes are included so they can be rehydrated if their thread reactivates.
  const notes = db
    .prepare(
      `SELECT
         pn.raw_note_id,
         pn.fidelity_tier,
         pn.essence,
         CAST(julianday('now') - julianday(rn.created_at) AS INTEGER) as age_days,
         CASE
           WHEN SUM(CASE WHEN t.status = 'active' THEN 1 ELSE 0 END) > 0 THEN 'active'
           WHEN SUM(CASE WHEN t.status = 'archived' THEN 1 ELSE 0 END) > 0 THEN 'archived'
           ELSE NULL
         END as thread_status
       FROM processed_notes pn
       JOIN raw_notes rn ON pn.raw_note_id = rn.id
       LEFT JOIN thread_notes tn ON rn.id = tn.raw_note_id
       LEFT JOIN threads t ON tn.thread_id = t.id
       WHERE rn.test_run IS NULL
       GROUP BY pn.raw_note_id`
    )
    .all() as NoteForEvaluation[];

  log.info({ noteCount: notes.length }, 'Notes to evaluate');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  const now = new Date().toISOString();
  const updateStmt = db.prepare(
    `UPDATE processed_notes SET fidelity_tier = ?, fidelity_evaluated_at = ? WHERE raw_note_id = ?`
  );

  for (const note of notes) {
    const newTier = computeTier({
      ageDays: note.age_days,
      hasEssence: note.essence !== null,
      threadStatus: note.thread_status,
    });

    if (newTier !== note.fidelity_tier) {
      updateStmt.run(newTier, now, note.raw_note_id);
      log.info(
        { noteId: note.raw_note_id, from: note.fidelity_tier, to: newTier },
        'Tier changed'
      );
      result.processed++;
      result.details.push({ id: note.raw_note_id, success: true });
    }
  }

  log.info(
    { evaluated: notes.length, changed: result.processed },
    'Fidelity evaluation complete'
  );
  return result;
}

// CLI entry point
if (require.main === module) {
  evaluateFidelity()
    .then((result) => {
      console.log('Evaluate-fidelity complete:', result);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Evaluate-fidelity failed:', err);
      process.exit(1);
    });
}
