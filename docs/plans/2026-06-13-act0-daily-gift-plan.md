# Act 0 — Daily Gift Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "things I noticed for you" section to the daily worksheet — ≤3 surfaced notes with guilt-free reaction taps — that builds an `attention_log` in `facts.db` over time.

**Architecture:** Gift items are a new `gift_surface` WorksheetFieldKind, always first in the fields array, submitted bundled with existing answers. Three DB slot queries (buried_treasure / connection / heating_up) are injected as deps via `BuildDeps.fetchGiftItems`. Reactions write to `facts.attention_log` via `ApplyDeps.logReaction`. iPad renders a new `GiftSurfaceView` in the existing `WorksheetView` field switch.

**Tech Stack:** TypeScript + better-sqlite3 (Selene backend) · Swift + SwiftUI (SeleneMarkup iPad app) · `facts.db` for precious attention data

---

### Task 1: `attention_log` schema in `facts-db.ts`

**Files:**
- Modify: `src/lib/facts-db.ts` — inside `initFactsSchema()`, after the `note_feedback` block
- Modify: `src/lib/facts-db.test.ts` — add a new test

**Step 1: Write the failing test**

Add to `src/lib/facts-db.test.ts` inside `describe('initFactsSchema', ...)`:

```typescript
it('creates attention_log table idempotently with correct columns', () => {
  const db = new Database(':memory:');
  initFactsSchema(db);
  initFactsSchema(db); // must not throw

  const cols = (db.prepare(`PRAGMA table_info(attention_log)`).all() as { name: string }[]).map(c => c.name);
  expect(cols).toEqual(expect.arrayContaining([
    'id', 'worksheet_id', 'note_id', 'slot_role', 'reaction', 'reacted_at',
  ]));
  db.close();
});
```

**Step 2: Run test to verify it fails**

```bash
npx jest facts-db
```

Expected: FAIL — `attention_log` table doesn't exist yet.

**Step 3: Add the table to `initFactsSchema`**

In `src/lib/facts-db.ts`, inside the `db.exec(` template string in `initFactsSchema`, add after the `note_feedback` block:

```sql
    -- Act 0 attention log (2026-06-13): human reactions to surfaced gift items.
    -- PRECIOUS — tap choices are the user's expressed attention. Lives in facts.db.
    CREATE TABLE IF NOT EXISTS attention_log (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      worksheet_id TEXT NOT NULL,
      note_id      INTEGER NOT NULL,
      slot_role    TEXT NOT NULL,
      reaction     TEXT NOT NULL,
      reacted_at   TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_attention_log_note ON attention_log(note_id);
    CREATE INDEX IF NOT EXISTS idx_attention_log_reacted ON attention_log(reacted_at);
```

**Step 4: Run test to verify it passes**

```bash
npx jest facts-db
```

Expected: PASS — all existing tests still pass, new test passes.

**Step 5: Commit**

```bash
git add src/lib/facts-db.ts src/lib/facts-db.test.ts
git commit -m "feat(schema): add attention_log table to facts.db (Act 0)"
```

---

### Task 2: TypeScript type extensions in `worksheets.ts`

**Files:**
- Modify: `src/types/worksheets.ts`

No new test file — pure types have no runtime behavior to test. Existing tests will catch any type breakage at compile time.

**Step 1: Add new types**

Replace the entire contents of `src/types/worksheets.ts` with:

```typescript
export type WorksheetFieldKind = 'free_capture' | 'note_review' | 'gift_surface';

export type GiftSlotRole = 'buried_treasure' | 'connection' | 'heating_up';
export type GiftReaction = 'important' | 'keep' | 'not_now' | 'let_go';

export interface GiftItem {
  noteId: number;
  title: string;
  snippet: string;
  date: string;             // YYYY-MM-DD
  slotRole: GiftSlotRole;
  connectionNote?: {        // only present when slotRole === 'connection'
    noteId: number;
    title: string;
  };
}

export interface ReviewNote {
  id: number;
  title: string;
  snippet: string;
  date: string;
}

export interface WorksheetField {
  id: string;
  kind: WorksheetFieldKind;
  prompt: string;
  notes?: ReviewNote[];     // note_review fields only
  gifts?: GiftItem[];       // gift_surface fields only
  binding: { action: 'new_note' | 'acknowledge' | 'react' };
}

export interface Worksheet {
  id: string;
  title: string;
  fields: WorksheetField[];
}

export type ChosenAction = 'new_note' | 'acknowledge' | 'react';

export interface WorksheetAnswer {
  fieldId: string;
  chosenAction: ChosenAction;
  text?: string;             // free_capture
  noteId?: number;           // react answers — which gift card
  reaction?: GiftReaction;   // react answers — which tap
  slotRole?: GiftSlotRole;   // react answers — echoed back from the gift item
}

export interface WorksheetSubmission {
  worksheetId: string;
  answers: WorksheetAnswer[];
}

export type AnswerOutcome = 'applied' | 'skipped' | 'failed' | 'acknowledged' | 'reacted';

export interface AnswerResult {
  fieldId: string;
  outcome: AnswerOutcome;
  noteId?: number;
  reason?: string;
}

export interface RelatedNote {
  noteId: number;
  title: string;
  snippet: string;
  date: string;
  score: number;
}

export interface RelatedNotesGroup {
  fieldId: string;
  matches: RelatedNote[];
}

export interface SubmissionResult {
  worksheetId: string;
  results: AnswerResult[];
  relatedNotes: RelatedNotesGroup[];
}
```

**Step 2: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors (existing callers use `text: string` — now optional, so they're still compatible).

**Step 3: Run existing tests**

```bash
npx jest generate-worksheet
```

Expected: all pass.

**Step 4: Commit**

```bash
git add src/types/worksheets.ts
git commit -m "feat(types): add gift_surface field kind, GiftItem, react action (Act 0)"
```

---

### Task 3: Gift field construction in `generate-worksheet.ts`

**Files:**
- Modify: `src/workflows/generate-worksheet.ts`
- Modify: `src/workflows/generate-worksheet.test.ts`

**Step 1: Write failing tests**

Add to `src/workflows/generate-worksheet.test.ts`:

```typescript
import type { GiftItem } from '../types/worksheets';

describe('buildTodayWorksheet — gift_surface', () => {
  const gift: GiftItem = {
    noteId: 7,
    title: 'improv dinner idea',
    snippet: 'want to host a dinner',
    date: '2026-05-20',
    slotRole: 'buried_treasure',
  };

  it('includes gift_surface as first field when fetchGiftItems returns items', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-06-13T09:00:00'), {
      fetchGiftItems: async () => [gift],
    });
    assert.strictEqual(ws.fields[0].kind, 'gift_surface');
    assert.deepStrictEqual(ws.fields[0].gifts, [gift]);
    assert.deepStrictEqual(ws.fields[0].binding, { action: 'react' });
  });

  it('omits gift_surface when fetchGiftItems returns empty', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-06-13T09:00:00'), {
      fetchGiftItems: async () => [],
    });
    assert.ok(ws.fields.every(f => f.kind !== 'gift_surface'));
  });

  it('omits gift_surface when fetchGiftItems is not provided', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-06-13T09:00:00'));
    assert.ok(ws.fields.every(f => f.kind !== 'gift_surface'));
  });

  it('gift_surface field comes before free_capture fields', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-06-13T09:00:00'), {
      fetchGiftItems: async () => [gift],
    });
    const kinds = ws.fields.map(f => f.kind);
    assert.strictEqual(kinds[0], 'gift_surface');
    assert.ok(kinds.slice(1).includes('free_capture'));
  });
});
```

**Step 2: Run to verify they fail**

```bash
npx jest generate-worksheet
```

Expected: FAIL — `gift_surface` not yet in the worksheet.

**Step 3: Extend `BuildDeps` and `buildTodayWorksheet`**

In `src/workflows/generate-worksheet.ts`, update `BuildDeps` and `buildTodayWorksheet`:

```typescript
import type {
  Worksheet,
  WorksheetSubmission,
  SubmissionResult,
  AnswerResult,
  RelatedNote,
  RelatedNotesGroup,
  ReviewNote,
  GiftItem,
} from '../types/worksheets';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'generate-worksheet' });

export interface BuildDeps {
  fetchReviewNotes?: () => Promise<ReviewNote[]>;
  fetchGiftItems?: () => Promise<GiftItem[]>;
}

const defaultBuildDeps: BuildDeps = {};

export async function buildTodayWorksheet(
  now: Date = new Date(),
  deps: BuildDeps = defaultBuildDeps,
): Promise<Worksheet> {
  const date = now.toISOString().slice(0, 10);

  const [reviewNotes, giftItems] = await Promise.all([
    deps.fetchReviewNotes?.() ?? Promise.resolve([]),
    deps.fetchGiftItems?.() ?? Promise.resolve([]),
  ]);

  const fields: Worksheet['fields'] = [];

  // Gift section first — "things I noticed for you"
  if (giftItems.length > 0) {
    fields.push({
      id: 'f_gift',
      kind: 'gift_surface',
      prompt: 'things i noticed for you',
      gifts: giftItems,
      binding: { action: 'react' },
    });
  }

  // Capture fields
  fields.push(
    {
      id: 'f1',
      kind: 'free_capture',
      prompt: "Anything on your mind? Write it and it'll become a note.",
      binding: { action: 'new_note' },
    },
    {
      id: 'f2',
      kind: 'free_capture',
      prompt: 'One thing to get done today?',
      binding: { action: 'new_note' },
    },
  );

  if (reviewNotes.length > 0) {
    fields.push({
      id: 'f3',
      kind: 'note_review',
      prompt: 'These notes need attention:',
      notes: reviewNotes,
      binding: { action: 'acknowledge' },
    });
  }

  return {
    id: `ws_${date}`,
    title: `Daily Review — ${date}`,
    fields,
  };
}
```

**Step 4: Run tests**

```bash
npx jest generate-worksheet
```

Expected: all pass including the new gift_surface tests.

**Step 5: Commit**

```bash
git add src/workflows/generate-worksheet.ts src/workflows/generate-worksheet.test.ts
git commit -m "feat(worksheet): add gift_surface field from fetchGiftItems dep (Act 0)"
```

---

### Task 4: React answer handling in `generate-worksheet.ts`

**Files:**
- Modify: `src/workflows/generate-worksheet.ts`
- Modify: `src/workflows/generate-worksheet.test.ts`

**Step 1: Write failing tests**

Add to `src/workflows/generate-worksheet.test.ts`:

```typescript
import type { GiftReaction, GiftSlotRole } from '../types/worksheets';

describe('applyWorksheetAnswers — react', () => {
  it('calls logReaction for react answers and records reacted outcome', async () => {
    const logged: Array<{ noteId: number; reaction: GiftReaction; slotRole: GiftSlotRole }> = [];
    const deps = {
      createNote: async () => 1,
      logReaction: async (args: { worksheetId: string; noteId: number; slotRole: GiftSlotRole; reaction: GiftReaction; reactedAt: string }) => {
        logged.push({ noteId: args.noteId, reaction: args.reaction, slotRole: args.slotRole });
      },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_2026-06-13',
      answers: [
        { fieldId: 'f_gift', chosenAction: 'react', noteId: 42, reaction: 'important', slotRole: 'buried_treasure' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.deepStrictEqual(logged, [{ noteId: 42, reaction: 'important', slotRole: 'buried_treasure' }]);
    assert.deepStrictEqual(result.results[0], { fieldId: 'f_gift', outcome: 'reacted', noteId: 42 });
  });

  it('skips react answers missing noteId or reaction', async () => {
    const logged: number[] = [];
    const deps = {
      createNote: async () => 1,
      logReaction: async () => { logged.push(1); },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [
        { fieldId: 'f_gift', chosenAction: 'react' }, // no noteId or reaction
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.strictEqual(logged.length, 0);
    assert.deepStrictEqual(result.results[0], { fieldId: 'f_gift', outcome: 'skipped', reason: 'empty' });
  });

  it('skips react when logReaction not provided (graceful degradation)', async () => {
    const deps = { createNote: async () => 1 };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [
        { fieldId: 'f_gift', chosenAction: 'react', noteId: 7, reaction: 'keep', slotRole: 'heating_up' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    assert.deepStrictEqual(result.results[0], { fieldId: 'f_gift', outcome: 'skipped', reason: 'empty' });
  });
});
```

**Step 2: Run to verify they fail**

```bash
npx jest generate-worksheet
```

Expected: FAIL — `react` case not handled.

**Step 3: Add `logReaction` to `ApplyDeps` and handle `react` in `applyWorksheetAnswers`**

Update `ApplyDeps` and `applyWorksheetAnswers` in `src/workflows/generate-worksheet.ts`:

```typescript
import type {
  // ... existing imports ...
  GiftSlotRole,
  GiftReaction,
} from '../types/worksheets';

export interface ApplyDeps {
  createNote: (text: string) => Promise<number>;
  findRelatedNotes?: (text: string, excludeId: number) => Promise<RelatedNote[]>;
  logReaction?: (args: {
    worksheetId: string;
    noteId: number;
    slotRole: GiftSlotRole;
    reaction: GiftReaction;
    reactedAt: string;
  }) => Promise<void>;
}

export async function applyWorksheetAnswers(
  submission: WorksheetSubmission,
  deps: ApplyDeps,
): Promise<SubmissionResult> {
  const results: AnswerResult[] = [];
  const relatedNotes: RelatedNotesGroup[] = [];

  for (const answer of submission.answers) {
    if (answer.chosenAction === 'acknowledge') {
      results.push({ fieldId: answer.fieldId, outcome: 'acknowledged' });
      continue;
    }

    if (answer.chosenAction === 'react') {
      if (!answer.noteId || !answer.reaction || !answer.slotRole || !deps.logReaction) {
        results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'empty' });
        continue;
      }
      await deps.logReaction({
        worksheetId: submission.worksheetId,
        noteId: answer.noteId,
        slotRole: answer.slotRole,
        reaction: answer.reaction,
        reactedAt: new Date().toISOString(),
      });
      results.push({ fieldId: answer.fieldId, outcome: 'reacted', noteId: answer.noteId });
      continue;
    }

    if (answer.chosenAction !== 'new_note') {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'unsupported_action' });
      continue;
    }

    const text = (answer.text ?? '').trim();
    if (text.length === 0) {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'empty' });
      continue;
    }

    let noteId: number;
    try {
      noteId = await deps.createNote(text);
      results.push({ fieldId: answer.fieldId, outcome: 'applied', noteId });
    } catch (err) {
      results.push({ fieldId: answer.fieldId, outcome: 'failed', reason: (err as Error).message });
      continue;
    }

    if (deps.findRelatedNotes) {
      try {
        const matches = await deps.findRelatedNotes(text, noteId);
        if (matches.length > 0) relatedNotes.push({ fieldId: answer.fieldId, matches });
      } catch (err) {
        log.warn({ err, fieldId: answer.fieldId }, 'findRelatedNotes failed — skipping context');
      }
    }
  }

  return { worksheetId: submission.worksheetId, results, relatedNotes };
}
```

**Step 4: Run tests**

```bash
npx jest generate-worksheet
```

Expected: all pass.

**Step 5: Commit**

```bash
git add src/workflows/generate-worksheet.ts src/workflows/generate-worksheet.test.ts
git commit -m "feat(worksheet): handle react answers → attention_log via logReaction dep (Act 0)"
```

---

### Task 5: Route wiring — slot queries + logReaction

**Files:**
- Modify: `src/routes/worksheets.ts`

No new test file — the route is integration-level; the logic is already tested via generate-worksheet.test.ts. Run the existing routes test if one exists.

**Step 1: Add slot selection queries and `logReaction` implementation**

Replace `src/routes/worksheets.ts` with:

```typescript
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../lib/auth';
import {
  buildTodayWorksheet,
  applyWorksheetAnswers,
} from '../workflows/generate-worksheet';
import { ingest } from '../workflows/ingest';
import { embed } from '../lib/ollama';
import { searchSimilarNotes } from '../lib/lancedb';
import { similarityFromCosineDistance } from '../lib/vector-similarity';
import { db } from '../lib/db';
import { testRunFilter } from '../lib/test-run';
import { logger } from '../lib/logger';
import type {
  WorksheetSubmission,
  ReviewNote,
  RelatedNote,
  GiftItem,
  GiftSlotRole,
  GiftReaction,
} from '../types/worksheets';

const log = logger.child({ module: 'worksheets-route' });

function fetchReviewNotes(): Promise<ReviewNote[]> {
  const rows = db.prepare(`
    SELECT id, title, content, created_at
    FROM raw_notes
    WHERE inbox_status = 'pending'
      ${testRunFilter()}
      AND created_at < datetime('now', '-1 day')
    ORDER BY created_at ASC
    LIMIT 3
  `).all() as Array<{ id: number; title: string; content: string; created_at: string }>;

  return Promise.resolve(rows.map(r => ({
    id: r.id,
    title: r.title,
    snippet: r.content.slice(0, 120).trimEnd(),
    date: r.created_at.slice(0, 10),
  })));
}

// ---------------------------------------------------------------------------
// Gift slot queries (Act 0)
// ---------------------------------------------------------------------------

function fetchGiftItems(): GiftItem[] {
  const items: GiftItem[] = [];

  // Slot 1: buried_treasure — random old note with no prior reactions
  const buried = db.prepare(`
    SELECT rn.id, rn.title, rn.content, rn.created_at
    FROM raw_notes rn
    LEFT JOIN facts.attention_log al ON rn.id = al.note_id
    WHERE al.id IS NULL
      AND rn.created_at < datetime('now', '-14 days')
      ${testRunFilter('rn')}
    ORDER BY RANDOM()
    LIMIT 1
  `).get() as { id: number; title: string; content: string; created_at: string } | undefined;

  if (buried) {
    items.push({
      noteId: buried.id,
      title: buried.title,
      snippet: buried.content.slice(0, 160).trimEnd(),
      date: buried.created_at.slice(0, 10),
      slotRole: 'buried_treasure',
    });
  }

  // Slot 2: connection — highest-similarity pair (one recent, one old)
  const conn = db.prepare(`
    SELECT
      rn1.id AS sourceId, rn1.title AS sourceTitle, rn1.content AS sourceContent, rn1.created_at AS sourceDate,
      rn2.id AS targetId, rn2.title AS targetTitle
    FROM note_connections nc
    JOIN raw_notes rn1 ON nc.source_note_id = rn1.id
    JOIN raw_notes rn2 ON nc.target_note_id = rn2.id
    WHERE rn1.created_at >= datetime('now', '-7 days')
      AND rn2.created_at < datetime('now', '-14 days')
      ${testRunFilter('rn1')}
      ${testRunFilter('rn2')}
    ORDER BY nc.similarity_score DESC
    LIMIT 1
  `).get() as {
    sourceId: number; sourceTitle: string; sourceContent: string; sourceDate: string;
    targetId: number; targetTitle: string;
  } | undefined;

  if (conn) {
    items.push({
      noteId: conn.sourceId,
      title: conn.sourceTitle,
      snippet: conn.sourceContent.slice(0, 160).trimEnd(),
      date: conn.sourceDate.slice(0, 10),
      slotRole: 'connection',
      connectionNote: { noteId: conn.targetId, title: conn.targetTitle },
    });
  }

  // Slot 3: heating_up — most recent unreacted note
  const heating = db.prepare(`
    SELECT rn.id, rn.title, rn.content, rn.created_at
    FROM raw_notes rn
    LEFT JOIN facts.attention_log al ON rn.id = al.note_id
    WHERE al.id IS NULL
      ${testRunFilter('rn')}
    ORDER BY rn.created_at DESC
    LIMIT 1
  `).get() as { id: number; title: string; content: string; created_at: string } | undefined;

  if (heating && heating.id !== buried?.id) {
    items.push({
      noteId: heating.id,
      title: heating.title,
      snippet: heating.content.slice(0, 160).trimEnd(),
      date: heating.created_at.slice(0, 10),
      slotRole: 'heating_up',
    });
  }

  return items;
}

function logReaction(args: {
  worksheetId: string;
  noteId: number;
  slotRole: GiftSlotRole;
  reaction: GiftReaction;
  reactedAt: string;
}): void {
  db.prepare(`
    INSERT INTO facts.attention_log (worksheet_id, note_id, slot_role, reaction, reacted_at)
    VALUES (?, ?, ?, ?, ?)
  `).run(args.worksheetId, args.noteId, args.slotRole, args.reaction, args.reactedAt);
}

async function findRelatedNotes(text: string, excludeId: number): Promise<RelatedNote[]> {
  const vector = await embed(text);
  const similar = await searchSimilarNotes(vector, {
    limit: 3,
    excludeIds: [excludeId],
    maxDistance: 1.0,
  });

  return similar.map(s => {
    const row = db.prepare('SELECT content, created_at FROM raw_notes WHERE id = ?').get(s.id) as { content: string; created_at: string } | undefined;
    return {
      noteId: s.id,
      title: s.title,
      snippet: row?.content.slice(0, 120).trimEnd() ?? '',
      date: row?.created_at.slice(0, 10) ?? '',
      score: Math.max(0, similarityFromCosineDistance(s.distance)),
    };
  });
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

export async function worksheetRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('preHandler', requireAuth);

  fastify.get('/api/worksheets/today', async () => {
    return buildTodayWorksheet(new Date(), {
      fetchReviewNotes,
      fetchGiftItems: async () => fetchGiftItems(),
    });
  });

  fastify.post<{
    Params: { id: string };
    Body: WorksheetSubmission & { test_run?: string };
  }>(
    '/api/worksheets/:id/answers',
    async (request, reply) => {
      const body = request.body;
      if (!body || !Array.isArray(body.answers)) {
        reply.status(400);
        return { error: 'answers array required' };
      }

      const worksheetId = request.params.id;
      return applyWorksheetAnswers(
        { worksheetId, answers: body.answers },
        {
          createNote: async (text: string) => {
            const res = await ingest({
              title: `Worksheet capture: ${worksheetId}`,
              content: text,
              capture_type: 'worksheet',
              test_run: body.test_run,
            });
            return (res.id ?? res.existingId) as number;
          },
          findRelatedNotes: body.test_run
            ? undefined
            : async (text, excludeId) => {
                try {
                  return await findRelatedNotes(text, excludeId);
                } catch (err) {
                  log.warn({ err }, 'findRelatedNotes failed in route — returning empty');
                  return [];
                }
              },
          logReaction: body.test_run
            ? undefined   // skip during test runs
            : async (args) => logReaction(args),
        },
      );
    },
  );
}
```

**Step 2: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

**Step 3: Run full test suite**

```bash
npm test
```

Expected: all pass.

**Step 4: Commit**

```bash
git add src/routes/worksheets.ts
git commit -m "feat(route): wire gift slot queries + logReaction into worksheet routes (Act 0)"
```

---

### Task 6: SeleneMarkup — model types

**Files:**
- Modify: `~/SeleneMarkup/Sources/SeleneMarkup/Models/Worksheet.swift`

**Step 1: Update model types**

Replace the contents of `~/SeleneMarkup/Sources/SeleneMarkup/Models/Worksheet.swift`:

```swift
import Foundation

// ---------------------------------------------------------------------------
// Server → client (GET /api/worksheets/today response)
// ---------------------------------------------------------------------------

struct Worksheet: Codable {
    let id: String
    let title: String
    let fields: [WorksheetField]
}

struct WorksheetField: Codable {
    let id: String
    let kind: String          // "free_capture" | "note_review" | "gift_surface"
    let prompt: String
    let notes: [ReviewNote]?  // note_review fields only
    let gifts: [GiftItem]?    // gift_surface fields only
    let binding: FieldBinding

    struct FieldBinding: Codable {
        let action: String    // "new_note" | "acknowledge" | "react"
    }
}

struct ReviewNote: Codable {
    let id: Int
    let title: String
    let snippet: String
    let date: String
}

struct GiftItem: Codable {
    let noteId: Int
    let title: String
    let snippet: String
    let date: String
    let slotRole: String    // "buried_treasure" | "connection" | "heating_up"
    let connectionNote: ConnectionNote?

    struct ConnectionNote: Codable {
        let noteId: Int
        let title: String
    }
}

// ---------------------------------------------------------------------------
// Client → server (POST /api/worksheets/:id/answers body)
// ---------------------------------------------------------------------------

struct WorksheetSubmission: Codable {
    let worksheetId: String
    let answers: [WorksheetAnswer]
}

struct WorksheetAnswer: Codable {
    let fieldId: String
    let chosenAction: String  // "new_note" | "acknowledge" | "react"
    let text: String?
    let noteId: Int?          // react answers — which gift card
    let reaction: String?     // react answers — "important" | "keep" | "not_now" | "let_go"
    let slotRole: String?     // react answers — echoed back from the gift item

    // Convenience init for free_capture / note_review (existing callers)
    init(fieldId: String, chosenAction: String, text: String) {
        self.fieldId = fieldId
        self.chosenAction = chosenAction
        self.text = text
        self.noteId = nil
        self.reaction = nil
        self.slotRole = nil
    }

    // Convenience init for react answers
    init(fieldId: String, noteId: Int, reaction: String, slotRole: String) {
        self.fieldId = fieldId
        self.chosenAction = "react"
        self.text = nil
        self.noteId = noteId
        self.reaction = reaction
        self.slotRole = slotRole
    }
}

// ---------------------------------------------------------------------------
// Server → client (POST response)
// ---------------------------------------------------------------------------

struct SubmissionResult: Codable {
    let worksheetId: String
    let results: [AnswerResult]
    let relatedNotes: [RelatedNotesGroup]?
}

struct AnswerResult: Codable {
    let fieldId: String
    let outcome: String
    let noteId: Int?
    let reason: String?
}

struct RelatedNotesGroup: Codable {
    let fieldId: String
    let matches: [RelatedNote]
}

struct RelatedNote: Codable {
    let noteId: Int
    let title: String
    let snippet: String
    let date: String
    let score: Double
}
```

**Step 2: Build to check for compile errors**

```bash
cd ~/SeleneMarkup && swift build 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: no errors. Existing callers of `WorksheetAnswer(fieldId:chosenAction:text:)` still work via the convenience init.

**Step 3: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Models/Worksheet.swift
git commit -m "feat(model): add gift_surface, GiftItem, react answer types (Act 0)"
```

---

### Task 7: SeleneMarkup — `GiftSurfaceView`

**Files:**
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Views/GiftSurfaceView.swift`

**Step 1: Create the view**

```swift
import SwiftUI

// ---------------------------------------------------------------------------
// GiftCard — one surfaced note with 4 tap buttons
// ---------------------------------------------------------------------------

struct GiftCard: View {
    let item: GiftItem
    @Binding var selectedReaction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Slot role label
            Text(slotLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            // Note content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let conn = item.connectionNote {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(conn.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Reaction buttons
            HStack(spacing: 8) {
                ForEach(reactions, id: \.0) { reaction, label, icon in
                    Button {
                        selectedReaction = (selectedReaction == reaction) ? nil : reaction
                    } label: {
                        Label(label, systemImage: icon)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedReaction == reaction ? Color.accentColor : Color(.tertiarySystemBackground))
                            .foregroundStyle(selectedReaction == reaction ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var slotLabel: String {
        switch item.slotRole {
        case "buried_treasure": return "buried treasure"
        case "connection": return "connecting thought"
        case "heating_up": return "recently heating up"
        default: return item.slotRole
        }
    }

    // (reaction string, display label, SF Symbol)
    private let reactions: [(String, String, String)] = [
        ("important", "Important", "star"),
        ("keep",      "Keep",      "heart"),
        ("not_now",   "Not now",   "clock"),
        ("let_go",    "Let go",    "xmark"),
    ]
}

// ---------------------------------------------------------------------------
// GiftSurfaceView — the full gift section with all cards
// ---------------------------------------------------------------------------

struct GiftSurfaceView: View {
    let field: WorksheetField
    @Binding var reactions: [Int: String]   // noteId → reaction string

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(field.gifts ?? [], id: \.noteId) { item in
                GiftCard(
                    item: item,
                    selectedReaction: Binding(
                        get: { reactions[item.noteId] },
                        set: { reactions[item.noteId] = $0 }
                    )
                )
            }
        }
    }
}
```

**Step 2: Build to check for compile errors**

```bash
cd ~/SeleneMarkup && swift build 2>&1 | grep -E "error:" | head -10
```

Expected: no errors.

**Step 3: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Views/GiftSurfaceView.swift
git commit -m "feat(ui): add GiftSurfaceView with slot cards and reaction buttons (Act 0)"
```

---

### Task 8: SeleneMarkup — `WorksheetView` integration

**Files:**
- Modify: `~/SeleneMarkup/Sources/SeleneMarkup/Views/WorksheetView.swift`

**Step 1: Add `giftReactions` to ViewModel and update `confirmSubmit`**

In `WorksheetViewModel`:

1. Add property after `@Published var recognizedTexts`:
```swift
@Published var giftReactions: [Int: String] = [:]   // noteId → reaction
```

2. In `fetchToday()`, reset gift reactions after fetching (add after `worksheet = ws`):
```swift
giftReactions = [:]
```

3. In `confirmSubmit()`, replace the answer-building loop with:
```swift
var answers: [WorksheetAnswer] = []
for field in ws.fields {
    if field.kind == "gift_surface" {
        // Emit one react answer per tapped card
        for item in (field.gifts ?? []) {
            if let reaction = giftReactions[item.noteId] {
                answers.append(WorksheetAnswer(
                    fieldId: field.id,
                    noteId: item.noteId,
                    reaction: reaction,
                    slotRole: item.slotRole
                ))
            }
        }
    } else {
        answers.append(WorksheetAnswer(
            fieldId: field.id,
            chosenAction: field.binding.action,
            text: field.kind == "free_capture" ? (recognizedTexts[field.id] ?? "") : ""
        ))
    }
}
```

4. In the reset block after successful submit, add `giftReactions = [:]` alongside the existing resets.

**Step 2: Add `gift_surface` case to `fieldView`**

In `fieldView(_ field:)`, add before the closing `}` of the function:

```swift
} else if field.kind == "gift_surface" {
    GiftSurfaceView(
        field: field,
        reactions: $vm.giftReactions
    )
}
```

(Replace the line `} else if field.kind == "note_review", let notes = field.notes {` block's closing so the chain reads:)

```swift
if field.kind == "free_capture" {
    // ... existing canvas code ...
} else if field.kind == "note_review", let notes = field.notes {
    ForEach(notes, id: \.id) { note in
        NoteReviewCard(note: note)
    }
} else if field.kind == "gift_surface" {
    GiftSurfaceView(
        field: field,
        reactions: $vm.giftReactions
    )
}
```

**Step 3: Build**

```bash
cd ~/SeleneMarkup && swift build 2>&1 | grep -E "error:" | head -10
```

Expected: no errors.

**Step 4: Run tests**

```bash
cd ~/SeleneMarkup && swift test 2>&1 | tail -10
```

Expected: all pass.

**Step 5: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Views/WorksheetView.swift
git commit -m "feat(ui): wire GiftSurfaceView + giftReactions into WorksheetView (Act 0)"
```

---

### Task 9: End-to-end smoke test + deploy

**Step 1: Run the full TypeScript test suite**

```bash
cd ~/selene && npm test
```

Expected: all pass.

**Step 2: Deploy the SeleneMarkup app to the iPad**

```bash
cd ~/SeleneMarkup && ./redeploy.sh
```

**Step 3: Manual validation**

1. Open the Selene app on iPad → Worksheet tab
2. Verify the gift section appears at the top ("things i noticed for you") with ≤3 cards
3. Tap a reaction button on one card — it should highlight
4. Submit the worksheet
5. On the Mac: `sqlite3 ~/selene-data-dev/facts.db "SELECT * FROM attention_log ORDER BY id DESC LIMIT 5;"`
6. Verify the tapped reaction appears in the table with correct `worksheet_id`, `note_id`, `slot_role`, `reaction`

**Step 4: Push to origin/main to deploy to prod**

```bash
cd ~/selene && git push origin main
```

Wait ~5 minutes for the deploy-watcher to pick it up. Then redeploy SeleneMarkup pointing at prod (`:5678`).

**Step 5: Mark design doc Done in INDEX.md**

Update `docs/plans/INDEX.md`: move the Act 0 entry from In Progress → Done with today's date.

```bash
git add docs/plans/INDEX.md
git commit -m "docs(plans): mark Act 0 daily gift Done"
git push origin main
```
