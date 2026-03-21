# Obsidian Maps of Content Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace freeform theme explosion with 8 fixed categories, generate Maps of Content per category, and produce a code-generated dashboard with guaranteed real links.

**Architecture:** Update the extract prompt to constrain categorization, add DB columns for category + cross-refs, rewrite export-obsidian to generate per-category MOC pages and a code-generated dashboard, backfill existing notes.

**Tech Stack:** TypeScript, SQLite (better-sqlite3), Ollama/mistral:7b, Obsidian markdown vault

---

### Task 1: Add CATEGORIES constant and update prompts

**Files:**
- Modify: `src/lib/prompts.ts`

**Step 1: Add the CATEGORIES constant at the top of the file**

After the existing imports (there are none — it's a pure export file), add:

```typescript
export const CATEGORIES = [
  'Personal Growth',
  'Relationships & Social',
  'Health & Body',
  'Projects & Tech',
  'Career & Work',
  'Creativity & Expression',
  'Politics & Society',
  'Daily Systems',
] as const;

export type Category = typeof CATEGORIES[number];
```

**Step 2: Replace EXTRACT_PROMPT with the category-aware version**

Replace the existing `EXTRACT_PROMPT` string with:

```typescript
export const EXTRACT_PROMPT = `Analyze this note and extract key information.

Note Title: {title}
Note Content: {content}

Categories (pick the BEST fit for "category", optionally 1-2 others for "cross_ref_categories"):
- Personal Growth
- Relationships & Social
- Health & Body
- Projects & Tech
- Career & Work
- Creativity & Expression
- Politics & Society
- Daily Systems

Respond in JSON format:
{
  "concepts": ["concept1", "concept2", "concept3"],
  "category": "one of the 8 categories above",
  "cross_ref_categories": [],
  "primary_theme": "short freeform descriptor 2-4 words",
  "overall_sentiment": "positive|negative|neutral|mixed",
  "emotional_tone": "reflective|anxious|excited|frustrated|calm|curious|etc",
  "energy_level": "high|medium|low"
}

JSON response:`;
```

**Step 3: Add MOC_PROMPT**

Add after `DASHBOARD_PROMPT`:

```typescript
export const MOC_PROMPT = `You are a librarian organizing a personal knowledge library.
Topic: "{category}"

Here are the notes in this category:
{notes_list}

Cross-referenced notes from other categories:
{cross_ref_notes}

Organize these notes into a Map of Content with:
1. A 2-3 sentence intro in second person ("You've been exploring...")
2. Group notes into named sub-sections (## headers) by theme
3. Under each sub-section, list notes as "- [[{filename}]] — one-line description"
4. A "## See Also" section listing cross-referenced notes as "- [[{filename}]] — why it's relevant here"
5. At the bottom, link to related category MOCs as "Related: [[{other_category}]]"

Rules:
- Use [[filename]] EXACTLY as provided — never invent link names
- Every note must appear in exactly one sub-section
- Sub-section names should be 1-3 words (e.g., "Dating", "Family", "Social Skills")
- If a sub-section would have only 1 note, merge it with the most related sub-section
- Skip the "See Also" section if there are no cross-references
- Do NOT include frontmatter or a top-level heading (we add those ourselves)`;
```

**Step 4: Update the lib/index.ts exports**

In `src/lib/index.ts`, update the prompts export line:

```typescript
export { EXTRACT_PROMPT, ESSENCE_PROMPT, buildEssencePrompt, TOPIC_INDEX_PROMPT, DASHBOARD_PROMPT, MOC_PROMPT, CATEGORIES } from './prompts';
export type { Category } from './prompts';
```

**Step 5: Run TypeScript compile check**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 6: Commit**

```bash
git add src/lib/prompts.ts src/lib/index.ts
git commit -m "feat: add fixed categories and MOC prompt for Obsidian export"
```

---

### Task 2: Add DB columns and update process-llm

**Files:**
- Modify: `src/workflows/process-llm.ts`

**Step 1: Add migration for new columns at the top of process-llm.ts**

Add after the existing imports, before the `log` declaration:

```typescript
import { db } from '../lib';

// --- Migration (harmless no-op if columns exist) ---
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN category TEXT');
} catch { /* column already exists */ }
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN cross_ref_categories TEXT');
} catch { /* column already exists */ }
```

Note: `db` is already imported via the destructured import on line 1-8. Add only the migration block after line 10 (after the `EXTRACT_PROMPT` import).

**Step 2: Update the INSERT statement to include new columns**

Replace the existing INSERT on lines 66-79:

```typescript
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
```

**Step 3: Update the fallback extracted object (parse failure case)**

Replace the fallback on lines 55-62:

```typescript
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
```

**Step 4: Run TypeScript compile check**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 5: Commit**

```bash
git add src/workflows/process-llm.ts
git commit -m "feat: save category and cross_ref_categories in process-llm"
```

---

### Task 3: Rewrite export-obsidian with MOC generation and code-generated dashboard

**Files:**
- Modify: `src/workflows/export-obsidian.ts`

This is the largest task. The file keeps Phase 1 (note export) mostly unchanged but replaces Phase 2 entirely.

**Step 1: Update imports**

Replace the existing import of prompts on line 4:

```typescript
import { MOC_PROMPT, CATEGORIES } from '../lib/prompts';
```

(Remove `TOPIC_INDEX_PROMPT` and `DASHBOARD_PROMPT` — they're no longer used.)

**Step 2: Add a new interface for MOC note data**

Add after the existing `TopicData` interface (or replace it):

```typescript
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
```

**Step 3: Replace the `curateLibrary` function with `generateMocs`**

Replace the entire `curateLibrary` function (lines 177-354) with:

```typescript
async function generateMocs(vaultPath: string): Promise<{ mocs: number; dashboard: boolean }> {
  const ollamaUp = await isAvailable();
  if (!ollamaUp) {
    log.warn('Ollama not available, skipping MOC generation');
    return { mocs: 0, dashboard: false };
  }

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
        AND rn.test_run IS NULL
        AND rn.status = 'processed'
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

  // Generate MOC pages
  const mapsDir = join(vaultPath, 'Selene', 'Maps');
  ensureDir(mapsDir);

  let mocCount = 0;

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

  // Generate code-based dashboard (no LLM)
  let dashboardGenerated = false;
  try {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    // Recent 10 notes
    const recentNotes = noteWithFilename.slice(0, 10);

    // Category table rows
    const categoryRows = CATEGORIES
      .map((cat) => {
        const data = categoryMap.get(cat)!;
        if (data.notes.length === 0) return null;
        const lastDate = data.lastActivity
          ? new Date(data.lastActivity).toISOString().split('T')[0]
          : '—';
        return `| [[${cat}]] | ${data.notes.length} | ${lastDate} |`;
      })
      .filter(Boolean);

    // Quiet categories (no notes in last 30 days)
    const quietCategories = CATEGORIES.filter((cat) => {
      const data = categoryMap.get(cat)!;
      if (data.notes.length === 0) return false;
      return !data.lastActivity || new Date(data.lastActivity) < thirtyDaysAgo;
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

    const seleneDir = join(vaultPath, 'Selene');
    ensureDir(seleneDir);
    writeFileSync(join(seleneDir, 'Dashboard.md'), dashboardMarkdown, 'utf-8');
    log.info('Generated dashboard');
    dashboardGenerated = true;
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Failed to generate dashboard');
  }

  return { mocs: mocCount, dashboard: dashboardGenerated };
}
```

**Step 4: Update the main `exportObsidian` function to use `generateMocs` and skip if no new notes**

Replace the Phase 2 section (lines 372-387) in the `exportObsidian` function:

```typescript
  // Phase 2: Generate MOCs (only if new notes were exported)
  let phase2 = { mocs: 0, dashboard: false };
  if (phase1.exported > 0) {
    try {
      phase2 = await generateMocs(vaultPath);
    } catch (err) {
      const error = err as Error;
      log.error({ err: error }, 'MOC generation failed (non-blocking)');
    }
  } else {
    log.info('No new notes exported, skipping MOC generation');
  }

  const message = [
    `Exported ${phase1.exported} notes`,
    phase2.mocs > 0 ? `${phase2.mocs} MOC pages` : null,
    phase2.dashboard ? 'dashboard updated' : null,
  ]
    .filter(Boolean)
    .join(', ');
```

**Step 5: Remove unused TOPIC_INDEX_PROMPT and DASHBOARD_PROMPT imports**

The import on line 4 should now only import `MOC_PROMPT` and `CATEGORIES`:

```typescript
import { MOC_PROMPT, CATEGORIES } from '../lib/prompts';
```

Also update `src/lib/index.ts` — the old `TOPIC_INDEX_PROMPT` and `DASHBOARD_PROMPT` exports can stay for now (they're not harmful), but remove them from any import in export-obsidian.

**Step 6: Run TypeScript compile check**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 7: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "feat: rewrite Obsidian export with MOC pages and code-generated dashboard"
```

---

### Task 4: Create backfill script

**Files:**
- Create: `scripts/backfill-categories.ts`

**Step 1: Write the backfill script**

```typescript
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
```

**Step 2: Run TypeScript compile check**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add scripts/backfill-categories.ts
git commit -m "feat: add backfill script for note category migration"
```

---

### Task 5: Clean up vault stubs and old Topics directory

**Files:**
- No code files — vault cleanup only

**Step 1: Delete 0-byte stub files from vault root**

```bash
find vault/ -maxdepth 1 -name "*.md" -empty -delete
```

**Step 2: Remove old Topics directory**

```bash
rm -rf vault/Selene/Topics
```

**Step 3: Verify vault structure looks clean**

```bash
ls -la vault/
ls -la vault/Selene/
```

Expected: No 0-byte files in vault root. No Topics directory. Dashboard.md and Notes/ still present.

**Step 4: Commit**

The vault directory is gitignored (check `.gitignore` first). If it is, no commit needed — this is a local-only cleanup. If vault IS tracked, commit the removals.

---

### Task 6: Run backfill and verify end-to-end

**Step 1: Run the backfill script**

```bash
npx ts-node scripts/backfill-categories.ts
```

Expected: Logs showing each note being categorized. ~133 notes processed. Should take 20-30 minutes on mistral:7b.

**Step 2: Verify categories in database**

```bash
sqlite3 data/selene.db "SELECT category, COUNT(*) FROM processed_notes WHERE category IS NOT NULL GROUP BY category ORDER BY COUNT(*) DESC;"
```

Expected: 8 categories with reasonable distribution (no single category should have >60% of notes).

**Step 3: Run the export to generate MOCs and dashboard**

```bash
npx ts-node src/workflows/export-obsidian.ts
```

Expected: Notes re-exported, MOC pages generated in `vault/Selene/Maps/`, dashboard generated.

**Step 4: Verify vault output**

```bash
ls vault/Selene/Maps/
cat vault/Selene/Dashboard.md
```

Expected: Up to 8 `.md` files in Maps/ (one per category with notes). Dashboard shows a table linking to `[[category]]` names.

**Step 5: Open in Obsidian and verify**

- Dashboard links to MOC pages (not empty stubs)
- MOC pages have sub-sections with wiki-links to actual note files
- No 0-byte stubs created
- Cross-references appear in "See Also" sections

**Step 6: Commit any final adjustments**

```bash
git add -A
git commit -m "feat: complete Obsidian MOC migration — categories backfilled, export verified"
```

---

### Task 7: Clean up old exports from lib/index.ts (optional)

**Files:**
- Modify: `src/lib/index.ts`

**Step 1: Remove TOPIC_INDEX_PROMPT and DASHBOARD_PROMPT from exports**

These prompts are no longer used by any workflow. Update the export line in `src/lib/index.ts`:

```typescript
export { EXTRACT_PROMPT, ESSENCE_PROMPT, buildEssencePrompt, MOC_PROMPT, CATEGORIES } from './prompts';
export type { Category } from './prompts';
```

**Step 2: Optionally remove the old prompt constants from prompts.ts**

Delete `TOPIC_INDEX_PROMPT` and `DASHBOARD_PROMPT` from `src/lib/prompts.ts` since nothing imports them anymore.

**Step 3: Run TypeScript compile check**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 4: Commit**

```bash
git add src/lib/prompts.ts src/lib/index.ts
git commit -m "chore: remove unused TOPIC_INDEX_PROMPT and DASHBOARD_PROMPT"
```
