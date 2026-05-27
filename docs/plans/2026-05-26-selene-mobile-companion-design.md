# Selene Mobile Companion App

**Date:** 2026-05-26
**Status:** Vision
**Topics:** ios, ipad, swiftui, pencilkit, widgetkit, annotation, obsidian

---

## Problem

Selene processes and organizes your notes on the Mac, but the only way to interact with the results is through Apple Notes digests, the Obsidian vault on the Mac, or the web dashboard. There is no mobile-native interface for:

- Capturing quick notes from your iPhone or iPad when away from the Mac
- Reading and acting on Selene's curated summaries on a mobile device
- Annotating Selene's processed notes with Apple Pencil and feeding those annotations back into the knowledge base

The archived SeleneMobile app (2026-02-14) had full feature parity with the Mac app but depended on the archived SeleneChat/thread architecture. It needs a clean rebuild against the current Selene core.

---

## Goal

A lean iPhone/iPad companion app that lets you:

1. **Capture** — quick note input (text + voice) posting to the existing Selene webhook
2. **Explore** — browse Selene's Obsidian vault notes on your iPhone or iPad
3. **Annotate** — draw Apple Pencil annotations on top of rendered notes (iPad); on-device Vision OCR converts ink to text and sends it back to the Selene librarian
4. **Glance** — home screen WidgetKit widget showing today's summary headline

The "annotate and feed back" loop is the core new capability: your Pencil becomes a way to refine, question, and build on top of what Selene has already organized.

---

## ADHD Design Check

- **Externalize working memory** ✓ — Widget shows what Selene knows today without opening the app
- **Reduce friction** ✓ — Capture tab opens directly to keyboard/voice; one tap from home screen
- **Visual over mental** ✓ — Rendered notes with PencilKit overlay; ink = thinking made visible
- **Make thinking tangible** ✓ — Drawing on top of a note is lower friction than typing a reaction

---

## Scope Check

This is a multi-phase build. Each phase ships independently:

- **Phase 0** (~3 days): Server endpoints + note list/reader (text-only) + widget
- **Phase 1** (~3 days): PencilKit annotation layer + Vision OCR + annotation feedback loop
- **Phase 2** (~2 days): Quick capture tab + voice dictation, polish

Total: ~2 weeks across phases. Phases are independently shippable.

---

## Architecture

### App Structure

**Platform:** iOS/iPadOS 17+, Swift + SwiftUI  
**Project:** `SeleneMobile/` directory at repo root, XcodeGen `project.yml`  
**No dependency on archived SeleneChat code** — clean rebuild  
**Icon:** Copied from `archive/shelved-2026-03-21/SeleneChat/SeleneChat.icon/`

**Tabs:**

| Tab | Content | Phase |
|-----|---------|-------|
| Explore | List → detail view of Obsidian vault notes, grouped by topic | 0 |
| Capture | Text field + voice input → POST /webhook/api/drafts | 2 |
| Settings | Tailscale URL + auth token + connection test | 0 |

**WidgetKit Extension (bundled in same project):**
- Small: today's summary headline (1 sentence)
- Medium: summary snippet + date

**PencilKit Annotation Layer (iPad only, Phase 1):**
- Transparent `PKCanvasView` overlaid on the note detail scroll view
- Toggle between "Read" mode and "Annotate" mode
- "Send to Selene" button → `VNRecognizeTextRequest` → POSTs extracted text as annotation

### Networking

Connects to Selene server over Tailscale (same model as archived SeleneMobile). Bearer token auth — same `Authorization: Bearer <token>` header the existing server already validates via `src/lib/auth.ts`.

### New Server Endpoints (4 additions to `src/server.ts`)

```
GET  /api/vault/notes              List all notes from the Obsidian vault (title, category, path)
GET  /api/vault/notes/:path        Serve note markdown content
POST /api/vault/notes/:path/annotations  Receive annotation text; store in note_annotations table
GET  /api/summary/latest           Latest daily_summary row (text + created_at)
```

All 4 follow the existing Bearer token auth pattern.

### New SQLite Table

```sql
CREATE TABLE note_annotations (
  id INTEGER PRIMARY KEY,
  note_path TEXT NOT NULL,
  annotation_text TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  processed INTEGER NOT NULL DEFAULT 0
);
```

### Librarian Integration

`export-obsidian.ts` queries unprocessed `note_annotations` rows when regenerating a note. Annotation text is appended to the LLM prompt: *"The user has annotated this note with: [text]. Incorporate these insights when refining the note."* Rows are marked `processed = 1` after the export run.

---

## Data Flow

```
[iPad] User draws on note
    → PKCanvasView captures PKDrawing
    → VNRecognizeTextRequest (on-device OCR) → text string
    → POST /api/vault/notes/:path/annotations (Bearer token, Tailscale)
    → SQLite note_annotations table (processed = 0)
    → next export-obsidian.ts run reads unprocessed annotations
    → LLM incorporates them into updated vault note
    → Obsidian vault updated
```

```
[iPhone/iPad] Widget
    → WidgetKit timeline entry refreshes every 30 min
    → GET /api/summary/latest
    → Shows today's summary headline on home screen
```

---

## Acceptance Criteria

**Phase 0:**
- [ ] Note list renders all Obsidian vault notes grouped by category
- [ ] Tapping a note renders its markdown content correctly
- [ ] Widget shows today's summary headline on the home screen
- [ ] Settings screen saves Tailscale URL + token; connection test passes

**Phase 1:**
- [ ] On iPad, "Annotate" toggle shows PencilKit canvas over the note
- [ ] Drawing with Apple Pencil and tapping "Send to Selene" produces readable OCR text
- [ ] Annotation appears in `note_annotations` table on the server
- [ ] After the next export-obsidian run, the note in the Obsidian vault includes the annotation content

**Phase 2:**
- [ ] Capture tab accepts text input + submits to webhook
- [ ] Voice dictation button captures speech and populates the text field

---

## Related Designs

- [2026-05-26-interactive-worksheets-design.md](2026-05-26-interactive-worksheets-design.md) — PencilKit worksheets on iPad; shares the on-device OCR approach
- [2026-05-25-folio-ipad-delivery-design.md](2026-05-25-folio-ipad-delivery-design.md) — Folio LAN reader with Apple Pencil annotation; related annotation-feedback concept
- [2026-02-13-selene-mobile-ios-design.md](2026-02-13-selene-mobile-ios-design.md) — Archived original SeleneMobile; preserved for reference

---

## Out of Scope

- Chat with Ollama (archived SeleneChat feature; not part of current Selene core)
- Push notifications / Live Activities (can be added in a future phase)
- Agent actions tab (can be added as a future tab once Phase 0 is stable)
- Syncing back to the Mac Obsidian app directly (server-mediated only)
