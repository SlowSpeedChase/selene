# Codebase Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Strip Selene to its working core (capture, process, browse, visibility) and archive everything else.

**Architecture:** Move shelved code to `archive/shelved-2026-03-21/`, delete legacy artifacts, clean up what remains. No database schema changes — tables stay inert. Active system: 6 workflows, 6 launchd agents, slim server.

**Tech Stack:** TypeScript, Fastify, SQLite, Ollama, launchd

---

## Pre-Flight

Before starting, verify the system is in a clean state:

```bash
git status                                    # Should be clean
curl http://localhost:5678/health              # Server running
launchctl list | grep selene                   # See current agents
```

---

### Task 1: Extract Prompts to Shared Library

**Why:** `distill-essences.ts` imports `buildEssencePrompt` from `process-llm.ts`. We need a clean shared location before any archiving.

**Files:**
- Create: `src/lib/prompts.ts`
- Modify: `src/workflows/process-llm.ts`
- Modify: `src/workflows/distill-essences.ts`
- Modify: `src/lib/index.ts`

**Step 1: Create `src/lib/prompts.ts`**

```typescript
// src/lib/prompts.ts
// Centralized LLM prompt templates for all Selene workflows

export const EXTRACT_PROMPT = `Analyze this note and extract key information.

Note Title: {title}
Note Content: {content}

Respond in JSON format:
{
  "concepts": ["concept1", "concept2", "concept3"],
  "primary_theme": "main theme or category",
  "secondary_themes": ["related theme 1", "related theme 2"],
  "overall_sentiment": "positive|negative|neutral|mixed",
  "emotional_tone": "reflective|anxious|excited|frustrated|calm|curious|etc",
  "energy_level": "high|medium|low"
}

JSON response:`;

export const ESSENCE_PROMPT = `Distill this note into 1-2 sentences capturing what it means to the person who wrote it. Focus on the core insight, decision, or question — not a summary of the text.

Title: {title}
Content: {content}
{context}

Respond with ONLY the 1-2 sentence distillation, no quotes or explanation:`;

export function buildEssencePrompt(
  title: string,
  content: string,
  concepts: string | null,
  primaryTheme: string | null
): string {
  const contextParts: string[] = [];
  if (concepts) {
    try {
      const conceptList = JSON.parse(concepts);
      if (conceptList.length > 0) {
        contextParts.push(`Key concepts: ${conceptList.join(', ')}`);
      }
    } catch { /* ignore */ }
  }
  if (primaryTheme) {
    contextParts.push(`Theme: ${primaryTheme}`);
  }
  const contextStr = contextParts.length > 0
    ? contextParts.join('\n')
    : '';

  return ESSENCE_PROMPT
    .replace('{title}', title)
    .replace('{content}', content)
    .replace('{context}', contextStr);
}
```

**Step 2: Update `process-llm.ts`**

Remove `EXTRACT_PROMPT`, `ESSENCE_PROMPT`, and `buildEssencePrompt` from this file. Replace with import:

```typescript
import { EXTRACT_PROMPT, buildEssencePrompt } from '../lib/prompts';
```

**Step 3: Update `distill-essences.ts`**

Change import from:
```typescript
import { buildEssencePrompt } from './process-llm';
```
To:
```typescript
import { buildEssencePrompt } from '../lib/prompts';
```

**Step 4: Add export to `src/lib/index.ts`**

```typescript
// From prompts
export { EXTRACT_PROMPT, ESSENCE_PROMPT, buildEssencePrompt } from './prompts';
```

**Step 5: Verify active workflows still compile**

```bash
npx tsc --noEmit src/workflows/process-llm.ts
npx tsc --noEmit src/workflows/distill-essences.ts
```

Expected: No errors.

**Step 6: Commit**

```bash
git add src/lib/prompts.ts src/lib/index.ts src/workflows/process-llm.ts src/workflows/distill-essences.ts
git commit -m "refactor: extract LLM prompts to shared lib/prompts.ts"
```

---

### Task 2: Create Archive Directory and README

**Files:**
- Create: `archive/shelved-2026-03-21/README.md`

**Step 1: Create archive structure**

```bash
mkdir -p archive/shelved-2026-03-21/{workflows,routes,queries,launchd,scripts,templates,things-bridge}
```

**Step 2: Write the README**

Create `archive/shelved-2026-03-21/README.md`:

```markdown
# Shelved Code — 2026-03-21

## Why

Selene was stripped to its working core (capture, process, browse, visibility).
These features need major rework before they're useful. They're preserved here
and in git history for future rebuilding.

## What's Here

- `workflows/` — 11 archived workflow scripts + their test files
- `SeleneChat/` — Full Swift package (macOS menu bar + iOS app)
- `routes/` — API route modules (threads, notes, sessions, etc.)
- `queries/` — Query utilities (related-notes)
- `launchd/` — 12 archived launchd agent plists
- `scripts/` — ~23 archived shell scripts
- `templates/` — HTML templates (daily-sheet)
- `things-bridge/` — Things.app integration scripts

## Rebuilding a Feature

1. Check `docs/plans/` for the original design doc
2. Copy the relevant file(s) from this archive
3. Create a new design doc for the improved version
4. Build against the clean core as a self-contained addition

## Active Core (NOT here)

These remain in `src/`:
- `ingest.ts` — Note capture
- `process-llm.ts` — Concept extraction
- `distill-essences.ts` — Essence generation
- `export-obsidian.ts` — Obsidian vault sync
- `daily-summary.ts` — Activity summary
- `send-digest.ts` — Apple Notes delivery
```

**Step 3: Commit**

```bash
git add archive/shelved-2026-03-21/README.md
git commit -m "docs: create archive directory for shelved features"
```

---

### Task 3: Unload and Archive Launchd Agents

**Why:** Stop background processes for shelved features before moving their code.

**Files:**
- Move: 12 launchd plists to archive
- Modify: `scripts/install-launchd.sh`

**Step 1: Unload shelved agents**

```bash
# Unload each shelved agent (ignore errors if already unloaded)
launchctl bootout gui/$(id -u)/com.selene.extract-tasks 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.index-vectors 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.compute-relationships 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.detect-threads 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.reconsolidate-threads 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.thread-lifecycle 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.transcribe-voice-memos 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.render-daily-sheet 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.evaluate-fidelity 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.compile-thread-digests 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.dev-process-batch 2>/dev/null || true
```

Also unload the things-bridge agents:
```bash
launchctl bootout gui/$(id -u)/com.selene.things-bridge 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.selene.projects-bridge 2>/dev/null || true
```

**Step 2: Verify only active agents remain**

```bash
launchctl list | grep selene
```

Expected: Only `com.selene.server`, `com.selene.process-llm`, `com.selene.distill-essences`, `com.selene.export-obsidian`, `com.selene.daily-summary`, `com.selene.send-digest`.

**Step 3: Move shelved plists to archive**

```bash
mv launchd/com.selene.extract-tasks.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.index-vectors.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.compute-relationships.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.detect-threads.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.reconsolidate-threads.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.thread-lifecycle.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.transcribe-voice-memos.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.render-daily-sheet.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.evaluate-fidelity.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.compile-thread-digests.plist archive/shelved-2026-03-21/launchd/
mv launchd/com.selene.dev-process-batch.plist archive/shelved-2026-03-21/launchd/
```

**Step 4: Update `scripts/install-launchd.sh`**

Replace the AGENTS array with only active agents:

```bash
AGENTS=(
    "com.selene.server"
    "com.selene.process-llm"
    "com.selene.distill-essences"
    "com.selene.export-obsidian"
    "com.selene.daily-summary"
    "com.selene.send-digest"
)
```

**Step 5: Verify remaining plists**

```bash
ls launchd/
```

Expected: Only 6 plist files for the active agents.

**Step 6: Commit**

```bash
git add -A launchd/ archive/shelved-2026-03-21/launchd/ scripts/install-launchd.sh
git commit -m "ops: unload and archive 12 shelved launchd agents"
```

---

### Task 4: Archive Shelved Workflows

**Files:**
- Move: 11 workflow files + 5 test files to archive

**Step 1: Move shelved workflow files**

```bash
mv src/workflows/detect-threads.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/reconsolidate-threads.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/thread-lifecycle.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/compute-associations.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/compute-relationships.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/index-vectors.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/extract-tasks.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/compile-thread-digests.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/render-daily-sheet.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/evaluate-fidelity.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/transcribe-voice-memos.ts archive/shelved-2026-03-21/workflows/
```

**Step 2: Move archived test files**

```bash
mv src/workflows/detect-threads.test.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/compile-thread-digests.test.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/evaluate-fidelity.test.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/extract-tasks.test.ts archive/shelved-2026-03-21/workflows/
mv src/workflows/process-llm-essence.test.ts archive/shelved-2026-03-21/workflows/
```

**Step 3: Verify remaining workflows**

```bash
ls src/workflows/
```

Expected: `ingest.ts`, `process-llm.ts`, `distill-essences.ts`, `export-obsidian.ts`, `daily-summary.ts`, `send-digest.ts`, `distill-essences.test.ts`, `send-digest.test.ts`

**Step 4: Commit**

```bash
git add -A src/workflows/ archive/shelved-2026-03-21/workflows/
git commit -m "refactor: archive 11 shelved workflows and their tests"
```

---

### Task 5: Archive Routes, Queries, and Templates

**Files:**
- Move: 7 route files, 1 query file, 1 template file

**Step 1: Move route files**

```bash
mv src/routes/notes.ts archive/shelved-2026-03-21/routes/
mv src/routes/threads.ts archive/shelved-2026-03-21/routes/
mv src/routes/sessions.ts archive/shelved-2026-03-21/routes/
mv src/routes/memories.ts archive/shelved-2026-03-21/routes/
mv src/routes/llm.ts archive/shelved-2026-03-21/routes/
mv src/routes/briefing.ts archive/shelved-2026-03-21/routes/
mv src/routes/devices.ts archive/shelved-2026-03-21/routes/
```

**Step 2: Move query files**

```bash
mv src/queries/related-notes.ts archive/shelved-2026-03-21/queries/
```

If the `src/queries/` directory has other files, move them too. Then remove empty directories:

```bash
rmdir src/routes/ src/queries/ 2>/dev/null || true
```

**Step 3: Move templates**

```bash
mv src/templates/daily-sheet.html archive/shelved-2026-03-21/templates/
rmdir src/templates/ 2>/dev/null || true
```

**Step 4: Commit**

```bash
git add -A src/routes/ src/queries/ src/templates/ archive/shelved-2026-03-21/routes/ archive/shelved-2026-03-21/queries/ archive/shelved-2026-03-21/templates/
git commit -m "refactor: archive route modules, queries, and templates"
```

---

### Task 6: Strip Server to Core

**Why:** Remove all route registrations and inline endpoints that depend on archived code.

**Files:**
- Modify: `src/server.ts`

**Step 1: Rewrite `src/server.ts`**

Replace the entire file with:

```typescript
import Fastify from 'fastify';
import { config, logger } from './lib';
import { ingest } from './workflows/ingest';
import { exportObsidian } from './workflows/export-obsidian';
import type { IngestInput, WebhookResponse } from './types';

const server = Fastify({
  logger: false, // We use our own logger
});

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

server.get('/health', async () => {
  return {
    status: 'ok',
    env: config.env,
    port: config.port,
    timestamp: new Date().toISOString(),
  };
});

// ---------------------------------------------------------------------------
// Webhook handlers (no auth required)
// ---------------------------------------------------------------------------

// POST /webhook/api/drafts - Note ingestion (called by Drafts app)
server.post<{ Body: IngestInput }>('/webhook/api/drafts', async (request, reply) => {
  const { title, content, created_at, test_run, capture_type } = request.body;

  logger.info({ title, test_run, capture_type }, 'Webhook received');

  // Validate required fields
  if (!title || !content) {
    logger.warn({ title: !!title, content: !!content }, 'Missing required fields');
    reply.status(400);
    return { status: 'error', message: 'Title and content are required' } as WebhookResponse;
  }

  try {
    const result = await ingest({ title, content, created_at, test_run, capture_type });

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

// POST /webhook/api/export-obsidian - Manual Obsidian export trigger
server.post<{ Body: { noteId?: number } }>('/webhook/api/export-obsidian', async (request, reply) => {
  const { noteId } = request.body || {};

  logger.info({ noteId }, 'Export-obsidian webhook received');

  try {
    const result = await exportObsidian(noteId);
    return result;
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error }, 'Export-obsidian failed');
    reply.status(500);
    return { success: false, exported_count: 0, errors: 1, message: error.message };
  }
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------

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

**Step 2: Clean up types**

Remove unused types from `src/types/index.ts`:

Keep: `IngestInput`, `IngestResult`, `WebhookResponse`, `WorkflowResult`, `ExportableNote`, `ExportResult`, `CalendarEvent`, `CalendarLookupResult`

Remove: `ProcessedFileEntry`, `ProcessedManifest`, `VoiceMemoWorkflowResult` (used only by archived transcribe-voice-memos.ts)

**Step 3: Verify server compiles**

```bash
npx tsc --noEmit src/server.ts
```

Expected: No errors.

**Step 4: Restart and test server**

```bash
launchctl kickstart -k gui/$(id -u)/com.selene.server
sleep 2
curl http://localhost:5678/health
```

Expected: `{"status":"ok",...}`

**Step 5: Test webhook ingestion**

```bash
TEST_RUN="test-simplify-$(date +%Y%m%d-%H%M%S)"
curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{\"title\": \"Simplification Test\", \"content\": \"Testing after codebase simplification\", \"test_run\": \"$TEST_RUN\"}"
```

Expected: `{"status":"created","id":...}`

**Step 6: Clean up test data**

```bash
./scripts/cleanup-tests.sh "$TEST_RUN"
```

**Step 7: Commit**

```bash
git add src/server.ts src/types/index.ts
git commit -m "refactor: strip server to health + webhook endpoints only"
```

---

### Task 7: Archive SeleneChat Swift Package

**Files:**
- Move: entire `SeleneChat/` directory

**Step 1: Move SeleneChat to archive**

```bash
mv SeleneChat archive/shelved-2026-03-21/
```

**Step 2: Verify it moved**

```bash
ls archive/shelved-2026-03-21/SeleneChat/Package.swift
```

Expected: File exists.

**Step 3: Commit**

```bash
git add -A SeleneChat/ archive/shelved-2026-03-21/SeleneChat/
git commit -m "refactor: archive SeleneChat Swift package (macOS + iOS apps)"
```

---

### Task 8: Archive Scripts and Things Bridge

**Files:**
- Move: ~23 scripts to archive
- Move: `scripts/things-bridge/` to archive
- Keep: 6 essential scripts

**Step 1: Move shelved scripts**

Keep these 6:
- `install-launchd.sh` (already updated)
- `uninstall-launchd.sh` (still useful)
- `cleanup-tests.sh`
- `create-dev-db.sh`
- `dev-process-batch.sh`
- `test-ingest.sh`

Archive everything else:

```bash
mv scripts/apply-context-updates.sh archive/shelved-2026-03-21/scripts/
mv scripts/archive-stale-plans.sh archive/shelved-2026-03-21/scripts/
mv scripts/batch-compute-associations.sh archive/shelved-2026-03-21/scripts/
mv scripts/batch-embed-notes.sh archive/shelved-2026-03-21/scripts/
mv scripts/clean-production-database.sh archive/shelved-2026-03-21/scripts/
mv scripts/cluster-stats.sh archive/shelved-2026-03-21/scripts/
mv scripts/create-synthetic-test-db.sh archive/shelved-2026-03-21/scripts/
mv scripts/create-test-db.sh archive/shelved-2026-03-21/scripts/
mv scripts/dev-reset-db.sh archive/shelved-2026-03-21/scripts/
mv scripts/dev-seed-data.sh archive/shelved-2026-03-21/scripts/
mv scripts/generate-backlog.sh archive/shelved-2026-03-21/scripts/
mv scripts/migrate-to-local-paths.sh archive/shelved-2026-03-21/scripts/
mv scripts/query-similar-notes.sh archive/shelved-2026-03-21/scripts/
mv scripts/reset-dev-data.sh archive/shelved-2026-03-21/scripts/
mv scripts/seed-test-data.sh archive/shelved-2026-03-21/scripts/
mv scripts/setup-git-hooks.sh archive/shelved-2026-03-21/scripts/
mv scripts/setup-hooks.sh archive/shelved-2026-03-21/scripts/
mv scripts/setup-test-isolation.sh archive/shelved-2026-03-21/scripts/
mv scripts/setup-whisper.sh archive/shelved-2026-03-21/scripts/
mv scripts/test-event-driven.sh archive/shelved-2026-03-21/scripts/
mv scripts/test-reset.sh archive/shelved-2026-03-21/scripts/
mv scripts/test-verify.sh archive/shelved-2026-03-21/scripts/
mv scripts/verify-production-clean.sh archive/shelved-2026-03-21/scripts/
```

**Step 2: Move things-bridge**

```bash
mv scripts/things-bridge archive/shelved-2026-03-21/things-bridge
```

**Step 3: Verify remaining scripts**

```bash
ls scripts/*.sh
```

Expected: `cleanup-tests.sh`, `create-dev-db.sh`, `dev-process-batch.sh`, `install-launchd.sh`, `test-ingest.sh`, `uninstall-launchd.sh`

**Step 4: Commit**

```bash
git add -A scripts/ archive/shelved-2026-03-21/scripts/ archive/shelved-2026-03-21/things-bridge/
git commit -m "refactor: archive 23 scripts and things-bridge integration"
```

---

### Task 9: Delete Legacy Artifacts

**Why:** These are n8n remnants from before the TypeScript migration (Jan 2026). Already in git history.

**Files:**
- Delete: `.n8n-local/` (210 MB)
- Delete: `.workflow-backup-*/` (228 KB)
- Delete: `archive/` (existing old n8n archive, 1.1 MB — NOT our new `archive/shelved-2026-03-21/`)

**Step 1: Check what exists**

```bash
ls -la .n8n-local/ 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"
ls -d .workflow-backup-* 2>/dev/null && echo "EXISTS" || echo "NOT FOUND"
```

Note: `.n8n-local/` and `.workflow-backup-*/` are in `.gitignore`, so they may not be tracked. If they're only on disk (not in git), just delete them locally:

```bash
rm -rf .n8n-local/ .workflow-backup-*
```

If there's an existing `archive/` directory with old n8n content (separate from our new `archive/shelved-2026-03-21/`), check what's there before deleting:

```bash
ls archive/ | grep -v shelved
```

If it's just old n8n workflows, remove those files (but NOT `archive/shelved-2026-03-21/`).

**Step 2: Commit if any tracked files were removed**

```bash
git add -A .n8n-local/ .workflow-backup-* archive/
git diff --cached --stat  # Check what's staged
git commit -m "chore: delete legacy n8n artifacts (preserved in git history)"
```

If nothing was tracked, skip the commit.

---

### Task 10: Security — Remove .env from Git Tracking

**Step 1: Check if .env is tracked**

```bash
git ls-files .env
```

If it returns `.env`, it's tracked and needs to be removed:

```bash
git rm --cached .env
git commit -m "security: remove .env from git tracking (already in .gitignore)"
```

If it returns nothing, `.env` is already untracked — skip this task.

**Step 2: Verify .gitignore has .env**

Check that `.gitignore` contains `.env` (it does based on current state — just verify).

---

### Task 11: Test All Active Workflows

**Why:** Verify nothing broke during the archiving.

**Step 1: Verify server health**

```bash
curl http://localhost:5678/health
```

Expected: `{"status":"ok",...}`

**Step 2: Test ingestion**

```bash
TEST_RUN="test-final-$(date +%Y%m%d-%H%M%S)"
curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{\"title\": \"Final Simplification Test\", \"content\": \"Verifying all active workflows after codebase simplification.\", \"test_run\": \"$TEST_RUN\"}"
```

Expected: `{"status":"created","id":...}`

**Step 3: Test process-llm**

```bash
npx ts-node src/workflows/process-llm.ts
```

Expected: Runs without error (may process 0 notes if Ollama is busy, that's ok).

**Step 4: Test distill-essences**

```bash
npx ts-node src/workflows/distill-essences.ts
```

Expected: Runs without error.

**Step 5: Test export-obsidian**

```bash
npx ts-node src/workflows/export-obsidian.ts
```

Expected: Runs without error, exports to Obsidian vault.

**Step 6: Test daily-summary**

```bash
npx ts-node src/workflows/daily-summary.ts
```

Expected: Runs without error, generates summary.

**Step 7: Run remaining unit tests**

```bash
npx jest src/workflows/distill-essences.test.ts src/workflows/send-digest.test.ts
```

Expected: Tests pass.

**Step 8: Clean up test data**

```bash
./scripts/cleanup-tests.sh "$TEST_RUN"
```

---

### Task 12: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/PROJECT-STATUS.md`
- Modify: `.claude/OPERATIONS.md`

**Step 1: Update CLAUDE.md**

Major updates needed:
- Remove SeleneChat from Architecture Overview (Tier 3)
- Update workflow list to show only 6 active workflows
- Update launchd list to show only 6 agents
- Update Quick Command Reference (remove shelved workflow commands)
- Update Project Status to reflect simplification
- Update File Organization to show archive directory
- Remove SeleneChat build commands from Key Patterns
- Add note about archive directory and how to rebuild features

**Step 2: Update PROJECT-STATUS.md**

- Add "Codebase Simplification" to completed items
- Update active system description
- Note what was archived and why

**Step 3: Update OPERATIONS.md**

- Remove references to archived workflows
- Update launchd management section
- Update testing procedures for simplified system
- Remove SeleneChat-specific operations

**Step 4: Commit**

```bash
git add CLAUDE.md .claude/PROJECT-STATUS.md .claude/OPERATIONS.md
git commit -m "docs: update all documentation for simplified codebase"
```

---

### Task 13: Final Verification and Summary Commit

**Step 1: Verify file counts**

```bash
echo "=== Active workflows ==="
ls src/workflows/*.ts | grep -v test | wc -l
echo "=== Launchd agents ==="
ls launchd/*.plist | wc -l
echo "=== Scripts ==="
ls scripts/*.sh | wc -l
echo "=== Archived files ==="
find archive/shelved-2026-03-21/ -type f | wc -l
```

Expected:
- Active workflows: 6
- Launchd agents: 6
- Scripts: 6
- Archived files: 100+

**Step 2: Verify no broken imports**

```bash
npx tsc --noEmit
```

Expected: No errors (or only pre-existing warnings).

**Step 3: Verify server is running**

```bash
curl http://localhost:5678/health
```

**Step 4: Git log to review all changes**

```bash
git log --oneline -10
```

Review that all commits are clean and logical.

---

## Summary of Commits

1. `refactor: extract LLM prompts to shared lib/prompts.ts`
2. `docs: create archive directory for shelved features`
3. `ops: unload and archive 12 shelved launchd agents`
4. `refactor: archive 11 shelved workflows and their tests`
5. `refactor: archive route modules, queries, and templates`
6. `refactor: strip server to health + webhook endpoints only`
7. `refactor: archive SeleneChat Swift package (macOS + iOS apps)`
8. `refactor: archive 23 scripts and things-bridge integration`
9. `chore: delete legacy n8n artifacts (preserved in git history)` (if applicable)
10. `security: remove .env from git tracking` (if applicable)
11. `docs: update all documentation for simplified codebase`

## Rollback

If anything goes wrong, every change is a separate commit. To undo:
```bash
git log --oneline -15       # Find the commit to revert to
git revert <commit-hash>    # Revert specific commit
```

To restore a single archived file:
```bash
cp archive/shelved-2026-03-21/workflows/<file>.ts src/workflows/
```
