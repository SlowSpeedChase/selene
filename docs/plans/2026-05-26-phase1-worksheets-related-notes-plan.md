# Phase 1 Worksheets + Related-Notes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the worksheet feature with structured multi-field forms and a post-submit "Selene remembers…" panel that surfaces semantically similar past notes.

**Architecture:** Two parallel tracks sharing a JSON contract. Track A (TypeScript, `selene/.worktrees/interactive-worksheets`) extends the server types, worksheet builder, and answer handler. Track B (Swift, `~/SeleneMarkup`) replaces the single-canvas view with a multi-field scrollable form and adds a `RelatedNotesSheet`. All LLM work (embed + vector search) stays on the Mac via the existing `ollama.embed` + `searchSimilarNotes` pipeline.

**Tech Stack:** TypeScript + Vitest + better-sqlite3 + @lancedb/lancedb + Ollama (Track A); Swift + SwiftUI + PencilKit + Vision (Track B); XcodeGen for `.xcodeproj` generation.

**Working directories:**
- Track A: `/Users/chaseeasterling/selene/.worktrees/interactive-worksheets/`
- Track B: `/Users/chaseeasterling/SeleneMarkup/`

---

## Task A1: Extend TypeScript types

**Files:**
- Modify: `src/types/worksheets.ts`

### Step 1: Replace the file contents

```typescript
export type WorksheetFieldKind = 'free_capture' | 'note_review';

export interface ReviewNote {
  id: number;
  title: string;
  snippet: string;
  date: string;  // ISO date string YYYY-MM-DD
}

export interface WorksheetField {
  id: string;
  kind: WorksheetFieldKind;
  prompt: string;
  notes?: ReviewNote[];                      // only on note_review fields
  binding: { action: 'new_note' | 'acknowledge' };
}

export interface Worksheet {
  id: string;
  title: string;
  fields: WorksheetField[];
}

export type ChosenAction = 'new_note' | 'acknowledge';

export interface WorksheetAnswer {
  fieldId: string;
  chosenAction: ChosenAction;
  text: string;
}

export interface WorksheetSubmission {
  worksheetId: string;
  answers: WorksheetAnswer[];
}

export type AnswerOutcome = 'applied' | 'skipped' | 'failed' | 'acknowledged';

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
  score: number;    // cosine similarity 0–1 (derived from L2 distance)
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

### Step 2: Verify TypeScript compiles

```bash
cd /Users/chaseeasterling/selene/.worktrees/interactive-worksheets
npx tsc --noEmit
```

Expected: no errors.

### Step 3: Commit

```bash
git add src/types/worksheets.ts
git commit -m "feat(worksheets): extend types for note_review, acknowledge, relatedNotes"
```

---

## Task A2: Extend generate-worksheet.ts

**Files:**
- Modify: `src/workflows/generate-worksheet.ts`
- Modify: `src/workflows/generate-worksheet.test.ts`

### Step 1: Write the failing tests first

Replace `src/workflows/generate-worksheet.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { buildTodayWorksheet, applyWorksheetAnswers } from './generate-worksheet';
import type { WorksheetSubmission, ReviewNote } from '../types/worksheets';

// ---------------------------------------------------------------------------
// buildTodayWorksheet
// ---------------------------------------------------------------------------

describe('buildTodayWorksheet', () => {
  it('always includes two free_capture fields', async () => {
    const ws = await buildTodayWorksheet(new Date('2026-05-26T09:00:00'));
    const captureFields = ws.fields.filter(f => f.kind === 'free_capture');
    expect(captureFields).toHaveLength(2);
    expect(captureFields[0].binding).toEqual({ action: 'new_note' });
    expect(captureFields[1].binding).toEqual({ action: 'new_note' });
    expect(ws.id).toBe('ws_2026-05-26');
    expect(ws.title).toContain('2026-05-26');
  });

  it('appends a note_review field when fetchReviewNotes returns notes', async () => {
    const reviewNotes: ReviewNote[] = [
      { id: 1, title: 'dentist', snippet: 'keep forgetting', date: '2026-04-03' },
    ];
    const ws = await buildTodayWorksheet(
      new Date('2026-05-26T09:00:00'),
      { fetchReviewNotes: async () => reviewNotes },
    );
    const reviewField = ws.fields.find(f => f.kind === 'note_review');
    expect(reviewField).toBeDefined();
    expect(reviewField!.notes).toEqual(reviewNotes);
    expect(reviewField!.binding).toEqual({ action: 'acknowledge' });
  });

  it('omits note_review field when fetchReviewNotes returns empty', async () => {
    const ws = await buildTodayWorksheet(
      new Date('2026-05-26T09:00:00'),
      { fetchReviewNotes: async () => [] },
    );
    expect(ws.fields.every(f => f.kind !== 'note_review')).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// applyWorksheetAnswers
// ---------------------------------------------------------------------------

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
        { fieldId: 'f2', chosenAction: 'new_note', text: '   ' },
      ],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(created).toEqual(['Book conference travel']);
    expect(result.results[0]).toEqual({ fieldId: 'f1', outcome: 'applied', noteId: 1 });
    expect(result.results[1]).toEqual({ fieldId: 'f2', outcome: 'skipped', reason: 'empty' });
    expect(result.relatedNotes).toEqual([]);
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

  it('records acknowledged outcome for acknowledge answers', async () => {
    const deps = { createNote: async () => 1 };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f3', chosenAction: 'acknowledge', text: '' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.results[0]).toEqual({ fieldId: 'f3', outcome: 'acknowledged' });
  });

  it('calls findRelatedNotes for each applied new_note answer', async () => {
    const related = [{ noteId: 99, title: 'dentist', snippet: 'keep forgetting', date: '2026-04-03', score: 0.92 }];
    const findRelatedNotes = async () => related;
    const deps = {
      createNote: async () => 42,
      findRelatedNotes,
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f1', chosenAction: 'new_note', text: 'dentist again' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.relatedNotes).toEqual([
      { fieldId: 'f1', matches: related },
    ]);
  });

  it('returns empty relatedNotes when findRelatedNotes throws', async () => {
    const deps = {
      createNote: async () => 42,
      findRelatedNotes: async () => { throw new Error('ollama down'); },
    };
    const submission: WorksheetSubmission = {
      worksheetId: 'ws_x',
      answers: [{ fieldId: 'f1', chosenAction: 'new_note', text: 'something' }],
    };

    const result = await applyWorksheetAnswers(submission, deps);

    expect(result.results[0].outcome).toBe('applied');
    expect(result.relatedNotes).toEqual([]);
  });
});
```

### Step 2: Run tests to confirm they fail

```bash
cd /Users/chaseeasterling/selene/.worktrees/interactive-worksheets
npx vitest run src/workflows/generate-worksheet.test.ts
```

Expected: multiple failures (functions don't match new signatures yet).

### Step 3: Rewrite generate-worksheet.ts

```typescript
import type {
  Worksheet,
  WorksheetSubmission,
  SubmissionResult,
  AnswerResult,
  RelatedNote,
  RelatedNotesGroup,
  ReviewNote,
} from '../types/worksheets';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'generate-worksheet' });

// ---------------------------------------------------------------------------
// buildTodayWorksheet
// ---------------------------------------------------------------------------

export interface BuildDeps {
  fetchReviewNotes: () => Promise<ReviewNote[]>;
}

const defaultBuildDeps: BuildDeps = {
  fetchReviewNotes: async () => [],
};

export async function buildTodayWorksheet(
  now: Date = new Date(),
  deps: BuildDeps = defaultBuildDeps,
): Promise<Worksheet> {
  const date = now.toISOString().slice(0, 10);
  const reviewNotes = await deps.fetchReviewNotes();

  const fields: Worksheet['fields'] = [
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
  ];

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

// ---------------------------------------------------------------------------
// applyWorksheetAnswers
// ---------------------------------------------------------------------------

export interface ApplyDeps {
  createNote: (text: string) => Promise<number>;
  findRelatedNotes?: (text: string, excludeId: number) => Promise<RelatedNote[]>;
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
        if (matches.length > 0) {
          relatedNotes.push({ fieldId: answer.fieldId, matches });
        }
      } catch (err) {
        log.warn({ err, fieldId: answer.fieldId }, 'findRelatedNotes failed — skipping context');
      }
    }
  }

  return { worksheetId: submission.worksheetId, results, relatedNotes };
}
```

### Step 4: Run tests — expect all pass

```bash
npx vitest run src/workflows/generate-worksheet.test.ts
```

Expected: 7 tests passing.

### Step 5: Commit

```bash
git add src/workflows/generate-worksheet.ts src/workflows/generate-worksheet.test.ts
git commit -m "feat(worksheets): multi-field builder + relatedNotes in apply"
```

---

## Task A3: Wire route with DB + Ollama deps

**Files:**
- Modify: `src/routes/worksheets.ts`

The route needs two new dep implementations:
- `fetchReviewNotes`: SQL query for oldest pending notes (excluding test data)
- `findRelatedNotes`: embed text → searchSimilarNotes → map to RelatedNote

### Step 1: Replace src/routes/worksheets.ts

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
import { db } from '../lib/db';
import { logger } from '../lib/logger';
import type { WorksheetSubmission, ReviewNote, RelatedNote } from '../types/worksheets';

const log = logger.child({ module: 'worksheets-route' });

function fetchReviewNotes(): Promise<ReviewNote[]> {
  const rows = db.prepare(`
    SELECT id, title, content, created_at
    FROM raw_notes
    WHERE inbox_status = 'pending'
      AND test_run IS NULL
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

async function findRelatedNotes(text: string, excludeId: number): Promise<RelatedNote[]> {
  const vector = await embed(text);
  const similar = await searchSimilarNotes(vector, {
    limit: 3,
    excludeIds: [excludeId],
    maxDistance: 1.0,
  });

  // Convert L2 distance to a 0-1 score (closer = higher score).
  // nomic-embed-text produces unit vectors, so L2 distance ≈ sqrt(2*(1-cosine)).
  // score = max(0, 1 - distance/2) gives an intuitive 0–1 range.
  return similar.map(s => {
    const snippet = (db.prepare('SELECT content FROM raw_notes WHERE id = ?').get(s.id) as { content: string } | undefined)
      ?.content.slice(0, 120).trimEnd() ?? '';
    const dateRow = db.prepare('SELECT created_at FROM raw_notes WHERE id = ?').get(s.id) as { created_at: string } | undefined;
    return {
      noteId: s.id,
      title: s.title,
      snippet,
      date: dateRow?.created_at.slice(0, 10) ?? '',
      score: Math.max(0, 1 - s.distance / 2),
    };
  });
}

export async function worksheetRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.get('/api/worksheets/today', { preHandler: requireAuth }, async () => {
    return buildTodayWorksheet(new Date(), { fetchReviewNotes });
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
            return (res.id ?? res.existingId) as number;
          },
          findRelatedNotes: body.test_run
            ? undefined   // skip Ollama during test runs
            : async (text, excludeId) => {
                try {
                  return await findRelatedNotes(text, excludeId);
                } catch (err) {
                  log.warn({ err }, 'findRelatedNotes failed in route — returning empty');
                  return [];
                }
              },
        },
      );
    },
  );
}
```

### Step 2: Verify TypeScript compiles

```bash
npx tsc --noEmit
```

Expected: no errors.

### Step 3: Smoke test — restart dev server and call the endpoint

```bash
# Kill existing dev server if running
pkill -f "ts-node src/server" || true
sleep 1
SELENE_ENV=development npx ts-node src/server.ts &
sleep 3
curl -s http://localhost:5679/api/worksheets/today | python3 -m json.tool
```

Expected: JSON with two `free_capture` fields plus optionally a `note_review` field.

```bash
# Test submit with related-notes
curl -s -X POST http://localhost:5679/api/worksheets/ws_2026-05-26/answers \
  -H "Content-Type: application/json" \
  -d '{"worksheetId":"ws_2026-05-26","answers":[{"fieldId":"f1","chosenAction":"new_note","text":"need to book dentist test_run_a3_smoke"}],"test_run":"test_a3_smoke"}' \
  | python3 -m json.tool
```

Expected: `results[0].outcome = "applied"`, `relatedNotes = []` (test_run skips Ollama).

```bash
# Cleanup
./scripts/cleanup-tests.sh test_a3_smoke
```

### Step 4: Commit

```bash
git add src/routes/worksheets.ts
git commit -m "feat(worksheets): wire DB + Ollama deps into route handler"
```

---

## Task B1: Extend Swift models

**Files:**
- Modify: `Sources/SeleneMarkup/Models/Worksheet.swift`

### Step 1: Replace Worksheet.swift

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
    let kind: String          // "free_capture" | "note_review"
    let prompt: String
    let notes: [ReviewNote]?  // only present on note_review fields
    let binding: FieldBinding

    struct FieldBinding: Codable {
        let action: String    // "new_note" | "acknowledge"
    }
}

struct ReviewNote: Codable {
    let id: Int
    let title: String
    let snippet: String
    let date: String
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
    let chosenAction: String  // "new_note" | "acknowledge"
    let text: String
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
    let outcome: String       // "applied" | "skipped" | "failed" | "acknowledged"
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

### Step 2: Update WorksheetServiceTests to match new SubmissionResult shape

In `Tests/SeleneMarkupTests/WorksheetServiceTests.swift`, update `sampleResultJSON`:

```swift
private let sampleResultJSON = """
{
    "worksheetId": "ws_2026-05-26",
    "results": [{"fieldId": "f1", "outcome": "applied", "noteId": 42}],
    "relatedNotes": []
}
"""
```

### Step 3: Build to verify

```bash
cd /Users/chaseeasterling/SeleneMarkup
xcodegen generate
xcodebuild -scheme SeleneMarkup -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Run tests

```bash
xcodebuild test -scheme SeleneMarkup \
  -destination "platform=iOS Simulator,id=4D03DBBC-CD21-4AF5-86F3-70FB7F873F28" \
  2>&1 | grep -E "(Test Case|passed|failed|BUILD)"
```

Expected: 6 tests passing.

### Step 5: Commit

```bash
cd /Users/chaseeasterling/SeleneMarkup
git add Sources/SeleneMarkup/Models/Worksheet.swift \
        Tests/SeleneMarkupTests/WorksheetServiceTests.swift
git commit -m "feat(B1): extend models for multi-field worksheets and relatedNotes"
```

---

## Task B2: Rebuild WorksheetView for multi-field form

**Files:**
- Modify: `Sources/SeleneMarkup/Views/CanvasView.swift` (add `isScrollEnabled = false`)
- Modify: `Sources/SeleneMarkup/Views/WorksheetView.swift` (full rewrite)

### Step 1: Add isScrollEnabled = false to CanvasView

In `CanvasView.swift`, update `makeUIView`:

```swift
func makeUIView(context: Context) -> ToolPickerCanvas {
    let canvas = ToolPickerCanvas()
    #if targetEnvironment(simulator)
    canvas.drawingPolicy = .anyInput
    #else
    canvas.drawingPolicy = .pencilOnly
    #endif
    canvas.isScrollEnabled = false   // parent ScrollView handles scrolling
    canvas.backgroundColor = .white
    canvas.delegate = context.coordinator
    return canvas
}
```

### Step 2: Rewrite WorksheetView.swift

```swift
import SwiftUI
import PencilKit

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@MainActor
final class WorksheetViewModel: ObservableObject {
    @Published var worksheet: Worksheet?
    @Published var drawings: [String: PKDrawing] = [:]   // keyed by fieldId
    @Published var isLoading = true
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var relatedNotes: [RelatedNotesGroup] = []
    @Published var showRelatedNotes = false

    private let service: WorksheetService
    private let ocr = HandwritingService()

    init(service: WorksheetService = WorksheetService()) {
        self.service = service
    }

    func fetchToday() async {
        isLoading = true
        errorMessage = nil
        do {
            let ws = try await service.fetchToday()
            worksheet = ws
            for field in ws.fields where field.kind == "free_capture" {
                drawings[field.id] = PKDrawing()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func submitAll(canvasSizes: [String: CGSize]) {
        guard let ws = worksheet else { return }
        isBusy = true
        errorMessage = nil
        Task {
            var answers: [WorksheetAnswer] = []
            for field in ws.fields {
                if field.kind == "free_capture" {
                    let text = await ocrText(for: field.id, canvasSizes: canvasSizes)
                    answers.append(WorksheetAnswer(
                        fieldId: field.id,
                        chosenAction: field.binding.action,
                        text: text
                    ))
                } else {
                    answers.append(WorksheetAnswer(
                        fieldId: field.id,
                        chosenAction: field.binding.action,
                        text: ""
                    ))
                }
            }
            let submission = WorksheetSubmission(worksheetId: ws.id, answers: answers)
            do {
                let result = try await service.submit(submission)
                for key in drawings.keys { drawings[key] = PKDrawing() }
                let groups = result.relatedNotes?.filter { !$0.matches.isEmpty } ?? []
                if !groups.isEmpty {
                    relatedNotes = groups
                    showRelatedNotes = true
                }
            } catch {
                errorMessage = "Submit failed — \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    private func ocrText(for fieldId: String, canvasSizes: [String: CGSize]) async -> String {
        guard let drawing = drawings[fieldId],
              !drawing.strokes.isEmpty,
              let size = canvasSizes[fieldId] else { return "" }
        let bounds = CGRect(origin: .zero, size: size)
        let image = drawing.image(from: bounds, scale: UIScreen.main.scale)
        return (try? await ocr.recognize(image)) ?? ""
    }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

struct WorksheetView: View {
    @StateObject private var vm = WorksheetViewModel()
    @State private var canvasSizes: [String: CGSize] = [:]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(vm.worksheet?.title ?? "Daily Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Submit") { vm.submitAll(canvasSizes: canvasSizes) }
                            .disabled(vm.isBusy || vm.worksheet == nil)
                    }
                }
                .sheet(isPresented: $vm.showRelatedNotes) {
                    if let ws = vm.worksheet {
                        RelatedNotesSheet(
                            groups: vm.relatedNotes,
                            worksheet: ws,
                            onDone: { vm.showRelatedNotes = false }
                        )
                        .presentationDetents([.medium, .large])
                    }
                }
                .task { await vm.fetchToday() }
        }
        .overlay(busyOverlay)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading worksheet…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let ws = vm.worksheet {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(ws.fields, id: \.id) { field in
                        fieldView(field)
                    }
                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        } else if let err = vm.errorMessage {
            errorView(err)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: WorksheetField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.prompt)
                .font(.headline)

            if field.kind == "free_capture" {
                GeometryReader { geo in
                    CanvasView(drawing: Binding(
                        get: { vm.drawings[field.id] ?? PKDrawing() },
                        set: { vm.drawings[field.id] = $0 }
                    ))
                    .onAppear { canvasSizes[field.id] = geo.size }
                    .onChange(of: geo.size) { canvasSizes[field.id] = $1 }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.separator, lineWidth: 1))
            } else if field.kind == "note_review", let notes = field.notes {
                ForEach(notes, id: \.id) { note in
                    NoteReviewCard(note: note)
                }
            }
        }
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if vm.isBusy {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .overlay(ProgressView().tint(.white))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.fetchToday() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ---------------------------------------------------------------------------
// NoteReviewCard
// ---------------------------------------------------------------------------

struct NoteReviewCard: View {
    let note: ReviewNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title).font(.subheadline).bold()
                Spacer()
                Text(shortDate(note.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }
}
```

### Step 3: Build to verify

```bash
cd /Users/chaseeasterling/SeleneMarkup
xcodegen generate
xcodebuild -scheme SeleneMarkup -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit

```bash
git add Sources/SeleneMarkup/Views/CanvasView.swift \
        Sources/SeleneMarkup/Views/WorksheetView.swift
git commit -m "feat(B2): multi-field scrollable worksheet form"
```

---

## Task B3: Add RelatedNotesSheet

**Files:**
- Create: `Sources/SeleneMarkup/Views/RelatedNotesSheet.swift`

### Step 1: Write RelatedNotesSheet.swift

```swift
import SwiftUI

struct RelatedNotesSheet: View {
    let groups: [RelatedNotesGroup]
    let worksheet: Worksheet
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.fieldId) { group in
                    Section(header: Text(promptFor(group.fieldId))) {
                        ForEach(group.matches, id: \.noteId) { match in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(match.title)
                                        .font(.subheadline)
                                        .bold()
                                    Spacer()
                                    Text(shortDate(match.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(match.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Selene remembers…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func promptFor(_ fieldId: String) -> String {
        worksheet.fields.first(where: { $0.id == fieldId })?.prompt ?? fieldId
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }
}
```

### Step 2: Delete ReviewSheet.swift (no longer used)

The `ReviewSheet.swift` (per-field OCR review) is replaced by the direct-submit flow. Delete it:

```bash
cd /Users/chaseeasterling/SeleneMarkup
rm Sources/SeleneMarkup/Views/ReviewSheet.swift
```

### Step 3: Build

```bash
xcodegen generate
xcodebuild -scheme SeleneMarkup -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Run full test suite

```bash
xcodebuild test -scheme SeleneMarkup \
  -destination "platform=iOS Simulator,id=4D03DBBC-CD21-4AF5-86F3-70FB7F873F28" \
  2>&1 | grep -E "(Test Case|passed|failed|BUILD)"
```

Expected: 6 tests passing.

### Step 5: Commit

```bash
git add Sources/SeleneMarkup/Views/RelatedNotesSheet.swift
git rm Sources/SeleneMarkup/Views/ReviewSheet.swift
git commit -m "feat(B3): RelatedNotesSheet replaces per-field ReviewSheet"
```

---

## Task B4: Deploy and end-to-end smoke test

### Step 1: Ensure dev server is running with worksheet routes

```bash
curl -s http://localhost:5679/api/worksheets/today | python3 -m json.tool
```

If not running:

```bash
cd /Users/chaseeasterling/selene/.worktrees/interactive-worksheets
SELENE_ENV=development npx ts-node src/server.ts &
sleep 3
```

### Step 2: Deploy to iPad

```bash
cd /Users/chaseeasterling/SeleneMarkup
./redeploy.sh
```

### Step 3: Manual end-to-end test on device

1. Open Selene app — should show two handwriting fields + optionally a note review card
2. Write in both free_capture fields with Apple Pencil
3. Tap **Submit**
4. If Ollama has past embeddings: "Selene remembers…" sheet appears with matches
5. Tap **Done** — form clears

### Step 4: Verify notes landed in DB

```bash
sqlite3 /Users/chaseeasterling/selene-data-dev/selene.db \
  "SELECT id, title, content FROM raw_notes ORDER BY id DESC LIMIT 5;"
```

Expected: two new "Worksheet capture" rows.

### Step 5: Final Track A commit in feature worktree

```bash
cd /Users/chaseeasterling/selene/.worktrees/interactive-worksheets
git add -A
git status  # confirm nothing unexpected
git commit -m "feat(worksheets): Phase 1 complete — structured form + related-notes"
```

### Step 6: Final Track B commit

```bash
cd /Users/chaseeasterling/SeleneMarkup
git add -A
git commit -m "feat(B4): Phase 1 deploy — multi-field form + Selene remembers panel"
```

---

## Acceptance Criteria Checklist

- [ ] `buildTodayWorksheet` returns two `free_capture` fields + optional `note_review`
- [ ] `note_review` field shows when DB has `inbox_status = 'pending'` notes older than 1 day
- [ ] Submit OCRs all canvases and sends one POST
- [ ] `relatedNotes` populated when Ollama finds matches; empty array when unavailable
- [ ] "Selene remembers…" sheet appears only when `relatedNotes` is non-empty
- [ ] Sheet skipped and form clears silently when no matches
- [ ] Ollama outage → note still saved, no crash, no error shown to user
- [ ] All 6 Swift unit tests passing
- [ ] All 7 Vitest tests passing
