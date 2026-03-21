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
- `scripts/` — Archived shell scripts
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
