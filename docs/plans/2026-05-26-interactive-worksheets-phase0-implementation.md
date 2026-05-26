# Interactive Worksheets — Phase 0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prove the worksheet round-trip end-to-end with the smallest build — a freeform handwriting page on the iPad becomes one new note in Selene — to de-risk Pencil + on-device OCR + LAN delivery before building the structured review machinery.

**Architecture:** Two tracks. **Track A (Selene)** adds two authenticated endpoints (`GET /api/worksheets/today`, `POST /api/worksheets/:id/answers`) backed by pure, injectable functions — buildable and testable on the Mac today. **Track B (iPad app)** is a minimal SwiftUI app (PencilKit capture → on-device Vision OCR → verify → POST) that is **hardware-gated**: it requires an M-series, iPadOS 17+ iPad and cannot be built or run until that device exists.

**Tech Stack:** TypeScript, Fastify, better-sqlite3, vitest (Track A). Swift, SwiftUI, PencilKit, Vision, SPM (Track B).

**Design doc:** `docs/plans/2026-05-26-interactive-worksheets-design.md`

---

## Conventions (read before starting)

- **Tests use vitest** (`import { describe, it, expect } from 'vitest'`). Run a single file with `npx vitest run src/workflows/<file>.test.ts`.
- **Two test layers.** (1) **Pure logic** (`buildTodayWorksheet`, `applyWorksheetAnswers`) is DB-free — inject a fake `createNote`, no DB at all. (2) The **route integration test** writes to the real DB through `ingest()` but tags every row with a `test_run` marker and deletes them in `afterAll` — this is what CLAUDE.md sanctions ("Always use test_run markers… cleanup with cleanup-tests.sh"). Do not attempt a temp/swappable DB: `src/lib/db` opens a module-level singleton at import time.
- **Never use the `any` type.** Define explicit types in `src/types/`.
- **Routes** register via `server.register(fn)` in `src/server.ts`; protect with the `requireAuth` preHandler from `src/lib/auth.ts`.
- **Note creation** goes through `ingest()` (`src/workflows/ingest.ts`), which handles dedup + insert. Reuse it; do not write raw INSERTs for notes.

---

# TRACK A — Selene (build & test now)

### Task A1: Worksheet types

**Files:**
- Create: `src/types/worksheets.ts`

**Step 1: Write the types**

```typescript
// The worksheet Selene sends to the iPad.
export type WorksheetFieldKind = 'free_capture' | 'note_review';

export interface FreeCaptureBinding {
  action: 'new_note';
}

export interface WorksheetField {
  id: string;                 // unique within the worksheet, e.g. "f1"
  kind: WorksheetFieldKind;
  prompt: string;
  // Phase 0 only emits free_capture; note_review arrives in Phase 1.
  binding: FreeCaptureBinding;
}

export interface Worksheet {
  id: string;                 // e.g. "ws_2026-05-26"
  title: string;
  fields: WorksheetField[];
}

// What the iPad posts back.
export type ChosenAction = 'new_note';

export interface WorksheetAnswer {
  fieldId: string;
  chosenAction: ChosenAction;
  text: string;
}

export interface WorksheetSubmission {
  worksheetId: string;
  answers: WorksheetAnswer[];
}

// Per-field result returned to the iPad.
export type AnswerOutcome = 'applied' | 'skipped' | 'failed';

export interface AnswerResult {
  fieldId: string;
  outcome: AnswerOutcome;
  noteId?: number;            // set when a note was created
  reason?: string;            // set when skipped/failed
}

export interface SubmissionResult {
  worksheetId: string;
  results: AnswerResult[];
}
```

**Step 2: Type-check**

Run: `npx tsc --noEmit`
Expected: no errors.

**Step 3: Commit**

```bash
git add src/types/worksheets.ts
git commit -m "feat(worksheets): add Phase 0 worksheet types"
```

---

### Task A2: `buildTodayWorksheet()` — the Phase 0 generator

A pure function returning a worksheet with a single freeform-capture field. No DB needed yet.

**Files:**
- Create: `src/workflows/generate-worksheet.ts`
- Test: `src/workflows/generate-worksheet.test.ts`

**Step 1: Write the failing test**

```typescript
import { describe, it, expect } from 'vitest';
import { buildTodayWorksheet } from './generate-worksheet';

describe('buildTodayWorksheet', () => {
  it('builds a worksheet with a single free_capture field for the given date', () => {
    const ws = buildTodayWorksheet(new Date('2026-05-26T09:00:00'));
    expect(ws.id).toBe('ws_2026-05-26');
    expect(ws.fields).toHaveLength(1);
    expect(ws.fields[0].kind).toBe('free_capture');
    expect(ws.fields[0].binding).toEqual({ action: 'new_note' });
    expect(ws.fields[0].id).toBeTruthy();
    expect(ws.title).toContain('2026-05-26');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx vitest run src/workflows/generate-worksheet.test.ts`
Expected: FAIL — `buildTodayWorksheet` is not defined.

**Step 3: Write minimal implementation**

```typescript
import type { Worksheet } from '../types/worksheets';

export function buildTodayWorksheet(now: Date = new Date()): Worksheet {
  const date = now.toISOString().slice(0, 10); // YYYY-MM-DD
  return {
    id: `ws_${date}`,
    title: `Daily Review — ${date}`,
    fields: [
      {
        id: 'f1',
        kind: 'free_capture',
        prompt: "Anything on your mind? Write it and it'll become a note.",
        binding: { action: 'new_note' },
      },
    ],
  };
}
```

**Step 4: Run test to verify it passes**

Run: `npx vitest run src/workflows/generate-worksheet.test.ts`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/workflows/generate-worksheet.ts src/workflows/generate-worksheet.test.ts
git commit -m "feat(worksheets): add Phase 0 today-worksheet generator"
```

---

### Task A3: `applyWorksheetAnswers()` — apply answers via injected (async) note-creator

Pure orchestration with an injected **async** `createNote` dependency, so it unit-tests without a DB *and* is the single source of truth the route reuses (no duplicated skip/blank/failed logic). Phase 0 supports only `new_note`. Blank answers are skipped.

**Files:**
- Modify: `src/workflows/generate-worksheet.ts`
- Modify: `src/workflows/generate-worksheet.test.ts`

**Step 1: Write the failing test**

```typescript
import { applyWorksheetAnswers } from './generate-worksheet';
import type { WorksheetSubmission } from '../types/worksheets';

describe('applyWorksheetAnswers', () => {
  it('creates a note for each non-blank new_note answer and skips blanks', async () => {
    const created: string[] = [];
    const deps = {
      createNote: async (text: string) => { created.push(text); return created.length; },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_2026-05-26',
      answers: [
        { fieldId: 'f1', chosenAction: 'new_note', text: 'Book conference travel' },
        { fieldId: 'f2', chosenAction: 'new_note', text: '   ' }, // blank
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(created).toEqual(['Book conference travel']);
    expect(result.results).toEqual([
      { fieldId: 'f1', outcome: 'applied', noteId: 1 },
      { fieldId: 'f2', outcome: 'skipped', reason: 'empty' },
    ]);
  });

  it('marks a field failed when createNote throws, without aborting the batch', async () => {
    const deps = {
      createNote: async (text: string) => {
        if (text === 'boom') throw new Error('db error');
        return 42;
      },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [
        { fieldId: 'f1', chosenAction: 'new_note', text: 'boom' },
        { fieldId: 'f2', chosenAction: 'new_note', text: 'ok' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.results[0].outcome).toBe('failed');
    expect(result.results[1]).toEqual({ fieldId: 'f2', outcome: 'applied', noteId: 42 });
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx vitest run src/workflows/generate-worksheet.test.ts`
Expected: FAIL — `applyWorksheetAnswers` is not defined.

**Step 3: Write minimal implementation (append to `generate-worksheet.ts`)**

```typescript
import type {
  WorksheetSubmission,
  SubmissionResult,
  AnswerResult,
} from '../types/worksheets';

export interface ApplyDeps {
  // Creates a note from text, returns the new note's id. Rejects on failure.
  createNote: (text: string) => Promise<number>;
}

export async function applyWorksheetAnswers(
  submission: WorksheetSubmission,
  deps: ApplyDeps,
): Promise<SubmissionResult> {
  const results: AnswerResult[] = [];
  for (const answer of submission.answers) {
    if (answer.chosenAction !== 'new_note') {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'unsupported_action' });
      continue;
    }
    const text = (answer.text ?? '').trim();
    if (text.length === 0) {
      results.push({ fieldId: answer.fieldId, outcome: 'skipped', reason: 'empty' });
      continue;
    }
    try {
      const noteId = await deps.createNote(text);
      results.push({ fieldId: answer.fieldId, outcome: 'applied', noteId });
    } catch (err) {
      results.push({ fieldId: answer.fieldId, outcome: 'failed', reason: (err as Error).message });
    }
  }
  return { worksheetId: submission.worksheetId, results };
}
```

**Step 4: Run test to verify it passes**

Run: `npx vitest run src/workflows/generate-worksheet.test.ts`
Expected: PASS (all 3 tests).

**Step 5: Commit**

```bash
git add src/workflows/generate-worksheet.ts src/workflows/generate-worksheet.test.ts
git commit -m "feat(worksheets): apply Phase 0 answers (new_note) with per-field results"
```

---

### Task A4: Worksheet routes

Two endpoints, both behind `requireAuth`. GET returns `buildTodayWorksheet()`. POST validates the body and delegates to the **already-tested** `applyWorksheetAnswers` from A3, injecting a `createNote` backed by `ingest()` (so dedup + normal processing work). One source of truth — the route adds no new skip/blank/failed logic.

**Files:**
- Create: `src/routes/worksheets.ts`
- Modify: `src/server.ts` (register the routes)

**Step 0: Verify the `capture_type` type before writing**

Run: `grep -n "capture_type" src/types/index.ts`
Expected: `IngestInput.capture_type` is typed as `string` (not a string-literal union). If it IS a union, add `'worksheet'` to it. (The `raw_notes` CHECK constraint is on `source_type`, NOT `capture_type`, so the DB accepts any `capture_type` — the only risk is TypeScript narrowing.)

**Step 1: Write the route module**

```typescript
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../lib/auth';
import {
  buildTodayWorksheet,
  applyWorksheetAnswers,
} from '../workflows/generate-worksheet';
import { ingest } from '../workflows/ingest';
import type { WorksheetSubmission } from '../types/worksheets';

export async function worksheetRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.get('/api/worksheets/today', { preHandler: requireAuth }, async () => {
    return buildTodayWorksheet();
  });

  fastify.post<{
    Params: { id: string };
    Body: WorksheetSubmission & { test_run?: string };
  }>(
    '/api/worksheets/:id/answers',
    { preHandler: requireAuth },
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
            return res.id as number;
          },
        },
      );
    },
  );
}
```

> **Note:** `ingest()` can return a duplicate result (`{ duplicate: true, existingId }`) instead of `{ id }`. For Phase 0 that's acceptable — map `existingId` to the returned id if `id` is undefined, so a re-submitted identical capture reports `applied` against the existing note rather than failing. Adjust the `createNote` body to `return (res.id ?? res.existingId) as number;` and confirm `IngestResult`'s shape in `src/types/index.ts`.

**Step 2: Register in `src/server.ts`**

Add the import near the other route imports (line ~5):
```typescript
import { worksheetRoutes } from './routes/worksheets';
```
Register alongside the others (near line ~83):
```typescript
server.register(worksheetRoutes);
```

**Step 3: Type-check**

Run: `npx tsc --noEmit`
Expected: no errors.

**Step 4: Commit**

```bash
git add src/routes/worksheets.ts src/server.ts
git commit -m "feat(worksheets): add GET /today and POST /:id/answers routes"
```

---

### Task A5: Route integration test (Fastify `inject`, real DB + test_run cleanup)

**Files:**
- Create: `src/routes/worksheets.test.ts`

**Step 1: Write the test**

> This is an **integration** test: it uses `fastify.inject()` (no real port) and writes to the **real** Selene DB via `ingest()`, tagged with a `test_run` marker — exactly what CLAUDE.md sanctions ("Always use test_run markers… cleanup with cleanup-tests.sh"). Do NOT try to swap in a temp DB; `src/lib/db` opens a module-level singleton at import time, so the simplest correct approach is the marker + `afterAll` delete. (The pure skip/blank logic is already covered DB-free in A3 — this test only needs to prove the route wires `ingest()` correctly.)

```typescript
import { describe, it, expect, afterAll } from 'vitest';
import Fastify from 'fastify';
import Database from 'better-sqlite3';
import { join } from 'path';
import { homedir } from 'os';
import { worksheetRoutes } from './worksheets';

const TEST_RUN = `test-worksheets-${Date.now()}`;
const DB_PATH = process.env.SELENE_DB_PATH || join(homedir(), 'selene-data/selene.db');

afterAll(() => {
  // Self-clean: remove any rows this test inserted.
  const db = new Database(DB_PATH);
  db.prepare('DELETE FROM raw_notes WHERE test_run = ?').run(TEST_RUN);
  db.close();
});

describe('worksheet routes', () => {
  it('GET /api/worksheets/today returns a free_capture worksheet', async () => {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({ method: 'GET', url: '/api/worksheets/today' });
    expect(res.statusCode).toBe(200);
    expect(res.json().fields[0].kind).toBe('free_capture');
    await app.close();
  });

  it('POST answers creates a note for non-blank text and skips blanks', async () => {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({
      method: 'POST',
      url: '/api/worksheets/ws_test/answers',
      payload: {
        worksheetId: 'ws_test',
        test_run: TEST_RUN,
        answers: [
          { fieldId: 'f1', chosenAction: 'new_note', text: `dentist ${TEST_RUN}` },
          { fieldId: 'f2', chosenAction: 'new_note', text: '   ' },
        ],
      },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.results[0].outcome).toBe('applied');
    expect(body.results[0].noteId).toBeTypeOf('number');
    expect(body.results[1].outcome).toBe('skipped');
    await app.close();
  });
});
```

**Step 2: Run the test**

Run: `npx vitest run src/routes/worksheets.test.ts`
Expected: both tests PASS; `afterAll` removes the inserted rows.

**Step 3: Belt-and-suspenders cleanup check**

Run: `sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE test_run LIKE 'test-worksheets-%';"`
Expected: `0`. If not, run `./scripts/cleanup-tests.sh --list` and clean the leftover marker.

**Step 4: Commit**

```bash
git add src/routes/worksheets.test.ts
git commit -m "test(worksheets): integration-test today + answers routes"
```

---

### Task A6: Manual end-to-end smoke (curl) + Track A wrap-up

**Step 1: Pick up the new routes in the running server**

The server runs under launchd (not `npm start`), so restart it to load the new routes:
```bash
launchctl kickstart -k gui/$(id -u)/com.selene.server
curl -s http://localhost:5678/health
```
Expected: health JSON with `"status":"ok"`.

**Step 2: Fetch today's worksheet**

```bash
curl -s http://localhost:5678/api/worksheets/today | npx pino-pretty 2>/dev/null || curl -s http://localhost:5678/api/worksheets/today
```
Expected: JSON with one `free_capture` field. (If `SELENE_API_TOKEN` is set, add `-H "Authorization: Bearer $SELENE_API_TOKEN"`.)

**Step 3: Submit a test answer**

```bash
curl -s -X POST http://localhost:5678/api/worksheets/ws_smoke/answers \
  -H "Content-Type: application/json" \
  -d '{"worksheetId":"ws_smoke","test_run":"test-smoke-001","answers":[{"fieldId":"f1","chosenAction":"new_note","text":"worksheet smoke test note"}]}'
```
Expected: `{"worksheetId":"ws_smoke","results":[{"fieldId":"f1","outcome":"applied","noteId":<n>}]}`

**Step 4: Verify the note exists, then clean up**

```bash
sqlite3 data/selene.db "SELECT id,title,capture_type FROM raw_notes WHERE test_run='test-smoke-001';"
./scripts/cleanup-tests.sh test-smoke-001
```

**Track A exit gate:** both endpoints work over HTTP, a note is created and verified, and the test row is cleaned up. **Track A is complete and shippable on its own** — the iPad can come later.

---

# TRACK B — iPad app (HARDWARE-GATED — do not start until an M-series, iPadOS 17+ iPad is available)

> **Why gated:** PencilKit interaction and on-device Vision OCR accuracy can only be verified on the device, and a 1st-gen iPad Pro cannot run iPadOS 17. These tasks are written so they're ready to execute the day the hardware arrives. SPM unit tests for `WorksheetService` logic CAN run on the Mac, but the app cannot be meaningfully built/installed without the device + free-signing setup.

### Task B1: App skeleton + one-command redeploy
- Create `~/SeleneMarkup/` SwiftUI app, iPadOS 17 target, SPM (no Xcode project), mirroring SeleneChat's structure (`Services/`, `Models/`, `Views/`).
- `AppConfig` model: Selene base URL (LAN IP:5678) + bearer token.
- `redeploy.sh` that builds and installs to the connected device via `xcrun devicectl`, mirroring SeleneChat's `build-app.sh` ergonomic.
- **Gate:** app launches on the device and survives a re-sign cycle.

### Task B2: `WorksheetService` (logic unit-testable in the iOS Simulator)
- `fetchToday()` → GET `/api/worksheets/today`, decode `Worksheet`.
- `submit(_:)` → POST `/api/worksheets/:id/answers`, decode `SubmissionResult`.
- Bearer auth header from `AppConfig`. Model on the archived `RemoteDataService` (reuse, don't reinvent).
- **Unit tests (run in the iOS Simulator, not a Mac binary — iPadOS-target):** JSON decode of a sample `Worksheet`, JSON encode of a `WorksheetSubmission`, auth header presence, error mapping. These mirror the contract in `src/types/worksheets.ts` — keep them in sync.

### Task B3: Capture + OCR + verify (on-device only)
- `WorksheetView`: render the single `free_capture` prompt + one `PKCanvasView`.
- `HandwritingService`: render `PKDrawing` to an image, run `VNRecognizeTextRequest`, return text.
- `ReviewSheet`: show OCR text, allow edit, confirm → `WorksheetService.submit`.
- Local draft persistence so handwriting survives an offline/Mac-asleep submit failure (retry later).
- **Gate (the whole point of Phase 0):** write a handful of *real* notes by hand; confirm OCR accuracy is good enough on your actual handwriting. If it isn't, this is where we learn it — before Phase 1 — and reconsider (server-side OCR fallback, or accept correction friction).

### Task B4: Phase 0 demo + decision
- Do a real freeform capture on the iPad; confirm the note lands in Selene and flows through `process-llm`.
- **Decision gate:** does handwriting capture feel good and is OCR trustworthy? If yes → proceed to Phase 1 (structured `note_review` worksheet). If no → revisit OCR strategy in the design doc before investing in bindings.

---

## Out of scope for Phase 0 (deferred to Phase 1+)

- `note_review` field kind, action chips, per-field boxes, binding to existing notes.
- `archive` / `follow_up` / `keep` actions, `connections` linking.
- `last_reviewed_at` review-tracking marker and the "notes needing review" query.
- Full idempotency / consumed-worksheet marker (Phase 0 leans on `ingest()`'s content-hash dedup).
- The other three worksheet generators (Q&A, task-breakdown, weekly).
- User guide (`docs/guides/features/`) — add when there's a user-facing feature to document (Phase 1).
```
