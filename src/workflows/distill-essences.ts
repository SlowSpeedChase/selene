// @map purpose: Backfill/retry LLM essences for processed notes that still lack one
// @map reads: processed_notes, raw_notes, note_feedback
// @map writes: processed_notes
import { createWorkflowLogger, db, generate, isAvailable } from '../lib';
import { testRunFilter } from '../lib/test-run';
import { buildEssencePrompt } from '../lib/prompts';
import { getIntentTexts } from '../lib/vault-feedback';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('distill-essences');

/**
 * Ensure the essence columns this workflow produces actually exist.
 *
 * essence/essence_at were historically created only by export-obsidian, which
 * runs LAST in the pipeline. On a freshly-reset DB that left distill-essences'
 * own `WHERE pn.essence IS NULL` query — and the downstream synthesize-topics
 * read of pn.essence — throwing "no such column" until export had run once.
 * The producer of the data now owns the migration. Idempotent (harmless no-op
 * if the columns already exist). Mirrors the per-workflow migration idiom in
 * process-llm.ts (category) and export-obsidian.ts (obsidian_export_hash).
 */
export function ensureEssenceColumns(database: typeof db = db): void {
  try {
    database.exec('ALTER TABLE processed_notes ADD COLUMN essence TEXT');
  } catch { /* column already exists */ }
  try {
    database.exec('ALTER TABLE processed_notes ADD COLUMN essence_at TEXT');
  } catch { /* column already exists */ }
}

// Run at module load so the columns exist before any query below executes.
ensureEssenceColumns();

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
         ${testRunFilter('rn')}
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
      // Obsidian feedback loop: retried/backfilled essences must carry the author's
      // stated intent, same as the inline essence path in process-llm.
      const intents = getIntentTexts(db, note.raw_note_id);
      const prompt = buildEssencePrompt(
        note.title,
        note.content,
        note.concepts,
        note.primary_theme,
        intents
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
