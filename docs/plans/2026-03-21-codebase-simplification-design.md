# Selene Codebase Simplification

**Date:** 2026-03-21
**Status:** Ready
**Scope:** 3-5 days

---

## Problem

Selene has grown to ~20,000 lines of active code, 17 background agents, and 64 scripts — but only 2 features are used daily (capture and LLM processing). The remaining features (threads, task extraction, SeleneChat, SeleneMobile, daily sheets, vector search) need major rework before they're useful. Meanwhile, they add complexity that makes the system harder for AI to maintain reliably.

## Goal

Strip Selene back to a clean, tight core that does 4 things well:

1. **Capture** — Notes from Drafts/voice into the database
2. **Process** — Ollama extracts concepts and essences
3. **Browse** — Obsidian export for reading and exploring notes
4. **Visibility** — Daily summary so the user knows what the system sees

Preserve all ideas and code for future rebuilding via archive directory and design docs.

## Acceptance Criteria

- [ ] Active codebase reduced to ~3,500 lines (6 workflows, 5 launchd agents, 6 scripts)
- [ ] Shelved code moved to `archive/shelved-2026-03-21/` with README
- [ ] Legacy n8n artifacts deleted (210MB reclaimed)
- [ ] `.env` removed from repo, `.gitignore` updated
- [ ] LLM prompts consolidated into `src/lib/prompts.ts`
- [ ] Types deduplicated into `src/types/index.ts`
- [ ] Server stripped to health + webhook routes only
- [ ] Scripts consolidated from 64 to ~6
- [ ] Launchd agents reduced from 17 to 5
- [ ] All documentation updated (CLAUDE.md, PROJECT-STATUS, OPERATIONS, INDEX)
- [ ] Log rotation added
- [ ] All active workflows still function correctly after changes
- [ ] Capture + process + export-obsidian + daily-summary tested end-to-end

## ADHD Check

- Reduces cognitive load (fewer moving parts to wonder about)
- Makes the system visible and understandable (4 clear functions)
- Removes friction for future work (clean foundation to build on)

## What Stays Active

### Workflows (6)

| File | Purpose | Schedule |
|------|---------|----------|
| `ingest.ts` | Note capture from webhooks | Called by server |
| `process-llm.ts` | Concept extraction via Ollama | Every 5 min |
| `distill-essences.ts` | Essence generation | Every 5 min |
| `export-obsidian.ts` | Sync to Obsidian vault | Hourly |
| `daily-summary.ts` | Activity summary generation | Daily midnight |
| `send-digest.ts` | Apple Notes delivery | Daily 6am |

### Server

- `server.ts` — Health check + webhook ingestion endpoint only
- All other routes removed (threads, notes API, Ollama proxy, etc.)

### Libraries (all of `src/lib/`)

Kept as-is. Small, clean, well-written utilities.

### Launchd Agents (5)

- `com.selene.server.plist`
- `com.selene.process-llm.plist`
- `com.selene.distill-essences.plist`
- `com.selene.export-obsidian.plist`
- `com.selene.daily-summary.plist`

### Scripts (6)

- `install-launchd.sh` (updated for 5 agents)
- `cleanup-tests.sh`
- `create-dev-db.sh` (consolidate 3 variants)
- `dev-process-batch.sh`
- `setup-hooks.sh` (merge two overlapping scripts)
- `test-ingest.sh`

### Database

No destructive schema changes. Tables stay; unused ones are simply inert.

## What Gets Archived

Moved to `archive/shelved-2026-03-21/` with a README explaining what's there and why.

### Workflows (11)

- `detect-threads.ts`, `reconsolidate-threads.ts`, `thread-lifecycle.ts`
- `compute-associations.ts`, `compute-relationships.ts`, `index-vectors.ts`
- `extract-tasks.ts`, `compile-thread-digests.ts`
- `render-daily-sheet.ts`, `evaluate-fidelity.ts`, `transcribe-voice-memos.ts`

### Apps

- `SeleneChat/` — Entire Swift package (macOS + iOS + shared)

### Routes

- All API route files (threads, notes, Ollama proxy, etc.)

### Launchd (12 plists)

All agents for shelved workflows.

### Scripts (~58)

Everything except the 6 kept scripts.

## What Gets Deleted

Already preserved in git history, just taking up space:

- `.n8n-local/` (210 MB) — n8n removed Jan 2026
- `.workflow-backup-*` (228 KB) — n8n backup
- `archive/` (existing, 1.1 MB) — Old n8n workflows

## Cleanup Tasks

### TypeScript
- Consolidate LLM prompts into `src/lib/prompts.ts`
- Deduplicate types into `src/types/index.ts`
- Remove dead imports from remaining files
- Inline remaining routes into `server.ts`, remove route files

### Scripts
- Merge `setup-hooks.sh` and `setup-git-hooks.sh`
- Consolidate 3 DB creation scripts into one
- Archive the rest

### Documentation
- Update `CLAUDE.md` for simplified system
- Update `.claude/PROJECT-STATUS.md`
- Update `.claude/OPERATIONS.md`
- Update `docs/plans/INDEX.md` with simplification note

### Security & Operations
- Remove `.env` from repo
- Update `.gitignore` for `.env`
- Add log rotation

## Rebuilding Features Later

When ready to bring a feature back:

1. Check `docs/plans/` for the original design doc and vision
2. Check `archive/shelved-2026-03-21/` for the original implementation
3. Create a new design doc for the improved version
4. Build against the clean core as a self-contained addition
5. Each rebuilt feature should be a single workflow file + its launchd agent

## Risks

- **Breaking active workflows:** Mitigated by testing each one after changes
- **Losing code:** Mitigated by archive directory + full git history
- **Export-obsidian dependencies:** This workflow may import from archived code — needs careful dependency check before archiving
- **daily-summary/send-digest dependencies:** Same — verify these don't pull from thread/task systems
