# E-Ink Notebook Ingestion Design

**Date:** 2026-03-21
**Status:** Ready
**Topic:** capture, ocr, eink

---

## Problem

Handwritten notebooks on a Kindle Scribe are exported as PDFs to an iCloud folder via a script. These notes contain journaling, ideas, and planning — valuable content that currently never enters Selene. Each notebook is a one-shot scratch pad (not a continuously updated document), making it a natural fit for Selene's capture-and-process model.

## Solution

A local OCR pipeline using Ollama vision models to transcribe handwritten PDF notebooks and ingest them into Selene, following the same architecture as the voice memo transcription workflow.

---

## Pipeline Architecture

```
iCloud Folder (PDFs)
    │
    ▼
[scan] ─── Find new unprocessed PDFs via manifest
    │
    ▼
[convert] ─ PDF pages → PNG images (pdftoppm from poppler)
    │
    ▼
[recognize] ─ Each page image → Ollama vision model → text
    │
    ▼
[combine] ── Concatenate all pages into one note body
    │
    ▼
[review] ─── Send to Drafts app for human review
    │
    ▼
[archive] ── Move PDF to archive folder, update manifest
```

### Key Decisions

- **Human review via Drafts** — Handwriting is messy; the note goes to Drafts first so the user can scan and correct before it hits Selene. Same pattern as voice memos.
- **One note per notebook** — All pages concatenated with `--- Page N ---` separators.
- **Local-only OCR** — No cloud APIs. Privacy-first. Vision model runs via Ollama.
- **`[?]` markers** — Unclear words are flagged so the user can quickly find spots needing attention during review.
- **capture_type: `'eink'`** — Enables downstream workflows (extract-tasks) to add context-aware hints.

---

## File Handling & Storage

```
~/selene-data/eink/
├── watch/                  ← Symlink or direct path to iCloud folder
├── archive/                ← Processed PDFs moved here
│   └── 2026-03-21-notebook-name.pdf
├── pages/                  ← Temporary extracted page images (cleaned up)
│   └── 2026-03-21-notebook-name/
│       ├── page-001.png
│       ├── page-002.png
│       └── page-003.png
└── .processed.json         ← Manifest tracking
```

### Manifest Entry

```json
{
  "notebook-name.pdf": {
    "processedAt": "2026-03-21T10:30:00Z",
    "pageCount": 3,
    "archivedTo": "~/selene-data/eink/archive/2026-03-21-notebook-name.pdf",
    "sentToDrafts": true,
    "draftsTitle": "E-Ink: notebook name"
  }
}
```

- Page images are temporary — extracted, OCR'd, then deleted.
- Original PDFs preserved in `archive/` indefinitely.
- File settling check (skip files modified in last 10 seconds) to avoid processing mid-sync PDFs.

---

## Vision Model & Recognition

### Model

**Starting recommendation: `granite3.2-vision:2b`**

- Purpose-built for document understanding
- Small (2B params) — fast inference, low memory alongside existing mistral:7b
- Runs well on Apple Silicon
- Swappable via config — can upgrade to `llama3.2-vision:11b` or others without code changes

### OCR Prompt (per page)

```
Transcribe all handwritten text from this image exactly as written.
Preserve line breaks and any structure (lists, headers, indentation).
If a word is unclear, make your best guess based on context and mark it with [?].
Do not add commentary or interpretation — just the raw transcription.
```

### Combined Output Format

```markdown
# E-Ink: notebook name

--- Page 1 ---
[transcribed text from page 1]

--- Page 2 ---
[transcribed text from page 2]
```

---

## Integration

After Drafts review, the note enters the standard Selene pipeline:

```
POST /webhook/api/drafts (capture_type: 'eink')
    → raw_notes table
    → process-llm.ts (concept extraction)
    → extract-tasks.ts (with eink-aware hints)
    → index-vectors.ts (embeddings)
    → detect-threads.ts (thread detection)
    → export-obsidian.ts (vault sync)
    → everything else
```

### Task Extraction Hint

For `capture_type: 'eink'`:
> "This is a transcribed handwritten notebook from an e-ink device. May contain loose ideas, sketches described as text, informal language, and OCR artifacts marked with [?]. Focus on capturing intent over exact wording."

---

## Scheduling & Trigger

### launchd Agent: `com.selene.transcribe-eink.plist`

- **Trigger:** WatchPaths on the iCloud folder (same mechanism as voice memos)
- **Behavior:** Processes all new PDFs found since last run

### Config Additions (`src/lib/config.ts`)

```typescript
einkWatchDir: '~/path/to/icloud/scribe/folder',
einkArchiveDir: '~/selene-data/eink/archive',
einkTempDir: '~/selene-data/eink/pages',
einkVisionModel: 'granite3.2-vision:2b',
```

### Dependencies

- `pdftoppm` (from poppler) — PDF to PNG conversion. Install: `brew install poppler`
- Ollama with a vision model: `ollama pull granite3.2-vision:2b`

---

## Workflow Script

**File:** `src/workflows/transcribe-eink.ts`

Follows the same structure as `transcribe-voice-memos.ts`:

| Function | Purpose |
|----------|---------|
| `scanForNewFiles()` | Detect unprocessed PDFs via manifest |
| `convertPdfToImages()` | pdftoppm extraction to PNG |
| `recognizePage()` | Ollama vision model OCR per page |
| `combinePages()` | Concatenate with page separators |
| `generateTitle()` | LLM title from combined text |
| `sendToDrafts()` | URL scheme to Drafts for review |
| `archivePdf()` | Move to archive, update manifest |
| `processNotebook()` | Full notebook pipeline |
| `retryFailedSends()` | Retry failed Drafts posts |

---

## ADHD Check

- **Reduces friction?** Yes — handwritten notes auto-flow into Selene without manual transcription
- **Makes information visible?** Yes — handwritten content becomes searchable, threadable, connected
- **Externalizes cognition?** Yes — ideas captured on paper don't stay trapped on paper
- **Realistic over idealistic?** Yes — human review step acknowledges messy handwriting reality

## Acceptance Criteria

- [ ] New PDFs in watch folder are automatically detected and processed
- [ ] Each page is OCR'd via local Ollama vision model
- [ ] Unclear words are marked with `[?]`
- [ ] Combined note is sent to Drafts for human review
- [ ] Processed PDFs are archived (not deleted)
- [ ] Manifest tracks processed files to prevent re-processing
- [ ] Notes ingested via webhook appear in SeleneChat queries and thread detection
- [ ] `capture_type: 'eink'` is set on ingested notes
- [ ] extract-tasks uses eink-aware hints for task classification
- [ ] Vision model is configurable (swappable without code changes)
- [ ] launchd agent triggers on new files via WatchPaths

## Scope Check

Estimated < 1 week. Core implementation is a single workflow script following an established pattern (voice memo pipeline). Main unknowns are vision model quality with the user's handwriting.
