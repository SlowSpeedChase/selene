# Archived legacy — 2026-06-09

Orphaned artifacts moved out of the active tree during the maintainability pass.
Each was verified to have **zero live references** in `src/`, `scripts/`, `launchd/`,
or `package.json` before moving. Preserved here (and in git history) for reference.

## What's here & why it's dead

- `database/` — the **pre-fact-store, single-DB** schema + numbered SQL migrations
  (`003`–`021`) and its own `CLAUDE.md`. The live schema is no longer applied from
  these files; it is built in TypeScript by `src/lib/ensure-migrated.ts` +
  `src/lib/facts-db.ts` (the two-file `facts.db` + `selene.db` fact store). These SQL
  files are historical record of how the schema evolved, not a runtime source.
  (The stray 0-byte `database/selene.db` was deleted, not archived.)

- `config/resurface-triggers.yaml` — config for the archived "resurface" feature
  (shelved 2026-03-21). No live loader references it; runtime config is `src/lib/config.ts`.

- `prompts/` — `feedback/` + `planning/` prompt text for archived features. The live
  LLM prompts are code constants in `src/lib/prompts.ts` (plus a few inlined in their
  workflows); nothing loads these files.

## If you need one back

`git mv archive/legacy-2026-06-09/<path> <original-path>` — but first confirm it's
actually wired into live code, since it wasn't when archived.
