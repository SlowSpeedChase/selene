/**
 * Idempotent Obsidian note export — pure render + hash + a DI'd reconcile loop.
 *
 * Replaces the old write-once gate (`exported_to_obsidian = 0`) that let a note's markdown be
 * written exactly once, so post-export enrichment (cluster `parent::` edges, essence or theme
 * changes) never reached the vault. Here each run renders every processed note's FULL markdown,
 * hashes it, and writes only when the hash differs from the stored `obsidian_export_hash`.
 *
 * Fact-store split: the export bookkeeping (`obsidian_export_hash`, `exported_to_obsidian`,
 * `exported_at`) now lives in `note_state` (written via setNoteState); reads come back through
 * the `raw_notes` view's LEFT JOIN, so the SELECT below is unchanged.
 *
 * Free of the db.ts singleton (the loop takes a Database arg) so it is unit-testable in-memory —
 * see obsidian-render.test.ts / obsidian-render.db.test.ts. Mirrors constellation.ts.
 */
import type { Database as DB } from 'better-sqlite3';
import { createHash } from 'crypto';
import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { buildParentFields, loadNoteClusters } from './constellation';
import { setNoteState } from './note-state';

export interface RenderableNote {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string | null;
  concepts: string | null;
  essence: string | null;
}

// --- Pure helpers (shared shape with export-obsidian.ts; kept identical so the rendered
//     markdown is byte-for-byte the same and only genuine content changes flip the hash). ---

export function createSlug(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .slice(0, 50);
}

function parseJson<T>(field: string | null, defaultValue: T): T {
  if (!field) return defaultValue;
  try {
    return JSON.parse(field) as T;
  } catch {
    return defaultValue;
  }
}

function sanitizeContent(content: string): string {
  // Strip old processing metadata blocks embedded in note content.
  return content
    .replace(/\n---\n✅ Processed by Selene[^\n]*\n(?:[^\n]*\n)*?(?=\n---\n✅|\s*$)/g, '')
    .replace(/\n---\n✅ Processed by Selene[\s\S]*$/g, '')
    .trim();
}

/** The date portion of a note's filename (and frontmatter `date:`). */
export function noteDateStr(createdAt: string): string {
  return new Date(createdAt).toISOString().split('T')[0];
}

/** `<date>-<slug>.md` — the vault filename for a note. */
export function noteFilename(note: { title: string; created_at: string }): string {
  return `${noteDateStr(note.created_at)}-${createSlug(note.title)}.md`;
}

/**
 * Render a note's FULL Obsidian markdown — frontmatter, body blockquote, essence, links, and the
 * `parent:: [[cluster]]` block. The hash is taken over THIS entire string, so a cluster-membership
 * change (which only touches the parent block) still flips the hash and triggers a rewrite. Hashing
 * only the body would re-freeze the exact edges this module exists to fix.
 */
export function renderNoteMarkdown(note: RenderableNote, parentClusters: string[]): string {
  const concepts = parseJson<string[]>(note.concepts, []);
  const dateStr = noteDateStr(note.created_at);
  const theme = note.primary_theme || 'uncategorized';

  const conceptsYaml = concepts.length > 0
    ? concepts.map((c) => `  - ${c}`).join('\n')
    : '  - uncategorized';
  const titleEscaped = note.title.replace(/"/g, '\\"');

  const cleanContent = sanitizeContent(note.content);
  const blockquotedContent = cleanContent
    .split('\n')
    .map((line) => `> ${line}`)
    .join('\n');

  const parts: string[] = [
    `---`,
    `title: "${titleEscaped}"`,
    `date: ${dateStr}`,
    `theme: ${theme}`,
    `concepts:`,
    conceptsYaml,
    `---`,
    ``,
    `# ${note.title}`,
    ``,
    blockquotedContent,
    ``,
    `---`,
  ];

  if (note.essence) {
    parts.push(``, `*${note.essence}*`);
  }

  const links: string[] = [`[[${theme}]]`];
  for (const concept of concepts) {
    links.push(`[[${concept}]]`);
  }
  parts.push(``, links.join(' '));

  const parentBlock = buildParentFields(parentClusters);
  if (parentBlock) parts.push(``, parentBlock);

  return parts.join('\n');
}

/** SHA-256 of the rendered markdown — the authoritative "is the vault file current?" signal.
 *  Same algorithm ingest uses for content_hash, so the codebase speaks one hashing language. */
export function exportHash(markdown: string): string {
  return createHash('sha256').update(markdown, 'utf-8').digest('hex');
}

export interface ReconcileResult {
  written: number;
  skipped: number;
  /** Changed notes left for a later run because the per-run write cap was hit. >0 means the
   *  backfill hasn't fully drained — the next run will continue it. */
  deferred: number;
  errors: number;
}

interface ReconcileRow extends RenderableNote {
  obsidian_export_hash: string | null;
}

/**
 * Reconcile the vault's `Notes/` directory against the DB: render every processed note, and write
 * its file only when the rendered hash differs from the stored one (or none is stored yet). The
 * first run after deploy finds NULL hashes everywhere and backfills the whole corpus.
 *
 * @param testRunSql injected `AND rn.test_run ...` fragment (the workflow passes testRunFilter('rn');
 *        tests pass ''), so this loop never imports the config singleton.
 * @param writeCap   max files written per run; changed-but-deferred notes drain on subsequent runs,
 *        so one backfill can't write the entire corpus in a single hanging pass.
 */
export function reconcileExportedNotes(
  database: DB,
  notesDir: string,
  testRunSql = '',
  writeCap = 200
): ReconcileResult {
  if (!existsSync(notesDir)) mkdirSync(notesDir, { recursive: true });

  const notes = database
    .prepare(
      `SELECT
        rn.id, rn.title, rn.content, rn.created_at, rn.obsidian_export_hash,
        pn.primary_theme, pn.concepts, pn.essence
      FROM raw_notes rn
      JOIN processed_notes pn ON rn.id = pn.raw_note_id
      WHERE rn.status = 'processed'
        ${testRunSql}
      ORDER BY rn.created_at DESC`
    )
    .all() as ReconcileRow[];

  const noteClusters = loadNoteClusters(database);

  let written = 0;
  let skipped = 0;
  let deferred = 0;
  let errors = 0;

  for (const note of notes) {
    try {
      const parentClusters = noteClusters.get(note.id) ?? [];
      const markdown = renderNoteMarkdown(note, parentClusters);
      const hash = exportHash(markdown);
      const filePath = join(notesDir, noteFilename(note));

      // Skip only when the rendered output is unchanged AND the file is actually present. The
      // existsSync guard keeps "self-healing" honest: an out-of-band delete (iCloud conflict,
      // vault restore) flips a matching hash back into a rewrite instead of being skipped forever.
      if (hash === note.obsidian_export_hash && existsSync(filePath)) {
        skipped++;
        continue;
      }

      // Changed (or never exported) but the per-run cap is reached — leave for the next run.
      if (written >= writeCap) {
        deferred++;
        continue;
      }

      writeFileSync(filePath, markdown, 'utf-8');
      // Fact-store split: export bookkeeping is derived → note_state (NOT the read-only raw_notes
      // view). Same three columns as before; setNoteState's partial UPSERT leaves status etc.
      // intact so the note keeps matching `WHERE rn.status = 'processed'` on the next run.
      setNoteState(database, note.id, {
        obsidian_export_hash: hash,
        exported_to_obsidian: 1,
        exported_at: new Date().toISOString(),
      });
      written++;
    } catch {
      errors++;
    }
  }

  return { written, skipped, deferred, errors };
}
