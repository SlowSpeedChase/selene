# Capturing Notes

**What this does for you:** Every note you jot, photograph, or handwrite makes its way into Selene automatically, so nothing you capture stays trapped in a separate app or on paper.
**Last Updated:** 2026-05-25

## Using it

There are three ways a note gets into Selene. Pick whichever fits the moment — they all land in the same place.

### 1. Typed notes from the Drafts app

When you type a note and run your Selene action in the Drafts app, it sends the note straight to Selene. This is the everyday, zero-friction path: type, send, done. Nothing else for you to do — the note shows up in Selene and gets processed automatically.

What you look at afterward: your Obsidian vault and the daily Apple Notes digest, where processed notes land.

### 2. Whiteboard and paper photos (iOS Shortcut)

When you snap a photo of a whiteboard or a handwritten page, the "Capture to Selene" iOS Shortcut interprets the image and sends the result to Selene. One tap from your lock screen or widget opens the camera; or share an existing photo from the Photos app into the Shortcut.

This is the path for messy, spatial thinking — arrows, groupings, sketches. The Shortcut uses Claude Vision to read the layout, not just flatten it into text.

Setup is a one-time thing and is covered in its own guide: **`docs/guides/ios-shortcut-setup.md`**. Follow that to build the Shortcut, then just use it.

### 3. Handwritten Kindle Scribe notebooks (e-ink OCR)

When you write in a Kindle Scribe notebook and it syncs to your iCloud folder as a PDF, Selene notices the new file, reads the handwriting, and ingests it — no action from you. Write on the device, let it sync, and the note appears in Selene a little while later.

You don't trigger anything. Just check that your Scribe is exporting PDFs to the watched iCloud folder (see Configure & customize for the exact path).

### What happens to every captured note

No matter which path a note takes, Selene checks for duplicates before storing it. If the same note comes in twice, the second copy is skipped rather than stored again.

## How it works

All three paths converge on the same ingestion logic.

### The shared ingestion core

- **Workflow:** `src/workflows/ingest.ts`
- Generates a SHA-256 hash of the note's **title + content** for duplicate detection. If a note with the same hash already exists, the incoming one is reported as a duplicate and skipped.
- Extracts `#hashtags` from the content as tags.
- Stores the note with its `capture_type` so downstream workflows know where it came from.

### Path 1: Drafts app

- **Endpoint:** `POST /webhook/api/drafts` on the Selene webhook server (`src/server.ts`), port **5678** in production.
- The Drafts action sends `title` and `content` (both required). `capture_type` defaults to `'drafts'`.
- **Server:** runs continuously via the launchd agent `com.selene.server` (`launchd/com.selene.server.plist`).

### Path 2: iOS Shortcut (whiteboard / paper)

- The "Capture to Selene" Shortcut runs **on your phone** — it calls Claude Vision to interpret the photo, then POSTs the structured result to the same `POST /webhook/api/drafts` endpoint.
- `capture_type` is set by the Shortcut: `'whiteboard'` for photos, `'daily_sheet_annotation'` for photographed daily planning sheets, or `'whiteboard_ocr'` when it falls back to on-device Apple Vision (offline).
- There is no separate Selene-side workflow for this path — it reuses the Drafts webhook and the shared `ingest.ts` core.

### Path 3: E-ink Kindle Scribe OCR

- **Workflow:** `src/workflows/eink-ingest.ts`, launched by the wrapper script `scripts/selene-eink-ingest`.
- **launchd agent:** `com.selene.eink-ingest` (`launchd/com.selene.eink-ingest.plist`). It triggers two ways: on **WatchPaths** (whenever the watched iCloud folder changes) and on a **StartInterval of 1800 seconds** (every 30 minutes) as a safety net.
- The pipeline per new PDF:
  1. **Scan** the watch folder for PDFs not yet in the manifest, skipping files modified in the last 10 seconds (to avoid grabbing a file mid-sync).
  2. **Convert** each page to a 300-DPI PNG using `pdftoppm` (from poppler).
  3. **Preprocess** each page with ImageMagick (`-deskew`, `-normalize`); if that fails it uses the original.
  4. **OCR** each page through a local Ollama vision model (default `qwen2.5vl:7b`). The prompt extracts only **handwritten annotations** — circled text, underlines, arrows, diagrams — and marks illegible writing with `[?]`. Pages with no handwriting return `[NO ANNOTATIONS]`.
  5. **Combine** pages into one note body with `--- Page N ---` separators, tagged `#eink #selene`.
  6. **Ingest** the note **directly** through `ingest.ts` (it does not go through the Drafts app for review). `capture_type` is `'eink'`, or `'folio'` for files whose names start with `folio__`.
  7. **Archive** the original PDF (moved, never deleted) and record it in the manifest so it is never processed twice.
- **Where output lands:** all captured notes end up in the Selene database, then flow into the Obsidian vault (via `export-obsidian.ts`) and the daily Apple Notes digest (via `send-digest.ts`).
- **Logs:** `logs/eink-ingest.log` and `logs/eink-ingest.error.log`.

## Configure & customize

### E-ink OCR (the most configurable path)

All knobs are environment variables read by `src/lib/config.ts`. Set them in your `.env` (the plist also sets `SELENE_ENV` and `SELENE_DB_PATH`):

| Setting | Env var | Default |
|---------|---------|---------|
| Watched iCloud folder | `EINK_WATCH_DIR` | `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/iCloud Kindle Notebooks` |
| Archive folder for processed PDFs | `EINK_ARCHIVE_DIR` | `~/selene-data/eink/archive` |
| Temp page-image folder | `EINK_TEMP_DIR` | `~/selene-data/eink/pages` |
| Manifest file (tracks processed PDFs) | `EINK_MANIFEST_PATH` | `~/selene-data/eink/.processed.json` |
| Ollama vision model | `EINK_VISION_MODEL` | `qwen2.5vl:7b` |

To change the **schedule or watched path**, edit `launchd/com.selene.eink-ingest.plist` (the `WatchPaths` and `StartInterval` keys), then reload it:

```
launchctl bootout gui/$(id -u)/com.selene.eink-ingest 2>/dev/null
launchctl bootstrap gui/$(id -u) launchd/com.selene.eink-ingest.plist
```

To **run it by hand** (useful for testing a new model or path):

```
npx ts-node src/workflows/eink-ingest.ts --dry-run
```

`--dry-run` does the OCR and shows the result without ingesting or archiving anything. You can also pass a number to limit how many notebooks it processes, e.g. `npx ts-node src/workflows/eink-ingest.ts 1`.

**Dependencies for e-ink OCR:** `pdftoppm` (`brew install poppler`), ImageMagick (`brew install imagemagick`), and Ollama with a vision model pulled (`ollama pull qwen2.5vl:7b`).

### Drafts app

`capture_type` defaults to `'drafts'`. Drafts-side action setup (building the action that POSTs to the webhook) is out of scope for this guide.

### iOS Shortcut

All Shortcut configuration — the Claude API key, your Mac's network address, and the offline fallback — is covered in `docs/guides/ios-shortcut-setup.md`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Note sent twice but only one appears | Working as designed — duplicate detection is a SHA-256 hash of **title + content**. Change either the title or the content to capture a near-identical note. |
| Webhook note returns an error | Both `title` and `content` are required. A missing field returns `400`. Confirm the server is up: `curl http://localhost:5678/health` |
| Webhook server not responding | Check health (`curl http://localhost:5678/health`); restart via launchd: `launchctl kickstart -k gui/$(id -u)/com.selene.server` |
| New Kindle PDF isn't getting picked up | Confirm it landed in the watched folder (`EINK_WATCH_DIR`). Files modified in the last 10 seconds are skipped until sync settles — wait, then run by hand: `npx ts-node src/workflows/eink-ingest.ts --dry-run` |
| E-ink OCR failing or producing junk | Check logs: `tail -f logs/eink-ingest.error.log`. Verify Ollama is up and the model is pulled (`ollama pull qwen2.5vl:7b`). Verify `pdftoppm` exists (`which pdftoppm`). |
| E-ink agent seems stuck / want to force a run | `launchctl kickstart -k gui/$(id -u)/com.selene.eink-ingest` |
| A Kindle PDF processed but you want to redo it | The manifest (`EINK_MANIFEST_PATH`, default `~/selene-data/eink/.processed.json`) records every processed file. Remove its entry to let it be reprocessed; the original PDF is in `EINK_ARCHIVE_DIR`. |

## Related

- Design docs in `docs/plans/`:
  - `docs/plans/2026-03-21-eink-notebook-ingestion-design.md` (e-ink OCR pipeline)
  - `docs/plans/2026-03-18-physical-digital-bridge-design.md` (whiteboard / paper capture)
- Connected guides:
  - `docs/guides/ios-shortcut-setup.md` (build the "Capture to Selene" Shortcut for whiteboard/paper photos)
