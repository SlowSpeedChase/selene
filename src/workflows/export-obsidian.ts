// @map purpose: Render processed notes into an Obsidian vault — note files, LLM Maps-of-Content & dashboard
// @map reads: raw_notes, processed_notes, topic_clusters
// @map writes: Obsidian vault, raw_notes (export hash)
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, config, generate, isAvailable } from '../lib';
import { testRunFilter } from '../lib/test-run';
import { MOC_PROMPT, CATEGORIES } from '../lib/prompts';
import { exportClusterNotes } from '../lib/constellation';
import { reconcileExportedNotes, createSlug } from '../lib/obsidian-render';

const log = createWorkflowLogger('export-obsidian');

// --- Migration (harmless no-op if columns exist) ---
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN essence TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN essence_at TEXT');
} catch { /* column already exists */ }
try {
  // Authoritative "is the vault file current?" signal — replaces the write-once
  // exported_to_obsidian gate so post-export enrichment (parent:: edges, essences) re-exports.
  db.exec('ALTER TABLE raw_notes ADD COLUMN obsidian_export_hash TEXT');
} catch { /* column already exists */ }

// --- Types ---

interface ExportableNote {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string;
  concepts: string | null;
  essence: string | null;
}

interface MocNote {
  id: number;
  title: string;
  created_at: string;
  essence: string | null;
  primary_theme: string | null;
  filename: string;
}

interface CategoryData {
  category: string;
  notes: MocNote[];
  crossRefNotes: MocNote[];
  lastActivity: string;
}

// --- Helpers ---

function parseJson<T>(field: string | null, defaultValue: T): T {
  if (!field) return defaultValue;
  try {
    return JSON.parse(field) as T;
  } catch {
    return defaultValue;
  }
}

function ensureDir(dirPath: string): void {
  if (!existsSync(dirPath)) {
    mkdirSync(dirPath, { recursive: true });
  }
}

// --- Phase 1: Export Notes ---

// Idempotent + self-healing: every run renders each processed note's full markdown and rewrites
// the vault file only when its content hash changed (cluster edges, essence, theme...). The
// render + hash + write-cap logic lives in lib/obsidian-render so it stays unit-testable in-memory.
// `exported` here means "rewritten this run" — it drives MOC regeneration below.
function exportNotes(vaultPath: string): { exported: number; errors: number } {
  const notesDir = join(vaultPath, 'Notes');
  const result = reconcileExportedNotes(db, notesDir, testRunFilter('rn'));
  log.info(
    { written: result.written, skipped: result.skipped, deferred: result.deferred, errors: result.errors },
    'Reconciled notes for export'
  );
  if (result.deferred > 0) {
    log.info({ deferred: result.deferred }, 'Backfill not fully drained — next run will continue');
  }
  return { exported: result.written, errors: result.errors };
}

// --- Phase 2: Generate MOCs ---

async function generateMocs(vaultPath: string, hasNewNotes: boolean): Promise<{ mocs: number; dashboard: boolean }> {
  // Query all exported non-test notes with category data
  const allNotes = db
    .prepare(
      `SELECT
        rn.id, rn.title, rn.created_at,
        pn.primary_theme, pn.concepts, pn.essence,
        pn.category, pn.cross_ref_categories
      FROM raw_notes rn
      JOIN processed_notes pn ON rn.id = pn.raw_note_id
      WHERE rn.exported_to_obsidian = 1
        AND rn.status = 'processed'
        ${testRunFilter('rn')}
      ORDER BY rn.created_at DESC`
    )
    .all() as Array<ExportableNote & { category: string | null; cross_ref_categories: string | null }>;

  log.info({ totalNotes: allNotes.length }, 'Queried exported notes for MOC generation');

  if (allNotes.length === 0) {
    return { mocs: 0, dashboard: false };
  }

  // Build filename for each note
  const noteWithFilename = allNotes.map((note) => {
    const dateStr = new Date(note.created_at).toISOString().split('T')[0];
    const slug = createSlug(note.title);
    return {
      ...note,
      filename: `${dateStr}-${slug}`,
    };
  });

  // Group notes by primary category
  const categoryMap = new Map<string, CategoryData>();

  // Initialize all categories
  for (const cat of CATEGORIES) {
    categoryMap.set(cat, { category: cat, notes: [], crossRefNotes: [], lastActivity: '' });
  }

  for (const note of noteWithFilename) {
    const cat = note.category || 'Daily Systems'; // fallback for uncategorized
    const data = categoryMap.get(cat);
    if (data) {
      data.notes.push({
        id: note.id,
        title: note.title,
        created_at: note.created_at,
        essence: note.essence,
        primary_theme: note.primary_theme,
        filename: note.filename,
      });
      if (!data.lastActivity || note.created_at > data.lastActivity) {
        data.lastActivity = note.created_at;
      }
    }

    // Add to cross-ref categories
    const crossRefs = parseJson<string[]>(note.cross_ref_categories, []);
    for (const xref of crossRefs) {
      const xrefData = categoryMap.get(xref);
      if (xrefData) {
        xrefData.crossRefNotes.push({
          id: note.id,
          title: note.title,
          created_at: note.created_at,
          essence: note.essence,
          primary_theme: note.primary_theme,
          filename: note.filename,
        });
      }
    }
  }

  // Generate MOC pages (only when new notes were exported and Ollama is up)
  const mapsDir = join(vaultPath, 'Maps');
  ensureDir(mapsDir);

  let mocCount = 0;

  if (!hasNewNotes) {
    log.info('No new notes exported, skipping MOC regeneration');
  } else if (!(await isAvailable())) {
    log.warn('Ollama not available, skipping MOC generation');
  } else {
  for (const [category, data] of categoryMap) {
    if (data.notes.length === 0) continue;

    try {
      const notesList = data.notes
        .map((n) => {
          const essence = n.essence ? ` — ${n.essence}` : '';
          const theme = n.primary_theme ? ` [${n.primary_theme}]` : '';
          const date = new Date(n.created_at).toISOString().split('T')[0];
          return `- [[${n.filename}]] (${date}): "${n.title}"${theme}${essence}`;
        })
        .join('\n');

      const crossRefList = data.crossRefNotes.length > 0
        ? data.crossRefNotes
            .map((n) => {
              const essence = n.essence ? ` — ${n.essence}` : '';
              return `- [[${n.filename}]]: "${n.title}"${essence}`;
            })
            .join('\n')
        : '(none)';

      const prompt = MOC_PROMPT
        .replace('{category}', category)
        .replace('{notes_list}', notesList)
        .replace('{cross_ref_notes}', crossRefList);

      const body = await generate(prompt, { timeoutMs: 120000 });

      const now = new Date().toISOString().split('T')[0];
      const mocMarkdown = [
        `---`,
        `type: moc`,
        `category: ${category}`,
        `updated: ${now}`,
        `note_count: ${data.notes.length}`,
        `---`,
        ``,
        `# ${category}`,
        ``,
        body.trim(),
      ].join('\n');

      const mocFile = join(mapsDir, `${category}.md`);
      writeFileSync(mocFile, mocMarkdown, 'utf-8');
      log.info({ category, noteCount: data.notes.length }, 'Generated MOC page');
      mocCount++;
    } catch (err) {
      const error = err as Error;
      log.error({ category, err: error }, 'Failed to generate MOC page');
    }
  }
  } // end MOC generation gate

  // Generate code-based dashboard (no LLM — always runs)
  let dashboardGenerated = false;
  try {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    // Recent 10 notes
    const recentNotes = noteWithFilename.slice(0, 10);

    // Category table rows
    const categoryRows = CATEGORIES
      .map((cat) => {
        const catData = categoryMap.get(cat)!;
        if (catData.notes.length === 0) return null;
        const lastDate = catData.lastActivity
          ? new Date(catData.lastActivity).toISOString().split('T')[0]
          : '—';
        return `| [[${cat}]] | ${catData.notes.length} | ${lastDate} |`;
      })
      .filter(Boolean);

    // Quiet categories (no notes in last 30 days)
    const quietCategories = CATEGORIES.filter((cat) => {
      const catData = categoryMap.get(cat)!;
      if (catData.notes.length === 0) return false;
      return !catData.lastActivity || new Date(catData.lastActivity) < thirtyDaysAgo;
    });

    const recentList = recentNotes
      .map((n) => {
        const essence = n.essence ? n.essence : n.title;
        return `- [[${n.filename}]] — ${essence}`;
      })
      .join('\n');

    const quietSection = quietCategories.length > 0
      ? `It's been quiet in ${quietCategories.join(', ')}. Maybe worth revisiting?`
      : 'All categories have recent activity!';

    const now = new Date().toISOString();
    const dashboardMarkdown = [
      `---`,
      `type: dashboard`,
      `updated: ${now}`,
      `---`,
      ``,
      `# Selene Library`,
      ``,
      `## Your Maps of Content`,
      ``,
      `| Category | Notes | Last Activity |`,
      `|---|---|---|`,
      ...categoryRows,
      ``,
      `## Recently Captured`,
      ``,
      recentList,
      ``,
      `## Quiet Areas`,
      ``,
      quietSection,
    ].join('\n');

    ensureDir(vaultPath);
    writeFileSync(join(vaultPath, 'Dashboard.md'), dashboardMarkdown, 'utf-8');
    log.info('Generated dashboard');
    dashboardGenerated = true;
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Failed to generate dashboard');
  }

  return { mocs: mocCount, dashboard: dashboardGenerated };
}

// --- Main Export Function ---

export async function exportObsidian(noteId?: number): Promise<{
  success: boolean;
  exported_count: number;
  errors: number;
  message: string;
}> {
  log.info({ noteId }, 'Starting Obsidian export');

  const vaultPath = config.vaultPath;
  log.info({ vaultPath }, 'Using vault path');

  // Phase 1: Export notes (always runs)
  const phase1 = exportNotes(vaultPath);

  // Phase 1b: Constellation cluster index notes (regenerated each run; non-blocking).
  let clusterNotes = 0;
  try {
    clusterNotes = exportClusterNotes(db, vaultPath);
  } catch (err) {
    log.error({ err: err as Error }, 'Cluster note export failed (non-blocking)');
  }

  // Phase 2: Generate MOCs and dashboard
  // MOCs only regenerate when notes were (re)written this run, but dashboard always regenerates.
  // Note: during a multi-run backfill the first run flags only the first ~writeCap notes as
  // exported, so that run's MOCs are built against a partial corpus and complete on the next run
  // once the backfill drains — self-correcting, expected for a one-time drain.
  let phase2 = { mocs: 0, dashboard: false };
  try {
    phase2 = await generateMocs(vaultPath, phase1.exported > 0);
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'MOC generation failed (non-blocking)');
  }

  const message = [
    `Exported ${phase1.exported} notes`,
    clusterNotes > 0 ? `${clusterNotes} constellation notes` : null,
    phase2.mocs > 0 ? `${phase2.mocs} MOC pages` : null,
    phase2.dashboard ? 'dashboard updated' : null,
  ]
    .filter(Boolean)
    .join(', ');

  log.info({ phase1, phase2 }, 'Export complete');

  return {
    success: phase1.errors === 0,
    exported_count: phase1.exported,
    errors: phase1.errors,
    message,
  };
}

// --- CLI Entry Point ---

if (require.main === module) {
  const noteId = process.argv[2] ? parseInt(process.argv[2], 10) : undefined;

  exportObsidian(noteId)
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Export failed:', err);
      process.exit(1);
    });
}
