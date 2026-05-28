# Pencil Annotation → Synthesis Loop Design

**Status:** Vision
**Created:** 2026-05-28
**Updated:** 2026-05-28
**Topics:** annotation, pencilkit, ocr, synthesis, versioning, pipeline, sqlite

---

## Problem

You want to browse notes like Obsidian and mark them up anywhere with the Apple
Pencil — writing in the margins of an already-written page — and then have the
system **synthesize the markup into one clean, updated page, as if it had been
written that way the first time.**

The existing [Selene Mobile Companion design](2026-05-26-selene-mobile-companion-design.md)
already covers the *app* side of this (PencilKit overlay, on-device Vision OCR,
a `note_annotations` table, a `POST .../annotations` endpoint). But its
annotation-feedback path is a **thin, destructive Path-1 rewrite**: the next
`export-obsidian.ts` run feeds annotation text to the LLM with "incorporate
these insights when refining the note," which silently overwrites the vault
note. That has three problems this design fixes:

1. **No trust / no undo** — a 7B local model rewrites your thinking with no
   review step and no way to see what changed or roll back.
2. **No edit-vs-react distinction** — "this is wrong, it's actually X" (an
   instruction to change the note) and "this reminds me of Y" (a new thought)
   both get blindly folded into the prose. Reactions get absorbed or dropped.
3. **No provenance** — the original note and the marginalia that produced the
   change are lost once the rewrite lands.

This design specifies the **brain** of the feature: the data model, the
non-destructive synthesis loop, and how it re-enters the existing pipeline. It
does not re-spec the iPad app — that stays owned by the companion design, which
this doc refines (see *Relationship to Existing Designs*).

---

## Solution

The **Path 2 + Path 3 hybrid** from the brainstorm:

- **Marginalia layer (Path 2):** each Pencil annotation is stored as anchored
  ink + OCR text on the source note. Ink is canonical; OCR text is the LLM
  payload. Nothing is overwritten.
- **Capture-as-event plumbing (Path 3):** an annotation is just a row that
  references its source note, so it can flow through the pipeline like any
  other capture.
- **Synthesis as a reviewable proposal (Path 1's output, de-risked):**
  "synthesize a clean version" produces a **candidate `note_versions` row** with
  a plain-language change summary. You accept or reject it. Accepting is the
  *only* thing that touches the live note — and even then the prior content is
  preserved as a version, so it is always recoverable.
- **Edit-vs-react resolved at review time:** the LLM *suggests* intent during
  processing; you confirm by either accepting a synthesized edit or promoting a
  reaction into its own linked note. The system never silently routes.

The payoff: accepting a synthesis just flips the two status flags the pipeline
already gates on, so the clean note re-runs concept/essence extraction and
re-exports to Obsidian as if freshly captured — no separate re-processing path.

---

## Relationship to Existing Designs

This doc **refines** the companion design's annotation portion and **reconciles
a schema conflict**. Read alongside:

- [2026-05-26-selene-mobile-companion-design.md](2026-05-26-selene-mobile-companion-design.md)
  — owns the iPad app (Explore/Capture tabs, PencilKit overlay, Vision OCR,
  Tailscale + bearer auth, widget). **Its `note_annotations` table and
  annotation-feedback path are superseded by this doc.** Its other three
  endpoints and the app architecture are unchanged.
- [2026-05-26-interactive-worksheets-design.md](2026-05-26-interactive-worksheets-design.md)
  — already established the principle this design leans on: *"Selene never
  infers intent from handwriting — the action is an explicit tap."* Worksheets
  do this with action chips on structured fields; here the equivalent is the
  accept / promote choice at review time for free-form margin annotations.
- [2026-05-26-phase1-worksheets-related-notes-design.md](2026-05-26-phase1-worksheets-related-notes-design.md)
  (Done) — established the **OCR review-before-submit** step. Reused here:
  OCR text is verified on-device before it ever reaches the server.

### Schema reconciliation

The companion design proposes:

```sql
-- SUPERSEDED by this design
CREATE TABLE note_annotations (
  id INTEGER PRIMARY KEY,
  note_path TEXT NOT NULL,          -- keyed on vault path
  annotation_text TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  processed INTEGER NOT NULL DEFAULT 0
);
```

This design replaces it with a richer table keyed on `raw_note_id` (the DB note
id, not the vault path) because the synthesis loop must write back into
`raw_notes` and re-enter `process-llm` / `export-obsidian`. The app browses the
vault and knows `note_path`; the **server resolves path → `raw_note_id`** at the
capture endpoint. If the companion app ships its simple table first, this design
is a forward migration (add columns, backfill `raw_note_id` from `note_path`,
rename `annotation_text` → `ocr_text`).

---

## Design

### Data model — two tables + one column

**`note_annotations`** — marginalia layer + capture event in one row:

```sql
CREATE TABLE IF NOT EXISTS note_annotations (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  raw_note_id   INTEGER NOT NULL,        -- source note being marked up
  ink_data      BLOB,                    -- serialized PKDrawing — CANONICAL, never lossy
  ocr_text      TEXT,                    -- recognized/typed text — the LLM payload
  anchor        TEXT,                    -- JSON: {paragraph_index, char_start, char_end}
  gesture_hint  TEXT,                    -- optional: 'strikethrough'|'margin'|'circle'|null
  intent        TEXT,                    -- 'edit'|'react'|null (null = undecided)
  status        TEXT NOT NULL DEFAULT 'pending', -- pending→processed→applied|dismissed|promoted
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  processed_at  TEXT,
  test_run      TEXT                     -- same test-data discipline as raw_notes
);
```

Key choices: **ink is the BLOB and canonical; `ocr_text` is the disposable
payload** the LLM reads. `anchor` is a text range, so "this scribble belongs to
paragraph 3" carries spatial meaning without a gesture-interpretation engine.
`gesture_hint` exists *if* a light convention (strike = edit, margin = react) is
adopted later; otherwise null. `test_run` keeps annotations under the same
test-data rules as every other table (per CLAUDE.md critical rules).

**`note_versions`** — the synthesized clean page as a non-destructive proposal:

```sql
CREATE TABLE IF NOT EXISTS note_versions (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  raw_note_id             INTEGER NOT NULL,
  version_number          INTEGER NOT NULL,  -- monotonic per note; v0 = seeded original
  content                 TEXT NOT NULL,     -- the rewritten note
  summary_of_changes      TEXT,              -- LLM's plain-language "here's what I changed"
  based_on_annotation_ids TEXT,              -- JSON array — provenance
  status                  TEXT NOT NULL DEFAULT 'proposed', -- proposed→accepted|rejected
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  accepted_at             TEXT
);
```

`raw_notes.content` is **never touched by synthesis**. A version is a candidate.
The true original is preserved as a seeded `version_number = 0` row the first
time a note is annotated, so accept is always reversible.

**One column on `raw_notes`** for reactions promoted into their own notes:

```sql
ALTER TABLE raw_notes ADD COLUMN parent_note_id INTEGER;  -- inline try/catch idiom
```

(A link table like `thread_notes` is the alternative, but a parent pointer is
simpler — a reaction is just a note that knows where it came from.)

### State flow

```
PENCIL MARKUP ──► note_annotations (pending)
                         │
        process-annotations (new launchd, every 5m)
                         │  OCR already done on-device; LLM SUGGESTS intent
                         ▼
                  note_annotations (processed, intent=edit|react)
                         │
            ┌────────────┴─────────────┐
       edit-type                    react-type
            │                            │
   synthesize → note_versions      surfaced as "promote to note?"
        (proposed)                       │
            │                            │
   ── YOU REVIEW IN BROWSE UI ──         │
   accept ──► copy content into     promote ──► new raw_notes row
   raw_notes.content                  (parent_note_id set, status=pending)
   + status='pending'                       │
   + exported_to_obsidian=0                 ▼
            │                       flows through normal pipeline
            ▼
   re-enters process-llm + export-obsidian automatically
```

Accepting a synthesis flips the same two flags the pipeline already gates on
(`status='pending'` for `process-llm`, `exported_to_obsidian=0` for
`export-obsidian`). The clean note re-runs extraction and re-exports on the next
cycle. No new re-processing path is built.

### Pipeline hooks (mapped to real files)

| What | Where | Mirrors |
|---|---|---|
| Capture annotation | new `POST /webhook/api/annotate` in `src/server.ts` → small `ingest-annotation` workflow (resolves note_path → raw_note_id) | `/webhook/api/drafts` → `ingest.ts` |
| Process + synthesize | new `src/workflows/process-annotations.ts` + `launchd/com.selene.process-annotations.plist` (every 5m) | `process-llm.ts` + its plist |
| Synthesis prompts | new `SYNTHESIZE_PROMPT` (+ optional `INTENT_CLASSIFY_PROMPT`) in `src/lib/prompts.ts` | `EXTRACT_PROMPT`, `buildEssencePrompt` |
| On-demand synth / accept / reject / promote | endpoints in `src/server.ts` (or `src/routes/annotations.ts`) | `routes/agents.ts`, `routes/dashboard.ts` |
| Table creation / migration | inline `CREATE TABLE IF NOT EXISTS` + `ALTER ... ADD COLUMN` in try/catch | `device_tokens` in `db.ts`, `category` in `process-llm.ts` |

### Endpoints

```
POST /webhook/api/annotate                   Store ink + OCR text + anchor (resolves note → raw_note_id)
POST /webhook/api/annotations/:noteId/synthesize   On-demand: build a candidate note_version now
POST /webhook/api/versions/:versionId/accept       Copy version.content → raw_notes.content;
                                                    mark version accepted, annotations applied;
                                                    set status='pending', exported_to_obsidian=0
POST /webhook/api/versions/:versionId/reject        Mark version rejected
POST /webhook/api/annotations/:id/promote           React → new raw_notes row (parent_note_id, status=pending)
```

All follow the existing bearer-auth pattern (`src/lib/auth.ts`).

### How the three forks are resolved

- **Input:** ink canonical (BLOB) + OCR text payload + text-range anchor →
  spatial meaning preserved without a gesture engine.
- **Intent:** LLM-suggested during processing, **confirmed at review** (accept
  edit vs promote reaction) → robust to ambiguity.
- **Output:** never overwrites; synthesis is a proposed `note_versions` row;
  original recoverable via the seeded v0. Accept is the only write to
  `raw_notes.content`.

---

## Implementation Notes

- **On-device OCR (not server-side).** The iPad app (companion design) runs
  PencilKit + Vision/Scribble locally and sends already-recognized text plus the
  ink blob. Apple's local handwriting recognition beats anything mistral:7b
  would do and keeps capture LLM-free. This matches the worksheets design's
  OCR-review-before-submit precedent.
- **Synthesis runs both scheduled and on-demand.** The launchd job keeps it
  ambient; the explicit `.../synthesize` endpoint makes "clean up this page now"
  work the moment you finish marking up.
- **Reuses `generate()` / `isAvailable()`** from `src/lib/ollama.ts` exactly like
  `process-llm.ts`, with the same JSON-extraction + fallback handling for flaky
  LLM output.
- **Migration idiom:** create tables/columns inline with `IF NOT EXISTS` /
  try-catch'd `ALTER`, matching `device_tokens` (`db.ts`) and the `category`
  column (`process-llm.ts`). No migration framework.
- **Test discipline:** every annotation/version carries (or inherits) a
  `test_run` marker; cleanup via `./scripts/cleanup-tests.sh`. Never the
  production DB.

---

## Open Decisions (path to "Ready")

These must be settled before promoting from Vision → Ready:

1. **Auto-synthesize vs on-demand only?** Recommend on-demand first (you tap
   "synthesize") — trust-preserving, avoids burning Ollama on every stray mark.
2. **Intent: LLM-suggested or gesture-convention?** Schema supports both
   (`intent` + `gesture_hint`). Recommend LLM-only with review-time
   confirmation; add gestures only if misrouting becomes annoying.
3. **Does an accepted synthesis recompute concepts/essence, or keep originals?**
   Flipping `status='pending'` recomputes everything; preserving the original
   analysis means accepting content but leaving `processed_notes` untouched.

---

## Ready for Implementation Checklist

- [ ] **Acceptance criteria defined** — see below
- [x] **ADHD check passed** — see below
- [ ] **Scope check** — server-side loop is < 1 week; full feature depends on
      companion app Phase 1. Scope this doc to the server loop + reconciled
      schema; app capture is tracked under the companion design.
- [ ] **No blockers** — three open decisions above must be settled; depends on
      companion app for the capture surface.

### Acceptance Criteria (server-side loop)

- [ ] `POST /webhook/api/annotate` stores ink blob + OCR text + anchor against
      the resolved `raw_note_id`, with a `test_run` marker honored.
- [ ] `process-annotations` OCR-classifies intent and, for edit-type
      annotations, produces a `note_versions` row (status `proposed`) with a
      non-empty `summary_of_changes` and correct `based_on_annotation_ids`.
- [ ] Accepting a version copies content into `raw_notes.content`, preserves the
      prior content as a version, marks contributing annotations `applied`, and
      flips `status='pending'` + `exported_to_obsidian=0`.
- [ ] After accept, the note re-runs `process-llm` and re-exports to Obsidian on
      the next cycle with the synthesized content.
- [ ] Promoting a react-type annotation creates a new `raw_notes` row with
      `parent_note_id` set and `status='pending'`.
- [ ] Rejecting a version leaves `raw_notes.content` unchanged.

### ADHD Design Check

- [x] **Reduces friction?** — marking up a page with a Pencil is lower
      activation energy than retyping; one-tap accept commits the synthesis.
- [x] **Visible?** — annotations persist as a visible marginalia layer; the
      change summary makes what the system did explicit rather than hidden.
- [x] **Externalizes cognition?** — the system holds the original, the
      marginalia, and every synthesized version; you never track what changed in
      your head, and undo is always available.

---

## Out of Scope

- The iPad app itself (Explore/Annotate UI, PencilKit, Vision OCR, widget) —
  owned by the companion design.
- Full gesture interpretation (arrows/circles connecting regions) — `anchor`
  + optional `gesture_hint` is the deliberate v1 ceiling.
- Preserving ink as rendered images in the Obsidian export — the vault gets the
  synthesized text; ink lives in the app/DB.
- Multi-user / concurrent annotation conflict resolution.

---

## Links

- **Branch:** `claude/note-annotation-pencil-YU0Tv`
- **PR:** (added when complete)
