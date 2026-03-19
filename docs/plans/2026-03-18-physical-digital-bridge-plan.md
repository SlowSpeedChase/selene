# Physical <-> Digital Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the loop between physical and digital capture — whiteboard photos enter Selene via Claude Vision, and Selene's brain prints to a daily planning sheet that feeds annotations back in.

**Architecture:** iOS Shortcut sends whiteboard photos to Claude Vision (Haiku 3.5) for interpretation, POSTs structured markdown to the existing `/webhook/api/drafts` endpoint with a new `capture_type` field. A new `render-daily-sheet.ts` workflow generates a QR-coded PDF daily planning sheet via Puppeteer. Annotated sheets photograph back through the same Shortcut, completing the loop.

**Tech Stack:** TypeScript, Fastify, better-sqlite3, Puppeteer (new dep), Claude API (Haiku 3.5), iOS Shortcuts, launchd

**Design Doc:** `docs/plans/2026-03-18-physical-digital-bridge-design.md`

---

## Task 1: Schema Migration — Add `capture_type` to `raw_notes`

**Files:**
- Create: `database/migrations/021_capture_type.sql`
- Modify: `src/lib/db.ts:94-123` (insertNote function)
- Modify: `src/types/index.ts:5-10` (IngestInput type)
- Modify: `src/workflows/ingest.ts:8-38` (ingest function)
- Modify: `src/server.ts:101-114` (webhook handler)

**Step 1: Write the migration**

Create `database/migrations/021_capture_type.sql`:
```sql
-- Add capture_type column to raw_notes
ALTER TABLE raw_notes ADD COLUMN capture_type TEXT DEFAULT 'drafts';

-- Backfill voice memos (they come in with title starting "Voice Memo" or tag voice-memo)
UPDATE raw_notes SET capture_type = 'voice'
WHERE tags LIKE '%voice-memo%' OR title LIKE 'Voice Memo%';

-- Index for routing queries
CREATE INDEX idx_raw_notes_capture_type ON raw_notes(capture_type);
```

**Step 2: Run the migration**

Run: `npx ts-node scripts/run-migration.ts database/migrations/021_capture_type.sql`
Expected: Migration applies successfully

**Step 3: Verify migration**

Run: `sqlite3 data/selene.db "SELECT capture_type, COUNT(*) FROM raw_notes GROUP BY capture_type;"`
Expected: Shows `drafts` for most rows, `voice` for voice memos

**Step 4: Add `capture_type` to `IngestInput` type**

In `src/types/index.ts`, update `IngestInput`:
```typescript
export interface IngestInput {
  title: string;
  content: string;
  created_at?: string;
  test_run?: string;
  capture_type?: string;
}
```

**Step 5: Thread `capture_type` through `insertNote`**

In `src/lib/db.ts`, update the `insertNote` function signature and SQL:
```typescript
export function insertNote(note: {
  title: string;
  content: string;
  contentHash: string;
  tags: string[];
  createdAt: string;
  testRun?: string;
  captureType?: string;
}): number {
  const wordCount = note.content.split(/\s+/).filter(Boolean).length;
  const characterCount = note.content.length;

  const result = db
    .prepare(
      `INSERT INTO raw_notes
       (title, content, content_hash, tags, word_count, character_count, created_at, status, test_run, capture_type)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
    )
    .run(
      note.title,
      note.content,
      note.contentHash,
      JSON.stringify(note.tags),
      wordCount,
      characterCount,
      note.createdAt,
      note.testRun || null,
      note.captureType || 'drafts'
    );

  return result.lastInsertRowid as number;
}
```

**Step 6: Thread `capture_type` through `ingest.ts`**

In `src/workflows/ingest.ts`, update the destructure and `insertNote` call:
```typescript
export async function ingest(input: IngestInput): Promise<IngestResult> {
  const { title, content, created_at, test_run, capture_type } = input;

  // ... existing duplicate detection and tag extraction ...

  const id = insertNote({
    title,
    content,
    contentHash,
    tags,
    createdAt,
    testRun: test_run,
    captureType: capture_type,
  });
```

**Step 7: Thread `capture_type` through the webhook handler**

In `src/server.ts`, update the webhook POST handler to pass `capture_type`:
```typescript
server.post<{ Body: IngestInput }>('/webhook/api/drafts', async (request, reply) => {
  const { title, content, created_at, test_run, capture_type } = request.body;
  // ...
  const result = await ingest({ title, content, created_at, test_run, capture_type });
```

**Step 8: Test the full pipeline**

Run:
```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Whiteboard", "content": "Project ideas grouped by theme", "capture_type": "whiteboard", "test_run": "test-bridge-001"}'
```
Expected: 201 response with `status: "created"`

Verify:
```bash
sqlite3 data/selene.db "SELECT id, title, capture_type FROM raw_notes WHERE test_run = 'test-bridge-001';"
```
Expected: Shows `whiteboard` as capture_type

**Step 9: Clean up and commit**

Run: `./scripts/cleanup-tests.sh test-bridge-001`

```bash
git add database/migrations/021_capture_type.sql src/types/index.ts src/lib/db.ts src/workflows/ingest.ts src/server.ts
git commit -m "feat: add capture_type column to raw_notes pipeline

Migration 021 adds capture_type to raw_notes with 'drafts' default.
Threads capture_type through IngestInput -> ingest() -> insertNote().
Backfills voice memos. Enables per-source routing in extract-tasks."
```

---

## Task 2: `extract-tasks.ts` — Capture-Type-Aware Classification

**Files:**
- Modify: `src/workflows/extract-tasks.ts:53-60` (CLASSIFY_PROMPT), `:87-96` (query), `:107-113` (classification call)

**Step 1: Update the query to include `capture_type`**

In `extract-tasks.ts`, update the notes query to also fetch `capture_type`:
```typescript
const notes = db
  .prepare(
    `SELECT rn.id, rn.title, rn.content, rn.capture_type
     FROM raw_notes rn
     JOIN processed_notes pn ON rn.id = pn.raw_note_id
     WHERE rn.status = 'processed'
     AND (pn.things_integration_status IS NULL OR pn.things_integration_status = 'pending')
     LIMIT ?`
  )
  .all(limit) as Array<{ id: number; title: string; content: string; capture_type: string | null }>;
```

**Step 2: Add capture-type prompt hints**

Add a helper function before the main `extractTasks` function:
```typescript
function getCaptureTypeHint(captureType: string | null): string {
  switch (captureType) {
    case 'whiteboard':
      return '\n\nContext: This was captured from a whiteboard photo. Whiteboards typically contain planning, brainstorming, and high-level ideas rather than individual tasks. Bias toward needs_planning unless you see explicit checkbox-style tasks.\n\n';
    case 'daily_sheet_annotation':
      return '\n\nContext: This contains handwritten annotations from a daily planning sheet. Look for: completed tasks (checked items), new ideas (scratch zone notes), and thread-related observations.\n\n';
    default:
      return '';
  }
}
```

**Step 3: Inject the hint into classification**

Update the classification call in the loop:
```typescript
const captureHint = getCaptureTypeHint(note.capture_type);
const classifyPrompt = CLASSIFY_PROMPT.replace('{content}', captureHint + note.content);
```

**Step 4: Test with a whiteboard-style note**

Run:
```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Whiteboard Planning", "content": "Project Selene:\n- Voice input improvements\n- Calendar integration\n- Mobile app polish\n\nThemes: capture friction, context switching\n\nQuestion: What ties these together?", "capture_type": "whiteboard", "test_run": "test-bridge-002"}'
```

Process through LLM first, then run extract-tasks:
```bash
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/extract-tasks.ts
```

Verify:
```bash
sqlite3 data/selene.db "SELECT pn.things_integration_status FROM processed_notes pn JOIN raw_notes rn ON rn.id = pn.raw_note_id WHERE rn.test_run = 'test-bridge-002';"
```
Expected: `no_tasks` (biased toward needs_planning, not actionable)

**Step 5: Clean up and commit**

Run: `./scripts/cleanup-tests.sh test-bridge-002`

```bash
git add src/workflows/extract-tasks.ts
git commit -m "feat: capture-type-aware classification in extract-tasks

Whiteboard captures biased toward needs_planning. Daily sheet
annotations parsed for completed tasks and new ideas. Default
behavior unchanged for 'drafts' capture type."
```

---

## Task 3: Install Puppeteer and Create Daily Sheet HTML Template

**Files:**
- Modify: `package.json` (add puppeteer dependency)
- Create: `src/templates/daily-sheet.html`

**Step 1: Install puppeteer**

Run: `npm install puppeteer`
Expected: puppeteer added to package.json dependencies

**Step 2: Create the HTML template**

Create `src/templates/daily-sheet.html`:
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <style>
    @page {
      size: letter;
      margin: 0.5in;
    }

    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif;
      font-size: 11pt;
      color: #1a1a1a;
      line-height: 1.4;
      width: 7.5in;
      height: 10in;
      display: flex;
      flex-direction: column;
    }

    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 8pt;
      border-bottom: 1.5pt solid #1a1a1a;
      margin-bottom: 12pt;
    }

    .header h1 {
      font-size: 14pt;
      font-weight: 600;
      letter-spacing: 2pt;
      text-transform: uppercase;
    }

    .header .date {
      font-size: 11pt;
      font-weight: 400;
      color: #555;
    }

    .header .qr {
      width: 48pt;
      height: 48pt;
    }

    .section {
      margin-bottom: 12pt;
    }

    .section-title {
      font-size: 9pt;
      font-weight: 600;
      letter-spacing: 1.5pt;
      text-transform: uppercase;
      color: #888;
      margin-bottom: 6pt;
    }

    .task-list {
      list-style: none;
    }

    .task-list li {
      padding: 3pt 0;
      padding-left: 20pt;
      position: relative;
      font-size: 10.5pt;
    }

    .task-list li::before {
      content: '';
      position: absolute;
      left: 0;
      top: 5pt;
      width: 12pt;
      height: 12pt;
      border: 1.5pt solid #1a1a1a;
      border-radius: 50%;
    }

    .thread-list {
      list-style: none;
    }

    .thread-list li {
      padding: 4pt 0;
      display: flex;
      align-items: baseline;
      gap: 6pt;
      font-size: 10.5pt;
    }

    .momentum {
      font-size: 10pt;
      width: 14pt;
      text-align: center;
      flex-shrink: 0;
    }

    .momentum.rising { color: #2d7d2d; }
    .momentum.stable { color: #666; }
    .momentum.cooling { color: #999; }

    .thread-name {
      font-weight: 500;
    }

    .thread-summary {
      color: #666;
      font-size: 9.5pt;
    }

    .capture-list {
      list-style: none;
    }

    .capture-list li {
      padding: 2pt 0;
      padding-left: 12pt;
      position: relative;
      font-size: 9.5pt;
      color: #444;
    }

    .capture-list li::before {
      content: '\00b7';
      position: absolute;
      left: 0;
      font-weight: bold;
    }

    .capture-time {
      color: #999;
      font-size: 8.5pt;
    }

    .scratch {
      flex: 1;
      min-height: 200pt;
      border: 1pt solid #ddd;
      border-radius: 4pt;
      position: relative;
    }

    .scratch-label {
      position: absolute;
      top: 6pt;
      left: 8pt;
      font-size: 8pt;
      color: #ccc;
      letter-spacing: 1pt;
      text-transform: uppercase;
    }
  </style>
</head>
<body>

  <div class="header">
    <div>
      <h1>Selene</h1>
      <span class="date">{{DATE}}</span>
    </div>
    <img class="qr" src="{{QR_DATA_URI}}" alt="QR" />
  </div>

  <div class="section">
    <div class="section-title">Tasks</div>
    <ul class="task-list">
      {{TASKS}}
    </ul>
  </div>

  <div class="section">
    <div class="section-title">Threads</div>
    <ul class="thread-list">
      {{THREADS}}
    </ul>
  </div>

  <div class="section">
    <div class="section-title">Recent Captures</div>
    <ul class="capture-list">
      {{CAPTURES}}
    </ul>
  </div>

  <div class="scratch">
    <span class="scratch-label">Scratch</span>
  </div>

</body>
</html>
```

**Step 3: Commit**

```bash
git add package.json package-lock.json src/templates/daily-sheet.html
git commit -m "feat: add puppeteer dep and daily-sheet HTML template

Letter-size layout with tasks (pen-checkable circles), threads
with momentum indicators, recent captures, and ~40% scratch zone.
QR code placeholder for annotation loop identification."
```

---

## Task 4: `render-daily-sheet.ts` — PDF Generation Workflow

**Files:**
- Create: `src/workflows/render-daily-sheet.ts`

**Step 1: Create the workflow**

Create `src/workflows/render-daily-sheet.ts`:
```typescript
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import puppeteer from 'puppeteer';
import { createWorkflowLogger, db, config, getActiveThreads, getRecentNotes } from '../lib';
import type { Thread } from '../lib/db';

const log = createWorkflowLogger('render-daily-sheet');

// QR code generation: simple SVG-based data matrix
// Encodes as a text data URI — Claude Vision can read printed text identifiers
function generateQrPlaceholder(date: string): string {
  // Use a simple text-based identifier that Claude Vision can read
  // For v1, render the date string as a small bordered label rather than a true QR
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
    <rect width="48" height="48" fill="white" stroke="#ccc" stroke-width="1" rx="4"/>
    <text x="24" y="20" text-anchor="middle" font-family="monospace" font-size="6" fill="#333">SELENE</text>
    <text x="24" y="32" text-anchor="middle" font-family="monospace" font-size="7" font-weight="bold" fill="#1a1a1a">${date}</text>
  </svg>`;
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
}

function getMomentumIndicator(score: number | null): { symbol: string; cssClass: string } {
  if (score === null || score === undefined) return { symbol: '\u2022', cssClass: 'stable' };
  if (score >= 0.6) return { symbol: '\u25B2', cssClass: 'rising' };
  if (score >= 0.3) return { symbol: '\u25CF', cssClass: 'stable' };
  return { symbol: '\u25BC', cssClass: 'cooling' };
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatRelativeTime(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));

  if (diffHours < 1) return 'just now';
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffHours < 48) return 'yesterday';
  return `${Math.floor(diffHours / 24)}d ago`;
}

interface DailySheetData {
  date: string;
  tasks: Array<{ title: string; notes?: string }>;
  threads: Array<{ name: string; summary: string | null; momentum_score: number | null }>;
  captures: Array<{ title: string; created_at: string }>;
}

function gatherData(): DailySheetData {
  const today = new Date();
  const dateStr = today.toISOString().split('T')[0];

  // Active tasks (from task_metadata, not completed)
  const tasks = db
    .prepare(
      `SELECT tm.id, rn.title, rn.content
       FROM task_metadata tm
       JOIN raw_notes rn ON tm.raw_note_id = rn.id
       WHERE tm.completed_at IS NULL
         AND rn.test_run IS NULL
       ORDER BY tm.id DESC
       LIMIT 12`
    )
    .all() as Array<{ title: string; content: string }>;

  // Active threads with momentum
  const threads = getActiveThreads(8);

  // Recent captures (last 24 hours)
  const captures = getRecentNotes(1, 10);

  return {
    date: dateStr,
    tasks: tasks.map((t) => ({ title: t.title })),
    threads: threads.map((t: Thread) => ({
      name: t.name,
      summary: t.summary,
      momentum_score: t.momentum_score,
    })),
    captures: captures.map((n) => ({
      title: n.title,
      created_at: n.created_at,
    })),
  };
}

function renderHtml(data: DailySheetData): string {
  const templatePath = join(config.projectRoot, 'src', 'templates', 'daily-sheet.html');
  let html = readFileSync(templatePath, 'utf-8');

  // Date
  html = html.replace('{{DATE}}', data.date);

  // QR
  html = html.replace('{{QR_DATA_URI}}', generateQrPlaceholder(data.date));

  // Tasks
  const tasksHtml = data.tasks.length > 0
    ? data.tasks.map((t) => `<li>${escapeHtml(t.title)}</li>`).join('\n      ')
    : '<li style="color: #999; list-style: none;">No active tasks</li>';
  html = html.replace('{{TASKS}}', tasksHtml);

  // Threads
  const threadsHtml = data.threads.length > 0
    ? data.threads
        .map((t) => {
          const m = getMomentumIndicator(t.momentum_score);
          const summary = t.summary ? ` — <span class="thread-summary">${escapeHtml(t.summary.slice(0, 80))}</span>` : '';
          return `<li><span class="momentum ${m.cssClass}">${m.symbol}</span> <span class="thread-name">${escapeHtml(t.name)}</span>${summary}</li>`;
        })
        .join('\n      ')
    : '<li style="color: #999;">No active threads</li>';
  html = html.replace('{{THREADS}}', threadsHtml);

  // Recent captures
  const capturesHtml = data.captures.length > 0
    ? data.captures
        .map(
          (c) =>
            `<li>${escapeHtml(c.title)} <span class="capture-time">${formatRelativeTime(c.created_at)}</span></li>`
        )
        .join('\n      ')
    : '<li style="color: #999;">No recent captures</li>';
  html = html.replace('{{CAPTURES}}', capturesHtml);

  return html;
}

export async function renderDailySheet(): Promise<{ success: boolean; path?: string }> {
  log.info('Starting daily sheet render');

  try {
    const data = gatherData();
    log.info(
      { tasks: data.tasks.length, threads: data.threads.length, captures: data.captures.length },
      'Data gathered'
    );

    const html = renderHtml(data);

    // Ensure output directory exists
    const outputDir = join(config.digestsPath, 'daily-sheets');
    if (!existsSync(outputDir)) {
      mkdirSync(outputDir, { recursive: true });
    }

    const pdfPath = join(outputDir, `selene-daily-${data.date}.pdf`);

    // Render PDF via Puppeteer
    const browser = await puppeteer.launch({ headless: true });
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });
    await page.pdf({
      path: pdfPath,
      format: 'Letter',
      printBackground: true,
      margin: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    });
    await browser.close();

    log.info({ pdfPath }, 'Daily sheet rendered');

    // Optional: auto-print (controlled by env var)
    if (process.env.SELENE_AUTO_PRINT === 'true') {
      const { execSync } = await import('child_process');
      try {
        execSync(`lp "${pdfPath}"`);
        log.info({ pdfPath }, 'Daily sheet sent to printer');
      } catch (err) {
        log.warn({ err }, 'Auto-print failed (non-fatal)');
      }
    }

    return { success: true, path: pdfPath };
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Failed to render daily sheet');
    return { success: false };
  }
}

// CLI entry point
if (require.main === module) {
  renderDailySheet()
    .then((result) => {
      console.log('Daily sheet render:', result);
      process.exit(result.success ? 0 : 1);
    })
    .catch((err) => {
      console.error('Daily sheet render failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Run it manually to test**

Run: `npx ts-node src/workflows/render-daily-sheet.ts`
Expected: PDF created at `~/selene-data/digests/daily-sheets/selene-daily-{date}.pdf`

**Step 3: Open the PDF and visually verify**

Run: `open ~/selene-data/digests/daily-sheets/selene-daily-$(date +%Y-%m-%d).pdf`
Expected: Single page with tasks, threads, captures, scratch zone. Readable, minimal ink.

**Step 4: Commit**

```bash
git add src/workflows/render-daily-sheet.ts
git commit -m "feat: add render-daily-sheet workflow for daily planning PDF

Gathers active tasks, threads with momentum, recent captures.
Renders HTML template to PDF via Puppeteer. Output to digests/daily-sheets/.
Optional auto-print via SELENE_AUTO_PRINT env var."
```

---

## Task 5: Launchd Agent for Daily Sheet

**Files:**
- Create: `launchd/com.selene.render-daily-sheet.plist`
- Modify: `scripts/install-launchd.sh` (add new agent)

**Step 1: Create the launchd plist**

Create `launchd/com.selene.render-daily-sheet.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.render-daily-sheet</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/npx</string>
        <string>ts-node</string>
        <string>src/workflows/render-daily-sheet.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_ENV</key>
        <string>production</string>
    </dict>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>5</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/render-daily-sheet.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/render-daily-sheet.error.log</string>
</dict>
</plist>
```

**Step 2: Add to install script**

Check `scripts/install-launchd.sh` for the pattern used for other agents and add the new plist to the install list.

**Step 3: Install the agent**

Run: `./scripts/install-launchd.sh`
Expected: `com.selene.render-daily-sheet` appears in `launchctl list | grep selene`

**Step 4: Verify scheduling**

Run: `launchctl list | grep render-daily-sheet`
Expected: Agent loaded (will trigger at 5:30am daily)

**Step 5: Commit**

```bash
git add launchd/com.selene.render-daily-sheet.plist scripts/install-launchd.sh
git commit -m "feat: add launchd agent for daily sheet rendering at 5:30am"
```

---

## Task 6: iOS Shortcut — "Capture to Selene"

**Files:**
- Create: `docs/guides/ios-shortcut-setup.md` (setup instructions)

This task is iOS Shortcuts configuration, not code. The Shortcut calls the Claude API directly and POSTs to the existing webhook.

**Step 1: Document the Shortcut setup**

Create `docs/guides/ios-shortcut-setup.md` with step-by-step instructions:

```markdown
# iOS Shortcut: "Capture to Selene"

## Setup

1. Open Shortcuts app on iPhone/iPad
2. Create new shortcut named "Capture to Selene"
3. Add actions in this order:

### Actions

**1. Receive Input**
- Accept: Images
- If there is no input: Continue (we'll open camera)

**2. If (no input received)**
- Take Photo (from Camera)
- Set variable `photo` to result

**3. Otherwise**
- Set variable `photo` to Shortcut Input

**4. End If**

**5. Resize Image**
- Image: `photo`
- Width: 1024 (saves API cost while maintaining readability)

**6. Base64 Encode**
- Input: resized image

**7. Get Contents of URL** (Claude API call)
- URL: `https://api.anthropic.com/v1/messages`
- Method: POST
- Headers:
  - `x-api-key`: (your Claude API key)
  - `anthropic-version`: `2023-06-01`
  - `content-type`: `application/json`
- Request Body (JSON):
  ```json
  {
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 1024,
    "messages": [{
      "role": "user",
      "content": [
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": "<Base64 Encoded>"
          }
        },
        {
          "type": "text",
          "text": "Interpret this handwritten note or whiteboard. Preserve spatial groupings, arrows, and relationships. Output structured markdown. If you see a label containing 'SELENE' and a date, this is an annotated daily planning sheet — extract only the handwritten annotations, not the printed content. For annotated sheets, output JSON: {\"type\": \"daily_sheet_annotation\", \"date\": \"YYYY-MM-DD\", \"completed_tasks\": [], \"new_notes\": [], \"thread_annotations\": []}. For all other images, output clean markdown."
        }
      ]
    }]
  }
  ```

**8. Get Dictionary Value**
- Key: `content[0].text` from API response

**9. If (result contains "daily_sheet_annotation")**
- Set `capture_type` to `daily_sheet_annotation`
- Set `title` to `Daily Sheet Annotations — <Current Date>`

**10. Otherwise**
- Set `capture_type` to `whiteboard`
- Set `title` to `Whiteboard — <Current Date>`

**11. End If**

**12. Get Contents of URL** (POST to Selene)
- URL: `http://<tailscale-ip>:5678/webhook/api/drafts`
- Method: POST
- Headers:
  - `Content-Type`: `application/json`
  - `Authorization`: `Bearer <your-token>`
- Request Body:
  ```json
  {
    "title": "<title>",
    "content": "<Claude response text>",
    "capture_type": "<capture_type>"
  }
  ```

**13. Show Notification**
- Title: "Selene"
- Body: "Captured!"

### Offline Fallback

Add an "If (error)" block around step 7 (Claude API call):
- On error: Use "Extract Text from Image" (Apple Vision)
- Set `capture_type` to `whiteboard_ocr`
- Continue to step 12

## Widget Setup

1. Long-press home screen → Add Widget
2. Add Shortcuts widget
3. Select "Capture to Selene" shortcut
4. Also add to Lock Screen (iOS 16+)
```

**Step 2: Build and test the Shortcut manually on device**

Test with:
1. A clean whiteboard photo → verify `capture_type: whiteboard` in DB
2. A paper note photo → verify interpretation quality
3. A photo from camera roll (Share Sheet) → verify it works

**Step 3: Commit the documentation**

```bash
git add docs/guides/ios-shortcut-setup.md
git commit -m "docs: add iOS Shortcut setup guide for Capture to Selene

Claude Vision (Haiku) interprets whiteboard/paper photos.
Detects annotated daily sheets via SELENE date label.
Offline fallback to Apple Vision OCR."
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `CLAUDE.md` (add new components to architecture)
- Modify: `.claude/PROJECT-STATUS.md` (update current status)
- Modify: `.claude/OPERATIONS.md` (add new commands)

**Step 1: Update CLAUDE.md**

Add to the Architecture > Key Components section:
- `src/workflows/render-daily-sheet.ts` — Daily planning sheet PDF
- `src/templates/daily-sheet.html` — Planning sheet HTML template
- `launchd/com.selene.render-daily-sheet.plist` — Daily at 5:30am

Add to Quick Command Reference:
```bash
# Render daily sheet manually
npx ts-node src/workflows/render-daily-sheet.ts

# Open today's sheet
open ~/selene-data/digests/daily-sheets/selene-daily-$(date +%Y-%m-%d).pdf
```

**Step 2: Update PROJECT-STATUS.md**

Add Physical <-> Digital Bridge to completed features with details.

**Step 3: Update OPERATIONS.md**

Add the new workflow to the workflow operations section.

**Step 4: Move design doc to "Done" in INDEX.md**

Move the entry from "Ready" to "Done" in `docs/plans/INDEX.md`.

**Step 5: Commit**

```bash
git add CLAUDE.md .claude/PROJECT-STATUS.md .claude/OPERATIONS.md docs/plans/INDEX.md
git commit -m "docs: update documentation for Physical <-> Digital Bridge"
```

---

## Summary

| Task | Component | Effort | Dependencies |
|------|-----------|--------|-------------|
| 1 | Schema migration + pipeline threading | Small | None |
| 2 | extract-tasks.ts capture_type routing | Small | Task 1 |
| 3 | Puppeteer + HTML template | Small | None |
| 4 | render-daily-sheet.ts workflow | Medium | Task 3 |
| 5 | Launchd agent | Tiny | Task 4 |
| 6 | iOS Shortcut setup + docs | Small | Task 1 |
| 7 | Documentation updates | Small | All above |

**Parallel tracks:**
- Tasks 1-2 (capture pipeline) and Tasks 3-5 (output pipeline) are independent and can be built in parallel
- Task 6 (iOS Shortcut) depends only on Task 1
- Task 7 (docs) comes last

**Total estimated effort:** ~4-5 hours of focused implementation
