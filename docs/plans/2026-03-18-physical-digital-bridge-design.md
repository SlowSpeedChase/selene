# Physical <-> Digital Bridge

**Status:** Ready
**Created:** 2026-03-18
**Area:** Capture / Output
**ADHD Check:** Passed
**Scope Check:** Passed

---

## Problem

Selene externalizes working memory digitally, but thinking still happens physically — on whiteboards during planning sessions, on paper during capture moments. These two layers don't talk to each other, which creates a leak: information captured physically gets re-typed manually into Drafts (friction), forgotten (context rot), or lives in a parallel system that Selene can't see.

The reverse is also broken. Selene generates rich digests, thread summaries, and morning briefings — but consuming them on a screen during analog work sessions creates a context-switching cost. There's no way to "print Selene's brain" into a physical artifact that supports annotation.

---

## Goal

Close the loop between physical and digital so that:

- Anything captured on a whiteboard or paper can enter Selene in under 30 seconds with no manual re-typing
- Selene's synthesized outputs can be rendered as physical artifacts (daily planning sheet) that support annotation and carry information back into the digital layer
- Annotated daily sheets feed back into Selene, creating a full closed loop

---

## Architecture

### Two Pipelines

```
PHYSICAL -> DIGITAL (Capture Pipeline)
--------------------------------------------------------------
[Whiteboard photo]  --+
[Paper note scan]   --+-> Claude Vision (Haiku 3.5) -> structured markdown
[Annotated sheet]   --+   -> POST /webhook/api/drafts
                              |
                         Existing Tier 1-2 pipeline
                    (ingest -> process-llm -> extract-tasks)

DIGITAL -> PHYSICAL (Output Pipeline)
--------------------------------------------------------------
[Tasks]             --+
[Active threads]    --+-> HTML template -> Puppeteer -> PDF
[Recent captures]   --+   -> ~/selene-data/daily-sheets/
                           -> optional auto-print via `lp`
```

---

## Capture Pipeline

### iOS Shortcut: "Capture to Selene"

**Two entry points, one Shortcut:**
- **Widget/lock screen tap** -> opens camera -> snap photo
- **Share Sheet** from Photos -> runs on existing image

**Flow:**
1. Receive or capture image
2. Convert image to base64
3. Call Claude API (Haiku 3.5) with vision prompt:
   > "Interpret this handwritten note or whiteboard. Preserve spatial groupings, arrows, and relationships. Output structured markdown. If you see a QR code containing a date, note this is an annotated daily planning sheet — extract only the handwritten annotations, not the printed content."
4. Receive structured markdown
5. POST to `https://{tailscale-ip}:5678/webhook/api/drafts` with:
   ```json
   {
     "title": "Whiteboard - 2026-03-18",
     "content": "{claude_markdown}",
     "capture_type": "whiteboard",
     "source_image_ref": "{photo_id}"
   }
   ```
6. Show banner: "Captured" / "Failed"

**Daily sheet annotation variant:**
- Same Shortcut, but Claude detects the QR code date
- Sets `capture_type: "daily_sheet_annotation"` instead
- Title becomes "Daily Sheet Annotations - 2026-03-18"

**Offline fallback:**
- If Claude API unreachable, fall back to Apple Vision "Recognize Text in Image"
- POST with `capture_type: "whiteboard_ocr"` and `low_confidence: true`

### Why Claude Vision over Apple Vision OCR

The user's handwriting is typically messy with spatial meaning — abbreviations, arrows, groupings. Apple Vision extracts text but flattens spatial relationships into a linear stream. Claude Vision interprets the layout: "these three items are grouped under a header with an arrow pointing to a question mark."

**Cost:** ~$0.006/capture with Haiku 3.5. At 10 captures/day, under $2/month.

Apple Vision remains the offline fallback, not the primary path.

---

## Schema Migration

```sql
-- Migration 021
ALTER TABLE raw_notes ADD COLUMN capture_type TEXT DEFAULT 'drafts';
-- Values: 'drafts' | 'whiteboard' | 'whiteboard_ocr' | 'scanner'
--       | 'voice' | 'daily_sheet_annotation'
```

Backfill: existing notes stay `'drafts'`, voice memos get updated to `'voice'`.

---

## Routing: `extract-tasks.ts` Changes

`capture_type` adds lightweight prompt hints to the existing classification pipeline. No new workflow needed.

**`whiteboard` captures:**
- Bias toward `needs_planning` classification (whiteboards are thinking, not todos)
- Prepend context to LLM classification prompt: "This was captured from a whiteboard — prioritize identifying themes and planning intent over individual tasks"
- If structured task-like items exist, still extract them

**`daily_sheet_annotation` captures:**
- Treat as high-signal feedback on Selene's own output
- Link back to thread/task context from that day's sheet (QR date enables this)
- Route completions -> update task status
- Route new thoughts -> standard ingestion

**All other `capture_type` values:**
- No behavior change — existing pipeline handles them

---

## Output Pipeline: Daily Planning Sheet

### `render-daily-sheet.ts`

**Trigger:** Daily at 5:30am via launchd (before the 6am digest)

**Data sources** (same SQLite queries used by `daily-summary.ts` and morning briefing):
- Active tasks from `extracted_tasks` (not completed)
- Active threads with momentum scores from `threads`
- Notes ingested in the last 24 hours from `raw_notes`

**Layout (single page, letter/A4):**

```
+---------------------------------------------+
|  SELENE . 2026-03-18            [QR: date]  |
+---------------------------------------------+
|                                             |
|  TASKS                          O Task 1    |
|                                 O Task 2    |
|                                 O Task 3    |
|                                 O Task 4    |
|                                             |
+---------------------------------------------+
|                                             |
|  THREADS                    ^ Thread A (up) |
|   Summary line...           . Thread B (-)  |
|   Summary line...           v Thread C (dn) |
|                                             |
+---------------------------------------------+
|                                             |
|  RECENT CAPTURES                            |
|   . Note title (yesterday 2pm)              |
|   . Note title (yesterday 6pm)              |
|                                             |
+---------------------------------------------+
|                                             |
|  SCRATCH                                    |
|                                             |
|                            (~40% of page)   |
|                                             |
|                                             |
+---------------------------------------------+
```

**Design details:**
- **QR code** in top-right encodes `selene-daily:2026-03-18` — Shortcut reads this to identify annotated sheets
- **Task circles** are large enough for pen checkmarks
- **Thread momentum** shown as arrows: rising / stable / cooling — readable at arm's length
- **Scratch zone** takes ~40% of the page — generous space for messy annotation
- Minimal ink — prints cleanly in black and white
- Works at three scales: printed letter/A4, iPad screen, wall-pinned

**Tech:**
- HTML template in `src/templates/daily-sheet.html`
- Puppeteer renders to PDF
- Output: `~/selene-data/daily-sheets/selene-daily-{date}.pdf`
- Optional: auto-print via `lp` command (configurable in `.env`)

**New launchd agent:**
```
launchd/com.selene.render-daily-sheet.plist   # Daily at 5:30am
```

---

## Annotation Loop (Closed Loop)

The daily sheet becomes a capture surface. This is what closes the full loop.

### Flow

```
5:30am  render-daily-sheet.ts -> PDF
        |
        Print / open on iPad
        |
        Work through the day, annotating:
          - Check off tasks with pen
          - Scribble new ideas in scratch zone
          - Draw arrows between threads
          - Add notes next to thread summaries
        |
        End of session: photograph the sheet
        |
        iOS Shortcut fires -> Claude Vision
        |
        Claude sees QR code -> "selene-daily:2026-03-18"
        |
        Structured output separates:
          - Completed tasks (checked circles)
          - New annotations (scratch zone content)
          - Thread annotations (notes next to thread summaries)
        |
        POST to webhook with capture_type: "daily_sheet_annotation"
        |
        extract-tasks.ts routes:
          - Completed tasks -> update status
          - New thoughts -> standard ingestion
          - Thread annotations -> link to that thread
```

### Claude Vision Prompt (annotated sheets)

Claude can visually diff printed content from handwritten annotations because:
- Printed content is clean, consistent font
- Handwriting is visually distinct
- The QR date tells Claude which sheet to expect

Prompt:
> "This is a photographed Selene daily planning sheet. The printed content is the system's output — ignore it. Extract ONLY the handwritten annotations: checked-off tasks, new notes in the scratch zone, and any writing next to thread summaries. Return structured JSON with sections: `completed_tasks`, `new_notes`, `thread_annotations`."

### What this is NOT

- No computer vision diffing between original PDF and photo — Claude handles this visually
- No annotation tracking over multiple photos of the same sheet — one capture per sheet
- No real-time sync — this is an end-of-session ritual, not continuous

---

## AI vs. Deterministic Decision Matrix

| Step | Approach | Rationale |
|------|----------|-----------|
| Interpret whiteboard/paper | Claude Vision (Haiku 3.5) | Messy handwriting + spatial layout needs LLM understanding |
| Offline fallback OCR | Apple Vision (deterministic) | Fast, private, on-device |
| Classify note type | Rule-based + LLM prompt hint | `capture_type` biases existing classification |
| Route to workflow | Deterministic | `capture_type` + existing `extract-tasks.ts` logic |
| Daily sheet rendering | Deterministic template | Fixed layout, no AI needed |
| Annotation extraction | Claude Vision | Visual diff of printed vs. handwritten content |

---

## New Components

### Must Build

| Component | Type | Effort | Phase |
|-----------|------|--------|-------|
| `capture_type` schema migration | SQL migration | Tiny | 1 |
| iOS Shortcut (Claude Vision + webhook POST) | Shortcut config | Small | 1 |
| `render-daily-sheet.ts` + HTML template | New workflow | Medium | 2 |
| `com.selene.render-daily-sheet.plist` | launchd agent | Tiny | 2 |
| `extract-tasks.ts` capture_type routing | Modify existing | Small | 2 |
| Annotation loop (QR detection + Claude prompt) | Shortcut + prompt | Small | 3 |

### Deferred

| Component | Type | Trigger |
|-----------|------|---------|
| `ingest-scan.ts` + WatchPaths | New workflow | When scan volume is real |
| Labels / Dymo printing | API endpoint | Stretch goal |
| Auto-print via `lp` | Config option | When daily sheet is proven useful |

---

## Testing & Safety

### Test Strategy

**iOS Shortcut:** Manual testing only. Test matrix: whiteboard photo, paper note, annotated daily sheet, blurry/unreadable image. Verify `test_run` marker passes through.

**`render-daily-sheet.ts`:** Unit test HTML template with mock data. Integration test PDF output. Test empty states (zero tasks, zero threads, zero captures).

**`extract-tasks.ts` routing:** Test `capture_type: 'whiteboard'` biases toward `needs_planning`. Test `capture_type: 'daily_sheet_annotation'` parses completed tasks. Existing tests must pass unchanged for `capture_type: 'drafts'`.

**Schema migration:** Verify default `'drafts'` for existing rows. Verify voice memo backfill.

### Error Handling

| Failure | Behavior |
|---------|----------|
| Claude API down | Fall back to Apple Vision OCR, tag `low_confidence: true` |
| OCR returns empty/garbage | Ingest with `low_confidence: true`, don't silently discard |
| Puppeteer PDF fails | Log error, skip that day's sheet, don't crash other workflows |
| QR code not detected on annotated sheet | Treat as regular whiteboard capture (safe fallback) |

---

## Acceptance Criteria

- [ ] iOS Shortcut captures a whiteboard photo and POSTs to Selene in under 30 seconds end-to-end
- [ ] Claude Vision (Haiku 3.5) correctly interprets messy handwriting with spatial layout
- [ ] Offline fallback to Apple Vision OCR works when Claude API is unreachable
- [ ] `capture_type` column exists on `raw_notes` with `'drafts'` default; existing rows unaffected
- [ ] `extract-tasks.ts` biases `capture_type: 'whiteboard'` toward `needs_planning` classification
- [ ] `render-daily-sheet.ts` produces a single-page PDF with: task checklist (pen-checkable circles), active threads with momentum, recent captures, scratch zone (~40% of page)
- [ ] Daily sheet includes QR code encoding `selene-daily:{date}`
- [ ] Photographing an annotated daily sheet correctly extracts only handwritten annotations (not printed content)
- [ ] `daily_sheet_annotation` captures route completed tasks and new thoughts correctly
- [ ] All new workflows follow `test_run` marker convention
- [ ] No silent data loss — low-confidence results are ingested with flags, not discarded

---

## ADHD Check

| Question | Answer |
|----------|--------|
| Does this reduce friction? | One tap capture replaces manual re-typing. Daily sheet auto-prints. |
| Does this externalize working memory? | Whiteboards enter Selene automatically. Selene's brain goes on paper. |
| Does this respect "out of sight, out of mind"? | Shortcut on lock screen. WatchPaths is invisible. Sheet is on desk. |
| Does this add cognitive load? | No new apps, no new habits — photograph what you already write. |

---

## Scope Check

**What this is NOT:**
- Not a general document management system
- Not a replacement for Obsidian export (already exists)
- Labels / Dymo are deferred, not v1
- `ingest-scan.ts` deferred until scan volume is real
- No multi-photo annotation tracking

**Minimum viable slice:** iOS Shortcut + schema migration. Everything else is additive.

---

## Build Order

1. **Schema migration** (`capture_type` column) — enables everything downstream
2. **iOS Shortcut** (Claude Vision + webhook POST) — real signal about what gets captured
3. **`render-daily-sheet.ts`** + HTML template + launchd — once capture is working
4. **`extract-tasks.ts` routing** — once there's real `capture_type` data flowing
5. **Annotation loop** (QR detection + annotated sheet prompt) — once daily sheet is in use

---

## Open Questions (Resolved)

- **Whiteboard note type vs `capture_type`?** — `capture_type` column is sufficient. No new note type needed.
- **`extract-tasks.ts` branching?** — Prompt hints based on `capture_type`, not hard forks. Evaluate after real data from Path A.
- **Low-confidence OCR handling?** — Ingest as-is with `low_confidence: flag. Don't discard, don't review-queue (friction).
- **Puppeteer vs WeasyPrint?** — Puppeteer. Already in the JS/TS ecosystem, consistent with stack.
- **Claude Vision vs Apple Vision OCR?** — Claude Vision default (handles messy spatial handwriting). Apple Vision as offline fallback only.
