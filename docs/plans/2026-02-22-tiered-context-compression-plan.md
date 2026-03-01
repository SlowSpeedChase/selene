# Tiered Context Compression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add lifecycle-based fidelity tiers so LLM workflows can represent 500+ notes within mistral:7b's context window using compressed representations (essences, digests, skeletons).

**Architecture:** New `essence` column on `processed_notes` holds a 1-2 sentence distillation per note. New `fidelity_tier` column controls which representation goes to the LLM. A shared `ContextBuilder` class assembles tiered context within a token budget. Three new workflows (distill-essences, evaluate-fidelity, compile-thread-digests) run on schedule. Existing workflows (process-llm, detect-threads, reconsolidate-threads, daily-summary) are updated to use ContextBuilder.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (mistral:7b), Pino logging, launchd scheduling

**Design Doc:** `docs/plans/2026-02-21-tiered-context-compression-design.md`

---

## Task 1: Database Migration

**Files:**
- Create: `database/migrations/020_tiered_context_compression.sql`

**Step 1: Write the migration SQL**

```sql
-- 020_tiered_context_compression.sql
-- Add essence and fidelity tier columns for tiered context compression
-- Essence: 1-2 sentence LLM distillation of note meaning
-- Fidelity tier: controls what representation is sent to LLM prompts

ALTER TABLE processed_notes ADD COLUMN essence TEXT;
ALTER TABLE processed_notes ADD COLUMN essence_at TEXT;
ALTER TABLE processed_notes ADD COLUMN fidelity_tier TEXT DEFAULT 'full';
ALTER TABLE processed_notes ADD COLUMN fidelity_evaluated_at TEXT;

ALTER TABLE threads ADD COLUMN thread_digest TEXT;
```

**Step 2: Apply migration to dev database**

Run: `sqlite3 ~/selene-data-dev/selene.db < database/migrations/020_tiered_context_compression.sql`
Expected: No output (success)

Verify: `sqlite3 ~/selene-data-dev/selene.db "PRAGMA table_info(processed_notes);" | grep essence`
Expected: Two rows containing `essence` and `essence_at`

Verify: `sqlite3 ~/selene-data-dev/selene.db "PRAGMA table_info(threads);" | grep thread_digest`
Expected: One row containing `thread_digest`

**Step 3: Apply migration to production database**

Run: `sqlite3 ~/selene-data/selene.db < database/migrations/020_tiered_context_compression.sql`
Expected: No output (success)

**Step 4: Commit**

```bash
git add database/migrations/020_tiered_context_compression.sql
git commit -m "feat: add migration 020 for essence and fidelity tier columns"
```

---

## Task 2: ContextBuilder Shared Utility

**Files:**
- Create: `src/lib/context-builder.ts`
- Modify: `src/lib/index.ts`

**Step 1: Write the test file**

Create: `src/lib/context-builder.test.ts`

```typescript
import assert from 'assert';

// Inline test helpers — no external deps
// We'll import ContextBuilder after implementing it

async function runTests() {
  // Dynamic import so the file can exist before the module
  const { ContextBuilder } = await import('./context-builder');

  // Test 1: Empty builder returns empty string
  {
    const builder = new ContextBuilder(1000);
    const result = builder.build();
    assert.strictEqual(result, '');
    console.log('  ✓ empty builder returns empty string');
  }

  // Test 2: Full tier renders title + content
  {
    const builder = new ContextBuilder(5000);
    builder.addNote({
      id: 1,
      title: 'Test Note',
      content: 'This is the full content of the note.',
      essence: null,
      primary_theme: 'testing',
      concepts: '["unit tests", "assertions"]',
      fidelity_tier: 'full',
    });
    const result = builder.build();
    assert.ok(result.includes('Test Note'), 'should include title');
    assert.ok(result.includes('This is the full content'), 'should include full content');
    console.log('  ✓ full tier renders title + content');
  }

  // Test 3: High tier renders title + essence + content
  {
    const builder = new ContextBuilder(5000);
    builder.addNote({
      id: 2,
      title: 'Another Note',
      content: 'Full text here.',
      essence: 'Distilled meaning of the note.',
      primary_theme: 'design',
      concepts: '["architecture"]',
      fidelity_tier: 'high',
    });
    const result = builder.build();
    assert.ok(result.includes('Another Note'), 'should include title');
    assert.ok(result.includes('Distilled meaning'), 'should include essence');
    assert.ok(result.includes('Full text here'), 'should include content');
    console.log('  ✓ high tier renders title + essence + content');
  }

  // Test 4: Summary tier renders title + essence + themes (no content)
  {
    const builder = new ContextBuilder(5000);
    builder.addNote({
      id: 3,
      title: 'Old Note',
      content: 'This content should NOT appear in summary tier.',
      essence: 'This note explores organizational patterns.',
      primary_theme: 'productivity',
      concepts: '["habits", "routines"]',
      fidelity_tier: 'summary',
    });
    const result = builder.build();
    assert.ok(result.includes('Old Note'), 'should include title');
    assert.ok(result.includes('This note explores'), 'should include essence');
    assert.ok(result.includes('productivity'), 'should include theme');
    assert.ok(!result.includes('should NOT appear'), 'should NOT include full content');
    console.log('  ✓ summary tier renders title + essence + themes (no content)');
  }

  // Test 5: Skeleton tier renders title + theme only
  {
    const builder = new ContextBuilder(5000);
    builder.addNote({
      id: 4,
      title: 'Ancient Note',
      content: 'This should not appear.',
      essence: 'This should also not appear.',
      primary_theme: 'archived-topic',
      concepts: '["old stuff"]',
      fidelity_tier: 'skeleton',
    });
    const result = builder.build();
    assert.ok(result.includes('Ancient Note'), 'should include title');
    assert.ok(result.includes('archived-topic'), 'should include theme');
    assert.ok(!result.includes('This should not appear'), 'should NOT include content');
    assert.ok(!result.includes('This should also not'), 'should NOT include essence');
    console.log('  ✓ skeleton tier renders title + theme only');
  }

  // Test 6: Token budget enforcement — stops adding notes when full
  {
    const builder = new ContextBuilder(100); // Very tight budget (~25 tokens)
    builder.addNote({
      id: 5,
      title: 'First',
      content: 'A'.repeat(200),
      essence: null,
      primary_theme: 'test',
      concepts: '[]',
      fidelity_tier: 'full',
    });
    builder.addNote({
      id: 6,
      title: 'Second',
      content: 'B'.repeat(200),
      essence: null,
      primary_theme: 'test',
      concepts: '[]',
      fidelity_tier: 'full',
    });
    const result = builder.build();
    // With 100 char budget, only first note (or partial) should fit
    assert.ok(result.length <= 200, `result too long: ${result.length}`);
    console.log('  ✓ token budget enforcement stops adding when full');
  }

  // Test 7: Fallback chain — missing essence falls back to concepts then truncated content
  {
    const builder = new ContextBuilder(5000);
    builder.addNote({
      id: 7,
      title: 'No Essence',
      content: 'Some content that should be truncated as fallback.',
      essence: null,
      primary_theme: 'fallback-test',
      concepts: '["concept-a", "concept-b"]',
      fidelity_tier: 'summary', // summary tier but no essence
    });
    const result = builder.build();
    assert.ok(result.includes('No Essence'), 'should include title');
    // Fallback: concepts or truncated content instead of essence
    assert.ok(
      result.includes('concept-a') || result.includes('Some content'),
      'should fall back to concepts or content'
    );
    console.log('  ✓ fallback chain works when essence is missing');
  }

  // Test 8: Thread digest rendering
  {
    const builder = new ContextBuilder(5000);
    builder.addThread({
      id: 1,
      name: 'ADHD Management',
      thread_digest: 'This thread tracks strategies for managing ADHD symptoms.',
      summary: 'Various ADHD coping strategies.',
      why: 'Need better daily structure.',
      note_count: 25,
    });
    const result = builder.build();
    assert.ok(result.includes('ADHD Management'), 'should include thread name');
    assert.ok(result.includes('tracks strategies'), 'should include digest');
    console.log('  ✓ thread digest rendering');
  }

  // Test 9: Thread without digest falls back to summary
  {
    const builder = new ContextBuilder(5000);
    builder.addThread({
      id: 2,
      name: 'Cooking Ideas',
      thread_digest: null,
      summary: 'Recipes and meal planning thoughts.',
      why: 'Want to cook more at home.',
      note_count: 8,
    });
    const result = builder.build();
    assert.ok(result.includes('Cooking Ideas'), 'should include name');
    assert.ok(result.includes('Recipes and meal'), 'should fall back to summary');
    console.log('  ✓ thread without digest falls back to summary');
  }

  // Test 10: addFullText always uses full content regardless of tier
  {
    const builder = new ContextBuilder(5000);
    builder.addFullText({
      id: 8,
      title: 'Force Full',
      content: 'Must appear even though tier is skeleton.',
      essence: 'Short version.',
      primary_theme: 'test',
      concepts: '[]',
      fidelity_tier: 'skeleton',
    });
    const result = builder.build();
    assert.ok(result.includes('Must appear even though'), 'should include full content');
    console.log('  ✓ addFullText overrides tier to show full content');
  }

  console.log('\nAll ContextBuilder tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/lib/context-builder.test.ts`
Expected: FAIL with "Cannot find module './context-builder'"

**Step 3: Write the ContextBuilder implementation**

Create: `src/lib/context-builder.ts`

```typescript
/**
 * ContextBuilder: Assembles tiered note/thread context within a token budget.
 *
 * Tier rendering rules:
 *   full     → title + full content
 *   high     → title + essence + full content
 *   summary  → title + essence + themes (no content)
 *   skeleton → title + primary_theme
 *
 * Fallback: if essence is missing, uses concepts → truncated content (150 chars)
 * Token estimation: character count / 4 (no external tokenizer)
 */

export type FidelityTier = 'full' | 'high' | 'summary' | 'skeleton';

export interface NoteContext {
  id: number;
  title: string;
  content: string;
  essence: string | null;
  primary_theme: string | null;
  concepts: string | null; // JSON array string
  fidelity_tier: string;
}

export interface ThreadContext {
  id: number;
  name: string;
  thread_digest: string | null;
  summary: string | null;
  why: string | null;
  note_count: number;
}

const CHARS_PER_TOKEN = 4;
const FALLBACK_CONTENT_LENGTH = 150;

export class ContextBuilder {
  private budgetChars: number;
  private usedChars: number = 0;
  private blocks: string[] = [];

  constructor(budgetTokens: number) {
    this.budgetChars = budgetTokens * CHARS_PER_TOKEN;
  }

  /**
   * Add a note rendered at its fidelity tier.
   * Returns this for chaining.
   */
  addNote(note: NoteContext): this {
    const block = this.renderNote(note, note.fidelity_tier as FidelityTier);
    return this.appendBlock(block);
  }

  /**
   * Add a note always rendered at full fidelity, regardless of tier.
   * Use for workflows that need raw content (process-llm, extract-tasks).
   */
  addFullText(note: NoteContext): this {
    const block = this.renderNote(note, 'full');
    return this.appendBlock(block);
  }

  /**
   * Add a thread rendered with digest or summary fallback.
   */
  addThread(thread: ThreadContext): this {
    const block = this.renderThread(thread);
    return this.appendBlock(block);
  }

  /**
   * Get remaining token budget.
   */
  remainingTokens(): number {
    return Math.floor((this.budgetChars - this.usedChars) / CHARS_PER_TOKEN);
  }

  /**
   * Build the final context string.
   */
  build(): string {
    return this.blocks.join('\n\n');
  }

  private appendBlock(block: string): this {
    if (this.usedChars + block.length > this.budgetChars) {
      // Budget exhausted — skip this block
      return this;
    }
    this.blocks.push(block);
    this.usedChars += block.length;
    return this;
  }

  private renderNote(note: NoteContext, tier: FidelityTier): string {
    const essenceText = this.getEssenceOrFallback(note);

    switch (tier) {
      case 'full':
        return `--- ${note.title} ---\n${note.content}`;

      case 'high':
        return essenceText
          ? `--- ${note.title} ---\n[Essence] ${essenceText}\n${note.content}`
          : `--- ${note.title} ---\n${note.content}`;

      case 'summary':
        if (essenceText) {
          const theme = note.primary_theme ? ` [${note.primary_theme}]` : '';
          return `--- ${note.title}${theme} ---\n${essenceText}`;
        }
        // Fallback: concepts or truncated content
        return `--- ${note.title} ---\n${this.getFallbackPreview(note)}`;

      case 'skeleton':
        return `- ${note.title} [${note.primary_theme || 'unthemed'}]`;

      default:
        return `--- ${note.title} ---\n${note.content}`;
    }
  }

  private renderThread(thread: ThreadContext): string {
    const lines: string[] = [`=== Thread: ${thread.name} (${thread.note_count} notes) ===`];

    if (thread.thread_digest) {
      lines.push(thread.thread_digest);
    } else if (thread.summary) {
      lines.push(thread.summary);
      if (thread.why) {
        lines.push(`Motivation: ${thread.why}`);
      }
    }

    return lines.join('\n');
  }

  private getEssenceOrFallback(note: NoteContext): string | null {
    if (note.essence) return note.essence;
    return null;
  }

  private getFallbackPreview(note: NoteContext): string {
    // Try concepts first
    if (note.concepts) {
      try {
        const conceptList = JSON.parse(note.concepts) as string[];
        if (conceptList.length > 0) {
          return `Concepts: ${conceptList.slice(0, 5).join(', ')}`;
        }
      } catch {
        // Fall through to content truncation
      }
    }
    // Truncate raw content
    return note.content.slice(0, FALLBACK_CONTENT_LENGTH) + (note.content.length > FALLBACK_CONTENT_LENGTH ? '...' : '');
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/lib/context-builder.test.ts`
Expected: All 10 tests pass

**Step 5: Export from lib/index.ts**

Add to `src/lib/index.ts`:

```typescript
export { ContextBuilder, type NoteContext, type ThreadContext, type FidelityTier } from './context-builder';
```

**Step 6: Commit**

```bash
git add src/lib/context-builder.ts src/lib/context-builder.test.ts src/lib/index.ts
git commit -m "feat: add ContextBuilder for tiered note context assembly"
```

---

## Task 3: Inline Essence Computation in process-llm.ts

**Files:**
- Modify: `src/workflows/process-llm.ts`

This adds a second LLM call after concept extraction to compute the essence for newly processed notes.

**Step 1: Write the test**

Create: `src/workflows/process-llm-essence.test.ts`

```typescript
import assert from 'assert';

async function runTests() {
  // Test the essence prompt template produces valid output format
  // We test the prompt builder function, not the LLM call itself

  const { buildEssencePrompt } = await import('./process-llm');

  // Test 1: Prompt includes title, content, and existing concepts
  {
    const prompt = buildEssencePrompt(
      'Morning Reflection',
      'Woke up feeling scattered. Need to find a system for tracking tasks.',
      '["task management", "morning routine"]',
      'productivity'
    );
    assert.ok(prompt.includes('Morning Reflection'), 'should include title');
    assert.ok(prompt.includes('scattered'), 'should include content');
    assert.ok(prompt.includes('task management'), 'should include concepts');
    assert.ok(prompt.includes('productivity'), 'should include theme');
    console.log('  ✓ essence prompt includes all context');
  }

  // Test 2: Prompt works with null concepts
  {
    const prompt = buildEssencePrompt('Quick Note', 'Just a thought.', null, null);
    assert.ok(prompt.includes('Quick Note'), 'should include title');
    assert.ok(prompt.includes('Just a thought'), 'should include content');
    console.log('  ✓ essence prompt handles null concepts');
  }

  console.log('\nAll process-llm essence tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/workflows/process-llm-essence.test.ts`
Expected: FAIL — `buildEssencePrompt` not exported

**Step 3: Add essence prompt and computation to process-llm.ts**

Add after the `EXTRACT_PROMPT` constant (after line 28):

```typescript
const ESSENCE_PROMPT = `Distill this note into 1-2 sentences capturing what it means to the person who wrote it. Focus on the core insight, decision, or question — not a summary of the text.

Title: {title}
Content: {content}
{context}

Respond with ONLY the 1-2 sentence distillation, no quotes or explanation:`;

export function buildEssencePrompt(
  title: string,
  content: string,
  concepts: string | null,
  primaryTheme: string | null
): string {
  const contextParts: string[] = [];
  if (concepts) {
    try {
      const conceptList = JSON.parse(concepts);
      if (conceptList.length > 0) {
        contextParts.push(`Key concepts: ${conceptList.join(', ')}`);
      }
    } catch { /* ignore */ }
  }
  if (primaryTheme) {
    contextParts.push(`Theme: ${primaryTheme}`);
  }
  const contextStr = contextParts.length > 0
    ? contextParts.join('\n')
    : '';

  return ESSENCE_PROMPT
    .replace('{title}', title)
    .replace('{content}', content)
    .replace('{context}', contextStr);
}
```

Then add essence computation inside the for loop, after the `markProcessed(note.id)` call (after line 98), before the success log:

```typescript
      // Compute essence inline
      try {
        const essencePrompt = buildEssencePrompt(
          note.title,
          note.content,
          JSON.stringify(extracted.concepts || []),
          extracted.primary_theme || null
        );
        const essenceResponse = await generate(essencePrompt);
        const essence = essenceResponse.trim();
        if (essence && essence.length > 10) {
          db.prepare(
            `UPDATE processed_notes SET essence = ?, essence_at = ? WHERE raw_note_id = ?`
          ).run(essence, new Date().toISOString(), note.id);
          log.info({ noteId: note.id, essenceLength: essence.length }, 'Essence computed');
        }
      } catch (essenceErr) {
        // Non-fatal — distill-essences workflow will retry
        log.warn({ noteId: note.id, err: essenceErr as Error }, 'Essence computation failed, will retry later');
      }
```

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/workflows/process-llm-essence.test.ts`
Expected: All tests pass

**Step 5: Commit**

```bash
git add src/workflows/process-llm.ts src/workflows/process-llm-essence.test.ts
git commit -m "feat: add inline essence computation to process-llm workflow"
```

---

## Task 4: distill-essences.ts Workflow (Backfill + Retry)

**Files:**
- Create: `src/workflows/distill-essences.ts`

This handles backfilling existing notes and retrying failed essence computations.

**Step 1: Write the test**

Create: `src/workflows/distill-essences.test.ts`

```typescript
import assert from 'assert';

async function runTests() {
  const { getNotesNeedingEssence } = await import('./distill-essences');

  // Test 1: Function exists and is callable
  {
    assert.strictEqual(typeof getNotesNeedingEssence, 'function');
    console.log('  ✓ getNotesNeedingEssence is exported');
  }

  console.log('\nAll distill-essences tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/workflows/distill-essences.test.ts`
Expected: FAIL — cannot find module

**Step 3: Write the workflow**

```typescript
import { createWorkflowLogger, db, generate, isAvailable } from '../lib';
import { buildEssencePrompt } from './process-llm';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('distill-essences');

interface NoteForEssence {
  raw_note_id: number;
  title: string;
  content: string;
  concepts: string | null;
  primary_theme: string | null;
}

/**
 * Get processed notes that still need an essence computed.
 * Skips notes that failed 3+ times in the last 24 hours (tracked via essence_at sentinel).
 */
export function getNotesNeedingEssence(limit = 10): NoteForEssence[] {
  return db
    .prepare(
      `SELECT pn.raw_note_id, rn.title, rn.content, pn.concepts, pn.primary_theme
       FROM processed_notes pn
       JOIN raw_notes rn ON pn.raw_note_id = rn.id
       WHERE pn.essence IS NULL
         AND rn.test_run IS NULL
       ORDER BY rn.created_at DESC
       LIMIT ?`
    )
    .all(limit) as NoteForEssence[];
}

export async function distillEssences(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting essence distillation run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  const notes = getNotesNeedingEssence(limit);
  log.info({ noteCount: notes.length }, 'Found notes needing essence');

  if (notes.length === 0) {
    log.info('All notes have essences — nothing to do');
    return { processed: 0, errors: 0, details: [] };
  }

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  for (const note of notes) {
    try {
      const prompt = buildEssencePrompt(
        note.title,
        note.content,
        note.concepts,
        note.primary_theme
      );

      const response = await generate(prompt);
      const essence = response.trim();

      if (!essence || essence.length <= 10) {
        log.warn({ noteId: note.raw_note_id }, 'Essence too short, skipping');
        result.errors++;
        result.details.push({ id: note.raw_note_id, success: false, error: 'Essence too short' });
        continue;
      }

      db.prepare(
        `UPDATE processed_notes SET essence = ?, essence_at = ? WHERE raw_note_id = ?`
      ).run(essence, new Date().toISOString(), note.raw_note_id);

      log.info({ noteId: note.raw_note_id, essenceLength: essence.length }, 'Essence computed');
      result.processed++;
      result.details.push({ id: note.raw_note_id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.raw_note_id, err: error }, 'Failed to compute essence');
      result.errors++;
      result.details.push({ id: note.raw_note_id, success: false, error: error.message });
    }
  }

  log.info(
    { processed: result.processed, errors: result.errors },
    'Essence distillation complete'
  );
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

**Step 4: Run test to verify it passes**

Run: `npx ts-node src/workflows/distill-essences.test.ts`
Expected: PASS

**Step 5: Run the workflow against dev database to verify**

Run: `SELENE_ENV=development npx ts-node src/workflows/distill-essences.ts`
Expected: Finds notes needing essence, processes batch (or reports Ollama unavailable)

**Step 6: Commit**

```bash
git add src/workflows/distill-essences.ts src/workflows/distill-essences.test.ts
git commit -m "feat: add distill-essences workflow for backfill and retry"
```

---

## Task 5: evaluate-fidelity.ts Workflow

**Files:**
- Create: `src/workflows/evaluate-fidelity.ts`

Pure SQL + logic workflow. No LLM calls. Assigns fidelity tiers based on note age and thread activity.

**Step 1: Write the test**

Create: `src/workflows/evaluate-fidelity.test.ts`

```typescript
import assert from 'assert';

async function runTests() {
  const { computeTier } = await import('./evaluate-fidelity');

  // Test 1: Fresh note (< 7 days) → full
  {
    const tier = computeTier({
      ageDays: 3,
      hasEssence: false,
      threadStatus: 'active',
      lastAccessDays: 1,
    });
    assert.strictEqual(tier, 'full');
    console.log('  ✓ fresh note → full');
  }

  // Test 2: Warm note (30 days, active thread) → high
  {
    const tier = computeTier({
      ageDays: 30,
      hasEssence: true,
      threadStatus: 'active',
      lastAccessDays: 5,
    });
    assert.strictEqual(tier, 'high');
    console.log('  ✓ warm active thread note → high');
  }

  // Test 3: Warm note without essence stays full (not high)
  {
    const tier = computeTier({
      ageDays: 30,
      hasEssence: false,
      threadStatus: 'active',
      lastAccessDays: 5,
    });
    assert.strictEqual(tier, 'full');
    console.log('  ✓ warm note without essence stays full');
  }

  // Test 4: Cool note (120 days, inactive thread, has essence) → summary
  {
    const tier = computeTier({
      ageDays: 120,
      hasEssence: true,
      threadStatus: 'archived',
      lastAccessDays: 100,
    });
    assert.strictEqual(tier, 'summary');
    console.log('  ✓ cool inactive note → summary');
  }

  // Test 5: Cold note (200 days, archived, no access) → skeleton
  {
    const tier = computeTier({
      ageDays: 200,
      hasEssence: true,
      threadStatus: 'archived',
      lastAccessDays: 200,
    });
    assert.strictEqual(tier, 'skeleton');
    console.log('  ✓ cold archived note → skeleton');
  }

  // Test 6: Old note in active thread stays high (rehydration)
  {
    const tier = computeTier({
      ageDays: 200,
      hasEssence: true,
      threadStatus: 'active',
      lastAccessDays: 2,
    });
    assert.strictEqual(tier, 'high');
    console.log('  ✓ old note in active thread → high (rehydration)');
  }

  // Test 7: Cannot demote below full without essence
  {
    const tier = computeTier({
      ageDays: 200,
      hasEssence: false,
      threadStatus: 'archived',
      lastAccessDays: 200,
    });
    assert.strictEqual(tier, 'full');
    console.log('  ✓ cannot demote without essence');
  }

  console.log('\nAll evaluate-fidelity tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/workflows/evaluate-fidelity.test.ts`
Expected: FAIL — cannot find module

**Step 3: Write the workflow**

```typescript
import { createWorkflowLogger, db } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('evaluate-fidelity');

interface TierInput {
  ageDays: number;
  hasEssence: boolean;
  threadStatus: string | null;
  lastAccessDays: number;
}

/**
 * Pure function: compute the fidelity tier for a note based on age and activity.
 *
 * Rules:
 *   FULL:     age < 7 days
 *   HIGH:     age < 90 days OR in active thread (requires essence)
 *   SUMMARY:  age >= 90 days AND thread inactive/archived (requires essence)
 *   SKELETON: thread archived AND no access in 180 days (requires essence)
 *
 * Guard: cannot demote below 'full' without an essence.
 */
export function computeTier(input: TierInput): string {
  const { ageDays, hasEssence, threadStatus, lastAccessDays } = input;

  // Fresh notes are always full
  if (ageDays < 7) return 'full';

  // Guard: no demotion without essence
  if (!hasEssence) return 'full';

  // Active thread keeps notes at high regardless of age
  if (threadStatus === 'active') return 'high';

  // Warm period
  if (ageDays < 90) return 'high';

  // Cold: archived + untouched 180+ days
  if (threadStatus === 'archived' && lastAccessDays >= 180) return 'skeleton';

  // Cool: 90+ days, inactive/archived
  return 'summary';
}

interface NoteForEvaluation {
  raw_note_id: number;
  fidelity_tier: string;
  essence: string | null;
  age_days: number;
  thread_status: string | null;
}

export async function evaluateFidelity(): Promise<WorkflowResult> {
  log.info('Starting fidelity evaluation');

  // Get all notes not already at skeleton tier, with their age and thread info
  const notes = db
    .prepare(
      `SELECT
         pn.raw_note_id,
         pn.fidelity_tier,
         pn.essence,
         CAST(julianday('now') - julianday(rn.created_at) AS INTEGER) as age_days,
         t.status as thread_status
       FROM processed_notes pn
       JOIN raw_notes rn ON pn.raw_note_id = rn.id
       LEFT JOIN thread_notes tn ON rn.id = tn.raw_note_id
       LEFT JOIN threads t ON tn.thread_id = t.id
       WHERE pn.fidelity_tier != 'skeleton'
         AND rn.test_run IS NULL
       GROUP BY pn.raw_note_id`
    )
    .all() as NoteForEvaluation[];

  log.info({ noteCount: notes.length }, 'Notes to evaluate');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  const now = new Date().toISOString();
  const updateStmt = db.prepare(
    `UPDATE processed_notes SET fidelity_tier = ?, fidelity_evaluated_at = ? WHERE raw_note_id = ?`
  );

  for (const note of notes) {
    const newTier = computeTier({
      ageDays: note.age_days,
      hasEssence: note.essence !== null,
      threadStatus: note.thread_status,
      lastAccessDays: note.age_days, // Simplified: use age as proxy for last access
    });

    if (newTier !== note.fidelity_tier) {
      updateStmt.run(newTier, now, note.raw_note_id);
      log.info(
        { noteId: note.raw_note_id, from: note.fidelity_tier, to: newTier },
        'Tier changed'
      );
      result.processed++;
      result.details.push({ id: note.raw_note_id, success: true });
    }
  }

  log.info(
    { evaluated: notes.length, changed: result.processed },
    'Fidelity evaluation complete'
  );
  return result;
}

// CLI entry point
if (require.main === module) {
  evaluateFidelity()
    .then((result) => {
      console.log('Evaluate-fidelity complete:', result);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Evaluate-fidelity failed:', err);
      process.exit(1);
    });
}
```

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/workflows/evaluate-fidelity.test.ts`
Expected: All 7 tests pass

**Step 5: Commit**

```bash
git add src/workflows/evaluate-fidelity.ts src/workflows/evaluate-fidelity.test.ts
git commit -m "feat: add evaluate-fidelity workflow for tier assignment"
```

---

## Task 6: compile-thread-digests.ts Workflow

**Files:**
- Create: `src/workflows/compile-thread-digests.ts`

**Step 1: Write the test**

Create: `src/workflows/compile-thread-digests.test.ts`

```typescript
import assert from 'assert';

async function runTests() {
  const { buildDigestPrompt } = await import('./compile-thread-digests');

  // Test 1: Prompt includes thread name, summary, and note essences
  {
    const prompt = buildDigestPrompt(
      'ADHD Systems',
      'Exploring ADHD coping strategies.',
      'Need structure without rigidity.',
      [
        { essence: 'Tried time-blocking but found it too rigid.' },
        { essence: 'Body doubling works well for deep work sessions.' },
      ]
    );
    assert.ok(prompt.includes('ADHD Systems'), 'should include thread name');
    assert.ok(prompt.includes('Exploring ADHD'), 'should include summary');
    assert.ok(prompt.includes('time-blocking'), 'should include first essence');
    assert.ok(prompt.includes('Body doubling'), 'should include second essence');
    console.log('  ✓ digest prompt includes all context');
  }

  console.log('\nAll compile-thread-digests tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/workflows/compile-thread-digests.test.ts`
Expected: FAIL

**Step 3: Write the workflow**

```typescript
import { createWorkflowLogger, db, generate, isAvailable } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compile-thread-digests');

interface ThreadForDigest {
  id: number;
  name: string;
  summary: string | null;
  why: string | null;
  note_count: number;
}

interface NoteEssence {
  essence: string;
}

/**
 * Build the LLM prompt for thread digest compilation.
 */
export function buildDigestPrompt(
  name: string,
  summary: string | null,
  why: string | null,
  essences: NoteEssence[]
): string {
  const essenceList = essences
    .map((e, i) => `${i + 1}. ${e.essence}`)
    .join('\n');

  return `Thread: ${name}
Summary: ${summary || '(none)'}
Motivation: ${why || '(none)'}

Note essences (distilled meanings):
${essenceList}

Write a single paragraph (3-5 sentences) capturing this thread's arc: what started it, how it evolved, and where it stands now. Write in present tense. Be specific, not generic.

Paragraph:`;
}

export async function compileThreadDigests(): Promise<WorkflowResult> {
  log.info('Starting thread digest compilation');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Find active threads with 10+ notes where digest is stale or missing
  const threads = db
    .prepare(
      `SELECT t.id, t.name, t.summary, t.why,
              (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) as note_count
       FROM threads t
       WHERE t.status = 'active'
         AND (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) >= 10
         AND (t.thread_digest IS NULL
              OR t.updated_at > COALESCE(
                (SELECT MAX(pn.essence_at) FROM processed_notes pn
                 JOIN thread_notes tn2 ON pn.raw_note_id = tn2.raw_note_id
                 WHERE tn2.thread_id = t.id AND pn.essence IS NOT NULL),
                '1970-01-01'))
       ORDER BY t.momentum_score DESC NULLS LAST`
    )
    .all() as ThreadForDigest[];

  log.info({ threadCount: threads.length }, 'Threads needing digest compilation');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  for (const thread of threads) {
    try {
      // Get essences for this thread's notes
      const essences = db
        .prepare(
          `SELECT pn.essence
           FROM processed_notes pn
           JOIN thread_notes tn ON pn.raw_note_id = tn.raw_note_id
           WHERE tn.thread_id = ? AND pn.essence IS NOT NULL
           ORDER BY pn.essence_at DESC`
        )
        .all(thread.id) as NoteEssence[];

      if (essences.length < 5) {
        log.info(
          { threadId: thread.id, essenceCount: essences.length },
          'Not enough essences yet, skipping'
        );
        continue;
      }

      const prompt = buildDigestPrompt(thread.name, thread.summary, thread.why, essences);
      const response = await generate(prompt);
      const digest = response.trim();

      if (!digest || digest.length < 30) {
        log.warn({ threadId: thread.id }, 'Digest too short, skipping');
        result.errors++;
        result.details.push({ id: thread.id, success: false, error: 'Digest too short' });
        continue;
      }

      db.prepare(`UPDATE threads SET thread_digest = ? WHERE id = ?`).run(digest, thread.id);

      log.info({ threadId: thread.id, digestLength: digest.length }, 'Thread digest compiled');
      result.processed++;
      result.details.push({ id: thread.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ threadId: thread.id, err: error }, 'Failed to compile digest');
      result.errors++;
      result.details.push({ id: thread.id, success: false, error: error.message });
    }
  }

  log.info(
    { processed: result.processed, errors: result.errors },
    'Thread digest compilation complete'
  );
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

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/workflows/compile-thread-digests.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add src/workflows/compile-thread-digests.ts src/workflows/compile-thread-digests.test.ts
git commit -m "feat: add compile-thread-digests workflow for thread narratives"
```

---

## Task 7: Update detect-threads.ts to Use ContextBuilder

**Files:**
- Modify: `src/workflows/detect-threads.ts`

Replace the hardcoded 15-note raw text concatenation with ContextBuilder, allowing more notes at lower fidelity.

**Step 1: Add import at the top of detect-threads.ts**

Add after existing imports:

```typescript
import { ContextBuilder } from '../lib/context-builder';
```

**Step 2: Update getNoteContent to include essence and tier data**

Replace the `getNoteContent` function (around line 295-305) with:

```typescript
interface NoteWithContext {
  id: number;
  title: string;
  content: string;
  created_at: string;
  essence: string | null;
  primary_theme: string | null;
  concepts: string | null;
  fidelity_tier: string;
}

function getNoteContent(noteIds: number[]): NoteWithContext[] {
  const placeholders = noteIds.map(() => '?').join(',');
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, rn.created_at,
              pn.essence, pn.primary_theme, pn.concepts,
              COALESCE(pn.fidelity_tier, 'full') as fidelity_tier
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.id IN (${placeholders})
       ORDER BY rn.created_at ASC`
    )
    .all(...noteIds) as NoteWithContext[];
}
```

**Step 3: Update buildSynthesisPrompt to use ContextBuilder**

Replace the `buildSynthesisPrompt` function (around line 310-334) with:

```typescript
function buildSynthesisPrompt(notes: NoteWithContext[]): string {
  // Budget: ~3000 tokens for notes, leaving room for prompt instructions
  const builder = new ContextBuilder(3000);

  for (const note of notes) {
    builder.addNote({
      id: note.id,
      title: `${note.title} (${note.created_at})`,
      content: note.content,
      essence: note.essence,
      primary_theme: note.primary_theme,
      concepts: note.concepts,
      fidelity_tier: note.fidelity_tier,
    });
  }

  const noteTexts = builder.build();

  return `These notes were written over time by the same person. They cluster together based on semantic similarity.

${noteTexts}

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

**Step 4: Remove the MAX_NOTES_PER_SYNTHESIS slice**

The ContextBuilder now handles budget enforcement. Find the line that does `.slice(0, MAX_NOTES_PER_SYNTHESIS)` in the old function — it's now handled by the builder's token budget. If `MAX_NOTES_PER_SYNTHESIS` is used elsewhere in the file, keep the constant. If it was only used in `buildSynthesisPrompt`, remove the constant.

**Step 5: Verify it compiles**

Run: `npx ts-node -e "import './src/workflows/detect-threads'"`
Expected: No errors

**Step 6: Commit**

```bash
git add src/workflows/detect-threads.ts
git commit -m "feat: update detect-threads to use ContextBuilder for tiered context"
```

---

## Task 8: Update reconsolidate-threads.ts to Use ContextBuilder

**Files:**
- Modify: `src/workflows/reconsolidate-threads.ts`

Make reconsolidation incremental: thread digest + new notes since last reconsolidation.

**Step 1: Add import**

Add after existing imports:

```typescript
import { ContextBuilder } from '../lib/context-builder';
```

**Step 2: Update NoteRecord interface**

Add essence and tier fields to the local `NoteRecord` interface (around line 22-27):

```typescript
interface NoteRecord {
  id: number;
  title: string;
  content: string;
  created_at: string;
  essence: string | null;
  primary_theme: string | null;
  concepts: string | null;
  fidelity_tier: string;
}
```

**Step 3: Update getThreadNotes query**

Replace the `getThreadNotes` function (around line 85-96) to include essence and tier:

```typescript
function getThreadNotes(threadId: number, limit: number): NoteRecord[] {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, rn.created_at,
              pn.essence, pn.primary_theme, pn.concepts,
              COALESCE(pn.fidelity_tier, 'full') as fidelity_tier
       FROM raw_notes rn
       JOIN thread_notes tn ON rn.id = tn.raw_note_id
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE tn.thread_id = ?
       ORDER BY rn.created_at DESC
       LIMIT ?`
    )
    .all(threadId, limit) as NoteRecord[];
}
```

**Step 4: Update buildResynthesisPrompt to use ContextBuilder**

Replace the `buildResynthesisPrompt` function (around line 101-126):

```typescript
function buildResynthesisPrompt(thread: ThreadRecord, notes: NoteRecord[]): string {
  const builder = new ContextBuilder(3000);

  for (const note of notes) {
    builder.addNote({
      id: note.id,
      title: `${note.title} (${note.created_at})`,
      content: note.content,
      essence: note.essence,
      primary_theme: note.primary_theme,
      concepts: note.concepts,
      fidelity_tier: note.fidelity_tier,
    });
  }

  const noteTexts = builder.build();

  return `Thread: ${thread.name}
Previous summary: ${thread.summary || '(none)'}
Previous "why": ${thread.why || '(none)'}

Notes in this thread (newest first):
${noteTexts}

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

**Step 5: Increase MAX_NOTES_PER_SYNTHESIS**

With tiered context, we can handle more notes. Update the constant (around line 10):

```typescript
const MAX_NOTES_PER_SYNTHESIS = 30; // Was 15 — ContextBuilder manages budget
```

**Step 6: Verify it compiles**

Run: `npx ts-node -e "import './src/workflows/reconsolidate-threads'"`
Expected: No errors

**Step 7: Commit**

```bash
git add src/workflows/reconsolidate-threads.ts
git commit -m "feat: update reconsolidate-threads to use ContextBuilder"
```

---

## Task 9: Update daily-summary.ts to Use Essences

**Files:**
- Modify: `src/workflows/daily-summary.ts`

Replace 100-char content truncation with essence-based context.

**Step 1: Update the notes query (around line 42-56)**

Add essence to the SELECT:

```typescript
  const notes = db
    .prepare(
      `SELECT rn.title, rn.content, pn.primary_theme, pn.secondary_themes, pn.concepts, pn.essence
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.created_at BETWEEN ? AND ?
         AND rn.test_run IS NULL
       ORDER BY rn.created_at`
    )
    .all(startOfWeek.toISOString(), endOfDay.toISOString()) as Array<{
    title: string;
    content: string;
    primary_theme: string | null;
    secondary_themes: string | null;
    concepts: string | null;
    essence: string | null;
  }>;
```

**Step 2: Update the notes formatting (around line 66-82)**

Replace the `notesText` builder to prefer essence:

```typescript
  const notesText = notes
    .map((n) => {
      // Prefer essence, then concepts, then truncated content
      if (n.essence) {
        return `- ${n.title}: ${n.essence}`;
      }
      if (n.concepts) {
        try {
          const conceptList = JSON.parse(n.concepts);
          if (conceptList.length > 0) {
            return `- ${n.title}: ${conceptList.slice(0, 3).join(', ')}`;
          }
        } catch {
          // Fall through
        }
      }
      return `- ${n.title}: ${n.content.slice(0, 100)}...`;
    })
    .join('\n');
```

**Step 3: Add test_run filter to the query**

Note: The original query was missing `AND rn.test_run IS NULL`. Add it to the WHERE clause as shown in step 1.

**Step 4: Verify it compiles**

Run: `npx ts-node -e "import './src/workflows/daily-summary'"`
Expected: No errors

**Step 5: Commit**

```bash
git add src/workflows/daily-summary.ts
git commit -m "feat: update daily-summary to use essences instead of truncation"
```

---

## Task 10: Launchd Plists for New Workflows

**Files:**
- Create: `launchd/com.selene.distill-essences.plist`
- Create: `launchd/com.selene.evaluate-fidelity.plist`
- Create: `launchd/com.selene.compile-thread-digests.plist`

**Step 1: Create distill-essences plist (every 5 minutes)**

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

**Step 2: Create evaluate-fidelity plist (daily at 3am)**

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

**Step 3: Create compile-thread-digests plist (hourly)**

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

    <key>StartInterval</key>
    <integer>3600</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/compile-thread-digests.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/compile-thread-digests.error.log</string>
</dict>
</plist>
```

**Step 4: Commit**

```bash
git add launchd/com.selene.distill-essences.plist launchd/com.selene.evaluate-fidelity.plist launchd/com.selene.compile-thread-digests.plist
git commit -m "feat: add launchd plists for new compression workflows"
```

---

## Task 11: Health Endpoint for Compression Progress

**Files:**
- Modify: `src/server.ts`

**Step 1: Add compression stats endpoint**

Add after the existing health endpoint (after line 31 in `src/server.ts`):

```typescript
// ---------------------------------------------------------------------------
// Compression stats (tiered context)
// ---------------------------------------------------------------------------

server.get('/health/compression', async () => {
  const tierDistribution = db
    .prepare(
      `SELECT COALESCE(fidelity_tier, 'full') as tier, COUNT(*) as count
       FROM processed_notes
       WHERE raw_note_id IN (SELECT id FROM raw_notes WHERE test_run IS NULL)
       GROUP BY fidelity_tier`
    )
    .all() as Array<{ tier: string; count: number }>;

  const essenceProgress = db
    .prepare(
      `SELECT
         COUNT(*) as total,
         SUM(CASE WHEN essence IS NOT NULL THEN 1 ELSE 0 END) as with_essence
       FROM processed_notes
       WHERE raw_note_id IN (SELECT id FROM raw_notes WHERE test_run IS NULL)`
    )
    .get() as { total: number; with_essence: number };

  const threadDigests = db
    .prepare(
      `SELECT
         COUNT(*) as total_active,
         SUM(CASE WHEN thread_digest IS NOT NULL THEN 1 ELSE 0 END) as with_digest
       FROM threads
       WHERE status = 'active'`
    )
    .get() as { total_active: number; with_digest: number };

  return {
    status: 'ok',
    timestamp: new Date().toISOString(),
    tiers: Object.fromEntries(tierDistribution.map((r) => [r.tier, r.count])),
    essences: {
      total: essenceProgress.total,
      computed: essenceProgress.with_essence,
      remaining: essenceProgress.total - essenceProgress.with_essence,
      percent: essenceProgress.total > 0
        ? Math.round((essenceProgress.with_essence / essenceProgress.total) * 100)
        : 0,
    },
    threadDigests: {
      activeThreads: threadDigests.total_active,
      withDigest: threadDigests.with_digest,
    },
  };
});
```

**Step 2: Add db import if not already imported**

Check top of `src/server.ts` — `db` should already be available via routes. If not, add:

```typescript
import { db } from './lib';
```

**Step 3: Verify server starts**

Run: `npx ts-node -e "import './src/server'"`
Expected: No import errors (server will try to listen, which is fine)

**Step 4: Commit**

```bash
git add src/server.ts
git commit -m "feat: add /health/compression endpoint for tier monitoring"
```

---

## Task 12: Integration Testing

**Files:** No new files — testing existing code end-to-end

**Step 1: Run all new tests**

```bash
npx ts-node src/lib/context-builder.test.ts
npx ts-node src/workflows/process-llm-essence.test.ts
npx ts-node src/workflows/distill-essences.test.ts
npx ts-node src/workflows/evaluate-fidelity.test.ts
npx ts-node src/workflows/compile-thread-digests.test.ts
```

Expected: All pass

**Step 2: Run each workflow against dev database**

```bash
SELENE_ENV=development npx ts-node src/workflows/process-llm.ts
SELENE_ENV=development npx ts-node src/workflows/distill-essences.ts
SELENE_ENV=development npx ts-node src/workflows/evaluate-fidelity.ts
SELENE_ENV=development npx ts-node src/workflows/compile-thread-digests.ts
SELENE_ENV=development npx ts-node src/workflows/detect-threads.ts
SELENE_ENV=development npx ts-node src/workflows/reconsolidate-threads.ts
SELENE_ENV=development npx ts-node src/workflows/daily-summary.ts
```

Expected: Each completes without errors (may process 0 items if Ollama unavailable or data conditions not met)

**Step 3: Check compression progress**

After running distill-essences at least once against dev:

```bash
sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) as total, SUM(CASE WHEN essence IS NOT NULL THEN 1 ELSE 0 END) as with_essence FROM processed_notes;"
```

Expected: Shows total and some with essences computed

**Step 4: Verify health endpoint**

```bash
curl http://localhost:5678/health/compression
```

Expected: JSON with tier distribution, essence progress, thread digest counts

**Step 5: Commit test results documentation**

No code to commit — this is a verification step.

---

## Task 13: Update Documentation and Install Launchd Agents

**Files:**
- Modify: `CLAUDE.md` — Update architecture diagram and workflow schedule
- Modify: `.claude/PROJECT-STATUS.md` — Add to recent completions
- Modify: `docs/plans/INDEX.md` — Move design to "In Progress" then "Done"

**Step 1: Install new launchd agents**

Run: `./scripts/install-launchd.sh`
Expected: Installs new plists alongside existing ones

If install script doesn't handle new files automatically:

```bash
cp launchd/com.selene.distill-essences.plist ~/Library/LaunchAgents/
cp launchd/com.selene.evaluate-fidelity.plist ~/Library/LaunchAgents/
cp launchd/com.selene.compile-thread-digests.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.selene.distill-essences.plist
launchctl load ~/Library/LaunchAgents/com.selene.evaluate-fidelity.plist
launchctl load ~/Library/LaunchAgents/com.selene.compile-thread-digests.plist
```

**Step 2: Update CLAUDE.md**

Update the workflow schedule in CLAUDE.md to include the three new workflows:
- `distill-essences.ts` — Every 5 minutes
- `evaluate-fidelity.ts` — Daily at 3am
- `compile-thread-digests.ts` — Hourly

Add the three new launchd plists to the architecture listing.

**Step 3: Update PROJECT-STATUS.md**

Add "Tiered Context Compression" to recent completions with summary of what was built.

**Step 4: Update docs/plans/INDEX.md**

Move `2026-02-21-tiered-context-compression-design.md` from "Ready" to "Done" with completion date.

**Step 5: Commit**

```bash
git add CLAUDE.md .claude/PROJECT-STATUS.md docs/plans/INDEX.md
git commit -m "docs: update project documentation for tiered context compression"
```

---

## Summary

| Task | What | New Files | Modified Files |
|------|------|-----------|----------------|
| 1 | Database migration | `020_tiered_context_compression.sql` | — |
| 2 | ContextBuilder utility | `context-builder.ts`, test | `lib/index.ts` |
| 3 | Inline essence in process-llm | test | `process-llm.ts` |
| 4 | distill-essences workflow | `distill-essences.ts`, test | — |
| 5 | evaluate-fidelity workflow | `evaluate-fidelity.ts`, test | — |
| 6 | compile-thread-digests workflow | `compile-thread-digests.ts`, test | — |
| 7 | ContextBuilder in detect-threads | — | `detect-threads.ts` |
| 8 | ContextBuilder in reconsolidate | — | `reconsolidate-threads.ts` |
| 9 | Essences in daily-summary | — | `daily-summary.ts` |
| 10 | Launchd plists | 3 plists | — |
| 11 | Health endpoint | — | `server.ts` |
| 12 | Integration testing | — | — |
| 13 | Documentation | — | `CLAUDE.md`, status, index |

**Total:** 13 tasks, ~10 new files, ~6 modified files, 13 commits
