import { createWorkflowLogger, db, generate, isAvailable } from '../lib';
import { buildEssencePrompt } from '../lib/prompts';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('distill-essences');

interface NoteForEssence {
  raw_note_id: number;
  title: string;
  content: string;
  concepts: string | null;
  primary_theme: string | null;
}

/**
 * Get processed notes that still need an essence computed.
 */
export function getNotesNeedingEssence(limit = 10): NoteForEssence[] {
  return db
    .prepare(
      `SELECT pn.raw_note_id, rn.title, rn.content, pn.concepts, pn.primary_theme
       FROM processed_notes pn
       JOIN raw_notes rn ON pn.raw_note_id = rn.id
       WHERE pn.essence IS NULL
         AND rn.test_run IS NULL
       ORDER BY rn.created_at DESC
       LIMIT ?`
    )
    .all(limit) as NoteForEssence[];
}

export async function distillEssences(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting essence distillation run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  const notes = getNotesNeedingEssence(limit);
  log.info({ noteCount: notes.length }, 'Found notes needing essence');

  if (notes.length === 0) {
    log.info('All notes have essences — nothing to do');
    return { processed: 0, errors: 0, details: [] };
  }

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  for (const note of notes) {
    try {
      const prompt = buildEssencePrompt(
        note.title,
        note.content,
        note.concepts,
        note.primary_theme
      );

      const response = await generate(prompt);
      const essence = response.trim();

      if (!essence || essence.length <= 10) {
        log.warn({ noteId: note.raw_note_id }, 'Essence too short, skipping');
        result.errors++;
        result.details.push({ id: note.raw_note_id, success: false, error: 'Essence too short' });
        continue;
      }

      db.prepare(
        `UPDATE processed_notes SET essence = ?, essence_at = ? WHERE raw_note_id = ?`
      ).run(essence, new Date().toISOString(), note.raw_note_id);

      log.info({ noteId: note.raw_note_id, essenceLength: essence.length }, 'Essence computed');
      result.processed++;
      result.details.push({ id: note.raw_note_id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.raw_note_id, err: error }, 'Failed to compute essence');
      result.errors++;
      result.details.push({ id: note.raw_note_id, success: false, error: error.message });
    }
  }

  log.info(
    { processed: result.processed, errors: result.errors },
    'Essence distillation complete'
  );
  return result;
}

// CLI entry point
if (require.main === module) {
  distillEssences()
    .then((result) => {
      console.log('Distill-essences complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Distill-essences failed:', err);
      process.exit(1);
    });
}
