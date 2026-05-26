import Database from 'better-sqlite3';
import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { join, resolve } from 'path';
import { homedir } from 'os';
import { createWorkflowLogger } from '../lib';

const log = createWorkflowLogger('folio-feedback');

// ── Types ──────────────────────────────────────────────────────────────────────

interface RawNoteRow {
  id: number;
  title: string;
  content: string;
  created_at: string;
  concepts: string | null;    // JSON array from processed_notes table
  primary_theme: string | null;
}

// ── Pure functions (exported for testing) ─────────────────────────────────────

export function parseFolioTitle(title: string): { projectDir: string; filePath: string } | null {
  const match = title.match(/^Folio: (.+?) :: (.+)$/);
  if (!match) return null;
  const projectDir = match[1].trim();
  const filePath = match[2].trim();
  if (!projectDir || !filePath) return null;
  return { projectDir, filePath };
}

export function buildFeedbackFilename(createdAt: string, filePath: string): string {
  const date = createdAt.slice(0, 10); // YYYY-MM-DD
  const slug = filePath
    .replace(/\.[^.]+$/, '')   // strip final extension only
    .replace(/[/\\]/g, '-');   // path separators → dashes
  return `${date}-${slug}-kindle.md`;
}

/**
 * Build the full markdown content for a feedback file.
 *
 * @param note      - The raw note row (id, title, content, created_at)
 * @param filePath  - The doc path parsed from the title (e.g. "src/server.ts")
 * @param concepts  - Array of concepts from processed_notes (may be empty)
 * @param primaryTheme - Primary theme from processed_notes (null/empty = omit field)
 */
export function buildFeedbackContent(
  note: Pick<RawNoteRow, 'content' | 'created_at'>,
  filePath: string,
  concepts: string[],
  primaryTheme: string | null
): string {
  const lines = [
    '---',
    `source: kindle-scribe`,
    `doc: ${filePath}`,
    `date: ${note.created_at}`,
    `concepts: [${concepts.map(c => `"${c.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`).join(', ')}]`,
  ];
  if (primaryTheme) lines.push(`primary_theme: ${primaryTheme}`);
  lines.push('---', '', note.content);
  return lines.join('\n');
}

// ── Main workflow ──────────────────────────────────────────────────────────────

export function runFolioFeedback(dbPath?: string): void {
  const resolvedDbPath =
    dbPath ||
    process.env.SELENE_DB_PATH ||
    join(homedir(), 'selene-data/selene.db');

  const db = new Database(resolvedDbPath);
  try {
    const notes = db.prepare(`
      SELECT rn.id, rn.title, rn.content, rn.created_at,
             pn.concepts, pn.primary_theme
      FROM raw_notes rn
      LEFT JOIN processed_notes pn ON pn.raw_note_id = rn.id
      WHERE rn.capture_type = 'folio'
        AND rn.status_folio IS NULL
        AND rn.status IN ('processed', 'archived')
    `).all() as RawNoteRow[];

    log.info({ count: notes.length }, 'Found folio notes needing feedback');

    for (const note of notes) {
      try {
        const meta = parseFolioTitle(note.title);
        if (!meta) {
          log.warn({ noteId: note.id, title: note.title }, 'Could not parse folio title — skipping');
          continue;
        }

        const { filePath } = meta;

        // Validate projectDir to prevent path traversal
        const resolvedProjectDir = resolve(meta.projectDir);
        const home = homedir();
        const safePrefix = home.endsWith('/') ? home : home + '/';
        if (!resolvedProjectDir.startsWith(safePrefix)) {
          console.warn(`[folio-feedback] Rejected unsafe projectDir: ${meta.projectDir}`);
          continue;
        }

        // Parse concepts from JSON (stored as JSON string in processed_notes.concepts)
        let concepts: string[] = [];
        if (note.concepts) {
          try {
            const parsed = JSON.parse(note.concepts);
            concepts = Array.isArray(parsed) ? parsed : [];
          } catch {
            log.warn({ noteId: note.id }, 'Could not parse concepts JSON — defaulting to []');
          }
        }

        const primaryTheme = note.primary_theme || null;

        const feedbackDir = join(resolvedProjectDir, 'feedback');
        if (!existsSync(feedbackDir)) {
          mkdirSync(feedbackDir, { recursive: true });
        }

        const filename = buildFeedbackFilename(note.created_at, filePath);
        const dest = join(feedbackDir, filename);
        const content = buildFeedbackContent(note, filePath, concepts, primaryTheme);

        writeFileSync(dest, content, 'utf-8');
        log.info({ noteId: note.id, dest }, 'Wrote feedback file');

        db.prepare("UPDATE raw_notes SET status_folio = 'written' WHERE id = ?").run(note.id);
      } catch (err) {
        console.error(`[folio-feedback] Failed to write feedback for note ${note.id}:`, err);
      }
    }

    log.info({ processed: notes.length }, 'Folio feedback run complete');
  } finally {
    db.close();
  }
}

// ── CLI entry ──────────────────────────────────────────────────────────────────

if (require.main === module) {
  try {
    runFolioFeedback();
    process.exit(0);
  } catch (err) {
    console.error('[folio-feedback] Fatal error:', err);
    process.exit(1);
  }
}
