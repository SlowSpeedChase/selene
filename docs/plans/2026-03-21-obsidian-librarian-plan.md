# Obsidian Librarian Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite export-obsidian.ts to produce clean single-file notes, LLM-generated topic indexes, and a dashboard — turning the Obsidian vault into an actively curated library.

**Architecture:** Two-phase hourly export: Phase 1 exports new notes as clean markdown (no LLM). Phase 2 uses Ollama to generate/update topic index pages and a dashboard with patterns and insights. Notes are flat in `Selene/Notes/`, topics in `Selene/Topics/`, dashboard at `Selene/Dashboard.md`.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (mistral:7b), Obsidian vault (markdown files)

---

### Task 1: Fix Missing Essence Column

**Why:** The `processed_notes` table is missing the `essence` and `essence_at` columns. The `distill-essences.ts` workflow tries to write them but silently fails. Notes need essences for the librarian to write good topic summaries.

**Files:**
- Modify: `src/workflows/export-obsidian.ts` (temporary — add migration at top)

We'll add the migration inline in export-obsidian since it's the workflow that needs it most, and there's no formal migration system.

**Step 1: Add migration to export-obsidian.ts**

Add this right after the imports and before any other code:

```typescript
// One-time migration: ensure essence columns exist
try {
  db.exec(`ALTER TABLE processed_notes ADD COLUMN essence TEXT`);
  db.exec(`ALTER TABLE processed_notes ADD COLUMN essence_at DATETIME`);
} catch {
  // Columns already exist — ignore
}
```

**Step 2: Verify migration runs**

```bash
npx ts-node src/workflows/export-obsidian.ts
sqlite3 data/selene.db "PRAGMA table_info(processed_notes);" | grep essence
```

Expected: Two rows showing `essence|TEXT` and `essence_at|DATETIME`

**Step 3: Run distill-essences to populate essences**

```bash
npx ts-node src/workflows/distill-essences.ts
```

Expected: Should now successfully process notes and write essences to the database.

**Step 4: Verify essences were stored**

```bash
sqlite3 data/selene.db "SELECT COUNT(*) FROM processed_notes WHERE essence IS NOT NULL;"
```

Expected: A number > 0.

**Step 5: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "fix: add missing essence columns to processed_notes

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rewrite Note Export (Phase 1)

**Why:** Replace the current 500-line over-engineered export with a clean, minimal note format.

**Files:**
- Rewrite: `src/workflows/export-obsidian.ts`

**Step 1: Rewrite export-obsidian.ts**

Replace the entire file. The new version has two main parts:
- `exportNotes()` — Phase 1: export new notes as clean markdown
- `curateLibrary()` — Phase 2: LLM-generated topics + dashboard (Task 3)

For now, implement only Phase 1. Phase 2 will be a stub.

```typescript
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, config, generate, isAvailable } from '../lib';

const log = createWorkflowLogger('export-obsidian');

// One-time migration: ensure essence columns exist
try {
  db.exec(`ALTER TABLE processed_notes ADD COLUMN essence TEXT`);
  db.exec(`ALTER TABLE processed_notes ADD COLUMN essence_at DATETIME`);
} catch {
  // Columns already exist
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ExportableNote {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string | null;
  concepts: string | null;
  essence: string | null;
}

interface TopicData {
  theme: string;
  noteCount: number;
  lastActivity: string;
  notes: Array<{
    filename: string;
    title: string;
    essence: string | null;
    date: string;
  }>;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Phase 1: Export new notes as clean markdown
// ---------------------------------------------------------------------------

function getNotesForExport(limit = 50): ExportableNote[] {
  return db
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
      LIMIT ?`
    )
    .all(limit) as ExportableNote[];
}

function generateNoteMarkdown(note: ExportableNote): string {
  const concepts = parseJson<string[]>(note.concepts, []);
  const theme = note.primary_theme || 'uncategorized';
  const dateStr = new Date(note.created_at).toISOString().split('T')[0];

  const conceptsYaml = concepts.length > 0
    ? concepts.map((c) => `  - ${c}`).join('\n')
    : '  - uncategorized';

  const conceptLinks = concepts.length > 0
    ? concepts.map((c) => `[[${c}]]`).join(', ')
    : '[[uncategorized]]';

  const essenceLine = note.essence
    ? `\n*Essence: ${note.essence}*\n`
    : '';

  return `---
title: "${note.title.replace(/"/g, '\\"')}"
date: ${dateStr}
theme: ${theme}
concepts:
${conceptsYaml}
---

# ${note.title}

> ${note.content.replace(/\n/g, '\n> ')}

---
${essenceLine}
*Theme: [[${theme}]] | Concepts: ${conceptLinks}*
`;
}

function exportNotes(vaultPath: string): { exported: number; errors: number } {
  const notesDir = join(vaultPath, 'Selene', 'Notes');
  ensureDir(notesDir);

  const notes = getNotesForExport();
  log.info({ noteCount: notes.length }, 'Found notes for export');

  if (notes.length === 0) {
    return { exported: 0, errors: 0 };
  }

  let exported = 0;
  let errors = 0;

  for (const note of notes) {
    try {
      const dateStr = new Date(note.created_at).toISOString().split('T')[0];
      const slug = createSlug(note.title);
      const filename = `${dateStr}-${slug}.md`;
      const filePath = join(notesDir, filename);

      const markdown = generateNoteMarkdown(note);
      writeFileSync(filePath, markdown, 'utf-8');

      db.prepare(
        `UPDATE raw_notes SET exported_to_obsidian = 1, exported_at = ? WHERE id = ?`
      ).run(new Date().toISOString(), note.id);

      log.info({ noteId: note.id, filename }, 'Note exported');
      exported++;
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to export note');
      errors++;
    }
  }

  return { exported, errors };
}

// ---------------------------------------------------------------------------
// Phase 2: Curate library (topics + dashboard) — implemented in Task 3
// ---------------------------------------------------------------------------

async function curateLibrary(_vaultPath: string): Promise<{ topics: number; dashboard: boolean }> {
  // Stub — will be implemented in Task 3
  return { topics: 0, dashboard: false };
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

export async function exportObsidian(noteId?: number): Promise<{
  success: boolean;
  exported_count: number;
  errors: number;
  message: string;
}> {
  log.info({ noteId }, 'Starting Obsidian export');

  const vaultPath = process.env.OBSIDIAN_VAULT_PATH || config.vaultPath;
  log.info({ vaultPath }, 'Using vault path');

  // Phase 1: Export new notes
  const { exported, errors } = exportNotes(vaultPath);

  // Phase 2: Curate library (topics + dashboard)
  let curation = { topics: 0, dashboard: false };
  try {
    curation = await curateLibrary(vaultPath);
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Library curation failed (notes still exported)');
  }

  const message = `Exported ${exported} notes. Curated ${curation.topics} topics.`;
  log.info({ exported, errors, curation }, 'Export complete');

  return {
    success: errors === 0,
    exported_count: exported,
    errors,
    message,
  };
}

// CLI entry point
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
```

**Step 2: Update types**

Remove `ExportableNote` and `ExportResult` from `src/types/index.ts` since they're now defined locally in export-obsidian.ts. Keep them if other files import them — check first.

**Step 3: Verify compilation**

```bash
npx tsc --noEmit
```

Expected: No errors.

**Step 4: Test with migration reset**

Reset export flags so all notes re-export in the new clean format:

```bash
sqlite3 data/selene.db "UPDATE raw_notes SET exported_to_obsidian = 0 WHERE test_run IS NULL;"
npx ts-node src/workflows/export-obsidian.ts
```

Expected: Notes exported to `vault/Selene/Notes/` as clean markdown files.

**Step 5: Verify a note looks correct**

```bash
ls vault/Selene/Notes/ | head -5
cat vault/Selene/Notes/$(ls vault/Selene/Notes/ | head -1)
```

Expected: Clean markdown with title, content in blockquote, essence, theme/concept links. No emoji tables, no ADHD badges, no 4-path copies.

**Step 6: Commit**

```bash
git add src/workflows/export-obsidian.ts src/types/index.ts
git commit -m "feat: rewrite Obsidian export — clean single-file notes

Phase 1 of Obsidian Librarian. Each note becomes one clean markdown
file in Selene/Notes/ with title, content, essence, and concept links.
Replaces 500-line over-engineered 4-copy format.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Implement Library Curation (Phase 2)

**Why:** This is the librarian — LLM-generated topic indexes and dashboard that make the vault worth opening.

**Files:**
- Modify: `src/workflows/export-obsidian.ts` (replace curateLibrary stub)
- Modify: `src/lib/prompts.ts` (add curation prompts)

**Step 1: Add curation prompts to `src/lib/prompts.ts`**

Append these to the existing file:

```typescript
export const TOPIC_INDEX_PROMPT = `You are a librarian organizing a personal knowledge base. Write a topic index page for the theme "{theme}".

Here are the notes in this topic ({count} total):

{noteList}

Write:
1. A 2-3 sentence summary of what this person thinks about regarding {theme}. Be specific — reference actual content from the notes, not generic descriptions.
2. A "Recent" section (notes from the last 2 weeks) with each note as: - [[{filename}]] — one-line description based on the essence or content
3. An "Earlier" section for older notes in the same format
4. A "Connections" line suggesting 2-3 related themes/concepts from the note contents

Write in second person ("You've been thinking about..."). Be conversational, not formal.
Do NOT include any frontmatter or markdown headers — I will add those myself.
Start directly with the summary paragraph.`;

export const DASHBOARD_PROMPT = `You are a librarian maintaining a personal knowledge dashboard. Write a dashboard for this knowledge base.

Library stats: {totalNotes} total notes

Recent captures (last 7 days):
{recentNotes}

Topic activity:
{topicStats}

Write these sections (no frontmatter, no top-level heading — I add those):

## What's New
A 2-3 sentence natural language summary of recent captures. What has this person been thinking about? Then list the recent notes as: - [[{filename}]] — one-line description

## Active Topics
A markdown table with columns: Topic, Recent Notes, Last Activity. Link topics as [[topic-name]].

## Emerging Patterns
1-2 paragraphs about what's recurring, what's new, what seems to be growing into a bigger theme. Be specific and insightful.

## Quiet Topics
List topics that haven't had new notes in 2+ weeks with their last activity date. Frame this as a gentle reminder, not a warning.

Write in second person. Be conversational and specific, not generic.`;
```

**Step 2: Implement curateLibrary in export-obsidian.ts**

Replace the stub `curateLibrary` function with the full implementation:

```typescript
// ---------------------------------------------------------------------------
// Phase 2: Curate library (topics + dashboard)
// ---------------------------------------------------------------------------

function getAllNotesForCuration(): Array<{
  id: number;
  title: string;
  created_at: string;
  primary_theme: string | null;
  concepts: string | null;
  essence: string | null;
  exported_at: string | null;
}> {
  return db
    .prepare(
      `SELECT
        rn.id, rn.title, rn.created_at,
        pn.primary_theme, pn.concepts, pn.essence
      FROM raw_notes rn
      JOIN processed_notes pn ON rn.id = pn.raw_note_id
      WHERE rn.status = 'processed'
        AND rn.test_run IS NULL
        AND rn.exported_to_obsidian = 1
      ORDER BY rn.created_at DESC`
    )
    .all() as Array<{
    id: number;
    title: string;
    created_at: string;
    primary_theme: string | null;
    concepts: string | null;
    essence: string | null;
    exported_at: string | null;
  }>;
}

function groupByTheme(notes: Array<{
  id: number;
  title: string;
  created_at: string;
  primary_theme: string | null;
  concepts: string | null;
  essence: string | null;
}>): TopicData[] {
  const themes = new Map<string, TopicData>();

  for (const note of notes) {
    const theme = note.primary_theme || 'uncategorized';
    const dateStr = new Date(note.created_at).toISOString().split('T')[0];
    const slug = createSlug(note.title);
    const filename = `${dateStr}-${slug}`;

    if (!themes.has(theme)) {
      themes.set(theme, {
        theme,
        noteCount: 0,
        lastActivity: dateStr,
        notes: [],
      });
    }

    const topic = themes.get(theme)!;
    topic.noteCount++;
    if (dateStr > topic.lastActivity) {
      topic.lastActivity = dateStr;
    }
    topic.notes.push({
      filename,
      title: note.title,
      essence: note.essence,
      date: dateStr,
    });
  }

  return Array.from(themes.values()).sort((a, b) =>
    b.lastActivity.localeCompare(a.lastActivity)
  );
}

async function generateTopicPage(topic: TopicData): Promise<string> {
  const noteList = topic.notes
    .map((n) => `- "${n.title}" (${n.date})${n.essence ? ` — ${n.essence}` : ''}`)
    .join('\n');

  const prompt = TOPIC_INDEX_PROMPT
    .replace(/\{theme\}/g, topic.theme)
    .replace('{count}', topic.noteCount.toString())
    .replace('{noteList}', noteList);

  const content = await generate(prompt);

  const relatedConcepts = topic.notes
    .flatMap((n) => parseJson<string[]>(null, []))  // concepts not stored on TopicData
    .filter((v, i, a) => a.indexOf(v) === i)
    .slice(0, 5);

  return `---
type: topic
updated: ${new Date().toISOString().split('T')[0]}
note_count: ${topic.noteCount}
---

# ${topic.theme.charAt(0).toUpperCase() + topic.theme.slice(1).replace(/-/g, ' ')}

${content.trim()}
`;
}

async function generateDashboard(
  topics: TopicData[],
  totalNotes: number
): Promise<string> {
  const now = new Date();
  const weekAgo = new Date(now);
  weekAgo.setDate(weekAgo.getDate() - 7);
  const weekAgoStr = weekAgo.toISOString().split('T')[0];

  const recentNotes = topics
    .flatMap((t) => t.notes.map((n) => ({ ...n, theme: t.theme })))
    .filter((n) => n.date >= weekAgoStr)
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, 15);

  const recentNotesStr = recentNotes.length > 0
    ? recentNotes
        .map((n) => `- "${n.title}" (${n.date}, theme: ${n.theme})${n.essence ? ` — ${n.essence}` : ''}`)
        .join('\n')
    : '- No notes captured this week';

  const topicStats = topics
    .slice(0, 15)
    .map((t) => {
      const recentCount = t.notes.filter((n) => n.date >= weekAgoStr).length;
      return `- ${t.theme}: ${t.noteCount} total, ${recentCount} this week, last activity ${t.lastActivity}`;
    })
    .join('\n');

  const prompt = DASHBOARD_PROMPT
    .replace('{totalNotes}', totalNotes.toString())
    .replace('{recentNotes}', recentNotesStr)
    .replace('{topicStats}', topicStats);

  const content = await generate(prompt, { timeoutMs: 180000 });

  const timestamp = now.toLocaleDateString('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });

  return `---
type: dashboard
updated: ${now.toISOString()}
---

# Selene Library

*Last updated: ${timestamp} — ${totalNotes} notes in the library*

${content.trim()}
`;
}

async function curateLibrary(vaultPath: string): Promise<{ topics: number; dashboard: boolean }> {
  if (!(await isAvailable())) {
    log.warn('Ollama not available — skipping library curation');
    return { topics: 0, dashboard: false };
  }

  const allNotes = getAllNotesForCuration();
  if (allNotes.length === 0) {
    log.info('No exported notes — skipping curation');
    return { topics: 0, dashboard: false };
  }

  const topics = groupByTheme(allNotes);
  const topicsDir = join(vaultPath, 'Selene', 'Topics');
  ensureDir(topicsDir);

  // Generate topic pages for themes with 2+ notes
  let topicCount = 0;
  for (const topic of topics) {
    if (topic.noteCount < 2) continue;

    try {
      const markdown = await generateTopicPage(topic);
      const filename = `${topic.theme}.md`;
      writeFileSync(join(topicsDir, filename), markdown, 'utf-8');
      log.info({ theme: topic.theme, noteCount: topic.noteCount }, 'Topic page generated');
      topicCount++;
    } catch (err) {
      const error = err as Error;
      log.error({ theme: topic.theme, err: error }, 'Failed to generate topic page');
    }
  }

  // Generate dashboard
  let dashboardGenerated = false;
  try {
    const markdown = await generateDashboard(topics, allNotes.length);
    writeFileSync(join(vaultPath, 'Selene', 'Dashboard.md'), markdown, 'utf-8');
    log.info('Dashboard generated');
    dashboardGenerated = true;
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Failed to generate dashboard');
  }

  return { topics: topicCount, dashboard: dashboardGenerated };
}
```

**Step 3: Add the prompt imports**

At the top of export-obsidian.ts, update the import from `../lib` and add:

```typescript
import { TOPIC_INDEX_PROMPT, DASHBOARD_PROMPT } from '../lib/prompts';
```

**Step 4: Verify compilation**

```bash
npx tsc --noEmit
```

**Step 5: Run the full export**

```bash
npx ts-node src/workflows/export-obsidian.ts
```

Expected: Notes exported, topic pages generated in `vault/Selene/Topics/`, dashboard generated at `vault/Selene/Dashboard.md`.

**Step 6: Verify topic page**

```bash
ls vault/Selene/Topics/
cat vault/Selene/Topics/$(ls vault/Selene/Topics/ | head -1)
```

Expected: LLM-written topic summary with recent/earlier note links.

**Step 7: Verify dashboard**

```bash
cat vault/Selene/Dashboard.md
```

Expected: Dashboard with What's New, Active Topics, Emerging Patterns, Quiet Topics sections.

**Step 8: Commit**

```bash
git add src/workflows/export-obsidian.ts src/lib/prompts.ts
git commit -m "feat: add LLM-curated topic indexes and dashboard

Phase 2 of Obsidian Librarian. Every hour, Ollama generates topic
index pages with summaries and a dashboard with patterns, active
topics, and quiet topic reminders.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Clean Up Old Vault Content

**Why:** The old export created files in 4 paths (Timeline, By-Concept, By-Theme, By-Energy) plus Concepts hub pages. These need to be removed so the vault is clean.

**Files:**
- No code changes — this is a one-time cleanup

**Step 1: Check what old content exists**

```bash
ls vault/Selene/ 2>/dev/null
```

Expected: Old directories like `Timeline/`, `By-Concept/`, `By-Theme/`, `By-Energy/`, `Concepts/`, plus our new `Notes/`, `Topics/`, `Dashboard.md`.

**Step 2: Move old content to archive**

```bash
mkdir -p archive/shelved-2026-03-21/vault-old
for dir in Timeline By-Concept By-Theme By-Energy Concepts Daily; do
  if [ -d "vault/Selene/$dir" ]; then
    mv "vault/Selene/$dir" archive/shelved-2026-03-21/vault-old/
  fi
done
```

**Step 3: Verify vault is clean**

```bash
ls vault/Selene/
```

Expected: Only `Notes/`, `Topics/`, `Dashboard.md`.

**Step 4: Commit**

```bash
git add -A vault/ archive/shelved-2026-03-21/vault-old/
git commit -m "chore: clean up old vault structure (4-path format archived)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

Note: vault/ may be in .gitignore. If so, this is just a local cleanup with no commit needed.

---

### Task 5: Test End-to-End and Update Docs

**Files:**
- Modify: `CLAUDE.md` (update export-obsidian description)

**Step 1: Full end-to-end test**

```bash
# 1. Send a test note
TEST_RUN="test-librarian-$(date +%Y%m%d-%H%M%S)"
curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{\"title\": \"Librarian Test Note\", \"content\": \"Testing the new Obsidian librarian export. This note should appear cleanly in the vault.\", \"test_run\": \"$TEST_RUN\"}"

# 2. Process it
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/distill-essences.ts

# 3. Export to vault
npx ts-node src/workflows/export-obsidian.ts

# 4. Check the result
ls vault/Selene/Notes/ | tail -3
cat vault/Selene/Dashboard.md | head -20

# 5. Cleanup
./scripts/cleanup-tests.sh "$TEST_RUN"
```

**Step 2: Update CLAUDE.md**

Update the export-obsidian description in the workflows table and any references to the vault structure.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for Obsidian Librarian export

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Summary of Commits

1. `fix: add missing essence columns to processed_notes`
2. `feat: rewrite Obsidian export — clean single-file notes`
3. `feat: add LLM-curated topic indexes and dashboard`
4. `chore: clean up old vault structure` (if applicable)
5. `docs: update CLAUDE.md for Obsidian Librarian export`

## Rollback

Each commit is independent and revertible. The old export-obsidian.ts is preserved in `archive/shelved-2026-03-21/workflows/export-obsidian.ts` from the earlier simplification work.
