# Thread Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatic thread lifecycle management — archive stale threads, split divergent threads, merge converging threads.

**Architecture:** Single workflow script (`thread-lifecycle.ts`) runs daily via launchd. Reuses existing BFS clustering from `detect-threads.ts` and LLM synthesis from `reconsolidate-threads.ts`. Requires one DB migration to expand CHECK constraints.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (mistral:7b), LanceDB (vector retrieval), launchd, Pino logging

**Design Doc:** `docs/plans/2026-02-13-thread-lifecycle-design.md`

---

### Task 1: Database Migration — Expand CHECK Constraints

**Files:**
- Create: `database/migrations/017_thread_lifecycle.sql`

**Step 1: Write migration SQL**

```sql
-- Migration: 017_thread_lifecycle.sql
-- Purpose: Expand thread status and history change_type for lifecycle operations
-- Date: 2026-02-13

-- SQLite does not support ALTER CHECK constraints directly.
-- We must recreate the tables with updated constraints.

-- Step 1: Recreate threads table with expanded status
CREATE TABLE threads_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    why TEXT,
    summary TEXT,
    status TEXT DEFAULT 'active',
    note_count INTEGER DEFAULT 0,
    last_activity_at TEXT,
    emotional_charge REAL,
    momentum_score REAL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'paused', 'completed', 'abandoned', 'archived', 'merged'))
);

INSERT INTO threads_new SELECT * FROM threads;
DROP TABLE threads;
ALTER TABLE threads_new RENAME TO threads;

-- Recreate indexes on threads
CREATE INDEX IF NOT EXISTS idx_threads_status ON threads(status);
CREATE INDEX IF NOT EXISTS idx_threads_activity ON threads(last_activity_at DESC);
CREATE INDEX IF NOT EXISTS idx_threads_momentum ON threads(momentum_score DESC);

-- Step 2: Recreate thread_history with expanded change_type
CREATE TABLE thread_history_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,
    change_type TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (trigger_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL,
    CHECK(change_type IN ('note_added', 'merged', 'split', 'renamed', 'summarized', 'created', 'archived', 'reactivated'))
);

INSERT INTO thread_history_new SELECT * FROM thread_history;
DROP TABLE thread_history;
ALTER TABLE thread_history_new RENAME TO thread_history;

-- Recreate indexes on thread_history
CREATE INDEX IF NOT EXISTS idx_thread_history_thread ON thread_history(thread_id);
```

**Step 2: Apply migration**

Run: `sqlite3 data/selene.db < database/migrations/017_thread_lifecycle.sql`

**Step 3: Verify migration**

Run: `sqlite3 data/selene.db "INSERT INTO threads (name, status) VALUES ('test-lifecycle', 'archived'); DELETE FROM threads WHERE name = 'test-lifecycle'; SELECT 'CHECK constraint updated';"`
Expected: `CHECK constraint updated` (no error)

Run: `sqlite3 data/selene.db "INSERT INTO thread_history (thread_id, change_type) VALUES (1, 'archived'); DELETE FROM thread_history WHERE change_type = 'archived' AND thread_id = 1; SELECT 'history CHECK updated';"`
Expected: `history CHECK updated` (no error)

**Step 4: Commit**

```bash
git add database/migrations/017_thread_lifecycle.sql
git commit -m "feat: add migration 017 for thread lifecycle status values"
```

---

### Task 2: Scaffold `thread-lifecycle.ts` with Archive Phase

**Files:**
- Create: `src/workflows/thread-lifecycle.ts`

**Step 1: Write the archive implementation**

```typescript
import { createWorkflowLogger, db, generate } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('thread-lifecycle');

// Configuration
const STALE_THRESHOLD_DAYS = 60;

// Types
interface ThreadRecord {
  id: number;
  name: string;
  why: string | null;
  summary: string | null;
  status: string;
  note_count: number;
  last_activity_at: string | null;
}

/**
 * Phase 1: Archive threads inactive for STALE_THRESHOLD_DAYS
 */
function archiveStaleThreads(): number {
  const cutoff = new Date(
    Date.now() - STALE_THRESHOLD_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();

  const stale = db
    .prepare(
      `SELECT id, name, summary FROM threads
       WHERE status = 'active' AND last_activity_at < ?`
    )
    .all(cutoff) as Pick<ThreadRecord, 'id' | 'name' | 'summary'>[];

  if (stale.length === 0) {
    log.info('No stale threads to archive');
    return 0;
  }

  const now = new Date().toISOString();

  const updateStmt = db.prepare(
    `UPDATE threads SET status = 'archived', updated_at = ? WHERE id = ?`
  );
  const historyStmt = db.prepare(
    `INSERT INTO thread_history (thread_id, summary_before, change_type, created_at)
     VALUES (?, ?, 'archived', ?)`
  );

  for (const thread of stale) {
    updateStmt.run(now, thread.id);
    historyStmt.run(thread.id, thread.summary, now);
    log.info({ threadId: thread.id, name: thread.name }, 'Archived stale thread');
  }

  log.info({ archived: stale.length }, 'Stale threads archived');
  return stale.length;
}

/**
 * Main workflow: thread lifecycle management
 */
export async function threadLifecycle(): Promise<WorkflowResult> {
  log.info('Starting thread lifecycle');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  // Phase 1: Archive stale threads
  try {
    const archived = archiveStaleThreads();
    result.processed += archived;
    result.details.push({ id: 0, success: true, error: `Archived ${archived} threads` });
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Error archiving stale threads');
    result.errors++;
    result.details.push({ id: 0, success: false, error: error.message });
  }

  // Phase 2: Split (Task 3)
  // Phase 3: Merge (Task 4)

  log.info(
    { processed: result.processed, errors: result.errors },
    'Thread lifecycle complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  threadLifecycle()
    .then((result) => {
      log.info({ result }, 'Thread lifecycle finished');
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      log.error({ err }, 'Thread lifecycle failed');
      process.exit(1);
    });
}
```

**Step 2: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/thread-lifecycle.ts`
Expected: No errors (or use `npx ts-node --transpile-only -e "import('./src/workflows/thread-lifecycle')"`)

**Step 3: Dry-run test**

Run: `npx ts-node --transpile-only src/workflows/thread-lifecycle.ts 2>&1 | npx pino-pretty`
Expected: Log output showing "Starting thread lifecycle", archive count (likely 0 if all threads are recent), "Thread lifecycle complete"

**Step 4: Commit**

```bash
git add src/workflows/thread-lifecycle.ts
git commit -m "feat: add thread-lifecycle workflow with archive phase"
```

---

### Task 3: Add Split Detection Phase

**Files:**
- Modify: `src/workflows/thread-lifecycle.ts`

**Step 1: Add types and constants for split**

Add after existing constants:

```typescript
const MIN_SPLIT_NOTES = 6;
const MIN_COMPONENT_SIZE = 3;
const SPLIT_SIMILARITY_THRESHOLD = 0.65;
const MAX_NOTES_PER_SYNTHESIS = 15;

interface AssociationRecord {
  note_a_id: number;
  note_b_id: number;
  similarity_score: number;
}

interface NoteRecord {
  id: number;
  title: string;
  content: string;
  created_at: string;
}

interface ThreadSynthesis {
  name: string;
  why: string;
  summary: string;
}
```

**Step 2: Add BFS connected-components function**

```typescript
/**
 * Find connected components in an adjacency graph via BFS
 */
function findConnectedComponents(adjacency: Map<number, Set<number>>): number[][] {
  const visited = new Set<number>();
  const components: number[][] = [];

  for (const nodeId of adjacency.keys()) {
    if (visited.has(nodeId)) continue;

    const component: number[] = [];
    const queue: number[] = [nodeId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      if (visited.has(current)) continue;

      visited.add(current);
      component.push(current);

      const neighbors = adjacency.get(current) || new Set();
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor)) {
          queue.push(neighbor);
        }
      }
    }

    components.push(component);
  }

  return components;
}
```

**Step 3: Add split synthesis prompt and parser**

```typescript
/**
 * Build LLM prompt for synthesizing a new thread from a note cluster
 * (Same pattern as detect-threads.ts)
 */
function buildSynthesisPrompt(notes: NoteRecord[]): string {
  const noteTexts = notes
    .slice(0, MAX_NOTES_PER_SYNTHESIS)
    .map((n, i) => `--- Note ${i + 1} (${n.created_at}) ---\nTitle: ${n.title}\n${n.content}`)
    .join('\n\n');

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
  "summary": "What connects these notes together"
}`;
}

/**
 * Parse LLM JSON response into ThreadSynthesis
 */
function parseSynthesis(response: string): ThreadSynthesis | null {
  try {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;

    const parsed = JSON.parse(jsonMatch[0]);
    if (!parsed.name || !parsed.summary) return null;

    return {
      name: parsed.name,
      why: parsed.why || '',
      summary: parsed.summary,
    };
  } catch {
    return null;
  }
}
```

**Step 4: Add the split phase function**

```typescript
/**
 * Phase 2: Split threads where sub-clusters have diverged
 */
async function splitDivergentThreads(): Promise<{ splits: number; errors: number }> {
  // Get active threads with enough notes to potentially split
  const threads = db
    .prepare(
      `SELECT t.id, t.name, t.why, t.summary, t.status, t.note_count
       FROM threads t
       WHERE t.status = 'active' AND t.note_count >= ?`
    )
    .all(MIN_SPLIT_NOTES) as ThreadRecord[];

  if (threads.length === 0) {
    log.info('No threads large enough to split');
    return { splits: 0, errors: 0 };
  }

  let splits = 0;
  let errors = 0;

  for (const thread of threads) {
    try {
      // Get note IDs for this thread
      const noteIds = db
        .prepare('SELECT raw_note_id FROM thread_notes WHERE thread_id = ?')
        .all(thread.id) as { raw_note_id: number }[];

      const noteIdSet = new Set(noteIds.map((n) => n.raw_note_id));

      // Get associations between notes IN this thread only
      const associations = db
        .prepare(
          `SELECT note_a_id, note_b_id, similarity_score
           FROM note_associations
           WHERE note_a_id IN (SELECT raw_note_id FROM thread_notes WHERE thread_id = ?)
             AND note_b_id IN (SELECT raw_note_id FROM thread_notes WHERE thread_id = ?)
             AND similarity_score >= ?`
        )
        .all(thread.id, thread.id, SPLIT_SIMILARITY_THRESHOLD) as AssociationRecord[];

      // Build intra-thread adjacency graph
      const adjacency = new Map<number, Set<number>>();
      for (const noteId of noteIdSet) {
        adjacency.set(noteId, new Set());
      }
      for (const assoc of associations) {
        adjacency.get(assoc.note_a_id)?.add(assoc.note_b_id);
        adjacency.get(assoc.note_b_id)?.add(assoc.note_a_id);
      }

      // Find connected components
      const components = findConnectedComponents(adjacency);
      const viableComponents = components.filter((c) => c.length >= MIN_COMPONENT_SIZE);

      if (viableComponents.length < 2) {
        // Thread is still cohesive (or has isolated notes that are too small to form threads)
        continue;
      }

      log.info(
        { threadId: thread.id, name: thread.name, components: viableComponents.length },
        'Thread has diverged — splitting'
      );

      // Sort by size descending — largest keeps the original thread
      viableComponents.sort((a, b) => b.length - a.length);
      const keepNoteIds = new Set(viableComponents[0]);
      const newClusters = viableComponents.slice(1);

      const now = new Date().toISOString();

      // Create new threads from split-off clusters
      for (const cluster of newClusters) {
        // Get note content for synthesis
        const placeholders = cluster.map(() => '?').join(',');
        const notes = db
          .prepare(
            `SELECT id, title, content, created_at FROM raw_notes WHERE id IN (${placeholders})`
          )
          .all(...cluster) as NoteRecord[];

        // LLM synthesizes identity for the new thread
        const prompt = buildSynthesisPrompt(notes);
        const llmResponse = await generate(prompt);
        const synthesis = parseSynthesis(llmResponse);

        if (!synthesis) {
          log.error({ threadId: thread.id, cluster }, 'Failed to synthesize split thread');
          errors++;
          continue;
        }

        // Create the new thread
        const insertResult = db
          .prepare(
            `INSERT INTO threads (name, why, summary, status, note_count, last_activity_at, created_at, updated_at)
             VALUES (?, ?, ?, 'active', ?, ?, ?, ?)`
          )
          .run(synthesis.name, synthesis.why, synthesis.summary, cluster.length, now, now, now);

        const newThreadId = insertResult.lastInsertRowid as number;

        // Move notes from old thread to new thread
        const moveStmt = db.prepare(
          `UPDATE thread_notes SET thread_id = ? WHERE thread_id = ? AND raw_note_id = ?`
        );
        for (const noteId of cluster) {
          moveStmt.run(newThreadId, thread.id, noteId);
        }

        // Record history on new thread
        db.prepare(
          `INSERT INTO thread_history (thread_id, summary_after, change_type, created_at)
           VALUES (?, ?, 'created', ?)`
        ).run(newThreadId, synthesis.summary, now);

        log.info(
          { newThreadId, name: synthesis.name, noteCount: cluster.length, fromThread: thread.name },
          'Split thread created'
        );
      }

      // Update original thread's note_count
      const remainingCount = db
        .prepare('SELECT COUNT(*) as count FROM thread_notes WHERE thread_id = ?')
        .get(thread.id) as { count: number };

      db.prepare(
        `UPDATE threads SET note_count = ?, updated_at = ? WHERE id = ?`
      ).run(remainingCount.count, now, thread.id);

      // Record split history on original thread
      db.prepare(
        `INSERT INTO thread_history (thread_id, summary_before, change_type, created_at)
         VALUES (?, ?, 'split', ?)`
      ).run(thread.id, thread.summary, now);

      // Resynthesize original thread (now smaller)
      const keepNotePlaceholders = [...keepNoteIds].map(() => '?').join(',');
      const keepNotes = db
        .prepare(
          `SELECT id, title, content, created_at FROM raw_notes WHERE id IN (${keepNotePlaceholders}) ORDER BY created_at DESC`
        )
        .all(...keepNoteIds) as NoteRecord[];

      if (keepNotes.length > 0) {
        const resynthPrompt = buildResynthesisPrompt(thread, keepNotes);
        const resynthResponse = await generate(resynthPrompt);
        const resynthesis = parseSynthesis(resynthResponse);

        if (resynthesis) {
          db.prepare(
            `UPDATE threads SET name = ?, summary = ?, why = ?, updated_at = ? WHERE id = ?`
          ).run(resynthesis.name, resynthesis.summary, resynthesis.why, now, thread.id);
        }
      }

      splits++;
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, threadId: thread.id }, 'Error splitting thread');
      errors++;
    }
  }

  log.info({ splits, errors }, 'Split phase complete');
  return { splits, errors };
}
```

**Step 5: Add resynthesis prompt for existing threads**

```typescript
/**
 * Build resynthesis prompt for a thread that has changed
 * (Same pattern as reconsolidate-threads.ts)
 */
function buildResynthesisPrompt(thread: ThreadRecord, notes: NoteRecord[]): string {
  const noteTexts = notes
    .slice(0, MAX_NOTES_PER_SYNTHESIS)
    .map((n, i) => `--- Note ${i + 1} (${n.created_at}) ---\nTitle: ${n.title}\n${n.content}`)
    .join('\n\n');

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
  "why": "..."
}`;
}
```

**Step 6: Wire split into main workflow**

Replace the `// Phase 2: Split (Task 3)` comment in `threadLifecycle()` with:

```typescript
  // Phase 2: Split divergent threads
  try {
    const splitResult = await splitDivergentThreads();
    result.processed += splitResult.splits;
    result.errors += splitResult.errors;
    result.details.push({ id: 0, success: true, error: `Split ${splitResult.splits} threads` });
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Error in split phase');
    result.errors++;
    result.details.push({ id: 0, success: false, error: error.message });
  }
```

**Step 7: Verify it compiles and runs**

Run: `npx ts-node --transpile-only src/workflows/thread-lifecycle.ts 2>&1 | npx pino-pretty`
Expected: Log output showing archive phase + split phase (likely 0 splits if threads are cohesive)

**Step 8: Commit**

```bash
git add src/workflows/thread-lifecycle.ts
git commit -m "feat: add split detection phase to thread lifecycle"
```

---

### Task 4: Add Merge Detection Phase

**Files:**
- Modify: `src/workflows/thread-lifecycle.ts`

**Step 1: Add merge constants and types**

Add after existing constants:

```typescript
const MERGE_DISTANCE_THRESHOLD = 200; // L2 distance between thread centroids
```

**Step 2: Add centroid computation**

```typescript
/**
 * Compute centroid (average embedding vector) for a thread's notes
 * Reads from note_embeddings table (768-dim vectors stored as JSON BLOB)
 */
function computeThreadCentroid(threadId: number): number[] | null {
  const embeddings = db
    .prepare(
      `SELECT ne.embedding
       FROM note_embeddings ne
       JOIN thread_notes tn ON ne.raw_note_id = tn.raw_note_id
       WHERE tn.thread_id = ?`
    )
    .all(threadId) as { embedding: Buffer }[];

  if (embeddings.length === 0) return null;

  // Parse JSON vectors and average them
  const vectors = embeddings.map((e) => JSON.parse(e.embedding.toString()) as number[]);
  const dims = vectors[0].length;
  const centroid = new Array(dims).fill(0);

  for (const vec of vectors) {
    for (let i = 0; i < dims; i++) {
      centroid[i] += vec[i];
    }
  }

  for (let i = 0; i < dims; i++) {
    centroid[i] /= vectors.length;
  }

  return centroid;
}

/**
 * L2 (Euclidean) distance between two vectors
 */
function l2Distance(a: number[], b: number[]): number {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const diff = a[i] - b[i];
    sum += diff * diff;
  }
  return Math.sqrt(sum);
}
```

**Step 3: Add merge phase function**

```typescript
/**
 * Phase 3: Merge threads with converging centroids
 */
async function mergeConvergingThreads(): Promise<{ merges: number; errors: number }> {
  const threads = db
    .prepare(
      `SELECT id, name, why, summary, status, note_count
       FROM threads WHERE status = 'active'`
    )
    .all() as ThreadRecord[];

  if (threads.length < 2) {
    log.info('Fewer than 2 active threads — nothing to merge');
    return { merges: 0, errors: 0 };
  }

  // Compute centroids for all active threads
  const threadCentroids: { thread: ThreadRecord; centroid: number[] }[] = [];
  for (const thread of threads) {
    const centroid = computeThreadCentroid(thread.id);
    if (centroid) {
      threadCentroids.push({ thread, centroid });
    }
  }

  // Find merge candidates (pairs within distance threshold)
  const candidates: { a: ThreadRecord; b: ThreadRecord; distance: number }[] = [];
  for (let i = 0; i < threadCentroids.length; i++) {
    for (let j = i + 1; j < threadCentroids.length; j++) {
      const distance = l2Distance(threadCentroids[i].centroid, threadCentroids[j].centroid);
      if (distance < MERGE_DISTANCE_THRESHOLD) {
        candidates.push({
          a: threadCentroids[i].thread,
          b: threadCentroids[j].thread,
          distance,
        });
      }
    }
  }

  if (candidates.length === 0) {
    log.info('No merge candidates found');
    return { merges: 0, errors: 0 };
  }

  // Sort by distance (closest first)
  candidates.sort((x, y) => x.distance - y.distance);

  let merges = 0;
  let errors = 0;
  const mergedThisRun = new Set<number>();

  for (const candidate of candidates) {
    // Skip if either thread already merged this cycle
    if (mergedThisRun.has(candidate.a.id) || mergedThisRun.has(candidate.b.id)) continue;

    try {
      // LLM confirmation to avoid false positives
      const confirmPrompt = `Thread A: "${candidate.a.name}" — ${candidate.a.summary || '(no summary)'}
Thread B: "${candidate.b.name}" — ${candidate.b.summary || '(no summary)'}

Are these fundamentally about the same line of thinking? Would combining them make sense, or are they distinct topics that happen to be related?

Respond ONLY with valid JSON:
{
  "should_merge": true or false,
  "reason": "Brief explanation"
}`;

      const llmResponse = await generate(confirmPrompt);
      const jsonMatch = llmResponse.match(/\{[\s\S]*\}/);

      if (!jsonMatch) {
        log.warn({ a: candidate.a.name, b: candidate.b.name }, 'LLM merge response unparseable');
        errors++;
        continue;
      }

      const confirmation = JSON.parse(jsonMatch[0]);
      if (!confirmation.should_merge) {
        log.info(
          { a: candidate.a.name, b: candidate.b.name, reason: confirmation.reason },
          'LLM rejected merge'
        );
        continue;
      }

      // Merge: larger thread (by note_count) is the keeper
      const [keeper, absorbed] =
        candidate.a.note_count >= candidate.b.note_count
          ? [candidate.a, candidate.b]
          : [candidate.b, candidate.a];

      const now = new Date().toISOString();

      // Move all notes from absorbed to keeper
      db.prepare(
        `UPDATE thread_notes SET thread_id = ? WHERE thread_id = ?`
      ).run(keeper.id, absorbed.id);

      // Update keeper's note_count
      const newCount = db
        .prepare('SELECT COUNT(*) as count FROM thread_notes WHERE thread_id = ?')
        .get(keeper.id) as { count: number };

      db.prepare(
        `UPDATE threads SET note_count = ?, updated_at = ? WHERE id = ?`
      ).run(newCount.count, now, keeper.id);

      // Mark absorbed as merged
      db.prepare(
        `UPDATE threads SET status = 'merged', updated_at = ? WHERE id = ?`
      ).run(now, absorbed.id);

      // Record history on both
      db.prepare(
        `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
         VALUES (?, ?, ?, 'merged', ?)`
      ).run(keeper.id, keeper.summary, `Merged with: ${absorbed.name}`, now);

      db.prepare(
        `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
         VALUES (?, ?, ?, 'merged', ?)`
      ).run(absorbed.id, absorbed.summary, `Merged into: ${keeper.name}`, now);

      // Resynthesize keeper with combined notes
      const combinedNotes = db
        .prepare(
          `SELECT r.id, r.title, r.content, r.created_at
           FROM raw_notes r
           JOIN thread_notes tn ON r.id = tn.raw_note_id
           WHERE tn.thread_id = ?
           ORDER BY r.created_at DESC
           LIMIT ?`
        )
        .all(keeper.id, MAX_NOTES_PER_SYNTHESIS) as NoteRecord[];

      if (combinedNotes.length > 0) {
        const resynthPrompt = buildResynthesisPrompt(keeper, combinedNotes);
        const resynthResponse = await generate(resynthPrompt);
        const resynthesis = parseSynthesis(resynthResponse);

        if (resynthesis) {
          db.prepare(
            `UPDATE threads SET name = ?, summary = ?, why = ?, updated_at = ? WHERE id = ?`
          ).run(resynthesis.name, resynthesis.summary, resynthesis.why, now, keeper.id);
        }
      }

      mergedThisRun.add(keeper.id);
      mergedThisRun.add(absorbed.id);
      merges++;

      log.info(
        { keeper: keeper.name, absorbed: absorbed.name, reason: confirmation.reason },
        'Threads merged'
      );
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, a: candidate.a.name, b: candidate.b.name }, 'Error merging threads');
      errors++;
    }
  }

  log.info({ merges, errors, candidatesEvaluated: candidates.length }, 'Merge phase complete');
  return { merges, errors };
}
```

**Step 4: Wire merge into main workflow**

Replace the `// Phase 3: Merge (Task 4)` comment in `threadLifecycle()` with:

```typescript
  // Phase 3: Merge converging threads
  try {
    const mergeResult = await mergeConvergingThreads();
    result.processed += mergeResult.merges;
    result.errors += mergeResult.errors;
    result.details.push({ id: 0, success: true, error: `Merged ${mergeResult.merges} thread pairs` });
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Error in merge phase');
    result.errors++;
    result.details.push({ id: 0, success: false, error: error.message });
  }
```

**Step 5: Verify it compiles and runs**

Run: `npx ts-node --transpile-only src/workflows/thread-lifecycle.ts 2>&1 | npx pino-pretty`
Expected: All three phases log output. Likely 0 merges if threads are distinct.

**Step 6: Commit**

```bash
git add src/workflows/thread-lifecycle.ts
git commit -m "feat: add merge detection phase to thread lifecycle"
```

---

### Task 5: Launchd Plist — Daily at 2am

**Files:**
- Create: `launchd/com.selene.thread-lifecycle.plist`

**Step 1: Write the plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.thread-lifecycle</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>--transpile-only</string>
        <string>src/workflows/thread-lifecycle.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
    </dict>

    <!-- Run daily at 2:00 AM -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/thread-lifecycle.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/thread-lifecycle.error.log</string>
</dict>
</plist>
```

**Step 2: Verify plist syntax**

Run: `plutil -lint launchd/com.selene.thread-lifecycle.plist`
Expected: `launchd/com.selene.thread-lifecycle.plist: OK`

**Step 3: Commit**

```bash
git add launchd/com.selene.thread-lifecycle.plist
git commit -m "feat: add launchd plist for daily thread lifecycle at 2am"
```

---

### Task 6: Modify `detect-threads.ts` — Reactivate Archived Threads

**Files:**
- Modify: `src/workflows/detect-threads.ts`

**Step 1: Find the thread assignment code**

In `detect-threads.ts`, find where notes are assigned to existing threads. After inserting into `thread_notes`, add reactivation logic.

Look for the section in `assignToExistingThreads()` where a note is linked to a thread. After the `INSERT INTO thread_notes` statement, add:

```typescript
      // Reactivate archived threads when new notes are assigned
      const threadStatus = db
        .prepare('SELECT status FROM threads WHERE id = ?')
        .get(match.threadId) as { status: string } | undefined;

      if (threadStatus?.status === 'archived') {
        db.prepare(
          `UPDATE threads SET status = 'active', updated_at = ? WHERE id = ?`
        ).run(now, match.threadId);

        db.prepare(
          `INSERT INTO thread_history (thread_id, trigger_note_id, change_type, created_at)
           VALUES (?, ?, 'reactivated', ?)`
        ).run(match.threadId, noteId, now);

        log.info({ threadId: match.threadId, noteId }, 'Reactivated archived thread');
      }
```

**Step 2: Verify it compiles**

Run: `npx tsc --noEmit src/workflows/detect-threads.ts` or `npx ts-node --transpile-only -e "import('./src/workflows/detect-threads')"`

**Step 3: Commit**

```bash
git add src/workflows/detect-threads.ts
git commit -m "feat: reactivate archived threads when new notes are assigned"
```

---

### Task 7: Modify `reconsolidate-threads.ts` — Archive Obsidian Export

**Files:**
- Modify: `src/workflows/reconsolidate-threads.ts`

**Step 1: Update `exportThreadsToObsidian()` to move archived threads to Archive subfolder**

In `reconsolidate-threads.ts`, modify the `exportThreadsToObsidian()` function. Replace the export loop with logic that routes archived threads to `Threads/Archive/`:

```typescript
function exportThreadsToObsidian(): number {
  const vaultPath = process.env.OBSIDIAN_VAULT_PATH;
  if (!vaultPath) {
    log.warn('OBSIDIAN_VAULT_PATH not set, skipping thread export');
    return 0;
  }

  const threadsDir = join(vaultPath, 'Selene', 'Threads');
  const archiveDir = join(threadsDir, 'Archive');

  // Ensure directories exist
  for (const dir of [threadsDir, archiveDir]) {
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
      log.info({ dir }, 'Created directory');
    }
  }

  const threads = getAllThreadsForExport();
  let exported = 0;

  for (const thread of threads) {
    try {
      const notes = getLinkedNotesForExport(thread.id);
      const markdown = generateThreadMarkdown(thread, notes);
      const slug = createSlug(thread.name);

      // Route archived/merged threads to Archive subfolder
      const targetDir = (thread.status === 'archived' || thread.status === 'merged')
        ? archiveDir
        : threadsDir;
      const filePath = join(targetDir, `${slug}.md`);

      // Clean up: if thread moved to archive, remove from main dir (and vice versa)
      const otherDir = targetDir === archiveDir ? threadsDir : archiveDir;
      const otherPath = join(otherDir, `${slug}.md`);
      if (existsSync(otherPath)) {
        const { unlinkSync } = require('fs');
        unlinkSync(otherPath);
      }

      writeFileSync(filePath, markdown, 'utf-8');
      exported++;

      log.debug({ threadId: thread.id, filePath }, 'Exported thread to Obsidian');
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, threadId: thread.id }, 'Failed to export thread');
    }
  }

  log.info({ exported, total: threads.length }, 'Thread export to Obsidian complete');
  return exported;
}
```

**Step 2: Update `getStatusEmoji()` to include new statuses**

```typescript
function getStatusEmoji(status: string): string {
  const emojis: Record<string, string> = {
    active: '🔥',
    paused: '⏸️',
    completed: '✅',
    abandoned: '💤',
    archived: '📦',
    merged: '🔗',
  };
  return emojis[status] || '📌';
}
```

**Step 3: Verify it compiles**

Run: `npx ts-node --transpile-only -e "import('./src/workflows/reconsolidate-threads')"`

**Step 4: Commit**

```bash
git add src/workflows/reconsolidate-threads.ts
git commit -m "feat: route archived/merged threads to Obsidian Archive subfolder"
```

---

### Task 8: End-to-End Verification

**Step 1: Run thread lifecycle manually**

Run: `npx ts-node --transpile-only src/workflows/thread-lifecycle.ts 2>&1 | npx pino-pretty`
Expected: All three phases run without errors. Archive/split/merge counts logged.

**Step 2: Verify database state**

Run: `sqlite3 data/selene.db "SELECT status, COUNT(*) FROM threads GROUP BY status;"`
Expected: Shows counts per status. Verify no unexpected status changes.

Run: `sqlite3 data/selene.db "SELECT change_type, COUNT(*) FROM thread_history GROUP BY change_type;"`
Expected: Shows history entries. New types (archived, split, merged) appear if any operations ran.

**Step 3: Run reconsolidation to test Obsidian export**

Run: `npx ts-node --transpile-only src/workflows/reconsolidate-threads.ts 2>&1 | npx pino-pretty`
Expected: Export completes. If any archived threads exist, they should be in the Archive subfolder.

**Step 4: Run detect-threads to verify reactivation code doesn't break**

Run: `npx ts-node --transpile-only src/workflows/detect-threads.ts 2>&1 | npx pino-pretty`
Expected: Completes without errors.

**Step 5: Verify launchd plist**

Run: `plutil -lint launchd/com.selene.thread-lifecycle.plist`
Expected: OK

**Step 6: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: address integration issues from end-to-end verification"
```
