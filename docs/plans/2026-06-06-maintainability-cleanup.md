# Maintainability Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove ~1,450 lines of dead and duplicated code from `src/` and `scripts/` (only) while preserving every live behavior, so the active codebase stays small and navigable.

**Architecture:** Sequenced by risk. Phase A is pure dead-code deletion (subsystems archived in the 2026-03-21 simplification that were never removed) — a senior engineer merges these on sight. Phase B fixes two drift bugs in glue/config. Phase C does a handful of low-risk consolidations that change behavior subtly. Each task is one coordinated commit gated by `tsc --noEmit` + a targeted `jest` run + a `git grep` that the removed symbol is gone.

**Tech Stack:** TypeScript, better-sqlite3, Fastify, Jest (ts-jest), launchd, bash. Local-only personal app; no CI.

**Source:** Findings produced by an 8-finder maintainability review (2026-06-06), each verified by an independent skeptical pass. Four candidates were deliberately **excluded** as premature abstraction and are recorded under "Explicitly out of scope" below — do not resurrect them.

---

## Scope & Hard Constraints (read before touching anything)

This plan was written for an engineer with **zero prior context**. Honor these or you will break things:

1. **Markdown / docs are OUT OF SCOPE.** Do not edit any `.md` file as part of this work (including `scripts/CLAUDE.md`, `CLAUDE.md`, `docs/`). Stale doc mentions of deleted code are acceptable and tracked separately.
2. **Do NOT delete fact-store cutover machinery.** The fact-store production cutover has not happened. These are *pending use*, not dead — never delete them: `scripts/cutover-*.sh`, `scripts/rebuild*.{ts,sh}`, `scripts/migrate-to-fact-store.ts`, `scripts/verify-*.sh`, `scripts/fact-store-*.ts`, `scripts/cutover-probe.ts`, `src/lib/migrate-to-fact-store.ts`, `src/lib/rebuild-core*.ts`, `src/lib/facts-db.ts`. Tasks 11–12 only *de-duplicate within* some of these — never delete them.
3. **Line numbers are advisory.** They were captured on the `feat/fact-store` tree; you will work off `main`. **Anchor every edit on the named symbol via `git grep`, not the line number.** The compiler is the source of truth for whether you deleted the right thing.
4. **The `tsc --noEmit` gate is mandatory after every deletion.** Dead-code removal here is multi-file (a deletion in one file leaves dangling re-exports in a barrel). A clean `tsc` proves you caught them all.

### Commands used throughout

```bash
# Type-check the whole project (authoritative "did I break the build?" gate)
npx tsc -p tsconfig.json --noEmit

# Full compile (final gate; what package.json "build" runs)
npm run build

# Run a specific test file (Jest is the runner; there is no `npm test` script)
npx jest <path/to/file.test.ts>

# Confirm a symbol is gone everywhere
git grep -n '<SymbolName>' -- 'src/**' 'scripts/**'
```

### Branch setup (Task 0)

All target files exist on `main`, so this work is independent of the unmerged `feat/fact-store` branch.

```bash
git fetch origin
git worktree add -b chore/maintainability-cleanup .worktrees/maintainability-cleanup origin/main
cd .worktrees/maintainability-cleanup
cp templates/BRANCH-STATUS.md .  # per repo GitOps convention
npx tsc -p tsconfig.json --noEmit   # baseline: confirm a clean tree BEFORE any edits
npx jest                            # baseline: confirm green BEFORE any edits
```

Expected: baseline `tsc` and `jest` both pass. If they don't, stop — the tree is not clean and you cannot attribute later failures to your edits.

---

## PHASE A — Dead-code deletion (~1,247 lines, near-zero risk)

### Task 1: Delete the archived thread / chat-session / memory subsystems from `db.ts` (~455 lines)

**Why:** `src/lib/db.ts` is 709 lines; ~447 are exported functions/interfaces with **zero live callers** — leftovers from the Thread System, SeleneChat sessions/memories, and SeleneMobile device registration archived on 2026-03-21. Confirmed: `getActiveThreads`, `listSessions`, `getCrossThreadAssociations`, `registerDevice`, `getAllNotes`, `getNotesSince` are referenced only inside `db.ts` and the `index.ts` barrel.

**Files:**
- Modify: `src/lib/db.ts` (delete the dead spans)
- Modify: `src/lib/index.ts` (drop the now-dangling re-exports)
- Modify: `src/lib/strings.ts` (delete `normalizeThreadName`)

**Dead set to DELETE from `db.ts`:**
- Unused note helpers: `getAllNotes`, `getNoteById`, `getRecentNotes`, `getNotesSince` (note: `routes/notes.ts` has its OWN local `getNoteById` closure — that stays).
- Thread subsystem: `getThreadAssignmentsForNotes`; interfaces `Thread`, `ThreadTask`, `NoteWithProcessedData`; `getActiveThreads`, `getThreadById`, `searchThreadByName`, `getThreadNotes`, `getTasksForThread`.
- Chat/memory subsystem: interfaces `ChatSession`, `ConversationMessage`, `ConversationMemory`, `CrossThreadAssociation`; `listSessions`, `getSessionById`, `upsertSession`, `deleteSession`, `updateSessionPin`, `getSessionMessages`, `saveConversationMessage`, `listMemories`, `getMemoryById`, `createMemory`, `updateMemory`, `deleteMemory`, `touchMemories`, `getCrossThreadAssociations`.
- Device register: `registerDevice`, `unregisterDevice`.

**MUST KEEP (interleaved inside the dead spans — do not delete):**
- `searchNotesKeyword` (used by `src/agents/things-metadata-enricher.ts`)
- `ensureLegacyRawNotesColumns` + its self-call (covered by `db-legacy-columns.test.ts`)
- `getDeviceTokens` + the `device_tokens` CREATE TABLE (used by `src/lib/apns.ts`)
- `RawNote` type, and all the insert/pending/calendar capture helpers.

**Step 1 — Delete the dead functions/interfaces from `db.ts`.** Anchor each by name (`git grep -n '<name>' src/lib/db.ts`), delete the full function/interface body, leave the KEEP list intact.

**Step 2 — Fix `src/lib/index.ts` re-exports.** Drop the re-export entries for `getAllNotes`, `getNoteById`, `getRecentNotes`, `getNotesSince`, `getThreadAssignmentsForNotes`, `getActiveThreads`. Change the `Thread` type re-export line to **`export type { RawNote }`** — do NOT delete the whole line; `RawNote` is live core. Drop the `normalizeThreadName` re-export.

**Step 3 — Delete `normalizeThreadName` from `src/lib/strings.ts`** (10-line file; it belongs to the dead thread subsystem).

**Step 4 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit   # MUST pass — catches any missed re-export
git grep -n 'getActiveThreads\|listSessions\|getCrossThreadAssociations\|registerDevice\|getAllNotes\|getNotesSince' -- 'src/**' 'scripts/**'
# Expect: zero hits (or only the definitions you intend to keep — there should be none)
npx jest src/lib/db-capture.test.ts src/lib/db-pending.test.ts src/lib/db-legacy-columns.test.ts
# Expect: all pass (proves the kept helpers + capture core still work)
```

**Step 5 — Commit:**
```bash
git add src/lib/db.ts src/lib/index.ts src/lib/strings.ts
git commit -m "refactor(db): remove archived thread/chat/memory subsystems (dead since 2026-03-21)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**Caveat / follow-up (do NOT fold into this task):** `registerDevice`/`unregisterDevice` were the only writers to `device_tokens`, and no route invokes them — so the kept `getDeviceTokens` and the whole APNs push path are *effectively* dead too. That is a larger cluster deserving its own investigation later; leave it intact here.

---

### Task 2: Delete the dead `ContextBuilder` module (~320 lines)

**Why:** `ContextBuilder` + its types (`NoteContext`, `ThreadContext`, `FidelityTier`) are leftovers from the archived "Tiered Context Compression" feature. The only references are the class itself, one barrel line, and its own test.

**Files:**
- Delete: `src/lib/context-builder.ts` (138 lines)
- Delete: `src/lib/context-builder.test.ts` (181 lines)
- Modify: `src/lib/index.ts` (remove the single `ContextBuilder` re-export line)

**Step 1 — Delete both files.**
**Step 2 — Remove the `export { ContextBuilder, ... } from './context-builder';` line in `src/lib/index.ts`.** (The three `export *` wildcards cover other modules; leave them.)
**Step 3 — Verify:**
```bash
git grep -n 'ContextBuilder\|FidelityTier' -- 'src/**' 'scripts/**'   # expect zero
npx tsc -p tsconfig.json --noEmit                                      # expect pass
npx jest                                                               # expect green; no dangling glob
```
**Step 4 — Commit:**
```bash
git add -A src/lib/context-builder.ts src/lib/context-builder.test.ts src/lib/index.ts
git commit -m "refactor(lib): delete dead ContextBuilder (archived tiered-context feature)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Delete three self-referential orphan clusters (~127 lines)

**Why:** Three independent micro-clusters each exist only to reference themselves.
1. `src/lib/cosine.ts` `cosineSimilarity` — referenced only by its own test. Runtime similarity uses inline L2-to-cosine approximations (`process-llm.ts`, `routes/worksheets.ts`) and never imports it.
2. `src/types/agents.ts` — a pure type re-export barrel ("re-exported from the canonical source in lib/agent-db"); real consumers import directly from `lib/agent-db`. Its test asserts only `assert.ok(true)`.
3. `src/types/index.ts` `ExportableNote` + `ExportResult` interfaces — nothing imports them (`export-obsidian.ts` has its own *separate, differently-shaped* local `ExportableNote` — leave that one alone).

**Files:**
- Delete: `src/lib/cosine.ts`, `src/lib/cosine.test.ts`
- Modify: `jest.config.js` (remove the `**/src/lib/cosine.test.ts` glob entry — **easy to miss**; without it the runner points at a deleted path)
- Delete: `src/types/agents.ts`, `src/types/agents.test.ts`
- Modify: `src/types/index.ts` (remove `export * from './agents';`; delete the `ExportableNote` and `ExportResult` interfaces + the orphaned `// Obsidian export types` comment)

**Step 1 — Delete the four files and make the three edits above** (anchor by symbol/string, confirm `jest.config.js` no longer lists the cosine glob).
**Step 2 — Verify:**
```bash
git grep -n 'cosineSimilarity\|ExportResult' -- 'src/**' 'scripts/**'   # expect zero
git grep -n "types/agents'" -- 'src/**' 'scripts/**'                     # expect zero
npx tsc -p tsconfig.json --noEmit                                        # expect pass
npx jest                                                                 # expect green; no dangling glob
```
**Step 3 — Commit:**
```bash
git add -A
git commit -m "refactor: remove self-referential dead code (cosine, agents type barrel, export interfaces)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Delete bit-rotted scripts + dead `package.json` entries (~345 lines)

**Why:** Four unrelated dead-script removals, all from the 2026-03-21 simplification. None is fact-store machinery, so the pending-cutover protection does not apply.

**Files:**
- Delete: `scripts/hooks/post-commit`, `scripts/hooks/post-merge`, `scripts/hooks/post-rewrite`, `scripts/hooks/selenechat-auto-build.sh` (the post-* hooks are absent from `.git/hooks`, so none runs; all `cd` into a `SeleneChat/` dir that moved to a separate repo). **Leave `scripts/hooks/pre-commit` and `scripts/hooks/pre-push` — those are the live hooks.**
- Delete: `scripts/test-ingest.sh` (POSTs to a route that doesn't exist, reads a stale DB, references docker-compose + a missing `test-verify.sh`).
- Delete: `scripts/test-eink-ocr.ts` (a served-its-purpose OCR spike, superseded by `src/workflows/eink-ingest.ts`, zero callers).
- Modify: `package.json` — delete the 7 dead `scripts` entries: `mcp-wrapper`, `test-mcp`, `workflow:extract-tasks`, `workflow:index-vectors`, `workflow:compute-relationships`, and the two `echo 'DEPRECATED' && exit 1` stubs (`workflow:compute-embeddings`, `workflow:compute-associations`). **Surviving entries:** `start`, `dev`, `workflow:process-llm`, `workflow:daily-summary`, `build`, `build:check`.

**Step 1 — Verify the claims before deleting:**
```bash
ls -la .git/hooks/                 # confirm only pre-commit + pre-push are symlinked
ls -d SeleneChat 2>/dev/null || echo "SeleneChat absent (expected)"
git grep -n 'test-ingest\|test-eink-ocr\|things-mcp-wrapper\|extract-tasks\|index-vectors\|compute-relationships' -- 'src/**' 'scripts/**' launchd/ package.json
# Expect: hits only on the lines you are about to delete
```
**Step 2 — Delete the six files and edit `package.json`.** Keep surviving lines comma-valid.
**Step 3 — Verify:**
```bash
node -e 'require("./package.json")'   # JSON still parses
git grep -n 'test-ingest\|test-eink-ocr\|extract-tasks' -- 'src/**' 'scripts/**' package.json   # expect zero
git grep -n 'mcp-wrapper\|test-mcp\|things-mcp-wrapper' -- .mcp.json   # surface any stale MCP-config reference to the deleted scripts
```
**Step 4 — Commit:**
```bash
git add -A
git commit -m "chore: remove bit-rotted scripts + dead package.json entries (archived features)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## PHASE B — Drift fixes (glue/config out of sync with reality)

### Task 5: Rewrite `.env.example` — it documents the n8n/Docker stack removed in 2026-01-09 (~55 lines)

**Why:** `.env.example` (a config template, not markdown → in scope) still describes the long-removed n8n + docker-compose stack (`N8N_BASIC_AUTH_*`, `WEBHOOK_URL`, "run docker-compose up", "Import the workflow JSON files"). `git grep N8N_ src/` is empty. A contributor copying this configures the wrong system.

**Files:**
- Modify: `.env.example`

**Step 1 — Confirm what `config.ts` and the workflows actually read**, then rewrite `.env.example` to ~25–30 lines covering only those: `SELENE_ENV`, `SELENE_VAULT_PATH`, `OBSIDIAN_VAULT_PATH` (**keep — still read by `daily-summary.ts`**), `OLLAMA_BASE_URL`/`OLLAMA_MODEL`/`OLLAMA_EMBED_MODEL`, `APPLE_NOTES_DIGEST_ENABLED`, `TRMNL_WEBHOOK_URL`/`TRMNL_DIGEST_ENABLED`, `SELENE_WEBHOOK_URL`. Drop all `N8N_*`, the docker steps, and `SELENE_DATA_PATH`/`SELENE_TEST_DATA_PATH`/`OBSIDIAN_TEST_VAULT_PATH` (no longer read).
**Step 2 — Verify:**
```bash
git grep -n 'N8N_\|SELENE_DATA_PATH' -- 'src/**' 'scripts/**'   # confirm those are fiction
for v in SELENE_ENV SELENE_VAULT_PATH OBSIDIAN_VAULT_PATH OLLAMA_BASE_URL APPLE_NOTES_DIGEST_ENABLED TRMNL_WEBHOOK_URL SELENE_WEBHOOK_URL; do echo "$v:"; git grep -n "$v" -- src/lib/config.ts 'src/workflows/**'; done
# Each kept var should appear in config.ts or a workflow
```
No build/test gate — nothing imports `.env.example`.
**Step 3 — Commit:**
```bash
git add .env.example
git commit -m "docs(env): rewrite .env.example to match real config (drop dead n8n/docker vars)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Derive launchd install/uninstall agent lists from `launchd/` (fixes a latent install bug, ~14 lines)

**Why:** Two hand-maintained agent lists drifted from `launchd/` in opposite directions. `install-launchd.sh` hardcodes 10 agents and **omits `com.selene.folio-feedback`** (a real scheduled agent — install silently never loads it). `uninstall-launchd.sh` still names 6 labels archived on 2026-03-21 that no longer exist.

**Files:**
- Modify: `scripts/install-launchd.sh`
- Modify: `scripts/uninstall-launchd.sh`

**Step 1 — Replace each hardcoded list with a glob over `launchd/com.selene.*.plist`, guarded by a `case` that skips prod/dev agents.** The exclusion is **MANDATORY** — a bare glob would match `com.selene.prod.deploy-watcher.plist` (arming auto-deploy in a dev context — the exact un-migrated-prod landmine the cutover gate exists to prevent) and `com.selene.dev.server.plist` (port collision):
```bash
for f in launchd/com.selene.*.plist; do
  label="$(basename "$f" .plist)"
  case "$label" in com.selene.prod.*|com.selene.dev.*) continue;; esac
  # ... existing per-agent install/uninstall logic, using "$label" / "$f"
done
```
**Step 2 — Verify the glob resolves correctly:**
```bash
for f in launchd/com.selene.*.plist; do label="$(basename "$f" .plist)"; case "$label" in com.selene.prod.*|com.selene.dev.*) continue;; esac; echo "$label"; done
# Expect: com.selene.folio-feedback IS listed; com.selene.prod.* and com.selene.dev.* are NOT
bash -n scripts/install-launchd.sh && bash -n scripts/uninstall-launchd.sh   # syntax check
```
**Step 3 — Commit:**
```bash
git add scripts/install-launchd.sh scripts/uninstall-launchd.sh
git commit -m "fix(launchd): derive agent list from launchd/ (installs folio-feedback; drops 6 archived labels)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## PHASE C — Consolidations (low-risk, judgment-call refactors)

### Task 7: Collapse `config.ts`'s five copy-pasted env-aware path resolvers into one helper (~32 lines)

**Why:** `getDbPath`, `getFactsDbPath`, `getVectorsPath`, `getDigestsPath`, `getLogsPath` are the same 4-branch ladder (env var → test path → dev path → prod default) copy-pasted five times. This is semantically one thing.

**Files:**
- Modify: `src/lib/config.ts`

**Step 1 — Add one private `resolvePath(envVar, rel, prodAbs)` helper** implementing the test/dev/prod ladder; call it five times inline. **WATCH:** `getLogsPath`'s TEST branch returns `join(projectRoot, 'logs')` — identical to its prod default, **not** `data-test/logs`. A naive uniform `data-test/<rel>` helper would silently relocate test-run logs. Pass `getLogsPath` its real test value (or deliberately normalize it). Leave `resolveVaultPath` separate (it has the dev-leak guard).
**Step 2 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit
npx jest src/lib/config.test.ts    # pins factsDbPath ends in facts.db + shares dir with dbPath
```
Manually diff resolved values for prod / dev / test envs (especially the logs path) before committing.
**Step 3 — Commit:**
```bash
git add src/lib/config.ts
git commit -m "refactor(config): collapse 5 duplicated path resolvers into one resolvePath helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Extract `loadTodaysDigest()` in `send-digest.ts` (~14 lines)

**Why:** `sendDigestToFile()` re-implements the identical first half of `sendDigest()` — today/yesterday date math, digest path with yesterday fallback, two `existsSync` guards, `readFileSync`+trim, empty-message guard, `buildSynthesisSections(db)`. The two diverge only at the final delivery step. Drift risk if the fallback window or empty-guard changes in one copy only.

**Files:**
- Modify: `src/workflows/send-digest.ts`

**Step 1 — Extract a private `loadTodaysDigest(): { message; synthesis } | null`** that does the date/path/exists/read/empty/synthesis work once and returns `null` on any skip. Both callers then branch only on delivery (Apple Notes + TRMNL vs writing `sent/<today>-sent.txt`).
**Step 2 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit
npx jest src/workflows/send-digest.test.ts
```
Optionally run the CLI entry in test mode and confirm `sent/<today>-sent.txt` is unchanged.
**Step 3 — Commit:**
```bash
git add src/workflows/send-digest.ts
git commit -m "refactor(send-digest): extract loadTodaysDigest() to kill duplicated load block

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Extract `upsertAppleNote()` — two hand-rolled osascript blocks with duplicated escape logic (~10 lines net)

**Why:** `send-digest.ts` (`updateAppleNote`) and `agent-manager.ts` (`deliverToAppleNotes`) both escape a body for AppleScript and run the same find-or-create osascript scaffold. They share ~18 lines of fiddly backslash/quote/newline escaping that is dangerous to get subtly wrong in only one place. Divergences are parameterizable: one REPLACES the body, the other APPENDS with a `<br><hr><br>` separator.

**Files:**
- Create: `src/lib/apple-notes.ts` — `upsertAppleNote(noteName, body, opts?: { mode?: 'replace' | 'append' })` owning the escape + osascript scaffold once.
- Modify: `src/workflows/send-digest.ts` (call `mode: 'replace'`)
- Modify: `src/workflows/agent-manager.ts` (call `mode: 'append'`)

**Step 1 — Write the helper**, folding the stricter single-quote escape uniformly into both name and body (currently each escapes only one). The append separator lives in the `'append'` branch.
**Step 2 — Replace both call sites.**
**Step 3 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit
npx jest src/workflows/send-digest.test.ts
```
Manually run both paths against the Notes app (or dry-run the constructed osascript string) and confirm a note is created, then updated/appended, correctly.
**Step 4 — Commit:**
```bash
git add src/lib/apple-notes.ts src/workflows/send-digest.ts src/workflows/agent-manager.ts
git commit -m "refactor(apple-notes): extract upsertAppleNote() with unified escaping

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: À-la-carte micro-cleanups (~14 lines; each independently optional)

**Why:** Five tiny, individually-marginal but senior-mergeable tidy-ups. Apply or skip each independently; bundle into one commit.

**Files & edits:**
1. `src/routes/agents.ts` — `/agents/:name/enable` and `/disable` handlers are byte-identical except a boolean. Collapse to one `fastify.post('/agents/:name/:action', ...)` using `request.params.action === 'enable'`. (Sole caller `dashboard.ts` already builds the URL as `'/agents/'+name+'/'+(enabled?'enable':'disable')`.)
2. `src/routes/notes.ts` + `src/routes/worksheets.ts` — replace the repeated per-route `{ preHandler: requireAuth }` with one `fastify.addHook('preHandler', requireAuth)` per plugin. **Per-plugin only (Fastify encapsulation) — NOT global. `pkm.ts` keeps its separate LAN-IP guard.**
3. `src/routes/worksheets.ts` — replace the two single-column `SELECT`s against the same `raw_notes` row with one `SELECT content, created_at FROM raw_notes WHERE id = ?`.
4. `src/lib/pkm-db.ts` — replace the hand-inlined predicate with the canonical `baseNoteFilter('rn')` from `pkm-queries.ts`.
5. `scripts/selene-eink-ingest` + `scripts/selene-folio-feedback` — drop the redundant `cd` line (every calling plist sets `WorkingDirectory` to the repo root). *Optional — the `cd` is harmless belt-and-suspenders that also helps manual runs.*

**Step 1 — Apply whichever sub-items you choose.**
**Step 2 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit
npx jest src/routes/notes.test.ts src/routes/worksheets.test.ts src/lib/pkm-db.test.ts
git grep -n 'agents/.*enable' -- 'src/**'   # confirm dashboard.ts is the only caller
bash -n scripts/selene-eink-ingest scripts/selene-folio-feedback
```
**Step 3 — Commit:**
```bash
git add -A
git commit -m "refactor(routes): collapse duplicated enable/disable + per-plugin auth hook + minor tidy-ups

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: De-duplicate `db.ts` connection wiring + the triplicated `/tmp` safety guard (~29 lines)

**Why:** Two single-source-of-truth violations. (1) `open-selene-connection.ts` is the documented "ONE true way" to build a raw_notes-view-capable connection, but `db.ts` re-implements its exact 5-step sequence inline (so the load-bearing ATTACH-before-view-DDL order lives in two places). (2) The `/tmp`-isolation guard — the only thing stopping a probe from writing the REAL prod/dev DB — is copied byte-identically into all three fact-store probes.

**Files:**
- Modify: `src/lib/db.ts` (replace the inline 5-step block with `openSeleneConnection(...)`)
- Create: a tiny leaf module for the shared guard (see CRITICAL PLACEMENT below)
- Modify: `scripts/cutover-probe.ts`, `scripts/fact-store-insert-probe.ts`, `scripts/fact-store-concurrency-check.ts` (import the shared guard)

**Step 1 — (1)** After the existing `ensureMigrated` guard, replace the inline connection-build block with `export const db: DatabaseType = openSeleneConnection(config.dbPath, config.factsDbPath)` and remove the now-dead imports (the `Database` default + the `./db-config`/`./facts-db` symbols used only in the deleted block; **keep `DatabaseType`**). The env-verification block and `process`-exit close stay.

**Step 2 — (2)** Extract one `assertTmpIsolated(dbPath, factsPath)` and import it in all three probes. **CRITICAL PLACEMENT:** home it in a leaf module with **no transitive `db.ts` import** — `cutover-probe.ts` deliberately defers its `db.ts` import until *after* the guard runs. A safe home is `open-selene-connection.ts` (all three probes already import it; verify it pulls only `db-config` + `facts-db`, neither of which imports `db.ts`).

**Step 3 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit   # catches the dead-import removals — run full tsc, not just jest
npx jest src/lib/open-selene-connection.test.ts src/lib/facts-db.test.ts src/lib/db-capture.test.ts src/lib/db-pending.test.ts
# Run a probe with its DB path pointed OUTSIDE /tmp and confirm it still REFUSES:
SELENE_DB_PATH=/Users/$USER/tmp-not-slashtmp.db npx ts-node scripts/cutover-probe.ts   # expect: refuses
```
**Step 4 — Commit:**
```bash
git add -A
git commit -m "refactor(db): use openSeleneConnection for singleton + share assertTmpIsolated guard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**Caveat:** The three probes are pending-cutover scripts — this de-duplicates *within* them, it does **not** delete them.

---

### Task 12: Extract `redirectSeleneSingleton()` test helper (~38 lines)

**Why:** Five Jest files that import `src/lib/db` (which opens its module singleton on import) each contain the SAME ~12–14 line block: snapshot the three env vars, force `SELENE_ENV='production'`, point `SELENE_DB_PATH`/`SELENE_FACTS_DB_PATH` at a throwaway temp dir *before* the import, restore env in `afterAll`. Byte-identical except the mkdtemp prefix. Bonus: 3 of the 5 never `rmSync` their temp dir — a leak a shared `restore()` fixes uniformly.

**Files:**
- Modify: `src/lib/test-two-file-db.ts` — add an exported `redirectSeleneSingleton(prefix): { dir; restore }` (this file is already in prod `tsc` scope and is **not** a `.test.ts`, so it survives the test exclude; `makeTwoFileTestDb` already lives here as precedent).
- Modify: `src/lib/db-capture.test.ts`, `src/lib/db-pending.test.ts`, `src/lib/db-legacy-columns.test.ts`, `scripts/migrate-to-fact-store.test.ts`, `scripts/backfill-categories.test.ts` (replace each ~14-line block with 2–3 lines).

**Step 1 — Write the helper:** snapshot `ENV_KEYS`, set `SELENE_ENV='production'`, `mkdtemp`, set both DB paths, return `restore()` that resets env + `rmSync`s the dir.
**Step 2 — Replace the block in each of the five test files.** **Do NOT** fold in `view-mode-readers.test.ts` or `routes/worksheets.test.ts` — those only override `SELENE_ENV` and never set the facts DB path (a genuinely different, smaller case).
**Step 3 — Verify:**
```bash
npx tsc -p tsconfig.json --noEmit
npx jest src/lib/db-capture.test.ts src/lib/db-pending.test.ts src/lib/db-legacy-columns.test.ts scripts/migrate-to-fact-store.test.ts scripts/backfill-categories.test.ts
```
**Step 4 — Commit:**
```bash
git add -A
git commit -m "test: extract redirectSeleneSingleton() helper (dedupes env-redirect + fixes temp-dir leak)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

**Caveat:** `migrate-to-fact-store.test.ts` and `backfill-categories.test.ts` are pending-cutover test files — this de-duplicates *within* them, it does **not** delete them.

---

## Final Task: Full-suite verification & wrap-up

**Step 1 — Full build + full test run:**
```bash
npm run build          # rm -rf dist && tsc -p tsconfig.json — must succeed
npx jest               # entire suite green
git grep -n 'ContextBuilder\|cosineSimilarity\|getActiveThreads\|listSessions\|N8N_' -- 'src/**' 'scripts/**'   # expect zero
```
**Step 2 — Sanity-run one real workflow** to confirm the runtime still boots (uses a `test_run` marker per repo rules; clean up after):
```bash
SELENE_ENV=development npx ts-node src/workflows/process-llm.ts   # or another touched workflow
```
**Step 3 — Confirm the diff is deletion-dominated:**
```bash
git diff --stat origin/main...HEAD   # expect ~1,400+ lines removed, few added
```
**Step 4 — Open the PR** (do not merge onto `feat/fact-store`):
```bash
git push -u origin chore/maintainability-cleanup
gh pr create --base main --title "chore: maintainability cleanup (~1.4k dead/duplicated lines removed)" --body "Removes dead subsystems archived 2026-03-21, fixes config/launchd drift, and consolidates duplicated helpers. See docs/plans/2026-06-06-maintainability-cleanup.md. No behavior change; fact-store cutover machinery untouched."
```

---

## Explicitly out of scope (excluded by the review — do NOT add these)

These four were flagged by a finder but **rejected** on verification as premature abstraction or net-negative. Resurrecting them would make the codebase worse:

- **Centralizing the per-workflow `try { db.exec('ALTER TABLE … ADD COLUMN') } catch {}` idiom.** This is an *intentional, documented* "the producer of the data owns its columns" design (see the comment in `distill-essences.ts`). Centralizing it increases coupling and re-introduces the migration-ordering bug it was written to fix.
- **Consolidating the prod-deploy shell scripts** (`deploy-prod.sh`/`rollback-prod.sh`/etc.). Net-zero-to-negative lines, and would land "standalone" helpers inside `scripts/lib/prod-agents.sh` whose documented contract is the opposite; risks a real `--label-prefix` regression.
- **Unifying the dev-DB-path resolution across shell scripts.** ~0 net lines; the `verify-*`/`cutover-*` harnesses are deliberately self-contained so they don't share failure modes with what they verify.
- **Markdown verbosity** (`scripts/CLAUDE.md` at 838 lines, stale n8n mentions in docs). Out of scope by user instruction; tracked separately.

## Appendix: leverage ranking

| Rank | Task | Category | Est. lines removed | Effort | Risk |
|------|------|----------|-------------------:|--------|------|
| 1 | db.ts dead subsystems | dead-code | 455 | low | low |
| 2 | ContextBuilder module | dead-code | 320 | low | low |
| 3 | self-referential orphans | dead-code | 127 | low | low |
| 4 | bit-rotted scripts + package.json | dead-code | 345 | low | low |
| 5 | .env.example rewrite | drift | 55 | low | low |
| 6 | launchd install/uninstall lists | drift | 14 | low | low |
| 7 | config.ts resolvePath | duplication | 32 | low | low |
| 8 | send-digest loadTodaysDigest | duplication | 14 | low | low |
| 9 | upsertAppleNote | consolidation | 10 | low | low |
| 10 | route/glue micro-cleanups | consolidation | 14 | low | low |
| 11 | db.ts connection + /tmp guard dedup | consolidation | 29 | low | low |
| 12 | redirectSeleneSingleton test helper | duplication | 38 | low | low |
| | **Total** | | **~1,453** | | |
