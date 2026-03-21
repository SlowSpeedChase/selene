# Selene Project - Current Status

**Last Updated:** 2026-03-21
**Status:** Simplified Core | Living System Active

---

## Project Overview

Selene is a **thought consolidation system** for someone with ADHD. The core problem is not capturing thoughts or organizing them - it is making sense of them over time and knowing when to act.

Notes are captured, processed by LLM for concept extraction, distilled into essences, and exported to Obsidian for browsing. A daily summary is delivered via Apple Notes.

**Architecture:** TypeScript + Fastify + launchd with SQLite database + Ollama LLM
**Location:** `/Users/chaseeasterling/selene`

---

## Current System (Post-Simplification)

**Branch:** `main` (all work merged)

On 2026-03-21, the codebase was simplified from ~20,000 lines to ~3,500 lines. The core capture-process-browse pipeline was preserved. Everything else was shelved to `archive/shelved-2026-03-21/` with a README. All design docs remain in `docs/plans/` and git history preserves everything.

### Active Workflows (6)

| Workflow | Schedule | What It Does |
|----------|----------|-------------|
| `ingest.ts` | Webhook trigger | Note ingestion with duplicate detection |
| `process-llm.ts` | Every 5 min | LLM concept extraction via Ollama |
| `distill-essences.ts` | Every 5 min | Essence backfill (1-2 sentence distillations) |
| `export-obsidian.ts` | Hourly | Sync notes to Obsidian vault |
| `daily-summary.ts` | Daily at midnight | Aggregate daily insights |
| `send-digest.ts` | Daily at 6am | Post summary to pinned Apple Note |

### Active Launchd Agents (6)

| Agent | Type |
|-------|------|
| `com.selene.server` | Always running (KeepAlive) |
| `com.selene.process-llm` | Every 5 minutes |
| `com.selene.distill-essences` | Every 5 minutes |
| `com.selene.export-obsidian` | Hourly |
| `com.selene.daily-summary` | Daily at midnight |
| `com.selene.send-digest` | Daily at 6am |

### Active Scripts (6)

- `install-launchd.sh` - Install/reload launchd agents
- `uninstall-launchd.sh` - Remove launchd agents
- `cleanup-tests.sh` - Remove test data
- `create-dev-db.sh` - Set up dev database
- `dev-process-batch.sh` - Run dev batch processing
- `test-ingest.sh` - Test ingestion endpoint

### Server

Fastify webhook server on port 5678 with 3 routes:
- `GET /health` - Health check
- `POST /webhook/api/drafts` - Note ingestion
- `POST /trigger/export-obsidian` - Trigger Obsidian export

### Libraries (src/lib/)

All shared libraries remain active: db, ollama, config, logger, prompts, auth, lancedb, context-builder.

---

## What Was Archived (2026-03-21)

Shelved to `archive/shelved-2026-03-21/`:

**Workflows (11):** extract-tasks, index-vectors, compute-associations, compute-relationships, detect-threads, reconsolidate-threads, thread-lifecycle, transcribe-voice-memos, evaluate-fidelity, compile-thread-digests, render-daily-sheet

**Apps:** SeleneChat macOS app, SeleneMobile iOS app (entire Swift package)

**Server:** 7 API route modules, ~30 REST endpoints, Ollama proxy, APNs push notifications

**Launchd (11):** All agents for archived workflows plus dev-process-batch

**Scripts (~50):** Build scripts, setup scripts, seed data, Things bridge, etc.

**Other:** Legacy n8n artifacts deleted (not archived)

---

## Completed Components

| Component | File | Status |
|-----------|------|--------|
| Webhook Server | `src/server.ts` | Active |
| Database Utilities | `src/lib/db.ts` | Active |
| Ollama Client | `src/lib/ollama.ts` | Active |
| Logger (Pino) | `src/lib/logger.ts` | Active |
| Configuration | `src/lib/config.ts` | Active |
| Ingestion Workflow | `src/workflows/ingest.ts` | Active |
| LLM Processing | `src/workflows/process-llm.ts` | Active |
| Essence Distillation | `src/workflows/distill-essences.ts` | Active |
| Obsidian Export | `src/workflows/export-obsidian.ts` | Active |
| Daily Summary | `src/workflows/daily-summary.ts` | Active |
| Apple Notes Digest | `src/workflows/send-digest.ts` | Active |
| Launchd Agents | `launchd/*.plist` | Active (6) |
| Install Script | `scripts/install-launchd.sh` | Active |

### Why Replace n8n?

1. **Simpler debugging** - TypeScript stack traces vs n8n execution logs
2. **Version control** - All code in git, no UI state to sync
3. **Fewer moving parts** - No Docker, no n8n runtime overhead
4. **Type safety** - TypeScript catches errors at compile time
5. **macOS native** - launchd is reliable, built-in, and efficient

---

## System Architecture

### Components

```
Drafts App
    |
    v
Fastify Server (port 5678, health + ingestion + export-obsidian trigger)
    |
    v
SQLite Database
    ^
    |
launchd scheduled workflows:
  - process-llm (every 5 min)
  - distill-essences (every 5 min)
  - export-obsidian (hourly)
  - daily-summary (midnight)
  - send-digest (daily 6am)
    |
    v
Ollama (localhost:11434)
  - mistral:7b (text generation)
  - nomic-embed-text (embeddings)
```

### Key Files

```
src/
  server.ts           # Fastify webhook server
  lib/
    config.ts         # Environment configuration
    db.ts             # better-sqlite3 database utilities
    logger.ts         # Pino structured logging
    ollama.ts         # Ollama API client
  workflows/
    ingest.ts             # Note ingestion (called by webhook)
    process-llm.ts        # LLM concept extraction
    distill-essences.ts   # Essence distillation
    export-obsidian.ts    # Obsidian vault sync
    daily-summary.ts      # Daily digest generation
    send-digest.ts        # Apple Notes digest delivery
  types/
    index.ts          # Shared TypeScript types

launchd/
  com.selene.server.plist
  com.selene.process-llm.plist
  com.selene.distill-essences.plist
  com.selene.export-obsidian.plist
  com.selene.daily-summary.plist
  com.selene.send-digest.plist

logs/
  selene.log          # Workflow logs (Pino JSON)
  server.out.log      # Server stdout
  server.err.log      # Server stderr
```

---

## Existing Features (Active)

### Ingestion
- Webhook endpoint: `POST /webhook/api/drafts`
- Duplicate detection via content hash
- Tag extraction from #hashtags
- Word/character count calculation
- Test data marking system (`test_run` column)

### LLM Processing
- Concept extraction via Ollama
- Theme detection
- Status tracking (pending -> processing -> completed)

### Essence Distillation
- 1-2 sentence LLM-generated distillations of each note
- Backfill processing with retry logic

### Obsidian Export
- Notes and summaries synced to Obsidian vault
- Markdown with frontmatter

### Daily Summary
- Aggregates notes, insights, patterns
- LLM-generated executive summary
- Delivered via Apple Notes at 6am

---

## Database Schema

**Type:** SQLite
**Location:** `data/selene.db`

**Tables:**
- `raw_notes` - Ingested notes
- `processed_notes` - LLM processed notes
- `note_embeddings` - Semantic embeddings
- `note_associations` - Note relationships
- `detected_patterns` - Pattern detection results
- `extracted_tasks` - Task classification results

---

## Common Commands

### Server
```bash
curl http://localhost:5678/health           # Health check
tail -f logs/server.out.log                 # Server logs
launchctl kickstart -k gui/$(id -u)/com.selene.server  # Restart
```

### Workflows
```bash
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/distill-essences.ts
npx ts-node src/workflows/export-obsidian.ts
npx ts-node src/workflows/daily-summary.ts
npx ts-node src/workflows/send-digest.ts
tail -f logs/selene.log | npx pino-pretty   # View logs
```

### Launchd
```bash
launchctl list | grep selene                # List agents
./scripts/install-launchd.sh                # Install agents
```

### Testing
```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Test", "content": "Test content", "test_run": "test-123"}'

./scripts/cleanup-tests.sh --list           # List test runs
./scripts/cleanup-tests.sh test-123         # Cleanup
```

---

## Recent Achievements

### 2026-03-21
- **Codebase Simplification** - Reduced from ~20,000 to ~3,500 lines
  - Archived 11 workflows, SeleneChat/SeleneMobile apps, 7 API route modules, ~50 scripts
  - Preserved core: 6 workflows, 6 launchd agents, 6 scripts
  - All shelved code in `archive/shelved-2026-03-21/` with README
  - All design docs preserved in `docs/plans/`
  - Git history preserves everything

### 2026-02-27
- **Intelligence Upgrade Layers 1+2** - Prosthetic executive function for chat (archived)

### 2026-02-22
- **Tiered Context Compression** - Lifecycle-based fidelity tiers (active: distill-essences.ts)
- **Dev Environment Isolation** - Full parallel dev environment with 536 fictional notes

### 2026-02-14
- **SeleneMobile iOS App** - Native iOS app (archived)
- **Server REST API Expansion** - ~30 endpoints (archived, server simplified to 3 routes)

### 2026-02-13
- **Morning Briefing, Menu Bar Orchestrator, Voice Memo Transcription, Apple Notes Digest, Thread Lifecycle** - All completed then archived in simplification

### Earlier
- Thread System, Thinking Partner, Voice Input, SeleneChat Planning Integration, Task Extraction - All completed and archived

---

## Files to Reference

**Must Read:**
- `docs/plans/INDEX.md` - Design documents for implementation
- `database/schema.sql` - Database structure

**Source Code:**
- `src/server.ts` - Webhook server entry point
- `src/lib/` - Shared utilities
- `src/workflows/` - Background processing scripts (6 active)
- `launchd/` - macOS launch agent configurations (6 active)

**Archive:**
- `archive/shelved-2026-03-21/` - All shelved features with README

---

## Questions for Next Session

1. What to build next on the simplified core?
2. Are the 6 active workflows running stably?
3. Is the Obsidian export producing useful output?
