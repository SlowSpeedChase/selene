import {
  createWorkflowLogger,
  getPendingNotes,
  markProcessed,
  generate,
  isAvailable,
  db,
} from '../lib';
import { EXTRACT_PROMPT, buildEssencePrompt } from '../lib/prompts';
import type { WorkflowResult } from '../types';

// --- Migration (harmless no-op if columns exist) ---
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN category TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN cross_ref_categories TEXT');
} catch { /* column already exists */ }

const log = createWorkflowLogger('process-llm');

export async function processLlm(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting LLM processing run');

  // Check Ollama availability
  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  const notes = getPendingNotes(limit);
  log.info({ noteCount: notes.length }, 'Found pending notes');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  for (const note of notes) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Processing note');

      const prompt = EXTRACT_PROMPT.replace('{title}', note.title).replace(
        '{content}',
        note.content
      );

      const response = await generate(prompt);

      // Try to parse JSON response
      let extracted;
      try {
        // Find JSON in response (Ollama sometimes adds extra text)
        const jsonMatch = response.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          extracted = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error('No JSON found in response');
        }
      } catch (parseErr) {
        log.warn({ noteId: note.id, response }, 'Failed to parse LLM response as JSON');
        extracted = {
          concepts: [],
          primary_theme: null,
          secondary_themes: [],
          overall_sentiment: 'neutral',
          emotional_tone: null,
          energy_level: 'medium',
          category: null,
          cross_ref_categories: [],
        };
      }

      // Store in processed_notes table
      db.prepare(
        `INSERT OR REPLACE INTO processed_notes
         (raw_note_id, concepts, primary_theme, secondary_themes, overall_sentiment, emotional_tone, energy_level, category, cross_ref_categories, processed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(
        note.id,
        JSON.stringify(extracted.concepts || []),
        extracted.primary_theme || null,
        JSON.stringify(extracted.secondary_themes || []),
        extracted.overall_sentiment || 'neutral',
        extracted.emotional_tone || null,
        extracted.energy_level || 'medium',
        extracted.category || null,
        JSON.stringify(extracted.cross_ref_categories || []),
        new Date().toISOString()
      );

      // Mark note as processed
      markProcessed(note.id);

      // Compute essence inline
      try {
        const essencePrompt = buildEssencePrompt(
          note.title,
          note.content,
          JSON.stringify(extracted.concepts || []),
          extracted.primary_theme || null
        );
        const essenceResponse = await generate(essencePrompt);
        const essence = essenceResponse.trim();
        if (essence && essence.length > 10) {
          db.prepare(
            `UPDATE processed_notes SET essence = ?, essence_at = ? WHERE raw_note_id = ?`
          ).run(essence, new Date().toISOString(), note.id);
          log.info({ noteId: note.id, essenceLength: essence.length }, 'Essence computed');
        }
      } catch (essenceErr) {
        // Non-fatal — distill-essences workflow will retry
        log.warn({ noteId: note.id, err: essenceErr as Error }, 'Essence computation failed, will retry later');
      }

      log.info({ noteId: note.id, concepts: extracted.concepts, theme: extracted.primary_theme }, 'Note processed successfully');
      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to process note');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  log.info({ processed: result.processed, errors: result.errors }, 'LLM processing run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  processLlm()
    .then((result) => {
      console.log('Process-LLM complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Process-LLM failed:', err);
      process.exit(1);
    });
}
