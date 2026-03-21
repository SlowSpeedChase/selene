import { db, generate, isAvailable, createWorkflowLogger } from '../src/lib';
import { CATEGORIES } from '../src/lib/prompts';

const log = createWorkflowLogger('backfill-categories');

// --- Migration (harmless no-op if columns exist) ---
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN category TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN cross_ref_categories TEXT');
} catch { /* column already exists */ }

const BACKFILL_PROMPT = `Given this note, pick the best category and optionally 1-2 cross-references.

Title: {title}
Theme: {theme}
Essence: {essence}
Concepts: {concepts}

Categories:
- Personal Growth
- Relationships & Social
- Health & Body
- Projects & Tech
- Career & Work
- Creativity & Expression
- Politics & Society
- Daily Systems

Respond in JSON ONLY: {"category": "...", "cross_ref_categories": ["..."]}`;

interface BackfillNote {
  id: number;
  raw_note_id: number;
  primary_theme: string | null;
  essence: string | null;
  concepts: string | null;
}

async function backfill(): Promise<void> {
  log.info('Starting category backfill');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    process.exit(1);
  }

  // Get all processed notes without a category
  const notes = db
    .prepare(
      `SELECT pn.id, pn.raw_note_id, pn.primary_theme, pn.essence, pn.concepts
       FROM processed_notes pn
       JOIN raw_notes rn ON rn.id = pn.raw_note_id
       WHERE pn.category IS NULL
         AND rn.test_run IS NULL`
    )
    .all() as BackfillNote[];

  log.info({ count: notes.length }, 'Found notes to backfill');

  // Also need titles from raw_notes
  const getTitle = db.prepare('SELECT title FROM raw_notes WHERE id = ?');

  let success = 0;
  let errors = 0;

  for (const note of notes) {
    try {
      const titleRow = getTitle.get(note.raw_note_id) as { title: string } | undefined;
      const title = titleRow?.title || 'Untitled';

      const prompt = BACKFILL_PROMPT
        .replace('{title}', title)
        .replace('{theme}', note.primary_theme || 'unknown')
        .replace('{essence}', note.essence || 'none')
        .replace('{concepts}', note.concepts || '[]');

      const response = await generate(prompt, { timeoutMs: 30000 });

      // Parse JSON from response
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new Error('No JSON found in response');
      }

      const result = JSON.parse(jsonMatch[0]);
      const category = CATEGORIES.includes(result.category) ? result.category : null;
      const crossRefs = Array.isArray(result.cross_ref_categories)
        ? result.cross_ref_categories.filter((c: string) => CATEGORIES.includes(c))
        : [];

      if (!category) {
        log.warn({ noteId: note.raw_note_id, response: result.category }, 'LLM returned invalid category, skipping');
        errors++;
        continue;
      }

      db.prepare(
        'UPDATE processed_notes SET category = ?, cross_ref_categories = ? WHERE id = ?'
      ).run(category, JSON.stringify(crossRefs), note.id);

      log.info({ noteId: note.raw_note_id, category, crossRefs }, 'Backfilled');
      success++;
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.raw_note_id, err: error }, 'Backfill failed for note');
      errors++;
    }
  }

  // Reset export flags so next export rebuilds MOCs
  if (success > 0) {
    const resetCount = db
      .prepare(
        `UPDATE raw_notes SET exported_to_obsidian = 0
         WHERE status = 'processed' AND test_run IS NULL`
      )
      .run();
    log.info({ resetCount: resetCount.changes }, 'Reset export flags for MOC rebuild');
  }

  log.info({ success, errors, total: notes.length }, 'Backfill complete');
}

backfill()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Backfill failed:', err);
    process.exit(1);
  });
