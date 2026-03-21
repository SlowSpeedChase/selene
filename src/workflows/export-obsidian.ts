import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, config, generate, isAvailable } from '../lib';
import { TOPIC_INDEX_PROMPT, DASHBOARD_PROMPT } from '../lib/prompts';

const log = createWorkflowLogger('export-obsidian');

// --- Migration (harmless no-op if columns exist) ---
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN essence TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN essence_at TEXT');
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

interface TopicData {
  theme: string;
  noteCount: number;
  lastActivity: string;
  notes: Array<{
    id: number;
    title: string;
    created_at: string;
    essence: string | null;
    filename: string;
  }>;
}

// --- Helpers ---

function createSlug(title: string): string {
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

function ensureDir(dirPath: string): void {
  if (!existsSync(dirPath)) {
    mkdirSync(dirPath, { recursive: true });
  }
}

function sanitizeContent(content: string): string {
  // Strip old processing metadata blocks embedded in note content
  // Pattern: "---\n✅ Processed by Selene...\n🤖...\n📊...\n🗃️...\n" (sometimes repeated)
  return content
    .replace(/\n---\n✅ Processed by Selene[^\n]*\n(?:[^\n]*\n)*?(?=\n---\n✅|\s*$)/g, '')
    .replace(/\n---\n✅ Processed by Selene[\s\S]*$/g, '')
    .trim();
}

// --- Phase 1: Export Notes ---

function exportNotes(vaultPath: string): { exported: number; errors: number } {
  const notesDir = join(vaultPath, 'Selene', 'Notes');
  ensureDir(notesDir);

  const notes = db
    .prepare(
      `SELECT
        rn.id, rn.title, rn.content, rn.created_at,
        pn.primary_theme, pn.concepts, pn.essence
      FROM raw_notes rn
      JOIN processed_notes pn ON rn.id = pn.raw_note_id
      WHERE rn.exported_to_obsidian = 0
        AND rn.status = 'processed'
        AND rn.test_run IS NULL
      ORDER BY rn.created_at DESC
      LIMIT 50`
    )
    .all() as ExportableNote[];

  log.info({ noteCount: notes.length }, 'Found notes for export');

  let exported = 0;
  let errors = 0;

  for (const note of notes) {
    try {
      const concepts = parseJson<string[]>(note.concepts, []);
      const createdAt = new Date(note.created_at);
      const dateStr = createdAt.toISOString().split('T')[0];
      const slug = createSlug(note.title);
      const filename = `${dateStr}-${slug}.md`;
      const theme = note.primary_theme || 'uncategorized';

      // YAML frontmatter
      const conceptsYaml = concepts.length > 0
        ? concepts.map((c) => `  - ${c}`).join('\n')
        : '  - uncategorized';
      const titleEscaped = note.title.replace(/"/g, '\\"');

      // Content in blockquote (strip old processing metadata)
      const cleanContent = sanitizeContent(note.content);
      const blockquotedContent = cleanContent
        .split('\n')
        .map((line) => `> ${line}`)
        .join('\n');

      // Build markdown
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

      // Theme and concept wiki-links
      const links: string[] = [`[[${theme}]]`];
      for (const concept of concepts) {
        links.push(`[[${concept}]]`);
      }
      parts.push(``, links.join(' '));

      const markdown = parts.join('\n');
      const filePath = join(notesDir, filename);

      writeFileSync(filePath, markdown, 'utf-8');

      // Mark as exported
      db.prepare(
        `UPDATE raw_notes
         SET exported_to_obsidian = 1, exported_at = ?
         WHERE id = ?`
      ).run(new Date().toISOString(), note.id);

      log.info({ noteId: note.id, filename }, 'Exported note');
      exported++;
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to export note');
      errors++;
    }
  }

  return { exported, errors };
}

// --- Phase 2: Curate Library ---

async function curateLibrary(vaultPath: string): Promise<{ topics: number; dashboard: boolean }> {
  const ollamaUp = await isAvailable();
  if (!ollamaUp) {
    log.warn('Ollama not available, skipping curation');
    return { topics: 0, dashboard: false };
  }

  // Query all exported non-test notes
  const allNotes = db
    .prepare(
      `SELECT
        rn.id, rn.title, rn.created_at,
        pn.primary_theme, pn.concepts, pn.essence
      FROM raw_notes rn
      JOIN processed_notes pn ON rn.id = pn.raw_note_id
      WHERE rn.exported_to_obsidian = 1
        AND rn.test_run IS NULL
        AND rn.status = 'processed'
      ORDER BY rn.created_at DESC`
    )
    .all() as ExportableNote[];

  log.info({ totalNotes: allNotes.length }, 'Queried exported notes for curation');

  if (allNotes.length === 0) {
    return { topics: 0, dashboard: false };
  }

  // Group by primary_theme
  const topicMap = new Map<string, TopicData>();
  const twoWeeksAgo = new Date();
  twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  for (const note of allNotes) {
    const theme = note.primary_theme || 'uncategorized';
    const dateStr = new Date(note.created_at).toISOString().split('T')[0];
    const slug = createSlug(note.title);
    const filename = `${dateStr}-${slug}`;

    if (!topicMap.has(theme)) {
      topicMap.set(theme, {
        theme,
        noteCount: 0,
        lastActivity: note.created_at,
        notes: [],
      });
    }

    const topic = topicMap.get(theme)!;
    topic.noteCount++;
    topic.notes.push({
      id: note.id,
      title: note.title,
      created_at: note.created_at,
      essence: note.essence,
      filename,
    });

    // lastActivity is the most recent note (notes are ordered DESC)
    if (topic.notes.length === 1) {
      topic.lastActivity = note.created_at;
    }
  }

  // Generate topic pages
  const topicsDir = join(vaultPath, 'Selene', 'Topics');
  ensureDir(topicsDir);

  let topicCount = 0;

  for (const [theme, topicData] of topicMap) {
    if (topicData.noteCount < 2) continue;

    try {
      // Build notes list for the prompt
      const notesList = topicData.notes
        .map((n) => {
          const essence = n.essence ? ` — ${n.essence}` : '';
          const date = new Date(n.created_at).toISOString().split('T')[0];
          return `- ${n.filename} (${date}): "${n.title}"${essence}`;
        })
        .join('\n');

      const prompt = TOPIC_INDEX_PROMPT
        .replace('{theme}', theme)
        .replace('{notes}', notesList);

      const body = await generate(prompt, { timeoutMs: 120000 });

      const now = new Date().toISOString().split('T')[0];
      const topicMarkdown = [
        `---`,
        `type: topic`,
        `updated: ${now}`,
        `note_count: ${topicData.noteCount}`,
        `---`,
        ``,
        `# ${theme}`,
        ``,
        body.trim(),
      ].join('\n');

      const topicFile = join(topicsDir, `${theme}.md`);
      writeFileSync(topicFile, topicMarkdown, 'utf-8');
      log.info({ theme, noteCount: topicData.noteCount }, 'Generated topic page');
      topicCount++;
    } catch (err) {
      const error = err as Error;
      log.error({ theme, err: error }, 'Failed to generate topic page');
    }
  }

  // Generate dashboard
  let dashboardGenerated = false;
  try {
    const recentNotes = allNotes.filter(
      (n) => new Date(n.created_at) >= sevenDaysAgo
    );

    const recentNotesList = recentNotes
      .map((n) => {
        const dateStr = new Date(n.created_at).toISOString().split('T')[0];
        const slug = createSlug(n.title);
        const filename = `${dateStr}-${slug}`;
        const essence = n.essence ? ` — ${n.essence}` : '';
        return `- ${filename}: "${n.title}"${essence}`;
      })
      .join('\n') || '(no notes in the last 7 days)';

    const topicActivity = Array.from(topicMap.values())
      .map((t) => {
        const recentCount = t.notes.filter(
          (n) => new Date(n.created_at) >= sevenDaysAgo
        ).length;
        const lastDate = new Date(t.lastActivity).toISOString().split('T')[0];
        return `- ${t.theme}: ${t.noteCount} total, ${recentCount} recent, last activity ${lastDate}`;
      })
      .join('\n');

    const stats = [
      `Total notes: ${allNotes.length}`,
      `Topics: ${topicMap.size}`,
      `Notes this week: ${recentNotes.length}`,
    ].join('\n');

    const prompt = DASHBOARD_PROMPT
      .replace('{stats}', stats)
      .replace('{recent_notes}', recentNotesList)
      .replace('{topic_activity}', topicActivity);

    const body = await generate(prompt, { timeoutMs: 180000 });

    const now = new Date().toISOString();
    const dashboardMarkdown = [
      `---`,
      `type: dashboard`,
      `updated: ${now}`,
      `---`,
      ``,
      `# Selene Library`,
      ``,
      body.trim(),
    ].join('\n');

    const seleneDir = join(vaultPath, 'Selene');
    ensureDir(seleneDir);
    writeFileSync(join(seleneDir, 'Dashboard.md'), dashboardMarkdown, 'utf-8');
    log.info('Generated dashboard');
    dashboardGenerated = true;
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Failed to generate dashboard');
  }

  return { topics: topicCount, dashboard: dashboardGenerated };
}

// --- Main Export Function ---

export async function exportObsidian(noteId?: number): Promise<{
  success: boolean;
  exported_count: number;
  errors: number;
  message: string;
}> {
  log.info({ noteId }, 'Starting Obsidian export');

  const vaultPath = process.env.OBSIDIAN_VAULT_PATH || config.vaultPath;
  log.info({ vaultPath }, 'Using vault path');

  // Phase 1: Export notes (always runs)
  const phase1 = exportNotes(vaultPath);

  // Phase 2: Curate library (failures don't block note export)
  let phase2 = { topics: 0, dashboard: false };
  try {
    phase2 = await curateLibrary(vaultPath);
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Library curation failed (non-blocking)');
  }

  const message = [
    `Exported ${phase1.exported} notes`,
    phase2.topics > 0 ? `${phase2.topics} topic pages` : null,
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
