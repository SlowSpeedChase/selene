# n8n Replacement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace n8n with plain TypeScript scripts for simpler workflow management.

**Architecture:** Fastify webhook server + standalone workflow scripts polling via launchd. Database coordinates work via status field. Structured logging with pino.

**Tech Stack:** TypeScript, Fastify, better-sqlite3, pino, launchd

**Design Doc:** `docs/plans/2026-01-09-n8n-replacement-design.md`

---

## Phase 1: Project Setup

### Task 1: Initialize TypeScript Project

**Files:**
- Create: `src/` directory
- Modify: `package.json`
- Create: `tsconfig.json`

**Step 1: Create src directory structure**

```bash
mkdir -p src/lib src/workflows src/types logs launchd
```

**Step 2: Update package.json with dependencies**

Add to `package.json`:
```json
{
  "scripts": {
    "start": "ts-node src/server.ts",
    "dev": "ts-node-dev src/server.ts",
    "workflow:process-llm": "ts-node src/workflows/process-llm.ts",
    "workflow:extract-tasks": "ts-node src/workflows/extract-tasks.ts",
    "workflow:compute-embeddings": "ts-node src/workflows/compute-embeddings.ts",
    "workflow:compute-associations": "ts-node src/workflows/compute-associations.ts",
    "workflow:daily-summary": "ts-node src/workflows/daily-summary.ts"
  },
  "dependencies": {
    "fastify": "^4.26.0",
    "better-sqlite3": "^11.0.0",
    "pino": "^8.18.0",
    "pino-pretty": "^10.3.0"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "ts-node": "^10.9.0",
    "ts-node-dev": "^2.0.0",
    "@types/node": "^20.11.0",
    "@types/better-sqlite3": "^7.6.8"
  }
}
```

**Step 3: Run npm install**

Run: `npm install`
Expected: Dependencies installed without errors

**Step 4: Create tsconfig.json**

Create `tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

**Step 5: Commit**

```bash
git add package.json tsconfig.json src/ logs/ launchd/
git commit -m "chore: initialize TypeScript project structure"
```

---

## Phase 2: Shared Libraries

### Task 2: Create Config Module

**Files:**
- Create: `src/lib/config.ts`

**Step 1: Write config module**

Create `src/lib/config.ts`:
```typescript
import { join } from 'path';

const projectRoot = join(__dirname, '../..');

export const config = {
  // Paths - same as current setup
  dbPath: process.env.SELENE_DB_PATH || join(projectRoot, 'data/selene.db'),
  logsPath: process.env.SELENE_LOGS_PATH || join(projectRoot, 'logs'),
  projectRoot,

  // Ollama - same config as n8n
  ollamaUrl: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  ollamaModel: process.env.OLLAMA_MODEL || 'mistral:7b',
  embeddingModel: process.env.OLLAMA_EMBED_MODEL || 'nomic-embed-text',

  // Server
  port: parseInt(process.env.PORT || '5678', 10),
  host: process.env.HOST || '0.0.0.0',

  // Things bridge - unchanged
  thingsPendingDir: join(projectRoot, 'scripts/things-bridge/pending'),
};
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat: add config module with environment defaults"
```

---

### Task 3: Create Logger Module

**Files:**
- Create: `src/lib/logger.ts`

**Step 1: Write logger module**

Create `src/lib/logger.ts`:
```typescript
import pino from 'pino';
import { join } from 'path';
import { existsSync, mkdirSync } from 'fs';
import { config } from './config';

// Ensure logs directory exists
if (!existsSync(config.logsPath)) {
  mkdirSync(config.logsPath, { recursive: true });
}

const logFile = join(config.logsPath, 'selene.log');

// Create logger with console + file output
export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    targets: [
      {
        target: 'pino-pretty',
        level: 'info',
        options: { colorize: true },
      },
      {
        target: 'pino/file',
        level: 'debug',
        options: { destination: logFile },
      },
    ],
  },
});

// Create child loggers per workflow
export function createWorkflowLogger(workflow: string) {
  return logger.child({ workflow });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/logger.ts
git commit -m "feat: add pino logger with file + console output"
```

---

### Task 4: Create Database Module

**Files:**
- Create: `src/lib/db.ts`

**Step 1: Write database module**

Create `src/lib/db.ts`:
```typescript
import Database from 'better-sqlite3';
import { config } from './config';
import { logger } from './logger';

// Initialize database connection
export const db = new Database(config.dbPath);

// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');

logger.info({ dbPath: config.dbPath }, 'Database connected');

// Type for raw_notes table
export interface RawNote {
  id: number;
  title: string;
  content: string;
  content_hash: string;
  source_type: string;
  word_count: number;
  character_count: number;
  tags: string | null;
  created_at: string;
  imported_at: string;
  processed_at: string | null;
  exported_at: string | null;
  status: string;
  exported_to_obsidian: number;
  test_run: string | null;
}

// Helper: Get pending notes for processing
export function getPendingNotes(limit = 10): RawNote[] {
  return db
    .prepare('SELECT * FROM raw_notes WHERE status = ? ORDER BY created_at ASC LIMIT ?')
    .all('pending', limit) as RawNote[];
}

// Helper: Get processed notes needing further work
export function getProcessedNotes(limit = 10): RawNote[] {
  return db
    .prepare('SELECT * FROM raw_notes WHERE status = ? ORDER BY processed_at ASC LIMIT ?')
    .all('processed', limit) as RawNote[];
}

// Helper: Mark note as processed
export function markProcessed(id: number): void {
  db.prepare('UPDATE raw_notes SET status = ?, processed_at = ? WHERE id = ?').run(
    'processed',
    new Date().toISOString(),
    id
  );
}

// Helper: Check for duplicate by content hash
export function findByContentHash(hash: string): RawNote | undefined {
  return db.prepare('SELECT * FROM raw_notes WHERE content_hash = ?').get(hash) as
    | RawNote
    | undefined;
}

// Helper: Insert new note
export function insertNote(note: {
  title: string;
  content: string;
  contentHash: string;
  tags: string[];
  createdAt: string;
  testRun?: string;
}): number {
  const wordCount = note.content.split(/\s+/).filter(Boolean).length;
  const characterCount = note.content.length;

  const result = db
    .prepare(
      `INSERT INTO raw_notes
       (title, content, content_hash, tags, word_count, character_count, created_at, status, test_run)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`
    )
    .run(
      note.title,
      note.content,
      note.contentHash,
      JSON.stringify(note.tags),
      wordCount,
      characterCount,
      note.createdAt,
      note.testRun || null
    );

  return result.lastInsertRowid as number;
}

// Cleanup on process exit
process.on('exit', () => {
  db.close();
});
```

**Step 2: Test database connection**

Run: `npx ts-node -e "import { db } from './src/lib/db'; console.log('Tables:', db.prepare(\"SELECT name FROM sqlite_master WHERE type='table'\").all().map((t: any) => t.name).join(', '));"`
Expected: Lists tables including `raw_notes`

**Step 3: Commit**

```bash
git add src/lib/db.ts
git commit -m "feat: add database module with typed helpers"
```

---

### Task 5: Create Ollama Client Module

**Files:**
- Create: `src/lib/ollama.ts`

**Step 1: Write Ollama client**

Create `src/lib/ollama.ts`:
```typescript
import { config } from './config';
import { logger } from './logger';

const log = logger.child({ module: 'ollama' });

export interface GenerateOptions {
  model?: string;
  temperature?: number;
  timeout?: number;
}

export interface GenerateResult {
  response: string;
  model: string;
  done: boolean;
}

// Generate text completion
export async function generate(
  prompt: string,
  options: GenerateOptions = {}
): Promise<string> {
  const model = options.model || config.ollamaModel;
  const timeout = options.timeout || 120000; // 2 minute default

  log.debug({ model, promptLength: prompt.length }, 'Sending generate request');

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(`${config.ollamaUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        prompt,
        stream: false,
        options: options.temperature ? { temperature: options.temperature } : undefined,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Ollama error: ${response.status} ${response.statusText}`);
    }

    const data = (await response.json()) as GenerateResult;
    log.debug({ model, responseLength: data.response.length }, 'Generate complete');

    return data.response;
  } finally {
    clearTimeout(timeoutId);
  }
}

export interface EmbeddingResult {
  embedding: number[];
}

// Generate embedding vector
export async function embed(text: string, model?: string): Promise<number[]> {
  const embeddingModel = model || config.embeddingModel;

  log.debug({ model: embeddingModel, textLength: text.length }, 'Generating embedding');

  const response = await fetch(`${config.ollamaUrl}/api/embeddings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: embeddingModel,
      prompt: text,
    }),
  });

  if (!response.ok) {
    throw new Error(`Ollama embedding error: ${response.status} ${response.statusText}`);
  }

  const data = (await response.json()) as EmbeddingResult;
  log.debug({ dimensions: data.embedding.length }, 'Embedding complete');

  return data.embedding;
}

// Check if Ollama is available
export async function isAvailable(): Promise<boolean> {
  try {
    const response = await fetch(`${config.ollamaUrl}/api/tags`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });
    return response.ok;
  } catch {
    return false;
  }
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/lib/ollama.ts
git commit -m "feat: add Ollama client with generate and embed functions"
```

---

### Task 6: Create Shared Types

**Files:**
- Create: `src/types/index.ts`

**Step 1: Write shared types**

Create `src/types/index.ts`:
```typescript
// Re-export database types
export { RawNote } from '../lib/db';

// Ingest workflow types
export interface IngestInput {
  title: string;
  content: string;
  created_at?: string;
  test_run?: string;
}

export interface IngestResult {
  id?: number;
  duplicate: boolean;
  existingId?: number;
}

// Webhook response types
export interface WebhookResponse {
  status: 'created' | 'duplicate' | 'error';
  id?: number;
  message?: string;
}

// Workflow result types
export interface WorkflowResult {
  processed: number;
  errors: number;
  details: Array<{ id: number; success: boolean; error?: string }>;
}
```

**Step 2: Create lib index for clean imports**

Create `src/lib/index.ts`:
```typescript
export { config } from './config';
export { logger, createWorkflowLogger } from './logger';
export {
  db,
  getPendingNotes,
  getProcessedNotes,
  markProcessed,
  findByContentHash,
  insertNote,
} from './db';
export type { RawNote } from './db';
export { generate, embed, isAvailable } from './ollama';
```

**Step 3: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 4: Commit**

```bash
git add src/types/index.ts src/lib/index.ts
git commit -m "feat: add shared types and lib index"
```

---

## Phase 3: Webhook Server and Workflows

### Task 7: Create Ingest Workflow

**Files:**
- Create: `src/workflows/ingest.ts`

**Step 1: Write ingest workflow**

Create `src/workflows/ingest.ts`:
```typescript
import { createHash } from 'crypto';
import { createWorkflowLogger, findByContentHash, insertNote } from '../lib';
import type { IngestInput, IngestResult } from '../types';

const log = createWorkflowLogger('ingest');

export async function ingest(input: IngestInput): Promise<IngestResult> {
  const { title, content, created_at, test_run } = input;

  log.info({ title, test_run }, 'Processing ingest request');

  // Generate content hash for duplicate detection
  const contentHash = createHash('sha256')
    .update(title + content)
    .digest('hex');

  // Check for duplicate
  const existing = findByContentHash(contentHash);

  if (existing) {
    log.info({ title, existingId: existing.id }, 'Duplicate detected');
    return { duplicate: true, existingId: existing.id };
  }

  // Extract tags from content
  const tags = content.match(/#\w+/g) || [];

  // Insert note
  const id = insertNote({
    title,
    content,
    contentHash,
    tags,
    createdAt: created_at || new Date().toISOString(),
    testRun: test_run,
  });

  log.info({ id, title, tags }, 'Note ingested successfully');

  return { id, duplicate: false };
}

// CLI entry point
if (require.main === module) {
  console.log('Ingest workflow - call via server or import as module');
  console.log('Usage: Import { ingest } from this file');
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/ingest.ts
git commit -m "feat: add ingest workflow with duplicate detection"
```

---

### Task 8: Create Webhook Server

**Files:**
- Create: `src/server.ts`

**Step 1: Write webhook server**

Create `src/server.ts`:
```typescript
import Fastify from 'fastify';
import { config, logger } from './lib';
import { ingest } from './workflows/ingest';
import type { IngestInput, WebhookResponse } from './types';

const server = Fastify({
  logger: false, // We use our own logger
});

// Health check endpoint
server.get('/health', async () => {
  return { status: 'ok', timestamp: new Date().toISOString() };
});

// Main webhook endpoint - same URL as n8n
server.post<{ Body: IngestInput }>('/webhook/api/drafts', async (request, reply) => {
  const { title, content, created_at, test_run } = request.body;

  logger.info({ title, test_run }, 'Webhook received');

  // Validate required fields
  if (!title || !content) {
    logger.warn({ title: !!title, content: !!content }, 'Missing required fields');
    reply.status(400);
    return { status: 'error', message: 'Title and content are required' } as WebhookResponse;
  }

  try {
    const result = await ingest({ title, content, created_at, test_run });

    if (result.duplicate) {
      logger.info({ title, existingId: result.existingId }, 'Duplicate skipped');
      return { status: 'duplicate', id: result.existingId } as WebhookResponse;
    }

    logger.info({ id: result.id, title }, 'Note created');
    return { status: 'created', id: result.id } as WebhookResponse;
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error, title }, 'Ingestion failed');
    reply.status(500);
    return { status: 'error', message: error.message } as WebhookResponse;
  }
});

// Start server
async function start() {
  try {
    await server.listen({ port: config.port, host: config.host });
    logger.info({ port: config.port, host: config.host }, 'Selene webhook server started');
  } catch (err) {
    logger.error({ err }, 'Server failed to start');
    process.exit(1);
  }
}

start();
```

**Step 2: Test server starts**

Run: `timeout 3 npx ts-node src/server.ts || true`
Expected: See "Selene webhook server started" in output

**Step 3: Commit**

```bash
git add src/server.ts
git commit -m "feat: add Fastify webhook server on same URL as n8n"
```

---

### Task 9: Create Process-LLM Workflow

**Files:**
- Create: `src/workflows/process-llm.ts`

**Step 1: Write process-llm workflow**

Create `src/workflows/process-llm.ts`:
```typescript
import {
  createWorkflowLogger,
  getPendingNotes,
  markProcessed,
  generate,
  isAvailable,
  db,
} from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('process-llm');

const EXTRACT_PROMPT = `Analyze this note and extract key information.

Note Title: {title}
Note Content: {content}

Respond in JSON format:
{
  "summary": "1-2 sentence summary",
  "concepts": ["concept1", "concept2"],
  "themes": ["theme1", "theme2"],
  "mood": "positive|negative|neutral",
  "actionable": true|false
}

JSON response:`;

export async function processLlm(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting LLM processing run');

  // Check Ollama availability
  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  const notes = getPendingNotes(limit);
  log.info({ noteCount: notes.length }, 'Found pending notes');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  for (const note of notes) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Processing note');

      const prompt = EXTRACT_PROMPT.replace('{title}', note.title).replace(
        '{content}',
        note.content
      );

      const response = await generate(prompt);

      // Try to parse JSON response
      let extracted;
      try {
        // Find JSON in response (Ollama sometimes adds extra text)
        const jsonMatch = response.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          extracted = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error('No JSON found in response');
        }
      } catch (parseErr) {
        log.warn({ noteId: note.id, response }, 'Failed to parse LLM response as JSON');
        extracted = { summary: response, concepts: [], themes: [], mood: 'neutral', actionable: false };
      }

      // Store in processed_notes table
      db.prepare(
        `INSERT OR REPLACE INTO processed_notes
         (note_id, summary, concepts, themes, mood, actionable, processed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).run(
        note.id,
        extracted.summary,
        JSON.stringify(extracted.concepts),
        JSON.stringify(extracted.themes),
        extracted.mood,
        extracted.actionable ? 1 : 0,
        new Date().toISOString()
      );

      // Mark note as processed
      markProcessed(note.id);

      log.info({ noteId: note.id, concepts: extracted.concepts }, 'Note processed successfully');
      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to process note');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  log.info({ processed: result.processed, errors: result.errors }, 'LLM processing run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  processLlm()
    .then((result) => {
      console.log('Process-LLM complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Process-LLM failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/process-llm.ts
git commit -m "feat: add process-llm workflow with concept extraction"
```

---

### Task 10: Create Extract-Tasks Workflow

**Files:**
- Create: `src/workflows/extract-tasks.ts`

**Step 1: Write extract-tasks workflow**

Create `src/workflows/extract-tasks.ts`:
```typescript
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, generate, isAvailable, config } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('extract-tasks');

const CLASSIFY_PROMPT = `Classify this note into one of three categories:
- actionable: Contains specific tasks that can be done
- needs_planning: Has ideas that need breakdown before acting
- archive_only: Reference material, no action needed

Note: {content}

Respond with just one word: actionable, needs_planning, or archive_only`;

const EXTRACT_TASKS_PROMPT = `Extract actionable tasks from this note.

Note: {content}

For each task, provide:
- title: Short task title
- notes: Any relevant context

Respond in JSON array format:
[{"title": "Task title", "notes": "Context"}]

JSON response:`;

export async function extractTasks(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting task extraction run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Get processed notes that haven't been classified yet
  const notes = db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, pn.actionable
       FROM raw_notes rn
       JOIN processed_notes pn ON rn.id = pn.note_id
       WHERE rn.status = 'processed'
       AND pn.task_classification IS NULL
       LIMIT ?`
    )
    .all(limit) as Array<{ id: number; title: string; content: string; actionable: number }>;

  log.info({ noteCount: notes.length }, 'Found notes needing classification');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  // Ensure Things pending directory exists
  if (!existsSync(config.thingsPendingDir)) {
    mkdirSync(config.thingsPendingDir, { recursive: true });
  }

  for (const note of notes) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Classifying note');

      // Classify the note
      const classifyPrompt = CLASSIFY_PROMPT.replace('{content}', note.content);
      const classification = (await generate(classifyPrompt)).trim().toLowerCase();

      const validClassifications = ['actionable', 'needs_planning', 'archive_only'];
      const finalClassification = validClassifications.includes(classification)
        ? classification
        : 'archive_only';

      log.info({ noteId: note.id, classification: finalClassification }, 'Note classified');

      // Update classification in database
      db.prepare('UPDATE processed_notes SET task_classification = ? WHERE note_id = ?').run(
        finalClassification,
        note.id
      );

      // If actionable, extract tasks and write to Things bridge
      if (finalClassification === 'actionable') {
        const extractPrompt = EXTRACT_TASKS_PROMPT.replace('{content}', note.content);
        const tasksResponse = await generate(extractPrompt);

        let tasks = [];
        try {
          const jsonMatch = tasksResponse.match(/\[[\s\S]*\]/);
          if (jsonMatch) {
            tasks = JSON.parse(jsonMatch[0]);
          }
        } catch {
          log.warn({ noteId: note.id }, 'Failed to parse tasks JSON');
          tasks = [{ title: note.title, notes: note.content }];
        }

        // Write tasks to Things bridge directory
        for (const task of tasks) {
          const taskFile = join(
            config.thingsPendingDir,
            `task-${note.id}-${Date.now()}.json`
          );
          writeFileSync(taskFile, JSON.stringify(task, null, 2));
          log.info({ noteId: note.id, taskFile }, 'Task written to Things bridge');
        }
      }

      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to classify note');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  log.info(result, 'Task extraction run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  extractTasks()
    .then((result) => {
      console.log('Extract-tasks complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Extract-tasks failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/extract-tasks.ts
git commit -m "feat: add extract-tasks workflow with Things bridge integration"
```

---

### Task 11: Create Compute-Embeddings Workflow

**Files:**
- Create: `src/workflows/compute-embeddings.ts`

**Step 1: Write compute-embeddings workflow**

Create `src/workflows/compute-embeddings.ts`:
```typescript
import { createWorkflowLogger, db, embed, isAvailable } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compute-embeddings');

export async function computeEmbeddings(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting embedding computation run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Get notes without embeddings
  const notes = db
    .prepare(
      `SELECT rn.id, rn.title, rn.content
       FROM raw_notes rn
       LEFT JOIN note_embeddings ne ON rn.id = ne.note_id
       WHERE ne.note_id IS NULL
       LIMIT ?`
    )
    .all(limit) as Array<{ id: number; title: string; content: string }>;

  log.info({ noteCount: notes.length }, 'Found notes needing embeddings');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  for (const note of notes) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Computing embedding');

      // Combine title and content for embedding
      const text = `${note.title}\n\n${note.content}`;
      const embedding = await embed(text);

      // Store embedding
      db.prepare(
        `INSERT INTO note_embeddings (note_id, embedding, model, created_at)
         VALUES (?, ?, ?, ?)`
      ).run(note.id, JSON.stringify(embedding), 'nomic-embed-text', new Date().toISOString());

      log.info({ noteId: note.id, dimensions: embedding.length }, 'Embedding stored');
      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to compute embedding');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  log.info(result, 'Embedding computation run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  computeEmbeddings()
    .then((result) => {
      console.log('Compute-embeddings complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compute-embeddings failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/compute-embeddings.ts
git commit -m "feat: add compute-embeddings workflow"
```

---

### Task 12: Create Compute-Associations Workflow

**Files:**
- Create: `src/workflows/compute-associations.ts`

**Step 1: Write compute-associations workflow**

Create `src/workflows/compute-associations.ts`:
```typescript
import { createWorkflowLogger, db } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compute-associations');

// Cosine similarity between two vectors
function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) return 0;

  let dotProduct = 0;
  let normA = 0;
  let normB = 0;

  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  const denominator = Math.sqrt(normA) * Math.sqrt(normB);
  return denominator === 0 ? 0 : dotProduct / denominator;
}

export async function computeAssociations(
  similarityThreshold = 0.7
): Promise<WorkflowResult> {
  log.info({ similarityThreshold }, 'Starting association computation run');

  // Get all embeddings
  const embeddings = db
    .prepare('SELECT note_id, embedding FROM note_embeddings')
    .all() as Array<{ note_id: number; embedding: string }>;

  log.info({ embeddingCount: embeddings.length }, 'Loaded embeddings');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  // Parse embeddings
  const parsed = embeddings.map((e) => ({
    noteId: e.note_id,
    vector: JSON.parse(e.embedding) as number[],
  }));

  // Compute pairwise similarities
  const associations: Array<{ noteId1: number; noteId2: number; similarity: number }> = [];

  for (let i = 0; i < parsed.length; i++) {
    for (let j = i + 1; j < parsed.length; j++) {
      const similarity = cosineSimilarity(parsed[i].vector, parsed[j].vector);

      if (similarity >= similarityThreshold) {
        associations.push({
          noteId1: parsed[i].noteId,
          noteId2: parsed[j].noteId,
          similarity,
        });
      }
    }
  }

  log.info({ associationCount: associations.length }, 'Found associations above threshold');

  // Store associations (clear existing first)
  const insertStmt = db.prepare(
    `INSERT OR REPLACE INTO note_associations (note_id_1, note_id_2, similarity, computed_at)
     VALUES (?, ?, ?, ?)`
  );

  const now = new Date().toISOString();

  for (const assoc of associations) {
    try {
      insertStmt.run(assoc.noteId1, assoc.noteId2, assoc.similarity, now);
      result.processed++;
    } catch (err) {
      const error = err as Error;
      log.error({ assoc, err: error }, 'Failed to store association');
      result.errors++;
    }
  }

  log.info(result, 'Association computation run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  computeAssociations()
    .then((result) => {
      console.log('Compute-associations complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compute-associations failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/compute-associations.ts
git commit -m "feat: add compute-associations workflow with cosine similarity"
```

---

### Task 13: Create Daily-Summary Workflow

**Files:**
- Create: `src/workflows/daily-summary.ts`

**Step 1: Write daily-summary workflow**

Create `src/workflows/daily-summary.ts`:
```typescript
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, generate, isAvailable, config } from '../lib';

const log = createWorkflowLogger('daily-summary');

const SUMMARY_PROMPT = `Generate a brief daily summary for someone with ADHD.

Notes captured today ({count} notes):
{notes}

Key themes detected:
{themes}

Write a 2-3 paragraph summary that:
1. Highlights the main threads of thought
2. Notes any patterns or connections
3. Suggests what might need attention tomorrow

Keep it encouraging and actionable.`;

export async function dailySummary(): Promise<{ success: boolean; path?: string }> {
  log.info('Starting daily summary generation');

  const obsidianPath = process.env.OBSIDIAN_VAULT_PATH || join(config.projectRoot, 'vault');

  // Get today's date range
  const today = new Date();
  const startOfDay = new Date(today.setHours(0, 0, 0, 0)).toISOString();
  const endOfDay = new Date(today.setHours(23, 59, 59, 999)).toISOString();

  // Get notes from today
  const notes = db
    .prepare(
      `SELECT rn.title, rn.content, pn.summary, pn.themes
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.note_id
       WHERE rn.created_at BETWEEN ? AND ?
       ORDER BY rn.created_at`
    )
    .all(startOfDay, endOfDay) as Array<{
    title: string;
    content: string;
    summary: string | null;
    themes: string | null;
  }>;

  log.info({ noteCount: notes.length }, 'Found notes for today');

  if (notes.length === 0) {
    log.info('No notes today, skipping summary');
    return { success: true };
  }

  // Format notes for prompt
  const notesText = notes
    .map((n) => `- ${n.title}: ${n.summary || n.content.slice(0, 100)}...`)
    .join('\n');

  // Collect all themes
  const allThemes = notes
    .flatMap((n) => (n.themes ? JSON.parse(n.themes) : []))
    .filter((t, i, arr) => arr.indexOf(t) === i);

  const themesText = allThemes.length > 0 ? allThemes.join(', ') : 'No themes detected yet';

  // Generate summary
  let summary: string;

  if (await isAvailable()) {
    const prompt = SUMMARY_PROMPT.replace('{count}', String(notes.length))
      .replace('{notes}', notesText)
      .replace('{themes}', themesText);

    summary = await generate(prompt);
  } else {
    log.warn('Ollama not available, using fallback summary');
    summary = `## Daily Summary\n\nCaptured ${notes.length} notes today.\n\nThemes: ${themesText}\n\n(Ollama was offline - no AI summary generated)`;
  }

  // Write to Obsidian vault
  const dailyDir = join(obsidianPath, 'Selene', 'Daily');
  if (!existsSync(dailyDir)) {
    mkdirSync(dailyDir, { recursive: true });
  }

  const dateStr = new Date().toISOString().split('T')[0];
  const outputPath = join(dailyDir, `${dateStr}-summary.md`);

  const markdown = `---
date: ${dateStr}
notes: ${notes.length}
themes: [${allThemes.map((t) => `"${t}"`).join(', ')}]
---

# Daily Summary - ${dateStr}

${summary}

---

## Notes Captured

${notes.map((n) => `- [[${n.title}]]`).join('\n')}
`;

  writeFileSync(outputPath, markdown);
  log.info({ outputPath }, 'Daily summary written');

  return { success: true, path: outputPath };
}

// CLI entry point
if (require.main === module) {
  dailySummary()
    .then((result) => {
      console.log('Daily summary complete:', result);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Daily summary failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/daily-summary.ts
git commit -m "feat: add daily-summary workflow with Obsidian export"
```

---

## Phase 4: Launchd Configuration

### Task 14: Create Launchd Plist Files

**Files:**
- Create: `launchd/com.selene.server.plist`
- Create: `launchd/com.selene.process-llm.plist`
- Create: `launchd/com.selene.extract-tasks.plist`
- Create: `launchd/com.selene.compute-embeddings.plist`
- Create: `launchd/com.selene.compute-associations.plist`
- Create: `launchd/com.selene.daily-summary.plist`

**Step 1: Create server plist (always running)**

Create `launchd/com.selene.server.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.server</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>/Users/chaseeasterling/selene/src/server.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>KeepAlive</key>
    <true/>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/server.out.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/server.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Step 2: Create process-llm plist (every 5 min)**

Create `launchd/com.selene.process-llm.plist`:
```xml
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

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>StartInterval</key>
    <integer>300</integer>

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

**Step 3: Create remaining plists**

Create `launchd/com.selene.extract-tasks.plist` (same as process-llm, change Label and script path)

Create `launchd/com.selene.compute-embeddings.plist` (same as process-llm, change Label and script path)

Create `launchd/com.selene.compute-associations.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.compute-associations</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>/Users/chaseeasterling/selene/src/workflows/compute-associations.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>StartInterval</key>
    <integer>3600</integer>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/compute-associations.out.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/compute-associations.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

Create `launchd/com.selene.daily-summary.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.daily-summary</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>/Users/chaseeasterling/selene/src/workflows/daily-summary.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>0</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/daily-summary.out.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/daily-summary.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Step 4: Commit**

```bash
git add launchd/
git commit -m "feat: add launchd plist files for all workflows"
```

---

### Task 15: Create Launchd Install Script

**Files:**
- Create: `scripts/install-launchd.sh`

**Step 1: Write install script**

Create `scripts/install-launchd.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$PROJECT_DIR/launchd"
AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "Installing Selene launchd agents..."

# Unload existing agents first
for plist in "$AGENTS_DIR"/com.selene.*.plist; do
    if [ -f "$plist" ]; then
        label=$(basename "$plist" .plist)
        echo "Unloading $label..."
        launchctl unload "$plist" 2>/dev/null || true
    fi
done

# Copy and load new agents
for plist in "$LAUNCHD_DIR"/*.plist; do
    if [ -f "$plist" ]; then
        name=$(basename "$plist")
        echo "Installing $name..."
        cp "$plist" "$AGENTS_DIR/"
        launchctl load "$AGENTS_DIR/$name"
    fi
done

echo ""
echo "Installed agents:"
launchctl list | grep com.selene || echo "  (none running yet)"
echo ""
echo "Done! Server should be running on port 5678."
```

**Step 2: Make executable**

Run: `chmod +x scripts/install-launchd.sh`

**Step 3: Commit**

```bash
git add scripts/install-launchd.sh
git commit -m "feat: add launchd install script"
```

---

## Phase 5: Switchover

### Task 16: Stop n8n and Archive Workflows

**Step 1: Stop n8n**

Run: `pkill -f "n8n start" || docker-compose down 2>/dev/null || true`

**Step 2: Archive n8n workflows**

Run:
```bash
mkdir -p archive
mv workflows archive/n8n-workflows
mv docker-compose.yml archive/ 2>/dev/null || true
mv Dockerfile archive/ 2>/dev/null || true
```

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: archive n8n workflows and Docker config"
```

---

### Task 17: Test End-to-End Flow

**Step 1: Start server manually**

Run: `npx ts-node src/server.ts &`
Expected: "Selene webhook server started"

**Step 2: Send test note**

Run:
```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Note","content":"Testing the new TypeScript backend #test","test_run":"e2e-test-001"}'
```

Expected: `{"status":"created","id":...}`

**Step 3: Verify in database**

Run: `sqlite3 data/selene.db "SELECT id, title, status FROM raw_notes WHERE test_run='e2e-test-001'"`
Expected: Shows the test note with status='pending'

**Step 4: Run process-llm manually**

Run: `npx ts-node src/workflows/process-llm.ts`
Expected: "Note processed successfully" in output

**Step 5: Cleanup test data**

Run: `sqlite3 data/selene.db "DELETE FROM raw_notes WHERE test_run='e2e-test-001'"`

**Step 6: Stop test server**

Run: `pkill -f "ts-node src/server.ts"`

---

### Task 18: Install Launchd Agents

**Step 1: Run install script**

Run: `./scripts/install-launchd.sh`
Expected: Shows installed agents

**Step 2: Verify server is running**

Run: `curl http://localhost:5678/health`
Expected: `{"status":"ok",...}`

**Step 3: Verify launchd jobs**

Run: `launchctl list | grep selene`
Expected: Shows all com.selene.* jobs

**Step 4: Commit any final changes**

```bash
git add -A
git commit -m "chore: complete switchover to TypeScript backend"
```

---

## Phase 6: Documentation Updates

### Task 19: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update Tech Stack section**

Replace n8n references with:
```markdown
- **TypeScript scripts** - Webhook server + workflow scripts
- **Fastify** - HTTP server for webhooks
- **launchd** - macOS job scheduling
```

**Step 2: Remove Workflow Procedure Check section**

Delete the entire "MANDATORY: Workflow Procedure Check" section.

**Step 3: Update Quick Command Reference**

Replace with:
```markdown
## Quick Command Reference

### Server Management
```bash
# Check server status
curl http://localhost:5678/health

# View server logs
tail -f logs/server.out.log

# Restart server
launchctl kickstart -k gui/$(id -u)/com.selene.server
```

### Run Workflows Manually
```bash
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/extract-tasks.ts
npx ts-node src/workflows/compute-embeddings.ts
npx ts-node src/workflows/compute-associations.ts
npx ts-node src/workflows/daily-summary.ts
```

### View Logs
```bash
# All logs (pretty)
tail -f logs/selene.log | npx pino-pretty

# Specific workflow
tail -f logs/process-llm.out.log

# Search for errors
grep '"level":50' logs/selene.log | npx pino-pretty
```

### Launchd Management
```bash
# List Selene jobs
launchctl list | grep selene

# Run job immediately
launchctl start com.selene.process-llm

# Reinstall all jobs
./scripts/install-launchd.sh
```
```

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for TypeScript backend"
```

---

### Task 20: Update Operations and Status Docs

**Files:**
- Modify: `.claude/OPERATIONS.md`
- Modify: `.claude/PROJECT-STATUS.md`

**Step 1: Update OPERATIONS.md**

Remove all n8n-specific procedures. Update with new workflow commands.

**Step 2: Update PROJECT-STATUS.md**

Update architecture section to reflect:
- TypeScript scripts instead of n8n
- launchd instead of Docker
- Direct file editing for changes

**Step 3: Commit**

```bash
git add .claude/
git commit -m "docs: update operations and status for new architecture"
```

---

### Task 21: Final Cleanup

**Step 1: Remove obsolete files**

Run:
```bash
rm -rf workflows/CLAUDE.md 2>/dev/null || true
rm -rf scripts/manage-workflow.sh 2>/dev/null || true
rm -rf scripts/start-n8n-local.sh 2>/dev/null || true
```

**Step 2: Update .gitignore if needed**

Ensure `logs/` is in `.gitignore`

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: remove obsolete n8n scripts and docs"
```

---

## Completion Checklist

- [ ] TypeScript project initialized
- [ ] All shared libraries created (config, logger, db, ollama)
- [ ] All workflows ported (ingest, process-llm, extract-tasks, compute-embeddings, compute-associations, daily-summary)
- [ ] Webhook server working on same URL
- [ ] launchd plists created and installed
- [ ] n8n archived
- [ ] E2E test passing
- [ ] Documentation updated
- [ ] Obsolete files removed
