# n8n Replacement Design: Plain TypeScript Scripts

**Date:** 2026-01-09
**Status:** Approved
**Author:** Claude + Chase

---

## Problem

n8n causes friction without providing value:

1. **Workflow JSON sync** - Export/update cycle is tedious; changes in UI don't persist to git cleanly
2. **Debugging difficulty** - Hard to see what's happening, logs are unclear, errors are cryptic
3. **Operational overhead** - Docker setup, module path hacking (better-sqlite3), environment complexity

The visual workflow model was valuable for human editing, but Claude does the implementation work now. We're paying the n8n tax without getting the benefit.

---

## Solution

Replace n8n with plain TypeScript scripts that Claude edits directly.

**Principles:**
- Simplicity over features
- Observability built-in
- Minimal ops - no Docker, runs natively on Mac
- Database as coordinator - scripts poll for work
- Preserve all external integrations (webhook URL, Things bridge, Ollama config)

---

## Architecture

### Project Structure

```
selene/
├── src/
│   ├── server.ts              # Webhook server (runs continuously)
│   ├── workflows/
│   │   ├── ingest.ts          # Receive note, store in SQLite
│   │   ├── process-llm.ts     # Send to Ollama, extract concepts
│   │   ├── extract-tasks.ts   # Classify, route to Things
│   │   ├── compute-embeddings.ts  # Generate embeddings
│   │   ├── compute-associations.ts # Find similar notes
│   │   └── daily-summary.ts   # Generate daily summary
│   ├── lib/
│   │   ├── db.ts              # SQLite connection + helpers
│   │   ├── ollama.ts          # Ollama API client
│   │   ├── logger.ts          # Structured logging (pino)
│   │   └── config.ts          # Environment/paths
│   └── types/
│       └── index.ts           # Shared TypeScript types
├── scripts/
│   └── things-bridge/         # Keep existing AppleScript bridge
├── logs/                      # Structured log files (JSON)
├── data/
│   └── selene.db              # SQLite database (unchanged)
├── launchd/                   # plist files for scheduling
├── archive/
│   └── n8n-workflows/         # Archived n8n workflows (for rollback)
├── package.json
└── tsconfig.json
```

### Data Flow

```
[Drafts App]
     │
     ▼ POST /webhook/api/drafts
[server.ts] ──► [ingest.ts] ──► SQLite (status='pending')
                                      │
              ┌───────────────────────┘
              ▼ (launchd, every 5 min)
        [process-llm.ts] ──► Ollama ──► SQLite (status='processed')
              │
              ├──► [extract-tasks.ts] ──► Things (via AppleScript bridge)
              │
              └──► [compute-embeddings.ts] ──► SQLite (note_embeddings)
                          │
                          ▼ (launchd, hourly)
                   [compute-associations.ts] ──► SQLite (note_associations)

[launchd, daily at midnight]
        [daily-summary.ts] ──► Ollama ──► Obsidian vault
```

### Polling vs Pipeline

Scripts poll for work via launchd rather than direct pipeline chaining. This provides:
- Resilience to Ollama slowness/downtime
- Independent failure and retry per step
- Simpler debugging (run any script manually)
- No hanging webhooks

Trade-off: Up to 5 minute delay between steps. Acceptable for personal notes system.

---

## Component Details

### Webhook Server

```typescript
// src/server.ts
import Fastify from 'fastify';
import { ingest } from './workflows/ingest';
import { logger } from './lib/logger';

const server = Fastify();

server.post('/webhook/api/drafts', async (request, reply) => {
  const { title, content, created_at, test_run } = request.body as any;

  logger.info({ title, test_run }, 'Note received');

  try {
    const result = await ingest({ title, content, created_at, test_run });

    if (result.duplicate) {
      logger.info({ title }, 'Duplicate detected, skipped');
      return { status: 'duplicate', id: result.existingId };
    }

    logger.info({ id: result.id, title }, 'Note ingested');
    return { status: 'created', id: result.id };
  } catch (err) {
    logger.error({ err, title }, 'Ingestion failed');
    reply.status(500);
    return { status: 'error', message: err.message };
  }
});

server.listen({ port: 5678, host: '0.0.0.0' }, () => {
  logger.info('Selene webhook server running on :5678');
});
```

Same webhook URL as n8n - Drafts action doesn't need to change.

### Workflow Script Pattern

Each workflow follows the same pattern:

```typescript
// src/workflows/ingest.ts
import { db } from '../lib/db';
import { logger } from '../lib/logger';
import { createHash } from 'crypto';

interface IngestInput {
  title: string;
  content: string;
  created_at?: string;
  test_run?: string;
}

interface IngestResult {
  id?: number;
  duplicate: boolean;
  existingId?: number;
}

export async function ingest(input: IngestInput): Promise<IngestResult> {
  const { title, content, created_at, test_run } = input;

  // Generate content hash for duplicate detection
  const contentHash = createHash('sha256')
    .update(title + content)
    .digest('hex');

  // Check for duplicate
  const existing = db.prepare(
    'SELECT id FROM raw_notes WHERE content_hash = ?'
  ).get(contentHash);

  if (existing) {
    return { duplicate: true, existingId: existing.id };
  }

  // Extract tags from content
  const tags = content.match(/#\w+/g) || [];

  // Insert note
  const result = db.prepare(`
    INSERT INTO raw_notes (title, content, content_hash, tags, created_at, status, test_run)
    VALUES (?, ?, ?, ?, ?, 'pending', ?)
  `).run(title, content, contentHash, JSON.stringify(tags), created_at || new Date().toISOString(), test_run);

  logger.info({ id: result.lastInsertRowid, title }, 'Note stored');

  return { id: result.lastInsertRowid as number, duplicate: false };
}

// CLI entry point
if (require.main === module) {
  console.log('Ingest workflow - call via server or import');
}
```

**Pattern:**
- Typed input/output interfaces
- Exported async function (importable by server or other scripts)
- Structured logging throughout
- CLI entry point for manual runs

### Shared Libraries

```typescript
// src/lib/config.ts
import { join } from 'path';

export const config = {
  // Paths - same as current setup
  dbPath: process.env.SELENE_DB_PATH || join(__dirname, '../../data/selene.db'),
  logsPath: join(__dirname, '../../logs'),

  // Ollama - same config
  ollamaUrl: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  ollamaModel: process.env.OLLAMA_MODEL || 'mistral:7b',
  embeddingModel: process.env.OLLAMA_EMBED_MODEL || 'nomic-embed-text',

  // Server
  port: parseInt(process.env.PORT || '5678'),

  // Things bridge - unchanged
  thingsPendingDir: join(__dirname, '../../scripts/things-bridge/pending'),
};
```

```typescript
// src/lib/db.ts
import Database from 'better-sqlite3';
import { config } from './config';

export const db = new Database(config.dbPath);
db.pragma('journal_mode = WAL');

export function getPendingNotes(limit = 10) {
  return db.prepare(
    'SELECT * FROM raw_notes WHERE status = ? LIMIT ?'
  ).all('pending', limit);
}

export function markProcessed(id: number) {
  db.prepare('UPDATE raw_notes SET status = ?, processed_at = ? WHERE id = ?')
    .run('processed', new Date().toISOString(), id);
}
```

```typescript
// src/lib/ollama.ts
import { config } from './config';

export async function generate(prompt: string, model = config.ollamaModel) {
  const response = await fetch(`${config.ollamaUrl}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, prompt, stream: false }),
  });
  const data = await response.json();
  return data.response;
}

export async function embed(text: string) {
  const response = await fetch(`${config.ollamaUrl}/api/embeddings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: config.embeddingModel, prompt: text }),
  });
  const data = await response.json();
  return data.embedding;
}
```

### Logging & Observability

```typescript
// src/lib/logger.ts
import pino from 'pino';
import { join } from 'path';
import { config } from './config';

const logFile = join(config.logsPath, 'selene.log');

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    targets: [
      { target: 'pino-pretty', level: 'info', options: { colorize: true } },
      { target: 'pino/file', level: 'debug', options: { destination: logFile } },
    ],
  },
});

export const createWorkflowLogger = (workflow: string) =>
  logger.child({ workflow });
```

**CLI commands for logs:**
```bash
# Tail live logs
tail -f logs/selene.log | npx pino-pretty

# Search for errors
grep '"level":50' logs/selene.log | npx pino-pretty

# Find activity for specific note
grep '"noteId":123' logs/selene.log | npx pino-pretty
```

### Scheduling with launchd

Example plist:

```xml
<!-- launchd/com.selene.process-llm.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.process-llm</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>/Users/chaseeasterling/selene/src/workflows/process-llm.ts</string>
    </array>

    <key>StartInterval</key>
    <integer>300</integer>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/process-llm.out.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/process-llm.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Schedule:**
| Workflow | Frequency | Trigger |
|----------|-----------|---------|
| server.ts | Always running | launchd KeepAlive |
| process-llm.ts | Every 5 min | StartInterval |
| extract-tasks.ts | Every 5 min | StartInterval |
| compute-embeddings.ts | Every 5 min | StartInterval |
| compute-associations.ts | Hourly | StartInterval |
| daily-summary.ts | Daily midnight | StartCalendarInterval |

---

## What Stays the Same

- **Webhook URL:** `/webhook/api/drafts` on port 5678
- **Database:** `data/selene.db` with existing schema
- **Things bridge:** AppleScript + launchd in `scripts/things-bridge/`
- **Ollama config:** Same environment variables
- **Test markers:** `test_run` column pattern preserved

---

## Migration Plan

### Phase 1: Setup
1. Initialize TypeScript project (`package.json`, `tsconfig.json`)
2. Create `src/lib/` shared code (db, logger, config, ollama)
3. Verify connection to existing `data/selene.db`

### Phase 2: Build & Test (parallel to n8n)
4. Build `src/server.ts` webhook on different port (5679)
5. Build each workflow script, test with `test_run` markers
6. Test full flow: Drafts → webhook → database → processing

### Phase 3: Switchover
7. Stop n8n: `pkill -f "n8n start"` or stop Docker
8. Archive workflows: `mv workflows/ archive/n8n-workflows/`
9. Switch webhook port to 5678
10. Install launchd plists
11. Verify Drafts action works (same URL)

### Phase 4: Cleanup & Documentation
12. Update `CLAUDE.md` - remove all n8n references
13. Update `.claude/OPERATIONS.md` - new commands
14. Update `.claude/PROJECT-STATUS.md` - new architecture
15. Remove n8n-specific files: `docker-compose.yml`, `Dockerfile`, etc.
16. Delete `workflows/CLAUDE.md` and workflow-specific docs

### Rollback Plan
Keep n8n Docker setup in `archive/` for 2 weeks. If something breaks badly, can restore.

---

## Documentation Updates

### CLAUDE.md Changes
- Remove "MANDATORY: Workflow Procedure Check" section
- Remove 6-step CLI workflow process
- Remove n8n references throughout
- Update "Tech Stack" - remove n8n, add "TypeScript scripts"
- Update "Quick Command Reference"
- Simplify "Common Workflows"

### New Commands
```bash
# Start server
npx ts-node src/server.ts

# Run workflow manually
npx ts-node src/workflows/process-llm.ts

# View logs
tail -f logs/selene.log | npx pino-pretty

# Check launchd jobs
launchctl list | grep selene

# Test with marker
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title":"Test","content":"Test content","test_run":"test-123"}'
```

### Files to Delete
- `workflows/CLAUDE.md`
- `workflows/*/README.md`, `workflows/*/STATUS.md`
- `docker-compose.yml`, `Dockerfile`
- n8n-specific scripts in `scripts/`

---

## Trade-offs

**What we gain:**
- Direct file editing - no export/import cycle
- Readable TypeScript instead of JSON blobs
- Structured logging with searchable context
- No Docker, no module path hacking
- Claude edits code directly

**What we trade:**
- No visual workflow editor (acceptable - Claude does the work)
- Up to 5 min processing delay (acceptable - not real-time system)

---

## Success Criteria

1. Drafts → webhook → database works without changes to Drafts action
2. All workflows process notes correctly (verified with test markers)
3. Logs are searchable and useful for debugging
4. launchd keeps everything running reliably
5. Documentation accurately reflects new architecture
6. Can edit any workflow by changing a `.ts` file directly
