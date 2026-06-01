// scripts/backfill-categories.ts
// One-shot: classify processed_notes that still lack a category (predate the feature).
// Reads title+content from raw_notes, runs EXTRACT_PROMPT, writes ONLY category +
// cross_ref_categories. Idempotent: rows that already have a category are skipped.
// Run (dev/copy): SELENE_ENV=development npx ts-node scripts/backfill-categories.ts
import { db, generate, isAvailable, createWorkflowLogger } from '../src/lib';
import type { Database as DatabaseType } from 'better-sqlite3';
import { EXTRACT_PROMPT } from '../src/lib/prompts';
import { extractCategoryFields } from '../src/lib/category-clusters';
import { setNoteState } from '../src/lib/note-state';
import { testRunFilter } from '../src/lib/test-run';

const log = createWorkflowLogger('backfill-categories');

/**
 * Force the Obsidian MOCs to rebuild on the next export by clearing exported_to_obsidian for every
 * processed note. Post fact-store split, `raw_notes` is a read-only view and `exported_to_obsidian`
 * lives in `note_state` — so we read the target ids THROUGH the view (a read is fine) and write the
 * flag via setNoteState, never `UPDATE raw_notes` (which would throw "cannot modify ... a view").
 * Returns the number of processed notes reset.
 */
export function resetExportFlagsForProcessed(conn: DatabaseType = db): number {
  const targets = conn
    .prepare(`SELECT id FROM raw_notes WHERE status = 'processed' ${testRunFilter()}`)
    .all() as Array<{ id: number }>;
  for (const { id } of targets) {
    setNoteState(conn, id, { exported_to_obsidian: 0 });
  }
  return targets.length;
}

async function backfillCategories(): Promise<{ updated: number; failed: number }> {
  if (!(await isAvailable())) {
    log.error('Ollama not available');
    return { updated: 0, failed: 0 };
  }

  const rows = db.prepare(`
    SELECT rn.id AS id, rn.title AS title, rn.content AS content
    FROM raw_notes rn
    JOIN processed_notes pn ON pn.raw_note_id = rn.id
    WHERE pn.category IS NULL ${testRunFilter('rn')}
  `).all() as Array<{ id: number; title: string; content: string }>;

  log.info({ count: rows.length }, 'Notes to classify');
  let updated = 0;
  let failed = 0;

  for (const note of rows) {
    try {
      const prompt = EXTRACT_PROMPT
        .replace('{title}', note.title)
        .replace('{content}', note.content);
      const response = await generate(prompt);
      const { category, crossRefs } = extractCategoryFields(response);
      if (!category) {
        failed++;
        log.warn({ noteId: note.id }, 'No valid category extracted; left NULL');
        continue;
      }
      db.prepare(
        `UPDATE processed_notes SET category = ?, cross_ref_categories = ? WHERE raw_note_id = ?`
      ).run(category, JSON.stringify(crossRefs), note.id);
      updated++;
      if (updated % 25 === 0) log.info({ updated }, 'progress');
    } catch (err) {
      failed++;
      log.warn({ noteId: note.id, err: err as Error }, 'Classification failed');
    }
  }

  // Preserve the behavior of the prior backfill script (main@10b4d20): force the
  // Obsidian MOCs to rebuild with the new categories on the next export run. The
  // design unifies both the iPad and Obsidian surfaces on categories.
  if (updated > 0) {
    const resetCount = resetExportFlagsForProcessed(db);
    log.info({ resetCount }, 'Reset export flags for MOC rebuild');
  }

  log.info({ updated, failed }, 'Backfill complete');
  return { updated, failed };
}

if (require.main === module) {
  backfillCategories()
    .then((r) => { console.log('backfill-categories:', r); process.exit(0); })
    .catch((err) => { console.error('backfill-categories failed:', err); process.exit(1); });
}

export { backfillCategories };
