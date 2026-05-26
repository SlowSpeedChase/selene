# Phase 1: Structured Worksheets + Related-Notes Response

**Status:** Ready
**Date:** 2026-05-26

---

## Summary

Extend the interactive worksheets feature in two directions:

1. **Structured multi-field worksheets** — the server returns multiple fields (freeform handwriting sections + note-review cards). The iPad renders them as a scrollable form.
2. **Related-notes response** — after submission, the server embeds each answer with `nomic-embed-text`, searches LanceDB for similar past notes, and returns the top matches. The iPad surfaces them in a post-submit sheet ("Selene remembers…").

All LLM processing stays on the Mac (Ollama). The M4 Neural Engine is capable of on-device embeddings, but the existing notes are already indexed in nomic-embed-text's 768-dim space — switching embedding models would require a full re-index with no practical benefit while the Mac is always available.

---

## Data Contract

### GET /api/worksheets/today — response

```typescript
interface Worksheet {
  id: string
  title: string
  fields: WorksheetField[]
}

interface WorksheetField {
  id: string
  kind: 'free_capture' | 'note_review'
  prompt: string
  notes?: ReviewNote[]        // only on note_review fields
  binding: { action: string } // 'new_note' | 'acknowledge'
}

interface ReviewNote {
  id: number
  title: string
  snippet: string
  date: string
}
```

### POST /api/worksheets/:id/answers — request (unchanged)

```typescript
interface WorksheetSubmission {
  worksheetId: string
  answers: WorksheetAnswer[]
}

interface WorksheetAnswer {
  fieldId: string
  chosenAction: string   // 'new_note' | 'acknowledge'
  text: string           // OCR text for free_capture; '' for acknowledge
}
```

### POST /api/worksheets/:id/answers — response (enriched)

```typescript
interface SubmissionResult {
  worksheetId: string
  results: AnswerResult[]
  relatedNotes: RelatedNotesGroup[]   // empty array if Ollama unavailable
}

interface RelatedNotesGroup {
  fieldId: string
  matches: RelatedNote[]
}

interface RelatedNote {
  noteId: number
  title: string
  snippet: string
  date: string
  score: number
}
```

---

## Server Changes (Track A — TypeScript)

### src/types/worksheets.ts
- Add `ReviewNote`, `RelatedNote`, `RelatedNotesGroup`
- Add `notes?: ReviewNote[]` to `WorksheetField`
- Add `relatedNotes: RelatedNotesGroup[]` to `SubmissionResult`

### src/workflows/generate-worksheet.ts — `buildTodayWorksheet`
- Always return two `free_capture` fields ("What's on your mind right now?", "One thing to get done today?")
- Query SQLite for notes not surfaced in the last 14 days, ordered by age; take top 3
- If any exist, append a `note_review` field with those notes
- If none, worksheet has only the two freeform fields

### src/workflows/generate-worksheet.ts — `applyWorksheetAnswers`
- After all `createNote` calls complete, run embed+search for each `free_capture` answer sequentially (not parallel, to avoid Ollama contention)
- For each: `embed(text)` → `vectorSearch(limit: 5)` → filter the just-created noteId → take top 3
- Catch any Ollama/LanceDB error → log warning, return `relatedNotes: []`
- Total added latency: ~600ms for two fields

---

## iPad Changes (Track B — Swift)

### Models
- `WorksheetField` gains `notes: [ReviewNote]?`
- `ReviewNote: Codable` — id, title, snippet, date
- `SubmissionResult` gains `relatedNotes: [RelatedNotesGroup]?`
- `RelatedNotesGroup: Codable` — fieldId, matches
- `RelatedNote: Codable` — noteId, title, snippet, date, score

### WorksheetView / WorksheetViewModel
- Render fields dynamically: `free_capture` → labeled `CanvasView` (fixed ~200pt height, `isScrollEnabled = false`); `note_review` → read-only note cards
- Outer `ScrollView` (finger scrolls); `.pencilOnly` canvases draw with pencil
- Submit button: OCR all canvases in order, build `WorksheetSubmission`, POST once
- On success: if `relatedNotes` has any matches → show `RelatedNotesSheet`; otherwise show existing toast

### RelatedNotesSheet (new view)
- Presented as a sheet after successful submit
- Groups matches by field prompt ("From 'What's on your mind?'")
- Each match: title, date chip, snippet (two lines)
- "Done" button dismisses; no action required

### CanvasView
- Add `isScrollEnabled = false` to `ToolPickerCanvas` so it doesn't fight the enclosing `ScrollView`

---

## Acceptance Criteria

- [ ] Worksheet with two freeform fields renders as scrollable form; finger scrolls, pencil draws in each canvas
- [ ] `note_review` field shows read-only cards when server includes backlog notes
- [ ] Submit OCRs all canvases and sends one POST
- [ ] Related-notes sheet appears after submit when Ollama finds matches
- [ ] Related-notes sheet is skipped (toast only) when `relatedNotes` is empty
- [ ] Ollama outage degrades gracefully — note still saved, no crash, no visible error beyond missing context

---

## ADHD Design Check

- Structured prompts reduce blank-page paralysis
- Note-review cards surface forgotten items automatically — no need to remember to check
- "Selene remembers…" sheet closes the cognitive loop: write a thought, immediately see your own history around it
- Graceful Ollama degradation means the capture ritual never fails even if context is missing
