# E-Ink Notebook Ingestion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically transcribe handwritten Kindle Scribe PDF notebooks using local Ollama vision models and ingest them into Selene.

**Architecture:** A TypeScript workflow (`transcribe-eink.ts`) watches an iCloud folder for new PDFs, converts pages to PNG images via `pdftoppm`, sends each page to an Ollama vision model for handwriting recognition, concatenates results into one note, sends to Drafts for human review, then archives the PDF. Follows the exact same manifest-tracking pattern as `transcribe-voice-memos.ts`.

**Tech Stack:** TypeScript, Ollama vision API (granite3.2-vision:2b), pdftoppm (poppler), launchd WatchPaths, Drafts URL scheme

**Design Doc:** `docs/plans/2026-03-21-eink-notebook-ingestion-design.md`

**Reference Implementation:** `src/workflows/transcribe-voice-memos.ts`

---

## Prerequisites

Before starting implementation:

```bash
# Install poppler for PDF→PNG conversion
brew install poppler

# Pull the vision model
ollama pull granite3.2-vision:2b

# Verify both work
which pdftoppm
ollama run granite3.2-vision:2b "describe this image" # (will fail without image, but confirms model loads)
```

---

### Task 1: Add Ollama Vision Support

The current `ollama.ts` only supports text generation. We need a function that sends images to Ollama's vision API.

**Files:**
- Modify: `src/lib/ollama.ts`
- Create: `src/lib/__tests__/ollama-vision.test.ts`

**Step 1: Write the failing test**

```typescript
// src/lib/__tests__/ollama-vision.test.ts
import { generateWithImage } from '../ollama';

describe('generateWithImage', () => {
  it('should be a function that accepts prompt, imageBase64, and options', () => {
    expect(typeof generateWithImage).toBe('function');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx jest src/lib/__tests__/ollama-vision.test.ts --no-coverage`
Expected: FAIL — `generateWithImage` is not exported

**Step 3: Implement generateWithImage**

Add to `src/lib/ollama.ts`:

```typescript
export async function generateWithImage(
  prompt: string,
  imageBase64: string,
  options: GenerateOptions = {}
): Promise<string> {
  const model = options.model || config.ollamaModel;
  const timeoutMs = options.timeoutMs || 120_000;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const body: Record<string, unknown> = {
      model,
      prompt,
      images: [imageBase64],
      stream: false,
    };

    if (options.temperature !== undefined || options.maxTokens !== undefined) {
      body.options = {
        ...(options.temperature !== undefined && { temperature: options.temperature }),
        ...(options.maxTokens !== undefined && { num_predict: options.maxTokens }),
      };
    }

    const response = await fetch(`${config.ollamaUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Ollama vision request failed: ${response.status} ${text}`);
    }

    const data = (await response.json()) as OllamaGenerateResponse;
    return data.response.trim();
  } catch (error: unknown) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error(`Ollama vision generation timed out after ${timeoutMs}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `npx jest src/lib/__tests__/ollama-vision.test.ts --no-coverage`
Expected: PASS

**Step 5: Commit**

```bash
git add src/lib/ollama.ts src/lib/__tests__/ollama-vision.test.ts
git commit -m "feat: add generateWithImage to ollama client for vision model support"
```

---

### Task 2: Add E-Ink Types

**Files:**
- Modify: `src/types/index.ts`

**Step 1: Add the types**

Add to `src/types/index.ts`:

```typescript
// E-ink notebook transcription
export interface EinkProcessedEntry {
  processedAt: string;
  pageCount: number;
  archivedTo: string;
  sentToDrafts: boolean;
  draftsTitle?: string;
}

export interface EinkManifest {
  files: Record<string, EinkProcessedEntry>;
}

export interface EinkWorkflowResult {
  processed: number;
  errors: number;
  retried: number;
  details: Array<{ filename: string; success: boolean; error?: string }>;
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/types/index.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/types/index.ts
git commit -m "feat: add EinkManifest and EinkWorkflowResult types"
```

---

### Task 3: Add E-Ink Config

**Files:**
- Modify: `src/lib/config.ts`

**Step 1: Add config entries**

Add alongside the voice memo config section in `src/lib/config.ts`:

```typescript
// E-ink notebook transcription
einkWatchDir: process.env.EINK_WATCH_DIR
  || join(homedir(), 'Library/Mobile Documents/com~apple~CloudDocs/Scribe'),
einkArchiveDir: process.env.EINK_ARCHIVE_DIR
  || join(getDataRoot(), 'eink', 'archive'),
einkTempDir: process.env.EINK_TEMP_DIR
  || join(getDataRoot(), 'eink', 'pages'),
einkVisionModel: process.env.EINK_VISION_MODEL || 'granite3.2-vision:2b',
```

Note: `getDataRoot()` should return `~/selene-data` (production), `~/selene-data-dev` (dev), or `data-test` (test). Follow the same pattern used for `voiceMemosOutputDir`. If no `getDataRoot()` helper exists, inline the same logic used for other paths.

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/lib/config.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat: add eink config entries for watch dir, archive, temp, and vision model"
```

---

### Task 4: Add E-Ink Capture Type Hint

**Files:**
- Modify: `src/workflows/extract-tasks.ts`

**Step 1: Add the eink case to getCaptureTypeHint**

In `src/workflows/extract-tasks.ts`, find the `getCaptureTypeHint` function's switch statement and add before the `default:` case:

```typescript
case 'eink':
  return '\n\nContext: This is a transcribed handwritten notebook from an e-ink device (Kindle Scribe). May contain loose ideas, sketches described as text, informal language, and OCR artifacts marked with [?]. Focus on capturing intent over exact wording.\n\n';
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/workflows/extract-tasks.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/extract-tasks.ts
git commit -m "feat: add eink capture type hint to extract-tasks"
```

---

### Task 5: Create the Transcribe E-Ink Workflow

This is the main task. Model it closely on `src/workflows/transcribe-voice-memos.ts`.

**Files:**
- Create: `src/workflows/transcribe-eink.ts`

**Step 1: Write the complete workflow**

```typescript
// src/workflows/transcribe-eink.ts

import {
  existsSync, mkdirSync, readFileSync, writeFileSync,
  readdirSync, statSync, copyFileSync, unlinkSync, rmSync
} from 'fs';
import { join, basename, extname } from 'path';
import { execSync } from 'child_process';
import { createWorkflowLogger } from '../lib/logger';
import { config } from '../lib/config';
import { generate, generateWithImage } from '../lib/ollama';
import type { EinkManifest, EinkProcessedEntry, EinkWorkflowResult } from '../types';

const log = createWorkflowLogger('transcribe-eink');

const MANIFEST_FILENAME = '.processed.json';
const MIN_FILE_SIZE_BYTES = 1024;       // 1KB minimum (skip empty/corrupt PDFs)
const FILE_SETTLE_SECONDS = 10;         // Wait for iCloud sync to finish
const VISION_TIMEOUT_MS = 3 * 60 * 1000; // 3 minutes per page
const OCR_PROMPT = `Transcribe all handwritten text from this image exactly as written.
Preserve line breaks and any structure (lists, headers, indentation).
If a word is unclear, make your best guess based on context and mark it with [?].
Do not add commentary or interpretation — just the raw transcription.`;

// --- Manifest Management ---

function manifestPath(): string {
  return join(config.einkWatchDir, MANIFEST_FILENAME);
}

function loadManifest(): EinkManifest {
  const path = manifestPath();
  if (!existsSync(path)) return { files: {} };
  try {
    return JSON.parse(readFileSync(path, 'utf-8')) as EinkManifest;
  } catch {
    log.warn('Corrupt manifest, starting fresh');
    return { files: {} };
  }
}

function saveManifest(manifest: EinkManifest): void {
  writeFileSync(manifestPath(), JSON.stringify(manifest, null, 2));
}

// --- File Scanning ---

interface NewPdfFile {
  filename: string;
  fullPath: string;
}

function scanForNewFiles(manifest: EinkManifest): NewPdfFile[] {
  const watchDir = config.einkWatchDir;
  if (!existsSync(watchDir)) {
    log.warn({ watchDir }, 'Watch directory does not exist');
    return [];
  }

  const files = readdirSync(watchDir).filter(f =>
    extname(f).toLowerCase() === '.pdf'
  );

  const newFiles: NewPdfFile[] = [];
  const now = Date.now();

  for (const filename of files) {
    if (manifest.files[filename]) continue; // Already processed

    const fullPath = join(watchDir, filename);
    try {
      const stat = statSync(fullPath);

      if (stat.size < MIN_FILE_SIZE_BYTES) {
        log.debug({ filename, size: stat.size }, 'Skipping: too small');
        continue;
      }

      const ageSeconds = (now - stat.mtimeMs) / 1000;
      if (ageSeconds < FILE_SETTLE_SECONDS) {
        log.debug({ filename, ageSeconds }, 'Skipping: still syncing');
        continue;
      }

      newFiles.push({ filename, fullPath });
    } catch (err) {
      log.warn({ filename, err }, 'Error checking file, skipping');
    }
  }

  return newFiles;
}

// --- PDF Conversion ---

function convertPdfToImages(pdfPath: string, outputDir: string): string[] {
  mkdirSync(outputDir, { recursive: true });

  const outputPrefix = join(outputDir, 'page');
  execSync(
    `pdftoppm -png -r 300 "${pdfPath}" "${outputPrefix}"`,
    { timeout: 60_000 }
  );

  // pdftoppm outputs page-01.png, page-02.png, etc.
  const pages = readdirSync(outputDir)
    .filter(f => f.startsWith('page-') && f.endsWith('.png'))
    .sort();

  return pages.map(p => join(outputDir, p));
}

// --- OCR Recognition ---

async function recognizePage(imagePath: string): Promise<string> {
  const imageBuffer = readFileSync(imagePath);
  const imageBase64 = imageBuffer.toString('base64');

  const text = await generateWithImage(OCR_PROMPT, imageBase64, {
    model: config.einkVisionModel,
    timeoutMs: VISION_TIMEOUT_MS,
    temperature: 0.1,
  });

  return text;
}

function combinePages(pageTexts: string[]): string {
  return pageTexts
    .map((text, i) => `--- Page ${i + 1} ---\n${text}`)
    .join('\n\n');
}

// --- Title Generation ---

async function generateTitle(content: string, fallbackTitle: string): Promise<string> {
  const truncated = content.slice(0, 500);
  const prompt = `Generate a short descriptive title (5-8 words) for these handwritten notes. Return ONLY the title, no quotes or punctuation:\n\n${truncated}`;

  try {
    const title = await generate(prompt, {
      temperature: 0.3,
      maxTokens: 20,
      timeoutMs: 15_000,
    });

    const cleaned = title.replace(/^["']|["']$/g, '').trim();
    if (cleaned.length >= 3 && cleaned.length <= 100) {
      return cleaned;
    }
  } catch (err) {
    log.warn({ err }, 'Title generation failed, using fallback');
  }

  return fallbackTitle;
}

// --- Drafts Integration ---

async function sendToDrafts(title: string, content: string): Promise<boolean> {
  const fullContent = `# ${title}\n\n${content}`;
  const encoded = encodeURIComponent(fullContent);
  const tag = 'eink-notebook';
  const url = `drafts://x-callback-url/create?text=${encoded}&tag=${tag}`;

  try {
    execSync(`open "${url}"`, { timeout: 10_000 });
    return true;
  } catch (err) {
    log.error({ err, title }, 'Failed to send to Drafts');
    return false;
  }
}

// --- Main Processing ---

async function processNotebook(
  pdf: NewPdfFile,
  manifest: EinkManifest
): Promise<void> {
  const nameWithoutExt = basename(pdf.filename, '.pdf');
  const datePrefix = new Date().toISOString().slice(0, 10);
  const outputDir = join(config.einkTempDir, `${datePrefix}-${nameWithoutExt}`);

  log.info({ filename: pdf.filename }, 'Processing notebook');

  // 1. Convert PDF to images
  const pageImages = convertPdfToImages(pdf.fullPath, outputDir);
  log.info({ filename: pdf.filename, pageCount: pageImages.length }, 'Extracted pages');

  if (pageImages.length === 0) {
    log.warn({ filename: pdf.filename }, 'No pages extracted, skipping');
    return;
  }

  try {
    // 2. OCR each page
    const pageTexts: string[] = [];
    for (let i = 0; i < pageImages.length; i++) {
      log.info({ filename: pdf.filename, page: i + 1, total: pageImages.length }, 'Recognizing page');
      const text = await recognizePage(pageImages[i]);
      pageTexts.push(text);
    }

    // 3. Combine pages
    const combined = combinePages(pageTexts);

    // 4. Generate title
    const fallbackTitle = `E-Ink: ${nameWithoutExt}`;
    const title = await generateTitle(combined, fallbackTitle);

    // 5. Send to Drafts for review
    const sent = await sendToDrafts(title, combined);

    // 6. Archive PDF
    mkdirSync(config.einkArchiveDir, { recursive: true });
    const archivePath = join(config.einkArchiveDir, `${datePrefix}-${pdf.filename}`);
    copyFileSync(pdf.fullPath, archivePath);
    unlinkSync(pdf.fullPath);

    // 7. Update manifest
    const entry: EinkProcessedEntry = {
      processedAt: new Date().toISOString(),
      pageCount: pageImages.length,
      archivedTo: archivePath,
      sentToDrafts: sent,
      draftsTitle: title,
    };
    manifest.files[pdf.filename] = entry;
    saveManifest(manifest);

    log.info({ filename: pdf.filename, title, pageCount: pageImages.length, sent }, 'Notebook processed');
  } finally {
    // 8. Cleanup temp images
    if (existsSync(outputDir)) {
      rmSync(outputDir, { recursive: true, force: true });
    }
  }
}

// --- Retry Failed Sends ---

async function retryFailedSends(manifest: EinkManifest): Promise<number> {
  let retried = 0;
  for (const [filename, entry] of Object.entries(manifest.files)) {
    if (entry.sentToDrafts) continue;

    log.info({ filename }, 'Retrying Drafts send');
    const title = entry.draftsTitle || `E-Ink: ${filename}`;

    // We don't have the content anymore (it was temporary), so we can't retry content send.
    // Mark as sent to avoid infinite retries. User can re-process from archive if needed.
    log.warn({ filename }, 'Cannot retry content send — original text not preserved. Marking as sent.');
    entry.sentToDrafts = true;
    retried++;
  }

  if (retried > 0) saveManifest(manifest);
  return retried;
}

// --- Main Export ---

export async function transcribeEink(): Promise<EinkWorkflowResult> {
  const result: EinkWorkflowResult = { processed: 0, errors: 0, retried: 0, details: [] };

  // Preflight: check pdftoppm
  try {
    execSync('which pdftoppm', { stdio: 'pipe' });
  } catch {
    log.error('pdftoppm not found. Install poppler: brew install poppler');
    return result;
  }

  // Ensure directories exist
  mkdirSync(config.einkArchiveDir, { recursive: true });
  mkdirSync(config.einkTempDir, { recursive: true });

  const manifest = loadManifest();

  // Retry failed sends first
  result.retried = await retryFailedSends(manifest);

  // Scan for new files
  const newFiles = scanForNewFiles(manifest);
  if (newFiles.length === 0) {
    log.info('No new PDFs found');
    return result;
  }

  log.info({ count: newFiles.length }, 'Found new PDFs');

  for (const pdf of newFiles) {
    try {
      await processNotebook(pdf, manifest);
      result.processed++;
      result.details.push({ filename: pdf.filename, success: true });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      log.error({ filename: pdf.filename, err }, 'Failed to process notebook');
      result.errors++;
      result.details.push({ filename: pdf.filename, success: false, error: message });
    }
  }

  return result;
}

// CLI entry point
if (require.main === module) {
  transcribeEink()
    .then(result => {
      log.info(result, 'E-ink transcription complete');
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch(err => {
      log.error({ err }, 'E-ink transcription failed');
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit src/workflows/transcribe-eink.ts`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/transcribe-eink.ts
git commit -m "feat: add transcribe-eink workflow for Kindle Scribe PDF notebooks"
```

---

### Task 6: Create launchd Agent

**Files:**
- Create: `launchd/com.selene.transcribe-eink.plist`

**Step 1: Create the plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.selene.transcribe-eink</string>

  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/npx</string>
    <string>ts-node</string>
    <string>src/workflows/transcribe-eink.ts</string>
  </array>

  <key>WorkingDirectory</key>
  <string>/Users/chaseeasterling/selene</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>SELENE_ENV</key>
    <string>production</string>
    <key>SELENE_DB_PATH</key>
    <string>/Users/chaseeasterling/selene-data/selene.db</string>
  </dict>

  <key>WatchPaths</key>
  <array>
    <string>/Users/chaseeasterling/Library/Mobile Documents/com~apple~CloudDocs/Scribe</string>
  </array>

  <key>ThrottleInterval</key>
  <integer>30</integer>

  <key>StandardOutPath</key>
  <string>/Users/chaseeasterling/selene/logs/transcribe-eink.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/chaseeasterling/selene/logs/transcribe-eink.error.log</string>
</dict>
</plist>
```

Note: The `WatchPaths` value must match the user's actual iCloud Scribe folder. The default above assumes `~/Library/Mobile Documents/com~apple~CloudDocs/Scribe`. The `ThrottleInterval` is 30 seconds (longer than voice memos) because PDF OCR takes longer and we don't want overlapping runs.

**Step 2: Verify plist is valid**

Run: `plutil -lint launchd/com.selene.transcribe-eink.plist`
Expected: `launchd/com.selene.transcribe-eink.plist: OK`

**Step 3: Commit**

```bash
git add launchd/com.selene.transcribe-eink.plist
git commit -m "feat: add launchd agent for eink notebook transcription"
```

---

### Task 7: Update Documentation

**Files:**
- Modify: `CLAUDE.md` — add workflow to architecture list, launchd list, and command reference

**Step 1: Update CLAUDE.md**

Add `transcribe-eink.ts` to the workflows list in the Architecture section:

```
    transcribe-voice-memos.ts   # whisper.cpp voice transcription
    transcribe-eink.ts          # Vision LLM e-ink notebook OCR
```

Add the launchd entry:

```
  com.selene.transcribe-eink.plist           # WatchPaths trigger
```

Add to the workflow commands section:

```bash
npx ts-node src/workflows/transcribe-eink.ts
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add eink transcription to architecture docs"
```

---

### Task 8: Manual Integration Test

This test must be done manually since it requires Ollama, pdftoppm, and a real PDF.

**Step 1: Create a test PDF**

Write something by hand on your Kindle Scribe and sync it to the iCloud folder. Or, for a quick smoke test, put any PDF with text in the watch folder.

**Step 2: Run the workflow manually**

```bash
npx ts-node src/workflows/transcribe-eink.ts
```

**Step 3: Verify results**

- [ ] PDF was detected and processed (check logs: `tail -f logs/selene.log | npx pino-pretty`)
- [ ] Page images were created and cleaned up (check `~/selene-data/eink/pages/` is empty)
- [ ] PDF was moved to `~/selene-data/eink/archive/`
- [ ] `.processed.json` has an entry for the file
- [ ] A note appeared in Drafts with `[?]` markers on unclear words
- [ ] The Drafts tag is `eink-notebook`

**Step 4: Test the full pipeline**

After reviewing in Drafts, send the note to Selene. Then verify:

```bash
sqlite3 ~/selene-data/selene.db "SELECT id, title, capture_type FROM raw_notes ORDER BY id DESC LIMIT 1;"
```

Expected: `capture_type` should be `eink` (set by the Drafts action, which needs to include `capture_type` in the webhook POST body).

**Step 5: Test idempotency**

Run the workflow again:

```bash
npx ts-node src/workflows/transcribe-eink.ts
```

Expected: "No new PDFs found" — the manifest prevents re-processing.

**Step 6: Install launchd agent**

```bash
./scripts/install-launchd.sh
# Or manually:
cp launchd/com.selene.transcribe-eink.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.selene.transcribe-eink.plist
```

Verify it's loaded:

```bash
launchctl list | grep eink
```

**Step 7: Commit any final adjustments**

```bash
git add -A
git commit -m "fix: integration test adjustments for eink workflow"
```

---

## Task Summary

| Task | What | Files | Estimated |
|------|------|-------|-----------|
| 1 | Add Ollama vision support | `src/lib/ollama.ts` | 5 min |
| 2 | Add e-ink types | `src/types/index.ts` | 2 min |
| 3 | Add e-ink config | `src/lib/config.ts` | 3 min |
| 4 | Add capture type hint | `src/workflows/extract-tasks.ts` | 2 min |
| 5 | Create workflow script | `src/workflows/transcribe-eink.ts` | 15 min |
| 6 | Create launchd agent | `launchd/com.selene.transcribe-eink.plist` | 3 min |
| 7 | Update documentation | `CLAUDE.md` | 3 min |
| 8 | Manual integration test | — | 10 min |

**Total: ~8 tasks, ~45 minutes**
