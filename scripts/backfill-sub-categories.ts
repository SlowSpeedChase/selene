// scripts/backfill-sub-categories.ts
// One-shot: assign sub-categories to processed_notes that have a category but no
// sub_categories yet (predate the sub-taxonomy feature). For each note, seeds the
// closed-set sub-lists for the categories it landed in, asks the LLM to pick one
// sub per category, and writes the validated map to processed_notes.sub_categories.
// Idempotent: rows that already have sub_categories are skipped (WHERE sub_categories IS NULL).
//
// --report runs LLM-free: it reads the stored taxonomy data and prints a content-free
// coverage histogram (counts only — never note titles/content) so you can see how well
// the sub-taxonomy fits and where the "none" misfit buckets are.
//
// Run (dev/copy): SELENE_ENV=development npx ts-node scripts/backfill-sub-categories.ts [--dry-run|--report]
import { db, generate, isAvailable, createWorkflowLogger } from '../src/lib';
import {
  buildAllowedFor,
  buildSubCategoryPrompt,
  parseSubCategories,
  parseCrossRefs,
  resolveCategories,
  aggregateSubCoverage,
} from '../src/lib/category-clusters';
import type { CoverageRow } from '../src/lib/category-clusters';
import { testRunFilter } from '../src/lib/test-run';

const log = createWorkflowLogger('backfill-sub-categories');

// Idempotent guard: the column is added by process-llm's migration, but make the
// script safe to run standalone. Harmless if the column already exists.
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN sub_categories TEXT');
} catch {
  /* column already exists */
}

/** Parse a stored sub_categories JSON object; {} on null/invalid. */
function safeParseSubMap(json: string | null): Record<string, string> {
  if (!json) return {};
  try {
    const parsed: unknown = JSON.parse(json);
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof v === 'string') out[k] = v;
    }
    return out;
  } catch {
    return {};
  }
}

interface ReportDbRow {
  category: string;
  crossRefs: string | null;
  subs: string | null;
}

/** Build the content-free coverage rows from stored taxonomy columns (no LLM). */
export function buildCoverageRows(rows: ReportDbRow[]): CoverageRow[] {
  return rows.map((r) => ({
    categories: [...resolveCategories(r.category, parseCrossRefs(r.crossRefs))],
    subCategories: safeParseSubMap(r.subs),
  }));
}

async function backfillSubCategories(
  dryRun: boolean,
): Promise<{ updated: number; skipped: number; failed: number }> {
  if (!(await isAvailable())) {
    log.error('Ollama not available');
    return { updated: 0, skipped: 0, failed: 0 };
  }

  const rows = db.prepare(`
    SELECT rn.id AS id, rn.title AS title, rn.content AS content,
           pn.category AS category, pn.cross_ref_categories AS crossRefs
    FROM raw_notes rn
    JOIN processed_notes pn ON pn.raw_note_id = rn.id
    WHERE pn.category IS NOT NULL AND pn.sub_categories IS NULL ${testRunFilter('rn')}
  `).all() as Array<{
    id: number;
    title: string;
    content: string;
    category: string | null;
    crossRefs: string | null;
  }>;

  log.info({ count: rows.length, dryRun }, 'Notes to sub-classify');
  let updated = 0;
  let skipped = 0;
  let failed = 0;

  for (const note of rows) {
    try {
      const allowed = buildAllowedFor(note.category, parseCrossRefs(note.crossRefs));
      if (Object.keys(allowed).length === 0) {
        skipped++;
        continue;
      }
      const response = await generate(
        buildSubCategoryPrompt(note.title, note.content, allowed),
        { temperature: 0 },
      );
      const subMap = parseSubCategories(response, allowed);
      if (!dryRun) {
        db.prepare(
          `UPDATE processed_notes SET sub_categories = ? WHERE raw_note_id = ?`,
        ).run(JSON.stringify(subMap), note.id);
      }
      updated++;
      if (updated % 25 === 0) log.info({ updated }, 'progress');
    } catch (err) {
      failed++;
      log.warn({ noteId: note.id, err: err as Error }, 'Sub-classification failed');
    }
  }

  log.info({ updated, skipped, failed, dryRun }, 'Sub-category backfill complete');
  return { updated, skipped, failed };
}

/** LLM-free: read stored taxonomy data and print a content-free coverage histogram. */
function reportCoverage(): void {
  const dbRows = db.prepare(`
    SELECT pn.category AS category, pn.cross_ref_categories AS crossRefs,
           pn.sub_categories AS subs
    FROM processed_notes pn
    JOIN raw_notes rn ON rn.id = pn.raw_note_id
    WHERE pn.category IS NOT NULL ${testRunFilter('rn')}
  `).all() as ReportDbRow[];

  const cov = aggregateSubCoverage(buildCoverageRows(dbRows));

  const categories = Object.keys(cov).sort();
  if (categories.length === 0) {
    console.log('(no categorized notes found)');
    return;
  }

  for (const cat of categories) {
    const buckets = cov[cat];
    const total = Object.values(buckets).reduce((a, b) => a + b, 0);
    console.log(`\n${cat} (${total} notes)`);
    const subNames = Object.keys(buckets)
      .filter((k) => k !== 'none')
      .sort((a, b) => buckets[b] - buckets[a]);
    for (const sub of subNames) {
      console.log(`  ${sub}  ${buckets[sub]}`);
    }
    const none = buckets['none'] ?? 0;
    const pct = total > 0 ? Math.round((none / total) * 100) : 0;
    console.log(`  none  ${none}  (${pct}% misfit)`);
  }
}

async function main(): Promise<void> {
  const argv = process.argv;
  if (argv.includes('--report')) {
    reportCoverage();
    return;
  }
  const dryRun = argv.includes('--dry-run');
  const result = await backfillSubCategories(dryRun);
  console.log('backfill-sub-categories:', result);
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('backfill-sub-categories failed:', err);
      process.exit(1);
    });
}

export { backfillSubCategories, reportCoverage };
