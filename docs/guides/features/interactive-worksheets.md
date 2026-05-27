# Interactive Worksheets

**What this does for you:** Opens a structured daily review form on your iPad where you write freehand answers — Selene OCRs them, saves them as notes, and shows you where you've written about the same topics before.

## Using it

Open **SeleneMarkup** on your iPad. The app loads today's worksheet automatically.

**The worksheet has two kinds of fields:**

1. **Handwriting fields** — write with your Apple Pencil. The full Notes-app pen palette appears (inking, eraser, lasso, rulers). Tap the pen in the toolbar to switch tools. Scribble to erase works.

2. **Note review cards** — notes from your backlog that Selene surfaced for you to acknowledge. These are notes older than a day that haven't been fully processed yet. You can read them; tapping Submit marks them acknowledged.

**To submit:**

Tap **Submit** in the top-right corner. Selene will:
- OCR all your handwritten fields
- Save each as a new note in your archive
- Search for notes you've written that are semantically related
- If anything relevant is found, "Selene remembers…" slides up with a grouped list

Tap **Done** on the remembers sheet when you're finished reading.

## How it works

**iPad side (SeleneMarkup app):**
- `GET /api/worksheets/today` — fetches today's worksheet from the Selene server
- PencilKit renders one `PKCanvasView` per handwriting field; `drawingPolicy = .pencilOnly` means your finger scrolls between fields and your pencil draws
- On Submit: Vision OCR runs on each canvas (white background composite, `.accurate` recognition level) to convert ink to text
- `POST /api/worksheets/:id/answers` — sends OCR'd text + action metadata to server

**Server side (selene repo, `feature/interactive-worksheets`):**
- `GET /api/worksheets/today` builds a fresh worksheet each day: 2 free-capture fields + a note-review field populated from your oldest unprocessed backlog notes
- `POST /api/worksheets/:id/answers` processes each answer:
  - `new_note` → inserts a raw note into the database, then runs nomic-embed-text embedding + LanceDB semantic search to find related notes (top 3, scored 0–1)
  - `acknowledge` → marks the review note as seen
- Related notes are returned in the response as `relatedNotes` grouped by field

**Ollama dependency:** The related-notes search requires `nomic-embed-text` to be loaded. If Ollama is down or the model isn't loaded, the submit still succeeds — related notes are simply omitted from the response.

## Configure & customize

| What | Where |
|------|-------|
| Server URL the iPad connects to | `Sources/SeleneMarkup/Models/AppConfig.swift` — `baseURL` default value |
| Bearer token auth | Same file — `bearerToken` default value (set to empty string to disable) |
| Number of review notes surfaced | `src/routes/worksheets.ts` — `LIMIT 3` in the `fetchReviewNotes` query |
| Number of related notes returned | `src/routes/worksheets.ts` — `limit: 3` in the `findRelatedNotes` call |
| Canvas height per field | `WorksheetView.swift` — `.frame(height: 200)` on the GeometryReader |
| Dev server port | Default `:5679`; production `:5678` |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| App shows "Loading worksheet…" forever | Check dev server is running: `curl http://localhost:5679/health` |
| App shows an error with red text | Server returned a non-200. Check logs: `tail -f logs/selene.log \| npx pino-pretty` |
| Notes land in DB but text is garbled | OCR quality depends on writing size and contrast. Larger, slower handwriting recognizes better. Dark strokes on the white canvas background help. |
| "Selene remembers…" never appears | Ollama may be down or `nomic-embed-text` not loaded: `curl http://localhost:11434/api/tags` — should list `nomic-embed-text`. If not: `ollama pull nomic-embed-text` |
| iPad can't reach the server | Confirm Mac and iPad are on the same WiFi. Use Mac's LAN IP (not `localhost`) in `AppConfig.swift`. |
| Redeploy script says "No connected iPad found" | Unlock iPad, trust the Mac if prompted, then re-run `./redeploy.sh` |

## Related

- Design doc: `docs/plans/2026-05-26-phase1-worksheets-related-notes-design.md`
- Plan doc: `docs/plans/2026-05-26-phase1-worksheets-related-notes-plan.md`
- iPad app repo: `~/SeleneMarkup`
- Server route: `src/routes/worksheets.ts` (feature/interactive-worksheets branch)
- Worksheet generation logic: `src/workflows/generate-worksheet.ts`

---
*Last updated: 2026-05-27*
