# Selene Note Annotation (iPad)

**Date:** 2026-05-26  
**Revised:** 2026-05-28  
**Status:** Ready  
**Topics:** ios, ipad, swiftui, pencilkit, ocr, annotation, selenemarkup

---

## Problem

Selene processes and organizes your notes on the Mac, but there is no way to think *on top of* what Selene has organized. Reading a processed note and wanting to react to it — to question it, extend it, connect it to something — has no surface. The only output path is Apple Notes digests and the Obsidian vault on the Mac.

---

## Goal

An iPad annotation layer inside the existing SeleneMarkup app. You browse notes by topic cluster, open a raw note, and write with Apple Pencil below it on an infinite canvas. Your annotation is sent back to Selene as a new first-class note, linked to the note you were annotating.

The LLM is a **navigator** (clusters, essences, concepts help you find notes) but never alters what you actually read — raw captures are ground truth.

---

## ADHD Design Check

- **Externalize working memory** ✓ — Topic clusters surface what Selene knows about your thinking; you don't have to remember what's in there
- **Reduce friction** ✓ — Draw to think; no keyboard, no mode switch, always annotatable
- **Visual over mental** ✓ — Your ink on the canvas is thinking made visible and persistent
- **Make thinking tangible** ✓ — Drawing below a note is lower friction than typing a reaction

---

## Scope Check

~1 week. Three new views + four server endpoints + one schema column. Builds on existing `PKCanvasView` + `VNRecognizeTextRequest` infrastructure in SeleneMarkup.

---

## Future Vision (Out of Scope Here)

A spatial knowledge graph: notes as draggable cards on an infinite canvas, connections as visible lines driven by Selene's `note_connections` data, Excalibrain-inspired "back of card" metadata. This is the longer-term direction; the annotation layer ships first.

---

## Architecture

### App

New tab in the existing **SeleneMarkup** app (`~/SeleneMarkup`). Three new views:

| View | Purpose |
|------|---------|
| `ClusterListView` | List of topic clusters from synthesis layer |
| `NoteListView` | Raw notes within a selected cluster |
| `NoteCanvasView` | Scrolling raw note + PencilKit canvas beneath |

Plus `NoteMetaSheet` — a peek/swipe panel showing the back-of-card: essence, extracted concepts, topic cluster, note connections. Read-only.

### Note Surface

- Raw capture text rendered at the top (non-editable `Text` or `AttributedString` view)
- Below it: `PKCanvasView` that grows as the user writes downward
- The whole document scrolls together — no mode toggle, always drawable
- `NoteMetaSheet` revealed via a peek button or swipe-up gesture

### Annotation Feedback

1. User draws on canvas
2. Taps "Send to Selene"
3. `VNRecognizeTextRequest` runs on the `PKDrawing` — on-device OCR
4. Recognized text is POSTed to `POST /api/notes/:id/annotations`
5. Server creates a new row in `raw_notes` with `source_note_id` = the parent note's ID
6. Selene's normal pipeline picks it up: concept extraction, essence distillation, synthesis

Annotations are first-class notes. They are not footnotes, not modifications of the original.

### New Server Endpoints (4 additions to `src/server.ts`)

```
GET  /api/clusters                   List topic clusters (id, label, note_count)
GET  /api/clusters/:id/notes         Raw notes in a cluster (id, title, created_at, word_count)
GET  /api/notes/:id                  Single raw note (title, content, created_at, tags)
POST /api/notes/:id/annotations      Receive OCR text → store as new raw note with source_note_id
```

All four use the existing `Authorization: Bearer <token>` auth pattern from `src/lib/auth.ts`.

### Schema Change

One new nullable column on `raw_notes`:

```sql
ALTER TABLE raw_notes ADD COLUMN source_note_id INTEGER REFERENCES raw_notes(id);
```

No new table. Annotations are notes.

---

## Data Flow

```
[iPad] User draws on canvas below a note
    → "Send to Selene" tapped
    → VNRecognizeTextRequest (on-device OCR) → text string
    → POST /api/notes/:id/annotations (Bearer token, Tailscale)
    → Server inserts new row in raw_notes (source_note_id = parent)
    → process-llm.ts picks it up (every 5 min)
    → distill-essences.ts distills it
    → synthesize-topics.ts may cluster it with related notes
```

---

## Acceptance Criteria

**Navigation:**
- [ ] Cluster list renders all topic clusters with note counts
- [ ] Tapping a cluster shows the raw notes in that cluster
- [ ] Tapping a note opens `NoteCanvasView` with raw capture text at the top

**Canvas:**
- [ ] Raw note text is rendered read-only at the top of the scroll view
- [ ] PencilKit canvas appears below the note text and grows as the user draws downward
- [ ] Note text and canvas scroll together as one document
- [ ] Apple Pencil draws on the canvas without interfering with note text

**Back of card:**
- [ ] Peek button / swipe gesture opens `NoteMetaSheet`
- [ ] Sheet shows: essence, extracted concepts, topic cluster, connected note titles
- [ ] Sheet is read-only

**Annotation feedback:**
- [ ] Tapping "Send to Selene" runs Vision OCR on the canvas drawing
- [ ] Recognized text appears as a new row in `raw_notes` with `source_note_id` set
- [ ] The new note surfaces in Selene's pipeline (processed by process-llm.ts)

**Auth / networking:**
- [ ] All requests use Tailscale URL + Bearer token from SeleneMarkup Settings
- [ ] Connection test in Settings passes against the new endpoints

---

## Related Designs

- [2026-05-26-interactive-worksheets-design.md](2026-05-26-interactive-worksheets-design.md) — shares PKCanvasView + VNRecognizeTextRequest infrastructure
- [2026-05-26-synthesis-retrieval-agent-design.md](2026-05-26-synthesis-retrieval-agent-design.md) — topic clusters that power the entry navigation
- [2026-02-13-selene-mobile-ios-design.md](2026-02-13-selene-mobile-ios-design.md) — archived original SeleneMobile; preserved for reference

---

## Out of Scope

- Spatial graph / Excalibrain-style canvas with connection lines (future vision)
- WidgetKit home screen widget (can be added later)
- Quick capture tab (can be added later)
- Chat with Ollama
- Push notifications / Live Activities
- Modifying the original raw note (annotations are always new notes)
