# Selene Project - Current Status

**Last Updated:** 2026-06-01
**Status:** Simplified Core | Agent Layer (scaffolded, dormant — see note) | Synthesis Layer Shipped | Note Annotation (iPad) Shipped | Dev/Prod Boundary Hardened (guard + corpus) | Content Clustering Rolled Out (8 categories, multi-membership) | Knowledge Constellation Phase A Shipped | PKM Browse Dashboard Shipped (`/pkm/*`) | Fact Store LIVE (two-file split) | **Sub-categories Phase 1 merged to main (taxonomy facets under the 8)**

> **2026-06-06 session — Sub-categories Phase 1 (merged to `main`, not yet pushed/deployed):** Added a second taxonomy level (facets) under the 8 fixed categories, subagent-driven (11 TDD tasks, two-stage review). Git-tracked seed taxonomy at `src/config/sub-taxonomy.ts` (the file you edit to curate; survives a fact-store `rebuild`). `process-llm` assigns a closed-set sub-category per note (NULL on Ollama failure → retriable by `scripts/backfill-sub-categories.ts`). `synthesize-topics` materializes sub-clusters (`topic_clusters` rows with `parent_id` + `health-body/running` slugs) in a **separate pass after the category loop** (decoupled from the `unchanged` short-circuit — a TRAP test guards it); orphan-cleanup rewritten as a structural `isValidClusterSlug` guard (fixes the silent-wipe landmine). Constellation `parent::` edges work with zero code change. Content-free curation dial: `backfill-sub-categories.ts --report` + `selene-inspect coverage` → per-category `none%`. `/api/clusters` (iPad) stays top-level (sub-clusters excluded in Ph1). 233 tests, tsc clean; reviewed per-task + Ollama-contract + whole-branch (the whole-branch pass caught the `/api/clusters` leak). **Next (operator):** dev smoke (process-llm→backfill→`--report`→synthesize→eyeball vault, needs Ollama); then push origin main to deploy; then run the prod backfill. Curate the v0 taxonomy names by reading `none%`. Ph2 (emergent tail + curator agent + firmness) remains. Pre-existing unrelated flake noted: `rebuild-core.db.test.ts` fails only under `jest --runInBand` (cross-suite isolation), green in default parallel runs. Plan: `docs/plans/2026-06-06-sub-categories-plan.md`.

> **2026-06-01 session — Fact Store cutover (Ph1 LIVE in prod):** Migrated prod's single DB to the two-file fact store (`facts.db` PRECIOUS captured notes + review state; `selene.db` DISPOSABLE derived layer; `raw_notes` is now a per-connection view). The gated `cutover-prod.sh` ran against prod: two attempts **auto-rolled-back cleanly** (zero data risk) on real prod-data cruft the clean dev DB couldn't surface (6 orphaned `processed_notes`, 61 pre-existing FK violations), then succeeded — 295 notes migrated, prod healthy. Migration hardened to TOLERATE pre-existing referential cruft (faithful: fail only on what it INTRODUCES). High-effort code review (9 findings) resolved; dev-tooling made two-file-aware (`reset-dev-data.sh`, `cleanup-tests.sh`); dev→prod vault-path bug FIXED (`resolveVaultPath`). All merged to `main`; 206 tests. Lesson: validate the migration on a `.backup` copy of REAL prod before merging. Remaining: fact-store Ph2 (`rebuild`) + Ph3 (`category_overrides`); PKM Track 3; Constellation Phase B.

> **2026-05-30 session:** Hardened the dev/prod boundary (Claude-out-of-prod guard + `selene-inspect` + designed dev corpus). Diagnosed a silent prod incident — the nightly `synthesize-topics` agent was crashing on `SQLITE_BUSY` (no `busy_timeout`), so content-clustering never rolled out; fixed (`db.ts` busy_timeout) and rolled out (prod: 83 old clusters → 8 content categories, multi-membership). Shipped Knowledge Constellation Phase A (`parent::` + `Constellation/` for ExcaliBrain) and the PKM browse dashboard (`/pkm/*`, Tracks 1+2). All deployed; 230 tests. Remaining: PKM Track 3 (exporter slim upgrade), Constellation Phase B (`friend::`, gated on `note_connections` spike), and the operator's visual ExcaliBrain check.

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

### Live inventory — see the generated map (do not hand-maintain counts here)

The 2026-03-21 simplification cut the core to 6 workflows; **the system has grown since** (synthesis, the agent layer, eink/voice ingest, worksheets, folio feedback, …). To prevent drift, this doc no longer hard-codes counts — each fact lives in exactly one generated/source place:

- **Workflows, launchd agents, schedules, reads/writes:** `docs/SYSTEM-MAP.md` — generated from `src/workflows/` + `launchd/` by `scripts/gen-system-map.ts`. A pre-push git hook and the session-end Stop hook run `--check` to catch drift.
- **HTTP routes:** see `src/server.ts` (`server.register(...)`); route plugins live in `src/routes/` (agents, dashboard, notes, pkm, worksheets).
- **Scripts:** `scripts/` (documented in `scripts/CLAUDE.md`).
- **Shared libraries:** `src/lib/` (db, ollama, config, logger, prompts, auth, lancedb, …).

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
| User Guides | `docs/guides/features/` + hub `docs/USER-EXPERIENCE.md` | Active (5 guides) |

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

## Recently Shipped — Prod/Dev Split (LIVE 2026-05-29)

**Branch:** `feat/prod-dev-split` (merged to main, PR #45)

Establishes a release boundary so dev work never touches what's running. **LIVE as of 2026-05-29:** production runs from the compiled artifact in `~/selene-prod/dist` (11 `com.selene.prod.*` agents + deploy-watcher, serving `:5678` against the real DB). `~/selene` is now a free dev sandbox on `main` with NO scheduled agents. The old `com.selene.*` agents were retired in the one-time cutover.

Three-directory model:
- `~/selene` — dev sandbox (dev DB `~/selene-data-dev`, ts-node, port 5679, manual workflows, no scheduled agents)
- `~/selene-build` — scratch build clone (build site only; never edited by hand)
- `~/selene-prod` — production (compiled `dist/`, real DB `~/selene-data/selene.db`, iCloud vault, port 5678, `com.selene.prod.*` agents)

Release flow: merge to `main` → a launchd deploy-watcher (`com.selene.prod.deploy-watcher`, `StartInterval` 300) polls `origin/main`, build-gates in the scratch clone, ships only `dist/` to prod (preserving `.env`), archives the prior release for rollback, reloads prod agents, health-checks `:5678`, and notifies on success or failure. Roll back with `./scripts/rollback-prod.sh`.

- Scripts: `scripts/deploy-watch.sh`, `scripts/deploy-prod.sh`, `scripts/install-prod.sh`, `scripts/rollback-prod.sh`, `scripts/lib/notify.sh`
- Agent: `launchd/com.selene.prod.deploy-watcher.plist`
- Two coexisting iPad app targets (Selene `:5678` / Selene Dev `:5679`) built in `~/SeleneMarkup` on branch `feat/dev-prod-apps` (not yet merged/device-installed)
- User guide: `docs/guides/features/releases.md`
- Follow-ups: reconstruct dev fixture generators; merge worksheet routes onto the prod server (so the prod iPad app's worksheets work)

---

## Recent Achievements

### 2026-05-28

- **Synthesis Layer shipped** — Three signals added to the 6am digest: topic clustering with Ollama synthesis narratives (nightly, `synthesize-topics.ts`), evolution detection when understanding shifts, and connection detection at process time (`process-llm.ts`). Four new digest sections: Topics circling, Understanding shifted, Unexpected connections, Pattern forming. Sunday weekly rollup.
  - New workflow: `src/workflows/synthesize-topics.ts` — 2am nightly via `com.selene.synthesize-topics` launchd agent
  - New libs: `src/lib/synthesis-db.ts`, `src/lib/cosine.ts`, `src/lib/synthesis-digest.ts`
  - Extended: `src/workflows/process-llm.ts` (embedding + connection detection), `src/workflows/send-digest.ts` (4 new sections)
  - New tables: `topic_clusters`, `topic_note_links`, `note_connections`, `synthesis_meta`
  - 17 tests passing. User guide: `docs/guides/features/synthesis-layer.md`
  - First production run: 14 clusters, 68 proto-clusters from 285 notes

### 2026-05-27

- **Interactive Worksheets Phase 1 shipped** — Multi-field scrollable form with per-field PKCanvasView (finger scrolls, pencil draws), note-review cards surfacing backlog notes, Vision OCR on submit, "Selene remembers…" related-notes sheet via nomic-embed-text + LanceDB. OCR review-before-submit step added: recognized text shown in editable field before POST fires.
  - Track A (TypeScript): `src/types/worksheets.ts`, `src/workflows/generate-worksheet.ts`, `src/routes/worksheets.ts` on `feature/interactive-worksheets` branch
  - Track B (Swift/iPad): `~/SeleneMarkup` — `WorksheetView`, `CanvasView`, `RelatedNotesSheet`, `HandwritingService`
  - User guide: `docs/guides/features/interactive-worksheets.md`
  - Dev server runs on port 5679; deploy via `cd ~/SeleneMarkup && ./redeploy.sh`

### 2026-05-25
- **Folio iPad Delivery** (`~/folio/scripts/send-ipad.ts`) — QR code in terminal → iPad opens folio LAN reader → Apple Pencil annotation → feedback routes to Selene. Bugs fixed: port conflict detection, Tailscale vs LAN IP preference, Safari dark mode (`color-scheme: light`).
  - Run: `cd ~/folio && FOLIO_PORT=3001 npx ts-node scripts/send-ipad.ts <file.md>` (port flag only needed when selene-docs is on 3000)
- **Agent Layer E2E test** (`src/agents/e2e.test.ts`) — full job lifecycle smoke test. All 7 agent test suites passing.
- **eink launchd bug fixed** — exit 126 from wrong npx path (`/opt/homebrew` → `/usr/local`). WatchPaths agent now triggers correctly.
- **Finishing skill updated** — Step 5 added: marks design doc as Done in INDEX.md after merge/push.
- **Folio Kindle delivery** (`~/folio/scripts/send-report.ts`) — generates PDF via Puppeteer, emails to Kindle via SMTP. Session reports deliverable to Kindle.

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
- Live schema is built in code by `src/lib/ensure-migrated.ts` + `src/lib/facts-db.ts` (two-file fact store). The old single-DB `database/` SQL migrations are archived under `archive/legacy-2026-06-09/`.

**Source Code:**
- `src/server.ts` - Webhook server entry point
- `src/lib/` - Shared utilities
- `src/workflows/` + `launchd/` - workflows & launchd agents (live inventory: `docs/SYSTEM-MAP.md`)

**Archive:**
- `archive/shelved-2026-03-21/` - All shelved features with README

---

## Questions for Next Session

1. **Synthesis layer** — next roadmap item (Vision status, plan written at `docs/plans/2026-05-24-synthesis-layer-plan.md`). Auto-detect topic clusters → Ollama synthesis → Obsidian `/synthesis/` folder.
2. Are the 6 active workflows running stably?
3. Is the Obsidian export producing useful output?
