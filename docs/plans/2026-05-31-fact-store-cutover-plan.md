# Fact Store — Prod Cutover Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the fact-store split safe to take to prod: a self-healing `ensureMigrated` startup guard (dev auto-migrates / prod fails loud) plus a gated, auto-rollback `cutover-prod.sh` an operator runs once.

**Architecture:** A pure `ensureMigrated(dbPath, factsPath, env)` runs at the very top of `db.ts` — before the long-lived connection opens — detecting an un-migrated DB (a physical `raw_notes` table) and either auto-migrating (dev/clone) or throwing loud (prod). `cutover-prod.sh` orchestrates the one-time prod event: pre-flight → pause watcher → stop agents → verified backup → migrate → Gate 1 → deploy → restart → Gate 2 → resume, with auto-rollback to byte-for-byte single-file on either gate. Its DB-surgery core is parameterized by paths so it's validated against a `/tmp` copy of the dev DB; Claude never runs it against prod (the prod-data guard enforces this).

**Tech Stack:** TypeScript, better-sqlite3, Jest, ts-node, bash, launchd (`launchctl`).

**Scope:** Companion to [2026-05-31-fact-store-cutover-design.md](2026-05-31-fact-store-cutover-design.md). Lands on `feat/fact-store` alongside Phase 1. Depends only on the already-built `scripts/migrate-to-fact-store.ts`, `deploy-prod.sh`, `rollback-prod.sh`, `selene-inspect.ts`.

---

## Pre-flight (read before Task 1)

- **Branch:** `feat/fact-store` (already has Phase 1 + the migration). Do NOT switch branches.
- **Never touch real DBs.** Tests use temp DBs; the cutover validation uses a `/tmp` copy of the dev DB. The prod-data guard blocks `~/selene-data` from Claude.
- **Verified facts:**
  - `migrateToFactStore(dbPath: string, factsPath: string): { notes; reviewRows; alreadyMigrated }` — self-contained, opens its own connections, transactional/idempotent/FK-safe. (`scripts/migrate-to-fact-store.ts:255`)
  - `db.ts:15` is `export const db = new Database(config.dbPath)` — the long-lived connection. The guard must run BEFORE it.
  - `config` exposes `env` ('test'|'development'|'production'), `isTestEnv`, `isDevEnv`, `dbPath`, `factsDbPath`.
  - **"un-migrated" detection:** `main.sqlite_master` has a table named `raw_notes`. New code never creates a physical `raw_notes` (it's a temp view), so a physical `raw_notes` table can ONLY be a legacy single-file DB. A fresh/empty DB has no `raw_notes` table → not un-migrated. After migration, `raw_notes_legacy_backup` exists and `raw_notes` is a temp view (not in `main.sqlite_master`).

---

## Task 1: `ensureMigrated()` guard (pure, env-parameterized)

**Files:**
- Create: `src/lib/ensure-migrated.ts`
- Test: `src/lib/ensure-migrated.test.ts`

**Step 1 — Write the failing test** (env passed explicitly so it's deterministic; uses real temp files):
```ts
import Database from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { ensureMigrated } from './ensure-migrated';
import { makeTwoFileTestDb } from './test-two-file-db';

function legacyDb(dir: string): string {
  const p = join(dir, 'selene.db');
  const db = new Database(p);
  db.exec(`CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
            content_hash TEXT NOT NULL, created_at DATETIME NOT NULL, status TEXT, inbox_status TEXT);`);
  db.prepare(`INSERT INTO raw_notes (id,title,content,content_hash,created_at,status)
              VALUES (1,'t','c','h',datetime('now'),'processed')`).run();
  db.close();
  return p;
}

describe('ensureMigrated', () => {
  it('development + un-migrated → migrates (raw_notes table becomes captured_notes + legacy_backup)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'em-dev-'));
    const dbPath = legacyDb(dir); const factsPath = join(dir, 'facts.db');
    ensureMigrated(dbPath, factsPath, 'development');
    const facts = new Database(factsPath);
    expect((facts.prepare(`SELECT COUNT(*) c FROM captured_notes`).get() as { c: number }).c).toBe(1);
    facts.close();
    const main = new Database(dbPath);
    expect(main.prepare(`SELECT name FROM sqlite_master WHERE name='raw_notes_legacy_backup'`).get()).toBeTruthy();
    main.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('production + un-migrated → throws loud and does NOT migrate', () => {
    const dir = mkdtempSync(join(tmpdir(), 'em-prod-'));
    const dbPath = legacyDb(dir); const factsPath = join(dir, 'facts.db');
    expect(() => ensureMigrated(dbPath, factsPath, 'production')).toThrow(/not migrated|cutover/i);
    expect(existsSync(factsPath)).toBe(false);              // nothing migrated
    const main = new Database(dbPath);
    expect((main.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes'`).get() as { type: string }).type).toBe('table');
    main.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('test env + un-migrated → skips (no migrate, no throw)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'em-test-'));
    const dbPath = legacyDb(dir); const factsPath = join(dir, 'facts.db');
    expect(() => ensureMigrated(dbPath, factsPath, 'test')).not.toThrow();
    expect(existsSync(factsPath)).toBe(false);
    rmSync(dir, { recursive: true, force: true });
  });

  it('already two-file (no physical raw_notes) → no-op in any env', () => {
    const two = makeTwoFileTestDb(); const dbPath = two.db.name; two.db.close();
    // makeTwoFileTestDb left a selene.db with no physical raw_notes (temp view only)
    expect(() => ensureMigrated(dbPath, join(two.dir, 'facts.db'), 'production')).not.toThrow();
    rmSync(two.dir, { recursive: true, force: true });
  });
});
```

**Step 2 — Run, expect FAIL** (`npx jest src/lib/ensure-migrated.test.ts`; register in `jest.config.js` testMatch alphabetically first). Module missing.

**Step 3 — Implement `src/lib/ensure-migrated.ts`:**
```ts
import Database from 'better-sqlite3';
import { migrateToFactStore } from '../../scripts/migrate-to-fact-store';
import { logger } from './logger';

/** Detect a legacy single-file DB (physical raw_notes table) and either auto-migrate (dev/clone)
 *  or fail loud (prod). Runs BEFORE db.ts opens its long-lived connection, so the migration's
 *  journal-mode change has no competing open handle. No-op once two-file. */
export function ensureMigrated(dbPath: string, factsPath: string, env: string): void {
  const probe = new Database(dbPath, { fileMustExist: false });
  let unmigrated = false;
  try {
    const row = probe.prepare(
      `SELECT type FROM sqlite_master WHERE name = 'raw_notes'`
    ).get() as { type: string } | undefined;
    unmigrated = row?.type === 'table'; // a physical raw_notes table == legacy single-file
  } finally {
    probe.close();
  }
  if (!unmigrated) return;                          // fresh or already two-file → nothing to do

  if (env === 'test') return;                       // tests manage their own DBs; never auto-migrate
  if (env === 'production') {
    throw new Error(
      `Prod DB at ${dbPath} is not migrated to the fact-store layout. ` +
      `Run scripts/cutover-prod.sh — refusing to serve in the incoherent split state.`
    );
  }
  // development / clone → self-heal
  logger.warn({ dbPath, factsPath }, 'Un-migrated DB detected — auto-migrating to fact-store layout');
  const r = migrateToFactStore(dbPath, factsPath);
  logger.info({ moved: r.notes, reviewRows: r.reviewRows }, 'Auto-migration complete');
}
```
(If importing from `../../scripts/...` trips tsc rootDir, instead move the migration's core into `src/lib/migrate-to-fact-store.ts` and have the script re-export — note which you did. Keep it a pure import; do NOT import `./db`.)

**Step 4 — Run, expect PASS** (4 tests).

**Step 5 — `npx tsc --noEmit` clean; commit:**
```bash
git add src/lib/ensure-migrated.ts src/lib/ensure-migrated.test.ts jest.config.js
git commit -m "feat(fact-store): ensureMigrated guard — dev auto-migrates, prod fails loud"
```

---

## Task 2: Wire `ensureMigrated` into `db.ts` startup

**Files:** Modify `src/lib/db.ts` (before line 15). Test: `src/lib/db-guard.test.ts`.

**Step 1 — Failing test:** spin a legacy temp DB, set env so config resolves it, import a small wrapper that calls `ensureMigrated(config.dbPath, config.factsDbPath, config.env)` — assert dev migrates / prod throws. (Simplest: test `ensureMigrated` is invoked with config values via a tiny exported `runStartupMigrationGuard()` in db.ts that you can call in isolation; OR assert behaviorally that importing db.ts under test env against a legacy DB does not throw and does not migrate.) Prefer the explicit `runStartupMigrationGuard()` export for testability.

**Step 2-4 — Implement:** add near the top of `db.ts`, BEFORE `export const db = new Database(config.dbPath)`:
```ts
import { ensureMigrated } from './ensure-migrated';
// Self-heal dev / fail-loud prod BEFORE opening the long-lived connection.
ensureMigrated(config.dbPath, config.factsDbPath, config.env);
```
Run the FULL suite (`npx jest`) — existing tests run under test env → `ensureMigrated` skips; two-file fixtures have no physical `raw_notes` → no-op. Expect 0 failures. `tsc` clean.

**Step 5 — Commit.**

---

## Task 3: `cutover-prod.sh` — DB-surgery core (pre-flight → backup → migrate → Gate 1 → rollback)

**Files:** Create `scripts/cutover-prod.sh` (this task: the path-parameterized, `/tmp`-testable core; Task 4 adds agent/deploy orchestration).

Design the script to honor overrides so it can run against a copy without touching prod:
- `SELENE_DB_PATH` (default `~/selene-data/selene.db`), `SELENE_FACTS_DB_PATH` (default `~/selene-data/facts.db`), `BACKUP_DIR` (default `~/selene-data/backups`), `--dry-run` (skip launchctl/deploy in Task 4), `--simulate-gate1-fail` (force the Gate-1 abort path, for testing rollback).

**Implement these functions (bash), each echoing PASS/FAIL:**
```bash
preflight() {
  # 0c: abort if already migrated (raw_notes is not a physical table) -> exit 0 "already done"
  # 0d: df check BACKUP_DIR has room for 2x the DB size
  # 0e: capture PRE_RAW=$(selene-inspect counts -> raw_notes), PRE_PROC, PRE_CLUSTERS  (content-free)
}
backup_and_verify() {            # step 3
  mkdir -p "$BACKUP_DIR"
  BACKUP="$BACKUP_DIR/pre-cutover-$(git rev-parse --short HEAD)-$(/bin/date +%Y%m%d-%H%M%S).db"
  cp "$SELENE_DB_PATH" "$BACKUP"
  # verify: open BACKUP read-only, raw_notes count == live raw_notes count, else ABORT (no migration yet)
  prune_backups   # keep newest 5
}
migrate() {                       # step 4
  SELENE_DB_PATH="$SELENE_DB_PATH" SELENE_FACTS_DB_PATH="$SELENE_FACTS_DB_PATH" \
    npx ts-node scripts/migrate-to-fact-store.ts
}
gate1() {                         # content-free, via selene-inspect + a self-deleted probe
  # rawNotes(view)==PRE_RAW; processedNotes==PRE_PROC; raw_notes_legacy_backup count==PRE_RAW;
  # facts.db exists & captured_notes==PRE_RAW; PRAGMA foreign_key_check empty;
  # probe: insert a test_run='cutover-probe' note via a tiny ts-node snippet using insertNote,
  #        assert it reads status='pending' through the view, then DELETE WHERE test_run='cutover-probe'
  # [ -n "$SIMULATE_GATE1_FAIL" ] && return 1
}
rollback_db() {                   # used by auto-rollback
  cp "$BACKUP" "$SELENE_DB_PATH"; rm -f "$SELENE_FACTS_DB_PATH"
  # confirm raw_notes is again a physical table with PRE_RAW rows, else SHOUT (manual recovery)
}
```
**Test (`scripts/cutover-core.test.ts` or a bash harness `scripts/cutover-core-check.sh`):** against a `/tmp` copy of the dev DB, run `preflight && backup_and_verify && migrate && gate1` → assert migrated + Gate-1 PASS + backup exists & verified. Then a second run with `--simulate-gate1-fail` → assert `rollback_db` returns the copy to a physical `raw_notes` with the original count and no facts.db. (Prefer a small bash test harness that sources the functions; keep assertions explicit.)

**Commit.**

---

## Task 4: `cutover-prod.sh` — orchestration (watcher, agents, deploy, Gate 2, resume, auto-rollback wiring)

**Files:** Modify `scripts/cutover-prod.sh`.

Add the thin orchestration around the Task-3 core, reusing existing scripts. Under `--dry-run` these print intended actions instead of executing (so the full flow is exercisable on a copy):
```bash
pause_watcher()  { launchctl bootout "gui/$(id -u)/com.selene.prod.deploy-watcher" 2>/dev/null || true; }
stop_agents()    { for a in $(prod_agents); do launchctl bootout "gui/$(id -u)/$a" 2>/dev/null || true; done; }
deploy()         { ./scripts/deploy-prod.sh --ref "$TARGET_SHA"; }
restart_agents() { for a in $(prod_agents); do launchctl kickstart -k "gui/$(id -u)/$a"; done; }
gate2()          { curl -fsS localhost:5678/health >/dev/null && live_probe_pending_then_delete && inspect_sane; }
resume_watcher() { launchctl bootstrap "gui/$(id -u)" launchd/com.selene.prod.deploy-watcher.plist; }
rollback_all()   { stop_agents; rollback_db; ./scripts/rollback-prod.sh "$OLD_SHA"; restart_agents; resume_watcher; selene_notify "Selene cutover ROLLED BACK" "..."; }
```
`prod_agents` mirrors `deploy-prod.sh`'s discovery (`launchctl list | awk '{print $3}' | grep '^com.selene.prod' | grep -v deploy-watcher`). Source `deploy-prod.sh`'s `selene_notify`. Build-gate (0a) reuses `npm run build && npm run build:check`.

`main()` wires the full sequence with the two gates calling `rollback_all` on failure:
```bash
preflight || exit 1
pause_watcher
stop_agents
backup_and_verify || { resume_watcher; restart_agents; exit 1; }   # pre-migration abort: nothing changed
migrate
gate1 || { rollback_all; exit 1; }
deploy
restart_agents
gate2 || { rollback_all; exit 1; }
resume_watcher
selene_notify "Selene cutover complete" "fact-store live on $TARGET_SHA"
```

**Commit.**

---

## Task 5: Validate `cutover-prod.sh` end-to-end on a `/tmp` dev copy

**Files:** `scripts/verify-cutover.sh` (mirrors `verify-fact-store.sh`'s isolation).

Run `cutover-prod.sh --dry-run` (launchctl/deploy stubbed) with `SELENE_DB_PATH`/`SELENE_FACTS_DB_PATH`/`BACKUP_DIR` pointed at a `/tmp` copy of `~/selene-data-dev/selene.db` (read via `.backup` snapshot), `SELENE_VAULT_PATH=/tmp/...`:
1. **Happy path:** full sequence → copy ends migrated (raw_notes view, facts.db present, counts preserved), backup exists & verified, Gate 1 + Gate 2 PASS.
2. **Forced Gate-1 failure** (`--simulate-gate1-fail`): assert `rollback_all` returns the copy to byte-for-byte single-file (physical `raw_notes`, original count, no facts.db) and reports ROLLED BACK.
Confirm the real dev DB + iCloud vault are never written. `tsc` clean; full `npx jest` 0 failures. **Commit.**

---

## Task 6: Operator guide

**Files:** Modify `docs/guides/features/releases.md` (add a "Fact-store cutover" section: when to run, the one command, what each gate means, how to read a rollback, where backups live). Update the hub link if needed. **Commit.**

---

## Definition of Done
- `ensureMigrated`: dev auto-migrates, prod throws loud, test skips, two-file no-ops — unit-tested; full suite green; `tsc` clean.
- `cutover-prod.sh` validated on a `/tmp` dev copy: happy path leaves it coherent; forced Gate-1 failure auto-rolls-back to byte-for-byte single-file.
- Pre-flight aborts cleanly on dirty build / already-migrated / no disk / Ollama down.
- All gate checks content-free; probes `test_run`-marked + deleted.
- Guide written. **Claude never ran any of it against prod.**

## Risks / watch-items
- **Import path for `migrateToFactStore` — CONFIRMED required relocate.** `tsconfig.json` has `rootDir: "./src"` + `include: ["src/**/*"]`, so a `src/` file CANNOT import from `scripts/` (won't compile). Task 1 step 0 therefore MOVES the migration core (`migrateToFactStore`, `stripRawNotesFk`, schema/column constants) into `src/lib/migrate-to-fact-store.ts`; `scripts/migrate-to-fact-store.ts` becomes a thin CLI wrapper (`import { migrateToFactStore } from '../src/lib/migrate-to-fact-store'` + `main()`); the existing migration test repoints its import to `src/lib/`. Then `ensure-migrated.ts` imports from `./migrate-to-fact-store` (same dir). Keep it a pure import (never `./db`).
- **`ensureMigrated` must run before the long-lived `db` connection** — opening the connection first risks a lock during the migration's `journal_mode=DELETE`.
- **`--dry-run` must NOT stub the DB surgery** (backup/migrate/Gate1/rollback run for real against the copy) — only launchctl/deploy are stubbed, or the validation proves nothing.
- The cutover touches prod agents + the real DB; it is operator-run only. Claude authors + `/tmp`-tests it exclusively.
