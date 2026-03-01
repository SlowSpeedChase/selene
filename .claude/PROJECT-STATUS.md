# Selene Project - Current Status

**Last Updated:** 2026-02-27
**Status:** Dev Environment Isolation | Living System Active

---

## Project Overview

Selene is a **thought consolidation system** for someone with ADHD. The core problem is not capturing thoughts or organizing them - it is making sense of them over time and knowing when to act.

Notes form **threads** - lines of thinking that span multiple notes, have underlying motivations, and eventually become projects or writing or decisions. **The system's job is to hold the thread so the user does not have to.**

**Architecture:** TypeScript + Fastify + launchd with SQLite database + Ollama embeddings
**Location:** `/Users/chaseeasterling/selene`

---
## Current Focus: All Major Features Shipped

**Branch:** `main` (all work merged)

All three "Ready" designs from 2026-02-12 are now implemented and merged. The system has grown significantly: menu bar orchestrator manages workflow scheduling, voice memos are auto-transcribed via whisper.cpp, and the morning briefing got a full redesign with structured cards.

### Recent Completions
- **Intelligence Upgrade Layers 1+2** (2026-02-27) - Prosthetic executive function for chat
  - `ContextualRetriever` — multi-signal retrieval (emotional history, task outcomes, sentiment trends, thread state)
  - `RetrievedContext`/`ContextBlock` — labeled context blocks for structured LLM injection
  - New DB queries: `getEmotionalNotes`, `getTaskOutcomes`, `getSentimentTrend`
  - All 5 prompt builders rewritten with zen personality (cite evidence, ask first, present options)
  - Planning intent detection expanded to 53 patterns
  - `Note` gains `essence`/`fidelityTier`, `Thread` gains `threadDigest`/`emotionalCharge`
  - 743 tests, 34 files changed, +1614/-167 lines
- **Tiered Context Compression** (2026-02-22) - Lifecycle-based fidelity tiers for LLM context scaling
  - `ContextBuilder` shared utility — tiered rendering (full/high/summary/skeleton) within token budgets
  - `distill-essences.ts` — backfills note essences (1-2 sentence distillations) at ~120/hour
  - `evaluate-fidelity.ts` — daily tier assignment based on age + thread activity
  - `compile-thread-digests.ts` — thread-level narrative digest compilation
  - Updated `detect-threads.ts`, `reconsolidate-threads.ts`, `daily-summary.ts` to use ContextBuilder
  - `/health/compression` endpoint for monitoring tier distribution and backfill progress
  - Migration 020: `essence`, `fidelity_tier` on `processed_notes`, `thread_digest` on `threads`
- **Dev Environment Isolation** (2026-02-22) - Full parallel dev environment with 536 fictional notes
  - `~/selene-data-dev/` with separate SQLite, LanceDB, Obsidian vault
  - `SELENE_ENV=development` environment switching via `src/lib/config.ts`
  - `dev-process-batch.sh` runs 6-step pipeline with configurable batch sizes
  - `compute-associations.ts` — new TypeScript workflow (was missing from old n8n port)
  - Hourly launchd agent (`com.selene.dev-process-batch`) for gradual processing
  - Scripts: `create-dev-db.sh`, `seed-dev-data.ts`, `reset-dev-data.sh`
- **SeleneMobile iOS App** (2026-02-14) - Full-parity iOS app over Tailscale VPN
  - Three-target SPM: SeleneShared + SeleneChat + SeleneMobile
  - Protocol-based data layer: DataProvider, LLMProvider
  - RemoteDataService (29 endpoints), RemoteOllamaService (LLM proxy)
  - Chat, threads, briefing, voice input, push notifications, Live Activities
  - ATS exception for Tailscale HTTP, APNs push via HTTP/2
- **Server REST API** (2026-02-14) - Expanded Fastify with ~30 endpoints
  - Bearer token auth middleware, Ollama proxy, device registration
  - APNs push notifications for briefing and thread activity
- **Thread Workspace Phase 3** (2026-02-13) - On-demand Things sync, task completion momentum boost, LLM "what's next" recommendation
- **Morning Briefing Redesign** (2026-02-13) - Structured cards, deep context chat, cross-thread connections
- **Menu Bar Orchestrator** (2026-02-13) - Silver Crystal icon, WorkflowScheduler replaces launchd, animated processing state
- **Voice Memo Transcription** (2026-02-13) - whisper.cpp pipeline, auto-detect new recordings, Selene ingestion
- **Apple Notes Daily Digest** (2026-02-13) - Replaced iMessage with pinned Apple Note
- **Thread Lifecycle** (2026-02-13) - Auto archive, split, merge with daily launchd schedule
- **Thread Workspace Phase 2** (2026-02-07) - Chat + task creation via confirmation banner
- **Voice Input Phase 1** (2026-02-05) - SpeechRecognitionService, VoiceMicButton, URL scheme
- **Thinking Partner** (2026-02-05) - Conversation memory, context builder, deep-dive, synthesis
- **Test Environment Isolation** (2026-02-06) - Anonymized test data, environment switching

### Dev Environment (Background)
A parallel development environment at `~/selene-data-dev/` processes 536 fictional notes through the full pipeline via hourly launchd batch job (`com.selene.dev-process-batch`). Use `SELENE_ENV=development` to target it. See `@.claude/OPERATIONS.md` (Development Environment section) for commands.

### Living System (Background)
The processing pipeline runs automatically (via WorkflowScheduler in SeleneChat menu bar app + launchd):
- LLM processing (every 5 min) - concept extraction via Ollama
- Task extraction (every 5 min) - classify and route to Things
- Vector indexing (every 10 min) - LanceDB embeddings via nomic-embed-text
- Relationship computation (every 10 min) - typed note relationships
- Thread detection (every 30 min) - cluster notes into threads
- Thread reconsolidation (hourly) - update summaries + calculate momentum
- Obsidian export (hourly) - sync threads/notes to vault
- Daily summary (midnight) - aggregate daily insights
- Apple Notes digest (6am) - post summary to pinned note
- Thread lifecycle (daily 2am) - archive stale, split divergent, merge converging
- Voice memo transcription (WatchPaths trigger) - auto-transcribe new recordings

### Completed Components

| Component | File | Status |
|-----------|------|--------|
| Webhook Server | `src/server.ts` | Done |
| Database Utilities | `src/lib/db.ts` | Done |
| Ollama Client | `src/lib/ollama.ts` | Done |
| Logger (Pino) | `src/lib/logger.ts` | Done |
| Configuration | `src/lib/config.ts` | Done |
| Ingestion Workflow | `src/workflows/ingest.ts` | Done |
| LLM Processing | `src/workflows/process-llm.ts` | Done |
| Task Extraction | `src/workflows/extract-tasks.ts` | Done |
| Vector Indexing | `src/workflows/index-vectors.ts` | Done |
| Relationship Computation | `src/workflows/compute-relationships.ts` | Done |
| Thread Detection | `src/workflows/detect-threads.ts` | Done |
| Thread Reconsolidation | `src/workflows/reconsolidate-threads.ts` | Done |
| Thread Lifecycle | `src/workflows/thread-lifecycle.ts` | Done |
| Obsidian Export | `src/workflows/export-obsidian.ts` | Done |
| Daily Summary | `src/workflows/daily-summary.ts` | Done |
| Apple Notes Digest | `src/workflows/send-digest.ts` | Done |
| Voice Memo Transcription | `src/workflows/transcribe-voice-memos.ts` | Done |
| Auth Middleware | `src/lib/auth.ts` | Done |
| APNs Client | `src/lib/apns.ts` | Done |
| REST API Endpoints | `src/server.ts` (~30 routes) | Done |
| SeleneShared Library | `SeleneChat/Sources/SeleneShared/` | Done |
| SeleneMobile iOS App | `SeleneChat/Sources/SeleneMobile/` | Done |
| Association Computation | `src/workflows/compute-associations.ts` | Done |
| Dev Batch Processor | `scripts/dev-process-batch.sh` | Done |
| Dev Launchd Agent | `launchd/com.selene.dev-process-batch.plist` | Done |
| Launchd Agents | `launchd/*.plist` | Done |
| Install Script | `scripts/install-launchd.sh` | Done |

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
Drafts App / Voice Memos
    |
    v
Fastify Server (port 5678, auth middleware, ~30 REST endpoints, Ollama proxy)
    |                                       ^
    v                                       |
SQLite Database + LanceDB        SeleneMobile (iOS via Tailscale)
    ^
    |
SeleneChat Menu Bar (WorkflowScheduler) + launchd:
  - process-llm (every 5 min)
  - extract-tasks (every 5 min)
  - index-vectors (every 10 min)
  - compute-relationships (every 10 min)
  - detect-threads (every 30 min)
  - reconsolidate-threads (hourly)
  - export-obsidian (hourly)
  - daily-summary (midnight)
  - thread-lifecycle (daily 2am)
  - send-digest (daily 6am)
  - transcribe-voice-memos (WatchPaths trigger)
    |
    v
Ollama (localhost:11434)
  - mistral:7b (text generation)
  - nomic-embed-text (embeddings)
whisper.cpp (~/.local/whisper.cpp/)
  - ggml-medium.bin (voice transcription)
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
    ingest.ts                   # Note ingestion (called by webhook)
    process-llm.ts              # LLM concept extraction
    extract-tasks.ts            # Task classification
    index-vectors.ts            # LanceDB vector indexing
    compute-associations.ts     # Pairwise note similarity (LanceDB)
    compute-relationships.ts    # Typed note relationships
    detect-threads.ts           # Thread detection
    reconsolidate-threads.ts    # Thread summary + momentum
    thread-lifecycle.ts         # Archive/split/merge threads
    export-obsidian.ts          # Obsidian vault sync
    daily-summary.ts            # Daily digest generation
    send-digest.ts              # Apple Notes digest delivery
    transcribe-voice-memos.ts   # whisper.cpp transcription
  types/
    index.ts          # Shared TypeScript types

launchd/
  com.selene.server.plist
  com.selene.process-llm.plist
  com.selene.extract-tasks.plist
  com.selene.index-vectors.plist
  com.selene.compute-relationships.plist
  com.selene.detect-threads.plist
  com.selene.reconsolidate-threads.plist
  com.selene.thread-lifecycle.plist
  com.selene.export-obsidian.plist
  com.selene.daily-summary.plist
  com.selene.send-digest.plist
  com.selene.transcribe-voice-memos.plist

logs/
  selene.log          # Workflow logs (Pino JSON)
  server.out.log      # Server stdout
  server.err.log      # Server stderr
```

---

## Existing Features (Migrated)

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

### Task Extraction
- Three-way classification: actionable / needs_planning / archive_only
- Things 3 integration for actionable tasks
- Discussion threads for planning items

### Vector Search & Relationships
- LanceDB for semantic vector search (replaced brute-force cosine similarity)
- Typed note relationships (BT/NT/RT/TEMPORAL/SAME_THREAD/SAME_PROJECT)
- Thread detection via note clustering

### Daily Summary
- Aggregates notes, insights, patterns
- LLM-generated executive summary
- Writes to Obsidian vault

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
npx ts-node src/workflows/extract-tasks.ts
npx ts-node src/workflows/index-vectors.ts
npx ts-node src/workflows/compute-relationships.ts
npx ts-node src/workflows/detect-threads.ts
npx ts-node src/workflows/reconsolidate-threads.ts
npx ts-node src/workflows/thread-lifecycle.ts
npx ts-node src/workflows/export-obsidian.ts
npx ts-node src/workflows/daily-summary.ts
npx ts-node src/workflows/send-digest.ts
npx ts-node src/workflows/transcribe-voice-memos.ts
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

## Next Steps

**Completed:**
- ✅ SeleneMobile iOS App (full parity chat, threads, briefing, voice, push, Live Activities)
- ✅ Server REST API (~30 endpoints, auth, Ollama proxy, APNs push)
- ✅ Menu Bar Orchestrator (Silver Crystal icon, WorkflowScheduler, animated states)
- ✅ Voice Memo Transcription (whisper.cpp, auto-detect, Selene pipeline)
- ✅ Apple Notes Daily Digest (replaced iMessage with pinned Apple Note)
- ✅ Morning Briefing Redesign (structured cards, deep context chat)
- ✅ Thread Lifecycle (auto archive, split, merge — daily launchd schedule)
- ✅ Thread Workspace Phase 1-2 (read-only view + chat with task creation)
- ✅ Voice Input Phase 1 (Apple Speech, push-to-talk, URL scheme)
- ✅ Thinking Partner (conversation memory, context builder, deep-dive, synthesis)
- ✅ Test Environment Isolation (anonymized data, environment switching)
- ✅ Thread System Phase 1-3 (embeddings, associations, detection, reconsolidation)
- ✅ Phase 7.2 (SeleneChat Planning Integration)
- ✅ n8n replacement (TypeScript + Fastify + launchd)

**Up Next (choose one track):**

**Track A: Thread Workspace Phase 3 (Feedback Loop)**
- Task completion syncs back from Things
- Thread momentum updates based on task progress
- "What's done" view in workspace

**Track B: Voice Input Phase 2+**
- Global hotkey for voice capture
- Voxtral upgrade for better recognition
- TTS responses

**Track C: SeleneChat UI**
- Forest Study visual redesign (design docs in Vision)
- Interface improvements (command palette, focus mode)

**Track D: Phase 7.3 (Cloud AI Integration)**
- Privacy-preserving cloud AI with sanitization
- Bundled with Things Checklist Generation

---

## Recent Achievements

### 2026-02-14
- **SeleneMobile iOS App** - Native iOS app with full SeleneChat feature parity
  - Three-target SPM: SeleneShared (shared library), SeleneChat (macOS), SeleneMobile (iOS)
  - Protocol-based data layer: `DataProvider` (29 methods), `LLMProvider` (3 methods)
  - `RemoteDataService` + `RemoteOllamaService` — REST clients over Tailscale VPN
  - Chat, threads, briefing, voice input views
  - `MobileChatViewModel` — simplified ChatViewModel using protocol abstractions
  - `ConnectionManager` — Tailscale server URL + API token management
  - `PushNotificationService` + `MobileAppDelegate` — APNs registration and handling
  - `LiveActivityManager` — ActivityKit Live Activities during chat processing
  - ATS exception (`NSAllowsLocalNetworking`) for Tailscale HTTP traffic
- **Server REST API Expansion** - ~30 new Fastify endpoints for iOS access
  - Bearer token auth middleware (`src/lib/auth.ts`)
  - Notes, threads, sessions, memories, LLM proxy, briefing, device registration endpoints
  - APNs HTTP/2 push notifications (`src/lib/apns.ts`) with JWT auth
  - Notification triggers in `daily-summary.ts` and `detect-threads.ts`
  - 25 implementation tasks across 5 phases, all completed

### 2026-02-13
- **Morning Briefing Redesign** - Structured cards with BriefingCardView, deep context chat integration
  - `BriefingContextBuilder` for discuss-this chat context
  - Removed old `BriefingGenerator`, rewrote `BriefingViewModel` with structured card orchestration
- **Menu Bar Orchestrator** - SeleneChat becomes a menu bar utility
  - `WorkflowScheduler` service replaces 7 launchd plists
  - Silver Crystal moon icon with animated shimmer during Ollama processing
  - `MenuBarStatusView`, `SilverCrystalIcon`, `CrystalStatusItem`
  - Launch at login, dock icon toggles with chat window
- **Voice Memo Transcription** - whisper.cpp pipeline for auto-transcription
  - `transcribe-voice-memos.ts` watches Voice Memos directory
  - Converts .m4a → WAV → text via whisper.cpp medium model
  - Posts transcriptions to Selene pipeline with `voice-memo` tag
  - `setup-whisper.sh` for one-command installation
- **Apple Notes Daily Digest** - Replaced iMessage with pinned Apple Note
  - `send-digest.ts` now uses AppleScript to update "Selene Daily" note
  - Removed iMessage code and `IMESSAGE_DIGEST_TO` dependency
- **Thread Lifecycle Complete** - Auto Archive, Split, Merge
  - `thread-lifecycle.ts` — single workflow with 3 phases (archive → split → merge)
  - Archive: threads inactive 60+ days set to `archived` status
  - Split: BFS on intra-thread associations detects divergent sub-clusters, LLM names new threads
  - Merge: centroid comparison + LLM confirmation prevents false positives
  - Reactivation: archived threads come back to life when new notes are assigned (`detect-threads.ts`)
  - Obsidian: archived/merged threads routed to `Threads/Archive/` subfolder
  - Migration 017: expanded CHECK constraints for `archived`/`merged`/`reactivated` statuses
  - `com.selene.thread-lifecycle.plist` — daily at 2am via launchd
  - 5 files changed, 935 lines

### 2026-02-07
- **Thread Workspace Phase 2 Complete** - Chat with Task Creation
  - `ThreadWorkspacePromptBuilder` - includes task state in LLM context
  - `ThreadWorkspaceChatViewModel` - thread-scoped message pipeline
  - Pending actions confirmation banner (Create in Things / Dismiss)
  - `ActionService.sendToThingsAndLinkThread()` - create + link in one call
  - HSplitView layout: context panel | chat panel
  - 24 new tests (353 total, 0 failures)

### 2026-02-06
- **Thread Workspace Phase 1 Complete** - Read-Only View
  - `ThreadWorkspaceView` with thread context, tasks, notes
  - `ThreadTask` model + `Migration009_ThreadTasks`
  - `getTasksForThread`, `linkTaskToThread`, `getThreadById` on DatabaseService
  - Navigation from Today view "Heating Up" column
  - 35 tests for Phase 1

### 2026-02-05
- **Thinking Partner Phase 2 Complete** - Context Builder
  - `ThinkingPartnerQueryType` enum with token budgets (1500/2000/3000)
  - `ThinkingPartnerContextBuilder` service
  - `buildBriefingContext()` - threads by momentum + recent notes
  - `buildSynthesisContext()` - cross-thread with note titles
  - `buildDeepDiveContext()` - full thread + chronological notes
  - Token budget enforcement for all context types
  - 26 tests (14 unit + 12 integration)

- **Thinking Partner Phase 1 Complete** - Conversation Memory
  - `SessionContext` model for formatting conversation history
  - Token-aware truncation preserves recent messages
  - Simple summary for older turns (first 5 words of user messages)
  - Integrated into `ChatViewModel.handleOllamaQuery()`
  - Toggle `useConversationHistory` for debugging
  - Comprehensive CLI tests (7 integration tests)
  - Multi-turn conversations now work

### 2026-02-02
- **Daily Digest** - Condensed daily summary generated at midnight, delivered at 6am
  - `daily-summary.ts` generates bullet-point digest via Ollama at midnight
  - `send-digest.ts` delivers at 6am (originally iMessage, now Apple Notes)
  - End-to-end tested and working

### 2026-01-11
- **Obsidian Thread Export Complete** - Threads export to `Selene/Threads/` during reconsolidation
  - Markdown with frontmatter for Dataview queries
  - Wiki-links to exported notes
  - Integrated into hourly reconsolidation workflow
- **SeleneChat Thread Queries Complete** - "what's emerging" and "show me [thread]" queries
  - Added Thread model to SeleneChat
  - Added thread query detection to QueryAnalyzer
  - Added getActiveThreads/getThreadByName to DatabaseService
  - Thread queries bypass Ollama for instant response
- **Thread System Phase 3 Complete** - Living System active
- Created `reconsolidate-threads.ts` workflow (summary updates + momentum)
- Created launchd plist for hourly reconsolidation
- Updated launchd intervals: index-vectors/compute-relationships now 10 min, detect-threads 30 min
- Fixed server launchd plist to use `npm run start`
- End-to-end pipeline tested and verified
- 2 active threads with momentum scores calculated

### 2026-01-10
- Synced ROADMAP.md with stories INDEX.md
- Confirmed Phase 7.2 fully complete (7.2f.2-6 all merged)
- Confirmed Thread System Phase 1-2 complete
- Updated documentation with four next-track options
- Completed US-045: Thread Detection Workflow
- Applied thread system database migration (013_thread_system.sql)
- Generated embeddings for 15 production notes
- Computed 64 associations (threshold 0.5)
- Detected 2 threads via LLM synthesis
- Created launchd plist for scheduled thread detection

### 2026-01-09
- Completed TypeScript backend replacement
- Implemented all workflow scripts
- Created launchd agents for scheduling
- Updated documentation

### 2026-01-04
- Thread System Design complete
- Stories US-040 through US-044 defined

### 2025-12-31
- Phase 7.2d Complete - AI Provider Toggle
- Phase 7.2 Design Complete - SeleneChat Planning Integration

### 2025-12-30
- Phase 7.1 Complete - Task Extraction with Classification
- File-based Things integration with launchd automation

---

## Files to Reference

**Must Read:**
- `docs/plans/2026-01-04-selene-thread-system-design.md` - Thread system design
- `docs/plans/INDEX.md` - Design documents for implementation
- `database/schema.sql` - Database structure

**Source Code:**
- `src/server.ts` - Webhook server entry point
- `src/lib/` - Shared utilities
- `src/workflows/` - Background processing scripts
- `launchd/` - macOS launch agent configurations

---

## Questions for Next Session

1. Which track to pursue next? (A: Workspace Phase 3 feedback loop, B: Voice Phase 2+, C: UI Redesign, D: Cloud AI)
2. Is the menu bar orchestrator running stably? Any issues with WorkflowScheduler?
3. Are voice memo transcriptions flowing through the pipeline correctly?
