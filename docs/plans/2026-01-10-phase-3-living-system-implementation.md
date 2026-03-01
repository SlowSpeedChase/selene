# Phase 3: Living System — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make thread system "living" with hourly reconsolidation that updates summaries and calculates momentum.

**Architecture:** New TypeScript workflow (`reconsolidate-threads.ts`) runs hourly via launchd. Finds threads with new notes, resynthesizes summaries via Ollama, calculates momentum scores. Also update existing launchd intervals for faster processing.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (mistral:7b), launchd

---

## Task 1: Update compute-associations interval

**Files:**
- Modify: `launchd/com.selene.compute-associations.plist`

**Step 1: Read current plist**

Check current interval value.

**Step 2: Update interval from 600 to 300**

Change `StartInterval` from 600 (10 min) to 300 (5 min):

```xml
<key>StartInterval</key>
<integer>300</integer>
```

**Step 3: Commit**

```bash
git add launchd/com.selene.compute-associations.plist
git commit -m "chore: reduce compute-associations interval to 5 min"
```

---

## Task 2: Update detect-threads to run every 30 minutes

**Files:**
- Modify: `launchd/com.selene.detect-threads.plist`

**Step 1: Replace StartCalendarInterval with StartInterval**

Remove the daily schedule:
```xml
<!-- Remove this block -->
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>6</integer>
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

Replace with interval-based:
```xml
<!-- Run every 30 minutes (1800 seconds) -->
<key>StartInterval</key>
<integer>1800</integer>
```

**Step 2: Commit**

```bash
git add launchd/com.selene.detect-threads.plist
git commit -m "chore: run detect-threads every 30 min instead of daily"
```

---

## Task 3: Create reconsolidate-threads workflow

**Files:**
- Create: `src/workflows/reconsolidate-threads.ts`

**Step 1: Create the workflow file**

```typescript
import { createWorkflowLogger, db, generate } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('reconsolidate-threads');

// Momentum weights from design doc
const MOMENTUM_WEIGHTS = {
  notes7Days: 2.0,
  notes30Days: 1.0,
  sentimentIntensity: 0.5,
};

const MAX_NOTES_PER_SYNTHESIS = 15;

// Types
interface ThreadRecord {
  id: number;
  name: string;
  why: string | null;
  summary: string | null;
  updated_at: string;
}

interface NoteRecord {
  id: number;
  title: string;
  content: string;
  created_at: string;
}

interface ThreadSynthesis {
  name: string;
  summary: string;
  why: string;
  direction: 'exploring' | 'emerging' | 'clear';
  shifted: boolean;
}

/**
 * Find threads that have new notes since last update
 */
function findThreadsNeedingUpdate(): ThreadRecord[] {
  return db.prepare(`
    SELECT t.id, t.name, t.why, t.summary, t.updated_at
    FROM threads t
    WHERE t.status = 'active'
      AND t.updated_at < (
        SELECT MAX(tn.added_at)
        FROM thread_notes tn
        WHERE tn.thread_id = t.id
      )
  `).all() as ThreadRecord[];
}

/**
 * Get notes for a thread, prioritizing recent ones
 */
function getThreadNotes(threadId: number): NoteRecord[] {
  return db.prepare(`
    SELECT r.id, r.title, r.content, r.created_at
    FROM raw_notes r
    JOIN thread_notes tn ON tn.raw_note_id = r.id
    WHERE tn.thread_id = ?
    ORDER BY r.created_at DESC
    LIMIT ?
  `).all(threadId, MAX_NOTES_PER_SYNTHESIS) as NoteRecord[];
}

/**
 * Build prompt for resynthesizing thread summary
 */
function buildResynthesisPrompt(thread: ThreadRecord, notes: NoteRecord[]): string {
  const noteTexts = notes
    .map((n, i) => `--- Note ${i + 1} (${n.created_at}) ---\nTitle: ${n.title}\n${n.content}`)
    .join('\n\n');

  return `You analyze threads of thinking from personal notes.

Thread: ${thread.name}
Previous summary: ${thread.summary || '(none)'}
Previous "why": ${thread.why || '(none)'}

Notes in this thread (newest first):
${noteTexts}

Questions:
1. Has the direction of this thread shifted with the new notes?
2. What is the updated summary of this thread?
3. Has the underlying motivation become clearer or changed?

Respond ONLY with valid JSON (no explanation):
{
  "name": "${thread.name}",
  "summary": "Updated summary of the thread",
  "why": "The underlying motivation or goal",
  "direction": "exploring|emerging|clear",
  "shifted": true or false
}`;
}

/**
 * Parse LLM response
 */
function parseSynthesis(response: string): ThreadSynthesis | null {
  try {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      log.warn({ response }, 'No JSON found in LLM response');
      return null;
    }

    const parsed = JSON.parse(jsonMatch[0]);

    if (!parsed.summary || typeof parsed.summary !== 'string') {
      log.warn({ parsed }, 'Missing or invalid summary field');
      return null;
    }

    return {
      name: parsed.name || '',
      summary: parsed.summary,
      why: parsed.why || '',
      direction: ['exploring', 'emerging', 'clear'].includes(parsed.direction)
        ? parsed.direction
        : 'exploring',
      shifted: Boolean(parsed.shifted),
    };
  } catch (err) {
    log.error({ err, response }, 'Failed to parse LLM response');
    return null;
  }
}

/**
 * Update thread with new synthesis
 */
function updateThread(threadId: number, synthesis: ThreadSynthesis, previousSummary: string | null): void {
  const now = new Date().toISOString();

  db.prepare(`
    UPDATE threads
    SET summary = ?, why = ?, updated_at = ?
    WHERE id = ?
  `).run(synthesis.summary, synthesis.why, now, threadId);

  // Record in history
  db.prepare(`
    INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
    VALUES (?, ?, ?, 'summarized', ?)
  `).run(threadId, previousSummary, synthesis.summary, now);

  if (synthesis.shifted) {
    log.info({ threadId, name: synthesis.name }, 'Thread direction shifted');
  }
}

/**
 * Calculate momentum for all active threads
 */
function calculateAllMomentum(): number {
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const threads = db.prepare(`
    SELECT t.id,
      (SELECT COUNT(*) FROM thread_notes tn
       JOIN raw_notes r ON r.id = tn.raw_note_id
       WHERE tn.thread_id = t.id AND r.created_at >= ?) as notes_7_days,
      (SELECT COUNT(*) FROM thread_notes tn
       JOIN raw_notes r ON r.id = tn.raw_note_id
       WHERE tn.thread_id = t.id AND r.created_at >= ?) as notes_30_days,
      COALESCE(t.emotional_charge, 0) as sentiment
    FROM threads t
    WHERE t.status = 'active'
  `).all(sevenDaysAgo, thirtyDaysAgo) as Array<{
    id: number;
    notes_7_days: number;
    notes_30_days: number;
    sentiment: number;
  }>;

  const updateStmt = db.prepare(`
    UPDATE threads SET momentum_score = ? WHERE id = ?
  `);

  for (const thread of threads) {
    const momentum =
      thread.notes_7_days * MOMENTUM_WEIGHTS.notes7Days +
      thread.notes_30_days * MOMENTUM_WEIGHTS.notes30Days +
      Math.abs(thread.sentiment) * MOMENTUM_WEIGHTS.sentimentIntensity;

    updateStmt.run(momentum, thread.id);
  }

  return threads.length;
}

/**
 * Main workflow: reconsolidate threads
 */
export async function reconsolidateThreads(): Promise<WorkflowResult> {
  log.info('Starting thread reconsolidation');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  // Step 1: Find threads needing summary update
  const threadsToUpdate = findThreadsNeedingUpdate();
  log.info({ count: threadsToUpdate.length }, 'Threads needing update');

  // Step 2: Resynthesize each thread
  for (const thread of threadsToUpdate) {
    try {
      const notes = getThreadNotes(thread.id);

      if (notes.length === 0) {
        log.warn({ threadId: thread.id }, 'Thread has no notes');
        continue;
      }

      const prompt = buildResynthesisPrompt(thread, notes);
      log.info({ threadId: thread.id, noteCount: notes.length }, 'Calling LLM for resynthesis');

      const llmResponse = await generate(prompt);
      const synthesis = parseSynthesis(llmResponse);

      if (!synthesis) {
        log.error({ threadId: thread.id }, 'Failed to parse synthesis');
        result.errors++;
        result.details.push({ id: thread.id, success: false, error: 'Parse failed' });
        continue;
      }

      updateThread(thread.id, synthesis, thread.summary);
      result.processed++;
      result.details.push({ id: thread.id, success: true });

      log.info({ threadId: thread.id, name: thread.name }, 'Thread summary updated');
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, threadId: thread.id }, 'Error resynthesizing thread');
      result.errors++;
      result.details.push({ id: thread.id, success: false, error: error.message });
    }
  }

  // Step 3: Calculate momentum for all active threads
  const momentumCount = calculateAllMomentum();
  log.info({ count: momentumCount }, 'Calculated momentum scores');

  log.info(
    { summariesUpdated: result.processed, errors: result.errors, momentumCalculated: momentumCount },
    'Reconsolidation complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  reconsolidateThreads()
    .then((result) => {
      console.log('Reconsolidate-threads complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Reconsolidate-threads failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/workflows/reconsolidate-threads.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/reconsolidate-threads.ts
git commit -m "feat(phase3): add reconsolidate-threads workflow

- Find threads with new notes since last update
- Resynthesize summaries via Ollama
- Calculate momentum scores for all active threads"
```

---

## Task 4: Create launchd plist for reconsolidation

**Files:**
- Create: `launchd/com.selene.reconsolidate-threads.plist`

**Step 1: Create the plist file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.reconsolidate-threads</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>--transpile-only</string>
        <string>src/workflows/reconsolidate-threads.ts</string>
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

    <!-- Run every hour (3600 seconds) -->
    <key>StartInterval</key>
    <integer>3600</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/reconsolidate-threads.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/reconsolidate-threads.error.log</string>
</dict>
</plist>
```

**Step 2: Commit**

```bash
git add launchd/com.selene.reconsolidate-threads.plist
git commit -m "feat(phase3): add launchd plist for hourly reconsolidation"
```

---

## Task 5: Test reconsolidation workflow manually

**Step 1: Run the workflow manually**

```bash
npx ts-node src/workflows/reconsolidate-threads.ts
```

Expected output:
```
Reconsolidate-threads complete: { processed: N, errors: 0, details: [...] }
```

**Step 2: Verify database updated**

```bash
sqlite3 /Users/chaseeasterling/selene-data/selene.db "SELECT id, name, momentum_score, updated_at FROM threads WHERE status = 'active';"
```

Expected: Threads show momentum_score values and recent updated_at timestamps.

**Step 3: Check logs**

```bash
tail -20 logs/selene.log | npx pino-pretty
```

Expected: Log entries for "Starting thread reconsolidation" and "Reconsolidation complete".

---

## Task 6: Reinstall launchd agents

**Step 1: Run install script**

```bash
./scripts/install-launchd.sh
```

Expected: All agents listed including `com.selene.reconsolidate-threads`.

**Step 2: Verify agents running**

```bash
launchctl list | grep selene
```

Expected: See all Selene agents including `reconsolidate-threads`.

**Step 3: Commit any install script changes if needed**

If install script needed modification:
```bash
git add scripts/install-launchd.sh
git commit -m "chore: add reconsolidate-threads to install script"
```

---

## Task 7: End-to-end test with new note

**Step 1: Capture a test note**

```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Phase 3 test note", "content": "Testing the living system pipeline. This note should get embedded, associated, detected into a thread, and trigger reconsolidation.", "test_run": "phase3-test"}'
```

**Step 2: Wait for pipeline (or trigger manually)**

Either wait ~35 minutes for full pipeline, or trigger each step:
```bash
npx ts-node src/workflows/compute-embeddings.ts
npx ts-node src/workflows/compute-associations.ts
npx ts-node src/workflows/detect-threads.ts
npx ts-node src/workflows/reconsolidate-threads.ts
```

**Step 3: Verify thread updated**

```bash
sqlite3 /Users/chaseeasterling/selene-data/selene.db "SELECT t.name, t.summary, t.momentum_score FROM threads t WHERE t.status = 'active';"
```

**Step 4: Cleanup test data**

```bash
./scripts/cleanup-tests.sh phase3-test
```

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat(phase3): complete living system implementation

- Reconsolidation workflow with summary updates + momentum
- Faster launchd intervals (5min embeddings, 30min threads)
- Hourly reconsolidation schedule
- End-to-end tested"
```

---

## Summary

| Task | Description | Est. Time |
|------|-------------|-----------|
| 1 | Update compute-associations interval | 2 min |
| 2 | Update detect-threads interval | 3 min |
| 3 | Create reconsolidate-threads.ts | 15 min |
| 4 | Create launchd plist | 3 min |
| 5 | Test workflow manually | 5 min |
| 6 | Reinstall launchd agents | 3 min |
| 7 | End-to-end test | 10 min |

**Total: ~40 minutes**
