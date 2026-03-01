# Tiered Context Compression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add lifecycle-based fidelity tiers so Selene's LLM workflows can scale with growing note volume by using compressed representations instead of raw text.

**Architecture:** New columns on `processed_notes` (essence, fidelity_tier) and `threads` (thread_digest). A shared `ContextBuilder` utility assembles prompts using the right representation per tier. Three new background workflows handle distillation, tier evaluation, and digest compilation.

**Tech Stack:** TypeScript, better-sqlite3, Ollama, Fastify, launchd

---

### Task 1: Schema Migration — Add New Columns

**Files:**
- Modify: `src/lib/db.ts`

**Step 1: Write the schema migration at the bottom of db.ts**

Add after the `device_tokens` table creation (after line 597), before the cleanup handler:

```typescript
// Schema migration: Tiered context compression
db.exec(`
  ALTER TABLE processed_notes ADD COLUMN essence TEXT;
`);
```

But `ALTER TABLE ADD COLUMN` fails if the column already exists. Use the safe pattern from the codebase — check first:

```typescript
// Schema migration: Tiered context compression columns
const processedNotesCols = db.prepare("PRAGMA table_info(processed_notes)").all() as Array<{ name: string }>;
const colNames = new Set(processedNotesCols.map(c => c.name));

if (!colNames.has('essence')) {
  db.exec(`ALTER TABLE processed_notes ADD COLUMN essence TEXT`);
  db.exec(`ALTER TABLE processed_notes ADD COLUMN essence_at TEXT`);
  db.exec(`ALTER TABLE processed_notes ADD COLUMN fidelity_tier TEXT DEFAULT 'full'`);
  db.exec(`ALTER TABLE processed_notes ADD COLUMN fidelity_evaluated_at TEXT`);
  logger.info('Migration: added essence/fidelity columns to processed_notes');
}

const threadsCols = db.prepare("PRAGMA table_info(threads)").all() as Array<{ name: string }>;
const threadColNames = new Set(threadsCols.map(c => c.name));

if (!threadColNames.has('thread_digest')) {
  db.exec(`ALTER TABLE threads ADD COLUMN thread_digest TEXT`);
  logger.info('Migration: added thread_digest column to threads');
}
```

**Step 2: Add the `ProcessedNote` type for queries that need essence/fidelity data**

Add after the `NoteWithProcessedData` interface (after line 255):

```typescript
// Type for processed_notes with essence and fidelity data
export interface ProcessedNoteWithEssence {
  raw_note_id: number;
  essence: string | null;
  essence_at: string | null;
  fidelity_tier: string;
  fidelity_evaluated_at: string | null;
  concepts: string | null;
  primary_theme: string | null;
  secondary_themes: string | null;
}
```

**Step 3: Add helper functions for essence and fidelity queries**

Add after the `getTasksForThread` function (after line 318):

```typescript
// Helper: Get processed notes that need essence distillation
export function getNotesNeedingEssence(limit = 10): Array<{ raw_note_id: number; title: string; content: string; concepts: string | null; primary_theme: string | null }> {
  return db.prepare(`
    SELECT p.raw_note_id, r.title, r.content, p.concepts, p.primary_theme
    FROM processed_notes p
    JOIN raw_notes r ON p.raw_note_id = r.id
    WHERE p.essence IS NULL
      AND r.test_run IS NULL
    ORDER BY p.processed_at ASC
    LIMIT ?
  `).all(limit) as Array<{ raw_note_id: number; title: string; content: string; concepts: string | null; primary_theme: string | null }>;
}

// Helper: Save essence for a processed note
export function saveEssence(rawNoteId: number, essence: string): void {
  db.prepare(`
    UPDATE processed_notes
    SET essence = ?, essence_at = ?
    WHERE raw_note_id = ?
  `).run(essence, new Date().toISOString(), rawNoteId);
}

// Helper: Get fidelity tier stats for health endpoint
export function getFidelityStats(): { pending_essences: number; tier_full: number; tier_high: number; tier_summary: number; tier_skeleton: number } {
  return db.prepare(`
    SELECT
      SUM(CASE WHEN essence IS NULL AND processed_at IS NOT NULL THEN 1 ELSE 0 END) as pending_essences,
      SUM(CASE WHEN fidelity_tier = 'full' OR fidelity_tier IS NULL THEN 1 ELSE 0 END) as tier_full,
      SUM(CASE WHEN fidelity_tier = 'high' THEN 1 ELSE 0 END) as tier_high,
      SUM(CASE WHEN fidelity_tier = 'summary' THEN 1 ELSE 0 END) as tier_summary,
      SUM(CASE WHEN fidelity_tier = 'skeleton' THEN 1 ELSE 0 END) as tier_skeleton
    FROM processed_notes
  `).get() as { pending_essences: number; tier_full: number; tier_high: number; tier_summary: number; tier_skeleton: number };
}

// Helper: Get essence and fidelity data for a set of note IDs
export function getEssenceData(noteIds: number[]): Map<number, ProcessedNoteWithEssence> {
  if (noteIds.length === 0) return new Map();
  const placeholders = noteIds.map(() => '?').join(',');
  const rows = db.prepare(`
    SELECT raw_note_id, essence, essence_at, fidelity_tier, fidelity_evaluated_at,
           concepts, primary_theme, secondary_themes
    FROM processed_notes
    WHERE raw_note_id IN (${placeholders})
  `).all(...noteIds) as ProcessedNoteWithEssence[];

  const map = new Map<number, ProcessedNoteWithEssence>();
  for (const row of rows) {
    map.set(row.raw_note_id, row);
  }
  return map;
}

// Helper: Update fidelity tier for a note
export function updateFidelityTier(rawNoteId: number, tier: string): void {
  db.prepare(`
    UPDATE processed_notes
    SET fidelity_tier = ?, fidelity_evaluated_at = ?
    WHERE raw_note_id = ?
  `).run(tier, new Date().toISOString(), rawNoteId);
}

// Helper: Save thread digest
export function saveThreadDigest(threadId: number, digest: string): void {
  db.prepare(`
    UPDATE threads SET thread_digest = ?, updated_at = ? WHERE id = ?
  `).run(digest, new Date().toISOString(), threadId);
}

// Helper: Get thread digest
export function getThreadDigest(threadId: number): string | null {
  const row = db.prepare('SELECT thread_digest FROM threads WHERE id = ?').get(threadId) as { thread_digest: string | null } | undefined;
  return row?.thread_digest ?? null;
}
```

**Step 4: Export new functions from lib/index.ts**

Add to the db exports in `src/lib/index.ts`:

```typescript
export {
  // ...existing exports...
  getNotesNeedingEssence,
  saveEssence,
  getFidelityStats,
  getEssenceData,
  updateFidelityTier,
  saveThreadDigest,
  getThreadDigest,
} from './db';
export type { ProcessedNoteWithEssence } from './db';
```

**Step 5: Verify the migration runs**

Run: `npx ts-node -e "require('./src/lib/db')"`
Expected: No errors, logger output shows migration messages on first run.

**Step 6: Verify columns exist**

Run: `sqlite3 ~/selene-data/selene.db "PRAGMA table_info(processed_notes);" | grep -E 'essence|fidelity'`
Expected: Shows essence, essence_at, fidelity_tier, fidelity_evaluated_at columns.

Run: `sqlite3 ~/selene-data/selene.db "PRAGMA table_info(threads);" | grep thread_digest`
Expected: Shows thread_digest column.

**Step 7: Commit**

```bash
git add src/lib/db.ts src/lib/index.ts
git commit -m "feat: add schema migration for essence and fidelity tier columns"
```

---

### Task 2: ContextBuilder Utility

**Files:**
- Create: `src/lib/context-builder.ts`
- Modify: `src/lib/index.ts`

**Step 1: Create the ContextBuilder**

Create `src/lib/context-builder.ts`:

```typescript
import { db } from './db';
import type { ProcessedNoteWithEssence } from './db';
import { logger } from './logger';

const log = logger.child({ module: 'context-builder' });

type FidelityTier = 'full' | 'high' | 'summary' | 'skeleton';

interface ContextBlock {
  noteId: number;
  tier: FidelityTier;
  content: string;
  tokenEstimate: number;
  relevance: number;
}

/**
 * Assembles LLM prompt context from notes and threads,
 * respecting fidelity tiers and a token budget.
 */
export class ContextBuilder {
  private blocks: ContextBlock[] = [];
  private budget: number;
  private forceFullIds = new Set<number>();

  constructor(budgetTokens: number) {
    this.budget = budgetTokens;
  }

  /**
   * Add notes — builder picks the right representation per fidelity tier.
   * Notes are rendered based on their stored fidelity_tier unless overridden by addFullText.
   */
  addNotes(noteIds: number[], relevanceScores?: Map<number, number>): this {
    if (noteIds.length === 0) return this;

    const placeholders = noteIds.map(() => '?').join(',');

    // Fetch raw note data
    const rawNotes = db.prepare(`
      SELECT id, title, content FROM raw_notes WHERE id IN (${placeholders})
    `).all(...noteIds) as Array<{ id: number; title: string; content: string }>;

    // Fetch processed data with essence/fidelity
    const processedRows = db.prepare(`
      SELECT raw_note_id, essence, fidelity_tier, concepts, primary_theme, secondary_themes
      FROM processed_notes WHERE raw_note_id IN (${placeholders})
    `).all(...noteIds) as Array<{
      raw_note_id: number;
      essence: string | null;
      fidelity_tier: string | null;
      concepts: string | null;
      primary_theme: string | null;
      secondary_themes: string | null;
    }>;

    const processedMap = new Map(processedRows.map(r => [r.raw_note_id, r]));
    const rawMap = new Map(rawNotes.map(r => [r.id, r]));

    for (const noteId of noteIds) {
      const raw = rawMap.get(noteId);
      if (!raw) continue;

      const processed = processedMap.get(noteId);
      const tier = (this.forceFullIds.has(noteId) ? 'full' : processed?.fidelity_tier || 'full') as FidelityTier;
      const relevance = relevanceScores?.get(noteId) ?? 0.5;

      const content = this.renderBlock(raw, processed ?? null, tier);
      const tokenEstimate = Math.ceil(content.length / 4);

      this.blocks.push({ noteId, tier, content, tokenEstimate, relevance });
    }

    return this;
  }

  /**
   * Add a thread's context. Uses thread_digest if available,
   * otherwise falls back to assembling member note essences.
   */
  addThread(threadId: number): this {
    const thread = db.prepare(`
      SELECT id, name, summary, why, thread_digest FROM threads WHERE id = ?
    `).get(threadId) as { id: number; name: string; summary: string | null; why: string | null; thread_digest: string | null } | undefined;

    if (!thread) return this;

    if (thread.thread_digest) {
      const content = `Thread: ${thread.name}\n${thread.thread_digest}`;
      this.blocks.push({
        noteId: -threadId, // negative to distinguish from notes
        tier: 'summary',
        content,
        tokenEstimate: Math.ceil(content.length / 4),
        relevance: 0.9,
      });
    } else {
      // Fall back to summary + why
      const parts = [`Thread: ${thread.name}`];
      if (thread.summary) parts.push(thread.summary);
      if (thread.why) parts.push(`Why: ${thread.why}`);

      // Add member essences
      const memberNotes = db.prepare(`
        SELECT r.id, r.title, p.essence
        FROM thread_notes tn
        JOIN raw_notes r ON tn.raw_note_id = r.id
        LEFT JOIN processed_notes p ON r.id = p.raw_note_id
        WHERE tn.thread_id = ?
        ORDER BY r.created_at DESC
        LIMIT 20
      `).all(threadId) as Array<{ id: number; title: string; essence: string | null }>;

      for (const note of memberNotes) {
        if (note.essence) {
          parts.push(`- ${note.title}: ${note.essence}`);
        } else {
          parts.push(`- ${note.title}`);
        }
      }

      const content = parts.join('\n');
      this.blocks.push({
        noteId: -threadId,
        tier: 'summary',
        content,
        tokenEstimate: Math.ceil(content.length / 4),
        relevance: 0.8,
      });
    }

    return this;
  }

  /**
   * Force full text for specific notes, regardless of their fidelity tier.
   * Must be called before addNotes for those IDs.
   */
  addFullText(noteIds: number[]): this {
    for (const id of noteIds) {
      this.forceFullIds.add(id);
    }
    return this;
  }

  /**
   * Assemble final context string. Sorts by relevance descending,
   * fills until budget is exhausted, returns concatenated blocks.
   */
  build(): string {
    // Sort by relevance (highest first)
    const sorted = [...this.blocks].sort((a, b) => b.relevance - a.relevance);

    const included: string[] = [];
    let tokensUsed = 0;

    for (const block of sorted) {
      if (tokensUsed + block.tokenEstimate > this.budget) {
        log.debug(
          { noteId: block.noteId, tokenEstimate: block.tokenEstimate, budgetRemaining: this.budget - tokensUsed },
          'Skipping block — over budget'
        );
        continue;
      }

      included.push(block.content);
      tokensUsed += block.tokenEstimate;
    }

    log.info({ blocksIncluded: included.length, blocksSkipped: sorted.length - included.length, tokensUsed, budget: this.budget }, 'Context assembled');

    return included.join('\n\n');
  }

  /**
   * Render a note at the appropriate fidelity tier.
   * Fallback chain: essence → concepts + themes → truncated raw text
   */
  private renderBlock(
    raw: { id: number; title: string; content: string },
    processed: { essence: string | null; concepts: string | null; primary_theme: string | null; secondary_themes: string | null } | null,
    tier: FidelityTier
  ): string {
    switch (tier) {
      case 'full':
        return `Title: ${raw.title}\n${raw.content}`;

      case 'high': {
        const essence = this.getEssenceOrFallback(raw, processed);
        return `Title: ${raw.title}\nEssence: ${essence}\nFull text: ${raw.content}`;
      }

      case 'summary': {
        const essence = this.getEssenceOrFallback(raw, processed);
        const themes = this.formatThemes(processed);
        return themes
          ? `Title: ${raw.title}\n${essence}\nThemes: ${themes}`
          : `Title: ${raw.title}\n${essence}`;
      }

      case 'skeleton': {
        const theme = processed?.primary_theme || 'unprocessed';
        return `${raw.title} [${theme}]`;
      }
    }
  }

  /**
   * Get essence with fallback chain:
   * essence → concepts + themes → truncated raw text (150 chars)
   */
  private getEssenceOrFallback(
    raw: { title: string; content: string },
    processed: { essence: string | null; concepts: string | null; primary_theme: string | null } | null
  ): string {
    if (processed?.essence) return processed.essence;

    // Fallback: concepts + theme
    if (processed?.concepts) {
      try {
        const concepts = JSON.parse(processed.concepts) as string[];
        if (concepts.length > 0) {
          const theme = processed.primary_theme ? ` (${processed.primary_theme})` : '';
          return concepts.slice(0, 3).join(', ') + theme;
        }
      } catch { /* fall through */ }
    }

    // Last resort: truncated content
    log.debug({ noteId: raw.title }, 'No essence or concepts — falling back to truncation');
    return raw.content.slice(0, 150) + (raw.content.length > 150 ? '...' : '');
  }

  private formatThemes(processed: { primary_theme: string | null; secondary_themes: string | null } | null): string {
    if (!processed) return '';
    const themes: string[] = [];
    if (processed.primary_theme) themes.push(processed.primary_theme);
    if (processed.secondary_themes) {
      try {
        const secondary = JSON.parse(processed.secondary_themes) as string[];
        themes.push(...secondary);
      } catch { /* ignore */ }
    }
    return themes.join(', ');
  }
}
```

**Step 2: Export from lib/index.ts**

Add to `src/lib/index.ts`:

```typescript
export { ContextBuilder } from './context-builder';
```

**Step 3: Verify it compiles**

Run: `npx tsc --noEmit src/lib/context-builder.ts`
Expected: No errors.

**Step 4: Commit**

```bash
git add src/lib/context-builder.ts src/lib/index.ts
git commit -m "feat: add ContextBuilder for tiered context assembly"
```

---

### Task 3: Modify process-llm.ts — Inline Essence Computation

**Files:**
- Modify: `src/workflows/process-llm.ts`

**Step 1: Add essence prompt and computation after existing LLM processing**

Add the `ESSENCE_PROMPT` constant after the existing `EXTRACT_PROMPT` (after line 28):

```typescript
const ESSENCE_PROMPT = `Summarize this note in 1-2 sentences. Capture what it means to the person who wrote it — not just the topic, but the intent or insight.

Title: {title}
Content: {content}
Key concepts: {concepts}
Theme: {theme}

One to two sentence essence:`;
```

Then inside the `for (const note of notes)` loop, after `markProcessed(note.id)` (after line 98), add a second LLM call:

```typescript
      // Compute essence inline (best-effort — failures handled by distill-essences backfill)
      try {
        const essencePrompt = ESSENCE_PROMPT
          .replace('{title}', note.title)
          .replace('{content}', note.content)
          .replace('{concepts}', JSON.stringify(extracted.concepts || []))
          .replace('{theme}', extracted.primary_theme || 'unknown');

        const essenceResponse = await generate(essencePrompt, { timeoutMs: 30000 });
        const essence = essenceResponse.trim().replace(/^["']|["']$/g, '');

        if (essence.length > 0 && essence.length < 500) {
          db.prepare('UPDATE processed_notes SET essence = ?, essence_at = ? WHERE raw_note_id = ?')
            .run(essence, new Date().toISOString(), note.id);
          log.info({ noteId: note.id, essenceLength: essence.length }, 'Essence computed inline');
        }
      } catch (essenceErr) {
        log.warn({ noteId: note.id, err: essenceErr }, 'Inline essence failed — will be picked up by distill-essences');
      }
```

**Step 2: Import `generate` directly if not already (it is — via `../lib`)**

Check: `generate` is already imported at line 5. No change needed.

**Step 3: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/process-llm.ts`
Expected: No errors.

**Step 4: Commit**

```bash
git add src/workflows/process-llm.ts
git commit -m "feat: compute note essence inline during LLM processing"
```

---

### Task 4: New Workflow — distill-essences.ts (Backfill)

**Files:**
- Create: `src/workflows/distill-essences.ts`
- Create: `launchd/com.selene.distill-essences.plist`

**Step 1: Create the workflow**

Create `src/workflows/distill-essences.ts`:

```typescript
import { createWorkflowLogger, getNotesNeedingEssence, saveEssence, generate, isAvailable, db } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('distill-essences');

const ESSENCE_PROMPT = `Summarize this note in 1-2 sentences. Capture what it means to the person who wrote it — not just the topic, but the intent or insight.

Title: {title}
Content: {content}
Key concepts: {concepts}
Theme: {theme}

One to two sentence essence:`;

// Track consecutive failures per note to skip problematic ones
const SKIP_AFTER_FAILURES = 3;
const SKIP_DURATION_MS = 24 * 60 * 60 * 1000; // 24 hours

interface SkipEntry { count: number; skipUntil: number }
const failureTracker = new Map<number, SkipEntry>();

export async function distillEssences(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting essence distillation run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  const notes = getNotesNeedingEssence(limit);
  log.info({ noteCount: notes.length }, 'Found notes needing essence');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };
  const now = Date.now();

  for (const note of notes) {
    // Check skip list
    const skipEntry = failureTracker.get(note.raw_note_id);
    if (skipEntry && skipEntry.count >= SKIP_AFTER_FAILURES && now < skipEntry.skipUntil) {
      log.debug({ noteId: note.raw_note_id }, 'Skipping — in cooldown after repeated failures');
      continue;
    }

    try {
      const concepts = note.concepts || '[]';
      const theme = note.primary_theme || 'unknown';

      const prompt = ESSENCE_PROMPT
        .replace('{title}', note.title)
        .replace('{content}', note.content)
        .replace('{concepts}', concepts)
        .replace('{theme}', theme);

      const response = await generate(prompt, { timeoutMs: 30000 });
      const essence = response.trim().replace(/^["']|["']$/g, '');

      if (essence.length > 0 && essence.length < 500) {
        saveEssence(note.raw_note_id, essence);
        failureTracker.delete(note.raw_note_id);
        log.info({ noteId: note.raw_note_id, essenceLength: essence.length }, 'Essence distilled');
        result.processed++;
        result.details.push({ id: note.raw_note_id, success: true });
      } else {
        throw new Error(`Invalid essence length: ${essence.length}`);
      }
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.raw_note_id, err: error }, 'Failed to distill essence');

      const entry = failureTracker.get(note.raw_note_id) || { count: 0, skipUntil: 0 };
      entry.count++;
      if (entry.count >= SKIP_AFTER_FAILURES) {
        entry.skipUntil = now + SKIP_DURATION_MS;
        log.warn({ noteId: note.raw_note_id, skipUntil: new Date(entry.skipUntil).toISOString() }, 'Note skipped for 24h after repeated failures');
      }
      failureTracker.set(note.raw_note_id, entry);

      result.errors++;
      result.details.push({ id: note.raw_note_id, success: false, error: error.message });
    }
  }

  log.info({ processed: result.processed, errors: result.errors }, 'Essence distillation run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  distillEssences()
    .then((result) => {
      console.log('Distill-essences complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Distill-essences failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Create launchd plist**

Create `launchd/com.selene.distill-essences.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.distill-essences</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>--transpile-only</string>
        <string>src/workflows/distill-essences.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_ENV</key>
        <string>production</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
    </dict>

    <key>StartInterval</key>
    <integer>300</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/distill-essences.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/distill-essences.error.log</string>
</dict>
</plist>
```

**Step 3: Verify it compiles and runs**

Run: `npx tsc --noEmit src/workflows/distill-essences.ts`
Expected: No errors.

Run: `npx ts-node src/workflows/distill-essences.ts`
Expected: Processes up to 10 notes, logs essence distillation results.

**Step 4: Commit**

```bash
git add src/workflows/distill-essences.ts launchd/com.selene.distill-essences.plist
git commit -m "feat: add distill-essences workflow for backfill and retry"
```

---

### Task 5: New Workflow — evaluate-fidelity.ts

**Files:**
- Create: `src/workflows/evaluate-fidelity.ts`
- Create: `launchd/com.selene.evaluate-fidelity.plist`

**Step 1: Create the workflow**

Create `src/workflows/evaluate-fidelity.ts`:

```typescript
import { createWorkflowLogger, db } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('evaluate-fidelity');

// Tier thresholds (days)
const FULL_MAX_AGE_DAYS = 7;
const HIGH_MAX_AGE_DAYS = 90;
const SKELETON_INACTIVE_DAYS = 180;

interface NoteForEvaluation {
  raw_note_id: number;
  fidelity_tier: string | null;
  essence: string | null;
  created_at: string;
  thread_status: string | null;
}

export async function evaluateFidelity(): Promise<WorkflowResult> {
  log.info('Starting fidelity tier evaluation');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };
  const now = new Date();

  // Get all notes not at skeleton tier (skeleton is terminal unless rehydrated by thread assignment)
  const notes = db.prepare(`
    SELECT p.raw_note_id, p.fidelity_tier, p.essence, r.created_at,
           t.status as thread_status
    FROM processed_notes p
    JOIN raw_notes r ON p.raw_note_id = r.id
    LEFT JOIN thread_notes tn ON r.id = tn.raw_note_id
    LEFT JOIN threads t ON tn.thread_id = t.id
    WHERE r.test_run IS NULL
      AND (p.fidelity_tier IS NULL OR p.fidelity_tier != 'skeleton')
  `).all() as NoteForEvaluation[];

  log.info({ noteCount: notes.length }, 'Notes to evaluate');

  const updateStmt = db.prepare(`
    UPDATE processed_notes SET fidelity_tier = ?, fidelity_evaluated_at = ? WHERE raw_note_id = ?
  `);

  const nowIso = now.toISOString();
  let transitions = { toFull: 0, toHigh: 0, toSummary: 0, toSkeleton: 0, unchanged: 0 };

  for (const note of notes) {
    try {
      const ageMs = now.getTime() - new Date(note.created_at).getTime();
      const ageDays = ageMs / (1000 * 60 * 60 * 24);
      const hasEssence = note.essence !== null;
      const inActiveThread = note.thread_status === 'active';
      const inArchivedThread = note.thread_status === 'archived' || note.thread_status === 'merged';

      let newTier: string;

      if (ageDays < FULL_MAX_AGE_DAYS) {
        newTier = 'full';
      } else if (ageDays < HIGH_MAX_AGE_DAYS || inActiveThread) {
        newTier = 'high';
      } else if (inArchivedThread && ageDays >= SKELETON_INACTIVE_DAYS && hasEssence) {
        newTier = 'skeleton';
      } else if (hasEssence) {
        newTier = 'summary';
      } else {
        // Guard: don't demote below full without an essence
        newTier = 'full';
      }

      const currentTier = note.fidelity_tier || 'full';
      if (newTier !== currentTier) {
        updateStmt.run(newTier, nowIso, note.raw_note_id);
        log.debug({ noteId: note.raw_note_id, from: currentTier, to: newTier, ageDays: Math.round(ageDays) }, 'Tier transition');
        result.processed++;

        if (newTier === 'full') transitions.toFull++;
        else if (newTier === 'high') transitions.toHigh++;
        else if (newTier === 'summary') transitions.toSummary++;
        else if (newTier === 'skeleton') transitions.toSkeleton++;
      } else {
        transitions.unchanged++;
      }

      result.details.push({ id: note.raw_note_id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.raw_note_id, err: error }, 'Error evaluating note fidelity');
      result.errors++;
      result.details.push({ id: note.raw_note_id, success: false, error: error.message });
    }
  }

  log.info({ transitions, total: notes.length, changed: result.processed, errors: result.errors }, 'Fidelity evaluation complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  evaluateFidelity()
    .then((result) => {
      console.log('Evaluate-fidelity complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Evaluate-fidelity failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Create launchd plist**

Create `launchd/com.selene.evaluate-fidelity.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.evaluate-fidelity</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>--transpile-only</string>
        <string>src/workflows/evaluate-fidelity.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_ENV</key>
        <string>production</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
    </dict>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/evaluate-fidelity.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/evaluate-fidelity.error.log</string>
</dict>
</plist>
```

**Step 3: Verify it compiles and runs**

Run: `npx tsc --noEmit src/workflows/evaluate-fidelity.ts`
Expected: No errors.

Run: `npx ts-node src/workflows/evaluate-fidelity.ts`
Expected: Evaluates all notes, logs tier transitions.

**Step 4: Commit**

```bash
git add src/workflows/evaluate-fidelity.ts launchd/com.selene.evaluate-fidelity.plist
git commit -m "feat: add evaluate-fidelity workflow for daily tier assessment"
```

---

### Task 6: New Workflow — compile-thread-digests.ts

**Files:**
- Create: `src/workflows/compile-thread-digests.ts`
- Create: `launchd/com.selene.compile-thread-digests.plist`

**Step 1: Create the workflow**

Create `src/workflows/compile-thread-digests.ts`:

```typescript
import { createWorkflowLogger, db, generate, isAvailable, saveThreadDigest } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compile-thread-digests');

const MIN_NOTES_FOR_DIGEST = 10;

const DIGEST_PROMPT = `You are summarizing a thread of thinking for someone with ADHD. This thread represents a recurring pattern in their notes.

Thread name: {name}
Thread summary: {summary}
Why this thread exists: {why}

Member note essences (newest first):
{essences}

Write a single paragraph (3-5 sentences) that captures:
1. The arc of this thread — how it started and where it's going
2. The current state — what's active or unresolved
3. The emotional texture — what this thread feels like

Paragraph:`;

interface ThreadForDigest {
  id: number;
  name: string;
  summary: string | null;
  why: string | null;
  note_count: number;
  updated_at: string;
  thread_digest: string | null;
}

export async function compileThreadDigests(): Promise<WorkflowResult> {
  log.info('Starting thread digest compilation');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  // Find active threads with enough notes whose digest is stale (older than last update)
  const threads = db.prepare(`
    SELECT t.id, t.name, t.summary, t.why, t.note_count, t.updated_at, t.thread_digest
    FROM threads t
    WHERE t.status = 'active'
      AND t.note_count >= ?
  `).all(MIN_NOTES_FOR_DIGEST) as ThreadForDigest[];

  // Filter to threads needing digest update
  const needsUpdate = threads.filter(t => {
    if (!t.thread_digest) return true; // No digest yet
    // Check if thread was updated after digest was last set
    // (We use updated_at as proxy since we update it on reconsolidation)
    return true; // Recompute each run — hourly is fine
  });

  log.info({ total: threads.length, needingUpdate: needsUpdate.length }, 'Threads eligible for digest');

  for (const thread of needsUpdate) {
    try {
      // Get member note essences
      const memberEssences = db.prepare(`
        SELECT r.title, p.essence, r.created_at
        FROM thread_notes tn
        JOIN raw_notes r ON tn.raw_note_id = r.id
        LEFT JOIN processed_notes p ON r.id = p.raw_note_id
        WHERE tn.thread_id = ?
        ORDER BY r.created_at DESC
        LIMIT 30
      `).all(thread.id) as Array<{ title: string; essence: string | null; created_at: string }>;

      const essencesText = memberEssences
        .map(n => {
          const date = n.created_at.split('T')[0];
          return n.essence
            ? `- ${n.title} (${date}): ${n.essence}`
            : `- ${n.title} (${date})`;
        })
        .join('\n');

      const prompt = DIGEST_PROMPT
        .replace('{name}', thread.name)
        .replace('{summary}', thread.summary || '(none)')
        .replace('{why}', thread.why || '(none)')
        .replace('{essences}', essencesText);

      const response = await generate(prompt, { timeoutMs: 60000 });
      const digest = response.trim();

      if (digest.length > 0 && digest.length < 2000) {
        saveThreadDigest(thread.id, digest);
        log.info({ threadId: thread.id, name: thread.name, digestLength: digest.length }, 'Thread digest compiled');
        result.processed++;
        result.details.push({ id: thread.id, success: true });
      } else {
        throw new Error(`Invalid digest length: ${digest.length}`);
      }
    } catch (err) {
      const error = err as Error;
      log.error({ threadId: thread.id, err: error }, 'Failed to compile thread digest');
      result.errors++;
      result.details.push({ id: thread.id, success: false, error: error.message });
    }
  }

  log.info({ processed: result.processed, errors: result.errors }, 'Thread digest compilation complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  compileThreadDigests()
    .then((result) => {
      console.log('Compile-thread-digests complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compile-thread-digests failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Create launchd plist**

Create `launchd/com.selene.compile-thread-digests.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.compile-thread-digests</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>--transpile-only</string>
        <string>src/workflows/compile-thread-digests.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_ENV</key>
        <string>production</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
    </dict>

    <!-- Run every hour (3600 seconds) -->
    <key>StartInterval</key>
    <integer>3600</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/compile-thread-digests.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/compile-thread-digests.error.log</string>
</dict>
</plist>
```

**Step 3: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/compile-thread-digests.ts`
Expected: No errors.

**Step 4: Commit**

```bash
git add src/workflows/compile-thread-digests.ts launchd/com.selene.compile-thread-digests.plist
git commit -m "feat: add compile-thread-digests workflow for thread narratives"
```

---

### Task 7: Integrate ContextBuilder into detect-threads.ts

**Files:**
- Modify: `src/workflows/detect-threads.ts`

**Step 1: Replace `buildSynthesisPrompt` to use ContextBuilder**

Import ContextBuilder at the top (line 1):

```typescript
import { createWorkflowLogger, db, generate, embed, searchSimilarNotes, getIndexedNoteIds, ContextBuilder } from '../lib';
```

Replace the `buildSynthesisPrompt` function (lines 310-334) with a version that uses ContextBuilder:

```typescript
/**
 * Build LLM prompt for thread synthesis using ContextBuilder
 */
function buildSynthesisPrompt(notes: NoteRecord[]): string {
  const noteIds = notes.map(n => n.id);
  const ctx = new ContextBuilder(3000)
    .addNotes(noteIds)
    .build();

  return `These notes were written over time by the same person. They cluster together based on semantic similarity.

${ctx}

Questions:
1. What thread of thinking connects these notes?
2. What is the underlying want, need, or motivation?
3. Is there a clear direction or is this still exploring?
4. Suggest a short name for this thread (2-5 words)

Respond ONLY with valid JSON (no explanation):
{
  "name": "Short Thread Name",
  "why": "The underlying motivation or goal",
  "summary": "What connects these notes together",
  "direction": "exploring|emerging|clear",
  "emotional_tone": "neutral|positive|negative|mixed"
}`;
}
```

Also remove the `MAX_NOTES_PER_SYNTHESIS` constant (line 12) since the ContextBuilder handles budget-based truncation now. Remove the `.slice(0, MAX_NOTES_PER_SYNTHESIS)` from the old function since it no longer exists.

**Step 2: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/detect-threads.ts`
Expected: No errors.

**Step 3: Commit**

```bash
git add src/workflows/detect-threads.ts
git commit -m "refactor: use ContextBuilder in detect-threads for tiered context"
```

---

### Task 8: Integrate ContextBuilder into reconsolidate-threads.ts

**Files:**
- Modify: `src/workflows/reconsolidate-threads.ts`

**Step 1: Import ContextBuilder**

Update the import line (line 1):

```typescript
import { createWorkflowLogger, db, generate, ContextBuilder } from '../lib';
```

**Step 2: Replace `buildResynthesisPrompt` to use ContextBuilder**

Replace the function (lines 101-126):

```typescript
/**
 * Build LLM prompt for thread resynthesis using ContextBuilder.
 * Uses thread digest + recent notes for incremental reconsolidation.
 */
function buildResynthesisPrompt(thread: ThreadRecord, recentNoteIds: number[]): string {
  const ctx = new ContextBuilder(2500)
    .addThread(thread.id)
    .addNotes(recentNoteIds)
    .build();

  return `Thread: ${thread.name}
Previous summary: ${thread.summary || '(none)'}
Previous "why": ${thread.why || '(none)'}

Current thread context:
${ctx}

Questions:
1. Has the direction of this thread shifted?
2. What is the updated summary?
3. Has the underlying motivation become clearer or changed?

Respond ONLY with valid JSON:
{
  "name": "${thread.name}",
  "summary": "...",
  "why": "...",
  "direction": "exploring|emerging|clear",
  "shifted": true or false
}`;
}
```

**Step 3: Update the call site in `reconsolidateThreads`**

In the main loop (around line 490), change:

```typescript
      const prompt = buildResynthesisPrompt(thread, notes);
```

To pass note IDs instead of full note objects:

```typescript
      const noteIds = notes.map(n => n.id);
      const prompt = buildResynthesisPrompt(thread, noteIds);
```

The `getThreadNotes` function (line 482) still fetches notes — we just pass the IDs to the new function instead of the full content.

**Step 4: Remove `MAX_NOTES_PER_SYNTHESIS` constant (line 10)** since ContextBuilder manages the budget.

Update the `getThreadNotes` call to fetch more notes (the builder will handle truncation):

```typescript
      const notes = getThreadNotes(thread.id, 30); // Builder handles budget
```

**Step 5: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/reconsolidate-threads.ts`
Expected: No errors.

**Step 6: Commit**

```bash
git add src/workflows/reconsolidate-threads.ts
git commit -m "refactor: use ContextBuilder in reconsolidate-threads for incremental updates"
```

---

### Task 9: Integrate ContextBuilder into daily-summary.ts

**Files:**
- Modify: `src/workflows/daily-summary.ts`

**Step 1: Import ContextBuilder**

Update the import line (line 3):

```typescript
import { createWorkflowLogger, db, generate, isAvailable, config, ContextBuilder } from '../lib';
```

**Step 2: Replace the note formatting section**

Replace the note formatting block (lines 66-82) — the section that builds `notesText` with 100-char truncations:

```typescript
  // Format notes using ContextBuilder for better essences
  const noteIds = notes.map(n => {
    // We need the raw_note IDs — query them
    const row = db.prepare('SELECT id FROM raw_notes WHERE title = ? AND created_at >= ? ORDER BY created_at ASC LIMIT 1')
      .get(n.title, startOfWeek.toISOString()) as { id: number } | undefined;
    return row?.id;
  }).filter((id): id is number => id !== undefined);

  let notesText: string;
  if (noteIds.length > 0) {
    notesText = new ContextBuilder(4000)
      .addNotes(noteIds)
      .build();
  } else {
    notesText = notes.map(n => `- ${n.title}: ${n.content.slice(0, 100)}...`).join('\n');
  }
```

**Step 3: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/daily-summary.ts`
Expected: No errors.

**Step 4: Commit**

```bash
git add src/workflows/daily-summary.ts
git commit -m "refactor: use ContextBuilder in daily-summary for essence-based previews"
```

---

### Task 10: Health Endpoint — Add Tier Distribution

**Files:**
- Modify: `src/server.ts`

**Step 1: Import `getFidelityStats` in server.ts**

Add to the import from `./lib` (line 2):

```typescript
import { config, logger } from './lib';
```

Change to:

```typescript
import { config, logger, getFidelityStats } from './lib';
```

(Note: `getFidelityStats` needs to be exported from `src/lib/index.ts` — this was done in Task 1.)

**Step 2: Add fidelity stats to health endpoint**

Modify the health endpoint (lines 24-31):

```typescript
server.get('/health', async () => {
  let fidelity = null;
  try {
    fidelity = getFidelityStats();
  } catch {
    // Table may not have columns yet during migration
  }

  return {
    status: 'ok',
    env: config.env,
    port: config.port,
    timestamp: new Date().toISOString(),
    fidelity,
  };
});
```

**Step 3: Verify it compiles**

Run: `npx tsc --noEmit src/server.ts`
Expected: No errors.

**Step 4: Test the endpoint**

Run: `curl http://localhost:5678/health | python3 -m json.tool`
Expected: Response includes `fidelity` object with `pending_essences`, `tier_full`, etc.

**Step 5: Commit**

```bash
git add src/server.ts
git commit -m "feat: add fidelity tier distribution to health endpoint"
```

---

### Task 11: Install New Launchd Agents

**Step 1: Run the install script**

Run: `./scripts/install-launchd.sh`
Expected: Installs all launchd agents including the three new ones.

If the script doesn't pick up new plists automatically, install manually:

```bash
launchctl load ~/Library/LaunchAgents/com.selene.distill-essences.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.selene.evaluate-fidelity.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.selene.compile-thread-digests.plist 2>/dev/null
```

**Step 2: Verify agents are running**

Run: `launchctl list | grep selene`
Expected: All three new agents appear in the list.

---

### Task 12: Manual Integration Test

**Step 1: Verify existing workflows still work**

Run: `npx ts-node src/workflows/process-llm.ts`
Expected: Processes pending notes AND computes essences inline. Check logs for "Essence computed inline" messages.

**Step 2: Verify distill-essences backfill**

Run: `npx ts-node src/workflows/distill-essences.ts`
Expected: Picks up any notes with `essence IS NULL` and distills them.

**Step 3: Verify evaluate-fidelity**

Run: `npx ts-node src/workflows/evaluate-fidelity.ts`
Expected: Evaluates all notes, assigns tiers based on age. Logs tier transitions.

**Step 4: Verify compile-thread-digests**

Run: `npx ts-node src/workflows/compile-thread-digests.ts`
Expected: Compiles digests for threads with 10+ notes.

**Step 5: Check health endpoint**

Run: `curl -s http://localhost:5678/health | python3 -m json.tool`
Expected: Shows `fidelity` object with accurate tier counts.

**Step 6: Verify detect-threads still synthesizes correctly**

Run: `npx ts-node src/workflows/detect-threads.ts`
Expected: Runs without errors, uses ContextBuilder internally.

**Step 7: Verify reconsolidate-threads**

Run: `npx ts-node src/workflows/reconsolidate-threads.ts`
Expected: Uses incremental digest-based approach, runs without errors.

**Step 8: Verify daily-summary**

Run: `npx ts-node src/workflows/daily-summary.ts`
Expected: Uses essences instead of 100-char truncations.
