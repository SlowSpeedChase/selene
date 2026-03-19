# Selene Project Context

> **This is THE single entry point.** Claude Code loads this automatically. Use the Context Navigation table below to find what you need.

---

## Purpose

ADHD-focused knowledge management system using TypeScript workflows, SQLite, and local LLM processing for note capture, organization, and retrieval. Designed to externalize working memory and make information visual and accessible.

---

## Tech Stack

- **TypeScript** - Webhook server + workflow scripts
- **Fastify** - HTTP server for webhooks (port 5678)
- **launchd** - macOS job scheduling for background workflows
- **SQLite** + better-sqlite3 - Database for note storage
- **Ollama** + mistral:7b/nomic-embed-text - Local LLM for concept extraction and embeddings
- **Swift** + SwiftUI - SeleneChat macOS app
- **Drafts** - iOS/Mac note capture app

---

## Context Navigation

**Load only what you need for the task:**

| Task | Primary Context | Supporting Context |
|------|-----------------|-------------------|
| **Plan new work** | `@docs/plans/INDEX.md` | `@.claude/GITOPS.md` |
| **Modify workflows** | `@src/workflows/` | `@.claude/OPERATIONS.md` |
| **Understand architecture** | `@.claude/DEVELOPMENT.md` | `@ROADMAP.md` |
| **Run tests** | `@.claude/OPERATIONS.md` | - |
| **Design ADHD features** | `@.claude/ADHD_Principles.md` | `@.claude/DEVELOPMENT.md` |
| **Daily operations** | `@.claude/OPERATIONS.md` | `@scripts/CLAUDE.md` |
| **Use dev environment** | `@.claude/OPERATIONS.md` (Dev Environment) | `@scripts/CLAUDE.md` |
| **Check status** | `@.claude/PROJECT-STATUS.md` | `@docs/plans/INDEX.md` |
| **Development workflow** | `@.claude/GITOPS.md` | `@docs/plans/INDEX.md` |

---

## Development Workflow (MANDATORY)

**Claude MUST follow `@.claude/GITOPS.md` for all development work.**

### Two-Layer System

1. **Design Docs** (`docs/plans/INDEX.md`) - Ideas, architecture, decisions
   - Status: Vision → Ready → In Progress → Done
   - "Ready" = acceptance criteria + ADHD check + scope check

2. **GitOps Branches** - Implementation tracking
   - Stages: planning → dev → testing → docs → review → ready
   - Each branch has `BRANCH-STATUS.md` with stage checklists

### Quick Commands
```bash
# Check design doc status
cat docs/plans/INDEX.md

# Start new work (design doc must be "Ready")
git worktree add -b feature-name .worktrees/feature-name main
cp templates/BRANCH-STATUS.md .worktrees/feature-name/

# Check active work
git worktree list
```

**See:** `@.claude/GITOPS.md` for complete workflow, `@docs/plans/INDEX.md` for design doc status

---

## Architecture Overview

### Three-Tier System

```
+-------------------------------------------------------------+
| TIER 1: CAPTURE                                             |
| Drafts App / Voice Memos -> Webhook -> SQLite + LanceDB    |
| Design: One-click capture, zero friction                    |
+-------------------------------------------------------------+

+-------------------------------------------------------------+
| TIER 2: PROCESS                                             |
| TypeScript Scripts -> Ollama LLM -> Extract patterns        |
| Scheduled via SeleneChat WorkflowScheduler + launchd        |
| Design: Automatic organization, visual patterns             |
+-------------------------------------------------------------+

+-------------------------------------------------------------+
| TIER 3: RETRIEVE                                            |
| SeleneChat (macOS menu bar) + Obsidian -> Query & Explore   |
| SeleneMobile (iOS) -> Query via Tailscale REST API          |
| Design: Information visible without mental overhead         |
+-------------------------------------------------------------+
```

### Key Components

```
src/
  server.ts           # Fastify webhook server (port 5678)
  lib/
    config.ts         # Environment configuration
    db.ts             # better-sqlite3 database utilities
    logger.ts         # Pino structured logging
    ollama.ts         # Ollama API client
    auth.ts           # Bearer token auth middleware
    apns.ts           # APNs push notification client
    context-builder.ts    # Tiered context assembly utility
  workflows/
    ingest.ts                   # Note ingestion (called by webhook)
    process-llm.ts              # LLM concept extraction
    extract-tasks.ts            # Task classification and routing
    index-vectors.ts            # LanceDB vector indexing
    compute-associations.ts     # Pairwise note similarity (LanceDB)
    compute-relationships.ts    # Typed note relationships
    detect-threads.ts           # Thread detection
    reconsolidate-threads.ts    # Thread summary + momentum
    thread-lifecycle.ts         # Archive/split/merge threads
    export-obsidian.ts          # Obsidian vault sync
    daily-summary.ts            # Daily summary generation
    send-digest.ts              # Apple Notes digest delivery
    transcribe-voice-memos.ts   # whisper.cpp voice transcription
    distill-essences.ts             # Essence backfill + retry
    evaluate-fidelity.ts            # Fidelity tier assignment (daily)
    compile-thread-digests.ts       # Thread digest compilation
    render-daily-sheet.ts           # Daily planning sheet PDF
  templates/
    daily-sheet.html        # Planning sheet HTML template

launchd/
  com.selene.server.plist                  # Webhook server (always running)
  com.selene.process-llm.plist             # Every 5 minutes
  com.selene.extract-tasks.plist           # Every 5 minutes
  com.selene.index-vectors.plist           # Every 10 minutes
  com.selene.compute-relationships.plist   # Every 10 minutes
  com.selene.detect-threads.plist          # Every 30 minutes
  com.selene.reconsolidate-threads.plist   # Hourly
  com.selene.export-obsidian.plist         # Hourly
  com.selene.daily-summary.plist           # Daily at midnight
  com.selene.thread-lifecycle.plist        # Daily at 2am
  com.selene.send-digest.plist             # Daily at 6am
  com.selene.transcribe-voice-memos.plist  # WatchPaths trigger
  com.selene.dev-process-batch.plist       # Dev: hourly batch processing
  com.selene.distill-essences.plist          # Every 5 minutes
  com.selene.evaluate-fidelity.plist         # Daily at 3am
  com.selene.compile-thread-digests.plist    # Hourly
  com.selene.render-daily-sheet.plist        # Daily at 5:30am
```

**Why this architecture?** See `@.claude/DEVELOPMENT.md` (System Architecture section)

---

## ADHD Design Principles

1. **Externalize Working Memory** - Visual systems, not mental tracking
2. **Make Time Visible** - Structured vs. unstructured time
3. **Reduce Friction** - One-click capture, minimal steps
4. **Visual Over Mental** - "Out of sight, out of mind"
5. **Realistic Over Idealistic** - Under-schedule, not over-schedule

**Full framework:** `@.claude/ADHD_Principles.md`

---

## MANDATORY: Worktree Sync Check

**BEFORE doing ANY work in a `.worktrees/*` directory, you MUST:**

1. Run: `git fetch origin && git rev-list --count HEAD..origin/main`
2. If behind: Announce and offer to rebase before proceeding
3. See `@.claude/GITOPS.md` (Session Start Ritual) for full procedure

**Trigger conditions:**
- User asks to continue work on a feature branch
- Session starts with working directory in `.worktrees/*`
- Switching from main repo to a worktree

**This is not optional.** Skipping this leads to painful rebases at merge time.

---

## Critical Rules (Do NOT)

**Testing:**
- Never use production database for testing - Always use test_run markers
- Never skip `test_run` marker when testing workflows
- Never commit test data to production tables
- Always cleanup test data with `./scripts/cleanup-tests.sh`

**Documentation:**
- Never create *_COMPLETE.md or *_STATUS.md files - Use design doc status and `docs/completed/` archive
- Always update documentation after changes

**Security:**
- Never commit .env files - Use .env.example only
- Never skip duplicate detection in ingestion

**Code Quality:**
- Never use ANY type in TypeScript/Swift - Always specify types
- Always use parameterized SQL queries (prevent injection)

**See:** `@.claude/OPERATIONS.md` for detailed procedures

---

## Quick Command Reference

### Server Operations
```bash
# Check server health
curl http://localhost:5678/health

# View server logs
tail -f logs/server.out.log

# Restart server via launchd
launchctl kickstart -k gui/$(id -u)/com.selene.server
```

### Workflow Operations
```bash
# Run workflows manually
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/extract-tasks.ts
npx ts-node src/workflows/index-vectors.ts
npx ts-node src/workflows/compute-associations.ts
npx ts-node src/workflows/compute-relationships.ts
npx ts-node src/workflows/detect-threads.ts
npx ts-node src/workflows/reconsolidate-threads.ts
npx ts-node src/workflows/thread-lifecycle.ts
npx ts-node src/workflows/export-obsidian.ts
npx ts-node src/workflows/daily-summary.ts
npx ts-node src/workflows/send-digest.ts
npx ts-node src/workflows/transcribe-voice-memos.ts
npx ts-node src/workflows/distill-essences.ts
npx ts-node src/workflows/evaluate-fidelity.ts
npx ts-node src/workflows/compile-thread-digests.ts
npx ts-node src/workflows/render-daily-sheet.ts

# Open today's sheet
open ~/selene-data/digests/daily-sheets/selene-daily-$(date +%Y-%m-%d).pdf

# View workflow logs
tail -f logs/selene.log | npx pino-pretty

# Check compression progress
curl http://localhost:5678/health/compression
```

### Launchd Management
```bash
# List Selene agents
launchctl list | grep selene

# Start/stop an agent
launchctl start com.selene.process-llm
launchctl stop com.selene.process-llm

# Install all launchd agents
./scripts/install-launchd.sh
```

### Database
```bash
sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes;"
sqlite3 data/selene.db ".schema raw_notes"
```

### Dev Environment
```bash
# Check dev processing status
./scripts/dev-process-batch.sh --status

# Run one batch manually
SELENE_ENV=development ./scripts/dev-process-batch.sh

# Set up from scratch
./scripts/create-dev-db.sh && npx ts-node scripts/seed-dev-data.ts

# View dev batch logs
tail -f ~/selene-data-dev/logs/batch-process.log
```

### Testing
```bash
# Test ingestion endpoint
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Test", "content": "Test content", "test_run": "test-123"}'

# List test runs
./scripts/cleanup-tests.sh --list

# Cleanup test data
./scripts/cleanup-tests.sh test-123
```

**Full command reference:** `@.claude/OPERATIONS.md`

---

## Project Status

**Completed:**
- Server infrastructure - Fastify webhook server with health checks
- Ingestion - Note capture with duplicate detection
- LLM Processing - Concept extraction working
- Vector Search - LanceDB integration (replaced brute-force similarity)
- Note Associations - Pairwise similarity via LanceDB vector search
- Relationships - Typed note relationships with incremental computation
- Dev Environment - Parallel dev environment with 536 fictional notes, hourly batch processing
- Thread System - Detection, reconsolidation, lifecycle (archive/split/merge), Obsidian export
- SeleneChat - Database integration, Ollama AI, thread queries, thread workspace
- Thinking Partner - Conversation memory, context builder, deep-dive, synthesis
- Voice Input - Apple Speech recognition, push-to-talk, URL scheme
- Voice Memo Transcription - whisper.cpp pipeline, auto-detect, Selene ingestion
- Menu Bar Orchestrator - Silver Crystal icon, WorkflowScheduler, animated states
- Morning Briefing - Structured cards with deep context chat
- Apple Notes Digest - Replaced iMessage with pinned daily note
- Phase 7.2 - SeleneChat Planning Integration
- SeleneMobile iOS App - Full parity chat, threads, briefing, voice input over Tailscale
- Server REST API - Auth middleware, ~30 endpoints, Ollama proxy, APNs push notifications

**Next Up (see `docs/plans/INDEX.md` for status):**
- Thread Workspace Phase 3 - Feedback loop (Things sync, momentum updates)
- Voice Input Phase 2+ - Global hotkey, Voxtral, TTS
- SeleneChat UI Redesign - Forest Study design system
- Phase 7.3 - Cloud AI Integration (sanitization layer)

**Details:** `@.claude/PROJECT-STATUS.md`

---

## File Organization

### Key Directories

```
selene/
+-- CLAUDE.md                # THIS FILE - single entry point
+-- .claude/                 # Context files for AI development
|   +-- OPERATIONS.md       # Commands, testing, debugging
|   +-- DEVELOPMENT.md      # Architecture and decisions
|   +-- PROJECT-STATUS.md   # Current state (update every session)
|   +-- GITOPS.md           # Branch workflow, git conventions
|   +-- ADHD_Principles.md  # ADHD design framework
+-- src/                     # TypeScript source code
|   +-- server.ts           # Fastify webhook server
|   +-- lib/                # Shared utilities
|   +-- workflows/          # Background processing scripts
|   +-- types/              # TypeScript type definitions
+-- launchd/                 # macOS launch agent plists
+-- scripts/                 # Project-wide utilities
|   +-- CLAUDE.md           # Script documentation
|   +-- install-launchd.sh  # Install launchd agents
|   +-- cleanup-tests.sh    # Remove test data
+-- docs/                    # Reference documentation
|   +-- INDEX.md            # Documentation navigation
|   +-- plans/              # Design documents
+-- SeleneChat/              # Swift package (3 targets)
|   +-- Sources/SeleneShared/  # Shared models, protocols, utilities
|   +-- Sources/SeleneChat/    # macOS menu bar app
|   +-- Sources/SeleneMobile/  # iOS app (Tailscale REST client)
+-- data/                    # SQLite database
    +-- selene.db
```

---

## Common Workflows

### Modifying a Workflow Script

1. Edit the TypeScript file in `src/workflows/`
2. Run manually to test: `npx ts-node src/workflows/<name>.ts`
3. Check logs: `tail -f logs/selene.log | npx pino-pretty`
4. Commit changes

### Testing Changes

1. Generate test ID: `TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"`
2. Send test data with `test_run` marker
3. Verify results in database
4. Cleanup: `./scripts/cleanup-tests.sh "$TEST_RUN"`

**See:** `@.claude/OPERATIONS.md` (Testing Procedures)

### Daily Development

**Starting:**
- Check `@.claude/PROJECT-STATUS.md`
- Verify server running: `curl http://localhost:5678/health`
- Check launchd agents: `launchctl list | grep selene`
- Review `@ROADMAP.md` for next tasks

**During:**
- Test frequently with `test_run` markers
- Check logs for errors
- Commit logical chunks

**Ending:**
- Run tests
- Update PROJECT-STATUS.md
- Cleanup test data
- Commit all changes

**See:** `@.claude/OPERATIONS.md` (Daily Development Checklist)

---

## Troubleshooting

- Check `@.claude/OPERATIONS.md` (Troubleshooting section)
- View logs: `tail -f logs/selene.log | npx pino-pretty`
- Check server: `curl http://localhost:5678/health`
- Check launchd: `launchctl list | grep selene`

---

## Version History

- **2026-03-01**: Renamed project from selene-n8n to selene (removed legacy n8n naming)
- **2026-01-27**: Simplified to two-layer system (design docs + GitOps). Archived user stories.
- **2026-01-09**: Replaced n8n with TypeScript backend (Fastify + launchd)
- **2026-01-06**: Migrated n8n from Docker to local installation (v1.110.1) for easier debugging
- **2026-01-02**: Documentation consolidation - single entry point, removed redundant files
- **2025-12-30**: Added GitOps development practices (.claude/GITOPS.md)
- **2025-12-30**: Phase 7.1 design revised - Task Extraction with Classification
- **2025-11-27**: Reorganized into modular context structure
- **2025-11-13**: Added SeleneChat enhancements phase
- **2025-11-01**: Added Phase 1.5 (UUID Tracking Foundation)
- **2025-10-30**: Phase 1 completed (10 notes processed)
- **2025-10-18**: Initial roadmap created

---

## Before Creating Documentation

**STOP. Check these rules before creating any new markdown file:**

1. **Does this info already exist?** Check `.claude/*.md`, `docs/INDEX.md`

2. **What type of information is this?**
   | Type | Canonical Location |
   |------|-------------------|
   | Current status | `.claude/PROJECT-STATUS.md` |
   | Commands/testing | `.claude/OPERATIONS.md` |
   | Architecture/patterns | `.claude/DEVELOPMENT.md` |
   | Git/branch workflow | `.claude/GITOPS.md` |
   | Design planning | `docs/plans/YYYY-MM-DD-topic-design.md` |

3. **Update existing file, don't create new one.**

4. **If creating a design doc:** Add entry to `docs/plans/INDEX.md`

---

**This is a living document. Update after major changes or architectural decisions.**
