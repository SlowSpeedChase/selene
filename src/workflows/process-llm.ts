// @map purpose: LLM-extract concepts/themes/category from pending notes, plus essence, embedding & connections
// @map reads: raw_notes
// @map writes: processed_notes, note_embeddings, note_connections
import {
  createWorkflowLogger,
  getPendingNotes,
  markProcessed,
  generate,
  embed,
  isAvailable,
  db,
  indexNote,
  searchSimilarNotes,
} from '../lib';
import { EXTRACT_PROMPT, buildEssencePrompt } from '../lib/prompts';
import { buildAllowedFor, buildSubCategoryPrompt, parseSubCategories } from '../lib/category-clusters';
import { initSynthesisSchema, writeConnection } from '../lib/synthesis-db';
import type { WorkflowResult } from '../types';

// --- Migration (harmless no-op if columns exist) ---
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN category TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN cross_ref_categories TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN sub_categories TEXT');
} catch { /* column already exists */ }

initSynthesisSchema(db);

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

  const CONNECTION_THRESHOLD = 0.75;
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

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

      // Closed-set sub-category classification over the categories this note landed in
      let subCategories: Record<string, string> = {};
      const allowed = buildAllowedFor(extracted.category || null, extracted.cross_ref_categories || []);
      if (Object.keys(allowed).length > 0) {
        try {
          const subPrompt = buildSubCategoryPrompt(note.title, note.content, allowed);
          const subResp = await generate(subPrompt, { temperature: 0 });
          subCategories = parseSubCategories(subResp, allowed);
        } catch (err) {
          log.warn({ noteId: note.id, err: err as Error }, 'Sub-category classification failed; leaving empty');
        }
      }

      // Store in processed_notes table
      db.prepare(
        `INSERT OR REPLACE INTO processed_notes
         (raw_note_id, concepts, primary_theme, secondary_themes, overall_sentiment, emotional_tone, energy_level, category, cross_ref_categories, sub_categories, processed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
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
        JSON.stringify(subCategories),
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

      try {
        const vector = await embed(note.content);

        db.prepare(
          `INSERT OR REPLACE INTO note_embeddings (raw_note_id, embedding, model_version, created_at)
           VALUES (?, ?, 'nomic-embed-text', ?)`
        ).run(note.id, JSON.stringify(vector), new Date().toISOString());

        await indexNote({
          id: note.id,
          vector,
          title: note.title,
          primary_theme: extracted.primary_theme || null,
          note_type: null,
          actionability: null,
          time_horizon: null,
          context: null,
          created_at: note.created_at,
          indexed_at: new Date().toISOString(),
        });

        log.info({ noteId: note.id }, 'Embedding generated and indexed');

        const similar = await searchSimilarNotes(vector, {
          limit: 5,
          excludeIds: [note.id],
        });

        for (const candidate of similar) {
          // L2-to-cosine approximation for unit vectors; accurate for d < ~0.8
          const approxSimilarity = 1 - (candidate.distance * candidate.distance) / 2;
          if (approxSimilarity < CONNECTION_THRESHOLD) continue;

          const isOlderThanSevenDays = db.prepare(
            'SELECT 1 FROM raw_notes WHERE id = ? AND created_at < ?'
          ).get(candidate.id, sevenDaysAgo);

          if (isOlderThanSevenDays) {
            writeConnection(db, note.id, candidate.id, approxSimilarity);
            log.info({ sourceId: note.id, targetId: candidate.id, similarity: approxSimilarity }, 'Connection found');
          }
        }
      } catch (embedErr) {
        log.warn({ noteId: note.id, err: embedErr as Error }, 'Embedding failed, will backfill later');
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
