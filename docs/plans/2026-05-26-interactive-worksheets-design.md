# Interactive Worksheets (iPad, Handwritten)

**Date:** 2026-05-26
**Status:** Vision
**Topic:** ipad, pencilkit, on-device-ocr, worksheets, review-ritual, selene-integration, executive-function

---

## Vision

Selene generates a **handwritten worksheet** — a themed page of prompts drawn from your own notes — and delivers it to the iPad. You answer with the Apple Pencil. Each answer routes back into Selene as a **specific action**: archive this note, add a follow-up to that one, capture a brand-new note. The first worksheet is a **daily/weekly review ritual**; the same engine grows to host other worksheet types later.

This is the bidirectional, *structured* cousin of the folio iPad markup app: that app reads one document → one freeform note (one-directional). Worksheets are Selene-generated, field-structured, and each field updates a known object.

---

## Decisions (locked during brainstorm)

- **Target worksheet (v1):** the **daily/weekly review ritual** — it exercises the hardest path (binding answers back to existing notes), so the other types become easy generators afterward.
- **Input:** **handwriting with Apple Pencil** (paper-like). Not tap-to-type.
- **OCR:** **on-device Vision OCR**, per the original folio markup design.
- **Hardware:** requires an **M-series, iPadOS 17+ iPad**. The 1st-gen iPad Pro (A9X) is explicitly **not supported** — it caps at iPadOS 16 *and* its on-device handwriting OCR would be weak. (Verified: A9X iPad Pro max OS is iPadOS 16.)
- **"Tasks" = things to do, not a DB table.** v1 operates on **notes only**; the archived Task Extraction system is NOT revived. Notes already support real actions: `is_archived`, linked follow-up notes, new notes.
- **Transport:** the iPad app talks **directly to Selene** (new authenticated endpoints on the existing Fastify server), not through folio. Worksheets are Selene-native data; folio stays for document/Kindle delivery. This is the "direct Selene access" step the folio design parked as a future north star.
- **Action vs content:** for each note under review, the **action is an explicit tap** (chips: Archive / Follow-up / Keep) and the **content is handwriting**. Selene never infers intent from handwriting — it only OCRs the content. This is what makes "update *this* note" trustworthy.

---

## Goals / Non-Goals

**Goals (v1 = Phase 0 + Phase 1)**
- Selene generates a review worksheet from notes "needing review."
- iPad renders prompts, captures handwriting per field, OCRs on-device, lets you verify/correct before sending.
- Answers commit precise actions: archive a note, append a linked follow-up note, keep, or capture a new note.
- A `last_reviewed_at` marker prevents the same note from re-appearing every day.
- One-command redeploy to survive 7-day free-signing expiry.

**Non-Goals (v1, "room to grow")**
- Reviving the archived Task Extraction system / a first-class `tasks` table.
- The other three worksheet types (Q&A, guided task-breakdown, weekly variant) — deferred to Phase 2+ as new generators.
- Browsing/searching the corpus, chat, briefings on the iPad.
- Preserving non-text marks (arrows/circles) as images.
- Fully on-device cognition (Foundation Models).

---

## Architecture

The iPad app talks **directly to Selene**. Three actors:

```
┌─ Selene (server.ts, port 5678, bearer auth — already exists) ──────┐
│  NEW: worksheet generator workflow                                  │
│    → queries notes "needing review" (recent / never-reviewed)       │
│    → builds a Worksheet (JSON: fields w/ prompts + bindings)        │
│  NEW endpoints:                                                      │
│    GET  /api/worksheets/today       → current worksheet JSON        │
│    POST /api/worksheets/:id/answers → apply each field's action     │
│         (archive / append linked follow-up / keep / new note)       │
└─────────────────────────────────────────────────────────────────────┘
          ▲  GET worksheet (LAN, bearer)        │  POST structured answers
          │                                       ▼
┌─ iPad app (new — "SeleneMarkup" foundation, SwiftUI, iPadOS 17+) ──┐
│  WorksheetService  → fetch worksheet, submit answers (bearer auth) │
│  WorksheetView     → renders each field's prompt + own Pencil box  │
│  HandwritingService→ on-device Vision OCR per answer box           │
│  ReviewSheet       → verify/correct OCR text before sending        │
└─────────────────────────────────────────────────────────────────────┘
```

**Flow:** Selene generates → iPad fetches → you handwrite per box → OCR + verify → POST structured answers → Selene applies each action → notes update → changes flow through normal `process-llm` / Obsidian export.

Relationship to existing work: the iPad app reuses the architecture in folio's `2026-05-25-ipad-markup-app-design.md` (FolioService → WorksheetService pattern, HandwritingService, `redeploy.sh`). The biggest difference is that worksheets point the app at **Selene**, not folio.

---

## Data contract

**Selene → iPad** (`GET /api/worksheets/today`):
```json
{
  "id": "ws_2026-05-26",
  "title": "Daily Review — May 26",
  "fields": [
    {
      "id": "f1",
      "kind": "note_review",
      "prompt": "From 3 days ago — keep, archive, or add a follow-up?",
      "context": { "noteId": 412, "excerpt": "Call dentist about..." },
      "binding": { "noteId": 412, "allowedActions": ["archive","follow_up","keep"] }
    },
    {
      "id": "f2",
      "kind": "free_capture",
      "prompt": "Anything else on your mind?",
      "binding": { "action": "new_note" }
    }
  ]
}
```

**iPad → Selene** (`POST /api/worksheets/:id/answers`):
```json
{
  "worksheetId": "ws_2026-05-26",
  "answers": [
    { "fieldId": "f1", "chosenAction": "archive", "text": "" },
    { "fieldId": "f2", "chosenAction": "new_note", "text": "Book conference travel" }
  ]
}
```

**Action semantics (Selene side):**
- `archive` → set `is_archived = true` on the bound note.
- `follow_up` → create a new `raw_note` from the OCR text, **linked** to the source note via the existing `connections` table; normal `process-llm` then handles it.
- `keep` → mark reviewed, no other change.
- `new_note` → create a fresh `raw_note` from the handwriting.

**Review tracking:** add a lightweight `last_reviewed_at` marker on notes (same spirit as the existing `status_folio` column used by `folio-feedback.ts`). "Needing review" = recent or never-reviewed notes.

---

## Phasing

**Phase 0 — App foundation + freeform warm-up** *(de-risk)*
- Build the `SeleneMarkup` app skeleton: SwiftUI, iPadOS 17+, bearer-auth `WorksheetService` → Selene, PencilKit canvas, on-device Vision OCR, verify screen, one-command `redeploy.sh`.
- First feature: a freeform review page → handwrite → OCR → verify → **one new note** into Selene.
- Selene (minimal): `GET /api/worksheets/today` returns a single `free_capture` field; `POST .../answers` handles only `new_note`.
- **Exit gate:** Pencil feels like paper, OCR is accurate enough on *your real handwriting*, a note lands in Selene over LAN. If OCR is poor, we learn it cheaply here.

**Phase 1 — Structured review worksheet** *(the target)*
- Add the `note_review` field kind: action chips (Archive / Follow-up / Keep) + per-field Pencil boxes.
- The real generator (notes needing review), the `last_reviewed_at` marker, and the archive / follow_up / keep actions + `connections` linking.
- **Exit gate:** a real daily review updates your notes correctly.

**Phase 2+ — More generators** *(later)*
- "Selene asks, I answer" (Q&A over stale notes), guided task-breakdown (one note/project → handwritten sub-steps → new linked notes), and a weekly variant become **new server-side generators on the same engine** — little or no new app code, just new field kinds / SQL / prompts.

Risk is front-loaded: Phases 0–1 own all the Pencil/OCR/app risk; Phase 2+ is mostly SQL + prompts.

---

## Error handling & edge cases

- **OCR misreads** → verify screen; you correct text before anything commits.
- **Stale binding** → on submit, Selene re-validates each binding; an already-archived/deleted note is skipped and reported, never crashes the batch.
- **Idempotent submit** → a consumed worksheet's re-POST is a safe no-op returning the prior result (no double-archiving).
- **Partial failure** → actions apply per-field; Selene returns per-field results (`applied` / `skipped` / `failed`) so the iPad can show "3 applied, 1 needs retry."
- **Offline / Mac asleep** → the app persists the captured worksheet + OCR text locally and retries later; handwriting is never lost.
- **Blank field** → no handwriting = no action (defaults to keep / no-op).
- **Free-signing expiry** → app disappears every 7 days; `redeploy.sh` is the one-command fix.

---

## Testing

Mirrors SeleneChat/folio; honors Selene test rules (always `test_run` markers, never the production DB, clean up with `cleanup-tests.sh`).

- **iPad app (SPM unit tests):** `WorksheetService` encode/decode of the contract, answer-assembly logic, OCR-text post-processing, binding handling.
- **Selene (unit tests, test DB):** the generator query, each action (archive / follow_up / keep / new_note), idempotency, partial-failure, stale-binding rejection.
- **Not unit-testable → on-device verification:** PencilKit feel and OCR accuracy. **Phase 0's exit gate is an explicit handwriting-sample test** — we confirm OCR on real writing rather than trusting a green suite.

---

## Biggest risks

1. **On-device OCR accuracy on real handwriting** — settled by the Phase 0 gate, not assumptions.
2. **PencilKit per-field capture UX** — multiple answer boxes + verify flow is more UI than a single markup canvas.
3. **Free-signing friction** — usability, mitigated by `redeploy.sh`.
4. **Hardware dependency** — requires acquiring/using an M-series iPad; the 1st-gen Pro is out.

---

## Open questions

- Does the worksheet generator live as a new `src/workflows/` script + endpoints, or fold into `server.ts`? (Likely: a generator workflow + thin endpoints.)
- Schedule: is "today's worksheet" generated on a launchd cadence (like `daily-summary`) or on-demand when the iPad asks?
- Should follow-up links use `connections` directly, or a dedicated relation type?
- Weekly vs daily: same generator with a window parameter, or two generators?

---

## Related

- folio `docs/plans/2026-05-25-ipad-markup-app-design.md` — the unbuilt native app this builds on (FolioService/HandwritingService/redeploy patterns).
- `2026-04-12-pkm-browse-layer-design.md` — LAN iPad browse dashboard (overlapping device/transport surface).
- `2026-03-21-close-the-loop-design.md` — executive-function completion-feedback ideas (references archived systems; redesign needed).
- `src/workflows/folio-feedback.ts` — existing round-trip; source of the `status_*` marker pattern and address-encoding precedent.
