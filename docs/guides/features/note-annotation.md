# Note Annotation (iPad)

**What this does for you:** On your iPad, browse your notes by topic, open one, and hand-write a follow-up thought with the Apple Pencil right below the original — Selene OCRs your ink and files it as a new note linked back to the one you were reading.

## Using it

In the **SeleneMarkup** app on your iPad, tap the **Notes** tab (the `note.text` icon).

1. **Pick a category.** The first screen lists your content categories (e.g. *"Relationships & Social"*, *"Health & Body"*) with note counts and a one-line synthesis snippet, largest first. These are the content groups Selene builds in the [synthesis layer](synthesis-layer.md) — a brain-dump note that spans several topics appears under **each** category it touches.
2. **Pick a note.** Tapping a category shows the raw captures in it, newest first.
3. **Read + annotate.** Tapping a note shows its text at the top with an **infinite canvas** below. Write a follow-up thought with the Apple Pencil — a reaction, an update, a connection you just made.
4. **Peek at the back of the card.** The **ⓘ** button (top-right) slides up Selene's processed metadata for that note: its essence, primary theme, and concept tags.
5. **Send it back.** Tap **Send to Selene** (↑). Vision OCR converts your handwriting to text and shows it to you in a review alert. Tap **Send** to confirm. You'll see a **"Sent to Selene ✓"** toast and the canvas clears.

Your annotation becomes a brand-new note in Selene, **linked to the note you were reading**, and flows through the normal pipeline (concepts, essence, theme, embedding) like any other capture.

## How it works

Two pieces talk over your home WiFi:

- **iPad app (SeleneMarkup):** the `Notes` tab is `ClusterListView` → `NoteListView` → `NoteCanvasView`. The canvas reuses the same `CanvasView` (PencilKit) and `HandwritingService` (Vision `VNRecognizeTextRequest`, on-device) as the worksheets feature. `AnnotationService` is the HTTP client.
- **Selene server:** `src/routes/notes.ts` adds four endpoints to the main server (`src/server.ts`, port 5678, launchd agent `com.selene.server`):
  - `GET /api/clusters` — non-proto topic clusters, ordered by note count
  - `GET /api/clusters/:id/notes` — raw notes linked to a cluster
  - `GET /api/notes/:id` — one note + its processed metadata (essence, concepts, theme)
  - `POST /api/notes/:id/annotations` — creates the new linked note

The link is a single column: `raw_notes.source_note_id` points back to the parent note. The new row is written with `capture_type = 'annotation'` and `status = 'pending'`, so the existing **LLM Processing** workflow (every 5 minutes) picks it up automatically — no special handling. There is no separate "annotations" table; an annotation *is* a note that happens to know its parent.

## Configure & customize

The iPad app reads two server URLs and a token from `UserDefaults` (see `SeleneMarkup/Sources/SeleneMarkup/Models/AppConfig.swift`):

| Key | Purpose | Default |
|-----|---------|---------|
| `selene_base_url` | Worksheets dev server | `http://192.168.1.239:5679` |
| `selene_main_url` | **Main server for notes/annotations** | `selene_base_url` with `:5679`→`:5678` |
| `selene_bearer_token` | Bearer auth (only if the server sets `SELENE_API_TOKEN`) | empty |

- **Point the app at your Mac:** if your Mac's LAN IP isn't `192.168.1.239`, set `selene_base_url` (or `selene_main_url`) accordingly. Find it with `ipconfig getifaddr en1` (or `en0`).
- **Deploy a new build:** `cd ~/SeleneMarkup && ./redeploy.sh` (iPad connected via USB; auto-discovers the device).
- **Auth:** the server skips auth entirely when `SELENE_API_TOKEN` is unset (local-only mode). If you set it in `~/selene/.env`, also set `selene_bearer_token` in the app.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Notes tab shows an error / no clusters | Confirm the main server is up: `curl http://localhost:5678/health`. From the iPad's network, the Mac must be reachable at the `selene_main_url` host:port. |
| Clusters list is empty | You have no synthesis clusters yet. Run `npx ts-node src/workflows/synthesize-topics.ts` (see [synthesis layer](synthesis-layer.md)). |
| OCR review shows wrong/garbled text | Write larger and more separated; Vision OCR favors clear print. You can cancel and redraw before sending. |
| "Sent ✓" but the note never gets a theme | Processing runs every 5 min via `com.selene.process-llm`. Force it: `npx ts-node src/workflows/process-llm.ts`. Confirm Ollama is up: `curl http://localhost:11434/api/tags`. |
| Verify an annotation landed | `sqlite3 ~/selene-data/selene.db "SELECT id, source_note_id, capture_type FROM raw_notes WHERE capture_type='annotation' ORDER BY id DESC LIMIT 5;"` |

## Related

- Design doc: `docs/plans/2026-05-26-selene-mobile-companion-design.md`
- Implementation plan: `docs/plans/2026-05-28-note-annotation-implementation.md`
- Connected guides: [Interactive worksheets](interactive-worksheets.md) (same iPad app), [Synthesis layer](synthesis-layer.md) (where the content categories come from)

---
*Last updated: 2026-05-29*
