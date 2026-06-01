# Fact-store Phase 2 — `rebuild` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a `rebuild` command that truncates the disposable `selene.db`, re-derives the whole corpus from the precious `facts.db` through Obsidian export, validates the result, and auto-rolls-back on failure — safe to run on dev daily and on prod as a gated operator maintenance op.

**Architecture:** Approach B — a typed, jest-tested TS core (`scripts/rebuild.ts` + pure helpers in `src/lib/rebuild-core.ts`) owns all logic; bash is confined to `launchctl` agent control via a shared `scripts/lib/prod-agents.sh` extracted from `cutover-prod.sh`. The wipe is a **truncate** (DELETE FROM each main-schema table), not a file delete — verified necessary because `processed_notes`/`note_embeddings` have no runtime `CREATE TABLE IF NOT EXISTS`. On prod the webhook server stays UP (capture writes only `facts.db`); only derivation agents stop, restarted via an EXIT trap.

**Tech Stack:** TypeScript + better-sqlite3, ts-node, jest, bash (launchctl orchestration). Design doc: `docs/plans/2026-06-01-fact-store-rebuild-design.md`.

**Conventions to follow (verified against the codebase):**
- Connections OUTSIDE `db.ts` use `openSeleneConnection(dbPath, factsPath, opts?)` from `src/lib/open-selene-connection.ts` (ATTACHes facts, builds the `raw_notes` temp view, applies WAL + busy_timeout). NEVER import the `db.ts` module singleton in `rebuild.ts` (it has open-on-import side effects).
- Pure logic → `*.test.ts` with `:memory:` / `mkdtempSync` DBs (see `src/lib/constellation.db.test.ts` for the in-memory seed pattern). DB-touching → `*.db.test.ts`.
- Workflow invocation mirrors `scripts/dev-process-batch.sh`: `SELENE_ENV=<env> npx ts-node src/workflows/<wf>.ts`, drain-loop the two LLM stages, run synthesize + export once.
- Backup verify + prune pattern: copy from `cutover-prod.sh` `backup_and_verify` (verify row count, keep newest 5).
- Bash safety: restore/teardown paths start with `set +e`; the prod wrapper restarts agents via an `EXIT` trap, never a linear tail.
- Config: `config.dbPath`, `config.factsDbPath`, `config.env` from `src/lib/config.ts`.

---

## Task 1: Extract `scripts/lib/prod-agents.sh` (shared agent control)

**Files:**
- Create: `scripts/lib/prod-agents.sh`
- Modify: `scripts/cutover-prod.sh` (replace inline `prod_agents`/`pause_watcher`/`resume_watcher`/`stop_agents`/`restart_agents` with a `source`)
- Regression: `scripts/verify-cutover.sh`

**Step 1: Create the shared lib.** Move these functions verbatim from `cutover-prod.sh` into `scripts/lib/prod-agents.sh` (a sourceable file, no `set -e`, no `main`): `prod_agents`, `pause_watcher`, `resume_watcher`, `stop_agents`, `restart_agents`. They reference `run_or_echo` (DRY_RUN stub) and color vars — keep using the caller's; document at the top of the file that the sourcing script must define `run_or_echo` (and `info`) before sourcing, exactly as cutover already does.

Add TWO new functions:

```bash
# Derivation agents only: every prod agent EXCEPT the webhook server and the
# deploy-watcher. Rebuild stops these (so none races the drain) while the SERVER
# stays up — capture writes only facts.db, which rebuild never touches.
stop_derivation_agents() {
  local a
  for a in $(prod_agents | grep -v '\.server$'); do
    run_or_echo launchctl bootout "gui/$(id -u)/$a" || true
  done
}

# Restart the derivation agents after a rebuild. Iterate installed plist FILES
# (post-bootout `launchctl list` is empty), EXCLUDING the watcher (resume_watcher
# owns it) and the server (never stopped → avoid double-bootstrap). Mirrors
# restart_agents but with the extra server exclusion.
restart_derivation_agents() {
  local plist base
  for plist in "$HOME/Library/LaunchAgents/com.selene.prod."*.plist; do
    [ -e "$plist" ] || continue
    base="$(basename "$plist")"
    case "$base" in
      *deploy-watcher.plist) continue ;;
      *server.plist) continue ;;
    esac
    run_or_echo launchctl bootstrap "gui/$(id -u)" "$plist" || true
  done
}
```

**Step 2: Re-point cutover.** In `cutover-prod.sh`, delete the now-moved function bodies and add, after `run_or_echo`/`info` are defined: `source "$(dirname "$0")/lib/prod-agents.sh"`. Cutover keeps calling `stop_agents` (stop-ALL) — its semantics are unchanged.

**Step 3: Run the regression.** Run: `DRY_RUN=1 ./scripts/verify-cutover.sh` (or its dry-run entry). Expected: **45/45 PASS**, identical to before — proving the extraction is behavior-preserving.

**Step 4: Commit.**
```bash
git add scripts/lib/prod-agents.sh scripts/cutover-prod.sh
git commit -m "refactor(ops): extract shared prod-agents.sh from cutover-prod.sh + add derivation-only agent control"
```

---

## Task 2: `rebuild-core.ts` — `listDerivedTables()` (the truncate target list)

**Files:**
- Create: `src/lib/rebuild-core.ts`
- Test: `src/lib/rebuild-core.db.test.ts`

**Step 1: Write the failing test.**
```ts
import Database from 'better-sqlite3';
import { listDerivedTables } from './rebuild-core';
type DB = InstanceType<typeof Database>;

it('lists only main-schema user tables, excluding sqlite_* and views', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE processed_notes (id INTEGER PRIMARY KEY);
    CREATE TABLE note_embeddings (raw_note_id INTEGER);
    CREATE VIEW v AS SELECT 1;
  `);
  expect(listDerivedTables(db).sort()).toEqual(['note_embeddings', 'processed_notes']);
});
```

**Step 2: Run to verify it fails.** Run: `npx jest src/lib/rebuild-core.db.test.ts -t listDerivedTables` → FAIL (module/function not found).

**Step 3: Implement.**
```ts
import type Database from 'better-sqlite3';
type DB = InstanceType<typeof Database>;

/** Tables in the `main` schema (selene.db) only — NOT the attached `facts` schema,
 *  NOT views (raw_notes), NOT sqlite internal tables. These are what wipe() truncates. */
export function listDerivedTables(db: DB): string[] {
  return (db.prepare(
    `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`
  ).all() as Array<{ name: string }>).map((r) => r.name);
}
```
> Note: `sqlite_master` (unqualified) reads the `main` schema only, so attached `facts.*` tables are never returned — `captured_notes`/`review_state` can't be truncated by accident.

**Step 4: Run to verify it passes.** Expected: PASS.

**Step 5: Commit.**
```bash
git add src/lib/rebuild-core.ts src/lib/rebuild-core.db.test.ts
git commit -m "feat(rebuild): listDerivedTables — main-schema truncate target list"
```

---

## Task 3: `rebuild-core.ts` — `snapshot()` (PRE/POST counts)

**Files:** Modify `src/lib/rebuild-core.ts`; extend `src/lib/rebuild-core.db.test.ts`.

**Step 1: Write the failing test.** Seed a tiny two-table DB + the `raw_notes`-view-backed counts. Use a real `openSeleneConnection` only in the verify harness; for the unit test, seed plain tables matching the count queries:
```ts
import { snapshot } from './rebuild-core';

it('counts captured + each derived metric', () => {
  const db: DB = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes_t (id INTEGER PRIMARY KEY);          -- stand-in for the view
    CREATE VIEW raw_notes AS SELECT id, 1 AS exported_to_obsidian FROM raw_notes_t;
    CREATE TABLE processed_notes (raw_note_id INTEGER, essence TEXT);
    CREATE TABLE note_embeddings (raw_note_id INTEGER);
    CREATE TABLE topic_clusters (id TEXT PRIMARY KEY);
    CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER);
  `);
  db.exec(`INSERT INTO raw_notes_t VALUES (1),(2),(3)`);
  db.exec(`INSERT INTO processed_notes VALUES (1,'e'),(2,NULL)`);
  db.exec(`INSERT INTO note_embeddings VALUES (1)`);
  db.exec(`INSERT INTO topic_clusters VALUES ('c1')`);
  db.exec(`INSERT INTO topic_note_links VALUES ('c1',1)`);
  expect(snapshot(db)).toEqual({
    captured: 3, processed: 2, essences: 1, embeddings: 1,
    clusters: 1, clusterLinks: 1, exported: 3,
  });
});
```

**Step 2: Run → FAIL.**

**Step 3: Implement.**
```ts
export interface Snapshot {
  captured: number; processed: number; essences: number; embeddings: number;
  clusters: number; clusterLinks: number; exported: number;
}
const count = (db: DB, sql: string): number =>
  (db.prepare(sql).get() as { n: number }).n;

/** Read derived counts from selene.db (facts via the raw_notes view). Content-free. */
export function snapshot(db: DB): Snapshot {
  return {
    captured: count(db, `SELECT COUNT(*) n FROM raw_notes`),
    processed: count(db, `SELECT COUNT(*) n FROM processed_notes`),
    essences: count(db, `SELECT COUNT(*) n FROM processed_notes WHERE essence IS NOT NULL`),
    embeddings: count(db, `SELECT COUNT(*) n FROM note_embeddings`),
    clusters: count(db, `SELECT COUNT(*) n FROM topic_clusters`),
    clusterLinks: count(db, `SELECT COUNT(*) n FROM topic_note_links`),
    exported: count(db, `SELECT COUNT(*) n FROM raw_notes WHERE exported_to_obsidian = 1`),
  };
}
```

**Step 4: Run → PASS.**

**Step 5: Commit.** `git commit -am "feat(rebuild): snapshot() derived-count reader"`

---

## Task 4: `rebuild-core.ts` — `verdict()` (the validation gate)

**Files:** Modify `src/lib/rebuild-core.ts`; add `src/lib/rebuild-core.test.ts` (pure, no DB).

**Step 1: Write the failing tests (truth table).**
```ts
import { verdict } from './rebuild-core';
const base = { captured: 100, processed: 100, essences: 100, embeddings: 100, clusters: 8, clusterLinks: 160, exported: 100 };
const T = { coverageMin: 0.95, driftTolerance: 0.20 };

it('passes a healthy rebuild', () => {
  expect(verdict(base, { ...base }, T).pass).toBe(true);
});
it('fails on coverage below floor', () => {
  const v = verdict(base, { ...base, processed: 90 }, T); // 0.90 < 0.95
  expect(v.pass).toBe(false);
  expect(v.reasons.join(' ')).toMatch(/coverage/i);
});
it('fails when a metric collapses past drift tolerance', () => {
  const v = verdict(base, { ...base, clusters: 6 }, T); // -25% < -20%
  expect(v.pass).toBe(false);
  expect(v.reasons.join(' ')).toMatch(/clusters/i);
});
it('allows upward drift (more clusters is fine)', () => {
  expect(verdict(base, { ...base, clusters: 20 }, T).pass).toBe(true);
});
it('skips drift on a zero baseline (fresh DB), coverage still applies', () => {
  const pre = { ...base, captured: 0, processed: 0, essences: 0, embeddings: 0, clusters: 0, clusterLinks: 0, exported: 0 };
  const post = { ...pre, captured: 10, processed: 10, essences: 10, embeddings: 10, clusters: 3, clusterLinks: 12, exported: 10 };
  expect(verdict(pre, post, T).pass).toBe(true);
});
```

**Step 2: Run → FAIL.**

**Step 3: Implement.**
```ts
export interface Thresholds { coverageMin: number; driftTolerance: number; }
export interface Verdict { pass: boolean; coverage: number; reasons: string[]; }

const DRIFT_METRICS: Array<keyof Snapshot> = [
  'processed', 'essences', 'embeddings', 'clusters', 'clusterLinks', 'exported',
];

export function verdict(pre: Snapshot, post: Snapshot, t: Thresholds): Verdict {
  const reasons: string[] = [];
  const coverage = post.captured === 0 ? 1 : post.processed / post.captured;
  if (coverage < t.coverageMin) {
    reasons.push(`coverage ${(coverage * 100).toFixed(1)}% < floor ${(t.coverageMin * 100).toFixed(0)}%`);
  }
  for (const m of DRIFT_METRICS) {
    if (pre[m] === 0) continue;                       // zero baseline → skip (can't drop below nothing)
    const drift = (post[m] - pre[m]) / pre[m];
    if (drift < -t.driftTolerance) {
      reasons.push(`${m} drift ${(drift * 100).toFixed(1)}% < -${(t.driftTolerance * 100).toFixed(0)}%`);
    }
  }
  return { pass: reasons.length === 0, coverage, reasons };
}

/** Thresholds from env, with the agreed defaults. */
export function thresholdsFromEnv(env = process.env): Thresholds {
  return {
    coverageMin: env.COVERAGE_MIN ? Number(env.COVERAGE_MIN) : 0.95,
    driftTolerance: env.DRIFT_TOLERANCE ? Number(env.DRIFT_TOLERANCE) : 0.20,
  };
}
```

**Step 4: Run → PASS** (add a `thresholdsFromEnv` test: unset → 0.95/0.20; `COVERAGE_MIN=0.8` → 0.8).

**Step 5: Commit.** `git commit -am "feat(rebuild): verdict() gate — coverage floor + bounded drift, env-overridable"`

---

## Task 5: `rebuild-core.ts` — `backupPath()` + `wipe()` truncation (DB-touching)

**Files:** Modify `src/lib/rebuild-core.ts`; extend `src/lib/rebuild-core.db.test.ts`.

**Step 1: Write the failing tests.**
```ts
import { backupPath, wipe, listDerivedTables } from './rebuild-core';

it('backupPath names a timestamped file under the backup dir', () => {
  expect(backupPath('/b', '20260601-120000')).toBe('/b/pre-rebuild-20260601-120000.db');
});

it('wipe empties every main-schema table but leaves attached facts untouched', () => {
  const db: DB = new Database(':memory:');
  db.exec(`ATTACH ':memory:' AS facts;
    CREATE TABLE facts.captured_notes (id INTEGER PRIMARY KEY);
    INSERT INTO facts.captured_notes VALUES (1),(2);
    CREATE TABLE processed_notes (raw_note_id INTEGER);
    INSERT INTO processed_notes VALUES (1),(2),(3);`);
  wipe(db);
  expect(listDerivedTables(db)).toContain('processed_notes');           // table still exists
  expect((db.prepare('SELECT COUNT(*) n FROM processed_notes').get() as any).n).toBe(0); // emptied
  expect((db.prepare('SELECT COUNT(*) n FROM facts.captured_notes').get() as any).n).toBe(2); // untouched
});
```

**Step 2: Run → FAIL.**

**Step 3: Implement.**
```ts
import { join } from 'path';

export function backupPath(dir: string, stamp: string): string {
  return join(dir, `pre-rebuild-${stamp}.db`);
}

/** Empty every main-schema (selene.db) table in one transaction. FK-safe via
 *  defer: disable FK enforcement for the truncation, re-enable after. Never
 *  touches the attached `facts` schema (captured_notes / review_state). */
export function wipe(db: DB): void {
  const tables = listDerivedTables(db);
  db.pragma('foreign_keys = OFF');
  const tx = db.transaction(() => {
    for (const name of tables) db.exec(`DELETE FROM "${name}"`);
  });
  tx();
  db.pragma('foreign_keys = ON');
}
```

**Step 4: Run → PASS.**

**Step 5: Commit.** `git commit -am "feat(rebuild): backupPath + wipe() truncation (facts schema untouched)"`

---

## Task 6: `scripts/rebuild.ts` — the orchestrator

**Files:**
- Create: `scripts/rebuild.ts`
- (Behavior covered end-to-end by `verify-rebuild.sh` in Task 8; the pure pieces it calls are already unit-tested in Tasks 2–5.)

**Step 1: Implement the orchestrator** (uses `openSeleneConnection`, never the `db.ts` singleton):

```ts
/**
 * rebuild — wipe selene.db, re-derive the whole corpus from facts.db, validate,
 * keep-or-rollback. Dev runs this directly; rebuild-prod.sh wraps it for prod.
 * Content-free (counts only). Flags: --dry-run, --json.
 */
import { execFileSync } from 'child_process';
import { copyFileSync, readdirSync, unlinkSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { config } from '../src/lib/config';
import { openSeleneConnection } from '../src/lib/open-selene-connection';
import { snapshot, wipe, verdict, thresholdsFromEnv, backupPath, type Snapshot } from '../src/lib/rebuild-core';
import { logger } from '../src/lib/logger';

const DRY = process.argv.includes('--dry-run');
const JSON_OUT = process.argv.includes('--json');
const BACKUP_DIR = process.env.BACKUP_DIR ?? join(dirname(config.dbPath), 'backups');
const STAMP = process.env.REBUILD_STAMP ?? new Date().toISOString().replace(/[-:T]/g, '').slice(0, 15); // harness can pin

function readSnapshot(): Snapshot {
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { readonly: true, fileMustExist: true });
  try { return snapshot(db); } finally { db.close(); }
}

function backup(): string {
  mkdirSync(BACKUP_DIR, { recursive: true });
  const dest = backupPath(BACKUP_DIR, STAMP);
  if (!DRY) copyFileSync(config.dbPath, dest);
  // verify: backup row count == live (open the copy, count captured via its own facts attach is N/A;
  // count a main-schema table instead — processed_notes — to prove a faithful copy)
  return dest;
}

function doWipe(): void {
  if (DRY) { logger.info('[dry-run] would truncate derived tables'); return; }
  const db = openSeleneConnection(config.dbPath, config.factsDbPath, { fileMustExist: true });
  try { wipe(db); } finally { db.close(); }
}

function rederive(): void {
  const run = (wf: string) => {
    if (DRY) { logger.info(`[dry-run] would run ${wf}`); return; }
    execFileSync('npx', ['ts-node', `src/workflows/${wf}.ts`], {
      stdio: 'inherit', env: { ...process.env, SELENE_ENV: config.env },
    });
  };
  const pending = () => {
    const db = openSeleneConnection(config.dbPath, config.factsDbPath, { readonly: true });
    try { return (db.prepare(`SELECT COUNT(*) n FROM raw_notes WHERE status='pending'`).get() as any).n as number; }
    finally { db.close(); }
  };
  // Drain the two per-batch LLM stages until no progress, then run synth + export once.
  let last = -1;
  for (let i = 0; i < 1000; i++) {              // generous cap; matches dev-process-batch drain
    if (!DRY && pending() === 0) break;
    run('process-llm');
    run('distill-essences');
    if (DRY) break;
    const now = pending();
    if (now === last) break;                    // no-progress guard
    last = now;
  }
  run('synthesize-topics');
  run('export-obsidian');
}

function restore(backupFile: string): void {
  if (DRY) { logger.warn('[dry-run] would restore backup'); return; }
  copyFileSync(backupFile, config.dbPath);
}

function pruneBackups(): void {
  const files = readdirSync(BACKUP_DIR).filter((f) => f.startsWith('pre-rebuild-')).sort();
  for (const f of files.slice(0, Math.max(0, files.length - 5))) unlinkSync(join(BACKUP_DIR, f));
}

function main(): void {
  const t = thresholdsFromEnv();
  const pre = readSnapshot();
  logger.info({ pre }, 'rebuild: PRE snapshot');
  const backupFile = backup();

  // Simulated-failure hooks (rollback proof in tests).
  if (process.env.SIMULATE_REDERIVE_FAIL === '1') throw new Error('SIMULATE_REDERIVE_FAIL');

  doWipe();
  rederive();

  let post = readSnapshot();
  if (process.env.SIMULATE_COVERAGE_FAIL === '1') post = { ...post, processed: 0 };
  if (process.env.SIMULATE_DRIFT_FAIL === '1') post = { ...post, clusters: 0 };

  const v = verdict(pre, post, t);
  const report = { pre, post, coverage: v.coverage, pass: v.pass, reasons: v.reasons, backup: backupFile };
  if (JSON_OUT) process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  else logger.info(report, v.pass ? 'rebuild: PASS — keeping' : 'rebuild: FAIL — rolling back');

  if (!v.pass) { restore(backupFile); process.exit(1); }
  pruneBackups();
}

try { main(); }
catch (err) {
  // A throw before/after wipe: if a backup exists, restore to be safe.
  logger.error({ err }, 'rebuild: aborted');
  process.exit(1);
}
```
> The `try/catch` restore-on-throw: refine so it only restores when the wipe has already happened (track a `wiped` boolean) — restoring before any wipe is a harmless no-op copy but skip it for clarity. Keep `STAMP` env-pinnable so `verify-rebuild.sh` can assert exact backup filenames.

**Step 2: Smoke it in dry-run.** Run: `SELENE_ENV=development npx ts-node scripts/rebuild.ts --dry-run --json`. Expected: prints a PRE snapshot + a simulated report, touches nothing.

**Step 3: Commit.** `git commit -am "feat(rebuild): rebuild.ts orchestrator (snapshot/backup/wipe/rederive/validate/rollback)"`

---

## Task 7: `scripts/rebuild-prod.sh` — thin prod wrapper + EXIT trap

**Files:** Create `scripts/rebuild-prod.sh`.

**Step 1: Implement.**
```bash
#!/usr/bin/env bash
# rebuild-prod.sh — operator-run prod rebuild. Keeps the webhook server UP;
# stops only derivation agents; restarts them + resumes the watcher via an EXIT
# trap so any exit (incl. crash) restores prod. Claude NEVER runs this vs prod.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN="${DRY_RUN:-}"
run_or_echo() { if [ -n "$DRY_RUN" ]; then echo "  [dry] $*"; else "$@"; fi; }
info() { echo "[..] $*"; }
source "$REPO_ROOT/scripts/lib/prod-agents.sh"

restored=0
cleanup() {                       # runs on ANY exit (set +e so the whole tail runs)
  set +e
  [ "$restored" = 1 ] && return
  restored=1
  info "restoring prod: restart derivation agents + resume watcher"
  restart_derivation_agents
  resume_watcher
}
trap cleanup EXIT

info "pausing watcher + stopping derivation agents (server stays up)"
pause_watcher
stop_derivation_agents

info "running rebuild (SELENE_ENV=production)"
SELENE_ENV=production npx ts-node "$REPO_ROOT/scripts/rebuild.ts" "$@"
# trap cleanup runs here on success AND on failure/crash.
```

**Step 2: Dry-run smoke.** Run: `DRY_RUN=1 ./scripts/rebuild-prod.sh --dry-run`. Expected: prints pause/stop, the rebuild dry-run, then restart/resume via the trap — no real launchctl calls.

**Step 3: Commit.** `git commit -m "feat(rebuild): rebuild-prod.sh wrapper — server-up, derivation-only stop, EXIT-trap restore"`

---

## Task 8: `scripts/verify-rebuild.sh` — end-to-end rehearsal harness

**Files:** Create `scripts/verify-rebuild.sh`. Model on `scripts/verify-cutover.sh`.

**What it does** (all against a `/tmp` two-file DB seeded from a dev `.backup` — NEVER prod):
1. **Seed:** `cp` dev `selene.db`+`facts.db` to a `mktemp -d`. **If the snapshot is still legacy single-file** (`sqlite_master` shows a physical `raw_notes` table), run `npx ts-node scripts/migrate-to-fact-store.ts <tmp>/selene.db <tmp>/facts.db` first (mirrors `reset-dev-data.sh`). Point `SELENE_DB_PATH`/`SELENE_FACTS_DB_PATH` (or the dev env vars `config.ts` reads) at the tmp copies.
2. **Scenario A — happy path:** run `rebuild.ts` (real Ollama drain on the small seeded corpus). Assert exit 0, verdict PASS, every captured note has a `processed_notes` row (coverage ≥ floor), `facts.db` byte-identical before/after (`shasum`), a `pre-rebuild-*.db` backup exists.
3. **Scenario B — coverage-fail rollback:** run with `SIMULATE_COVERAGE_FAIL=1`. Assert exit 1, and `selene.db` restored to the PRE snapshot (processed count == PRE).
4. **Scenario C — drift-fail rollback:** `SIMULATE_DRIFT_FAIL=1` → exit 1, restored.
5. **Scenario D — crash-resume:** `SIMULATE_REDERIVE_FAIL=1` (throws after wipe is reached only if you order it post-wipe; otherwise assert the catch restores). Then run a plain `process-llm` and confirm pending notes get processed (self-heal property).
6. **Scenario E — facts untouched on every path** (shasum `facts.db` pre/post for each scenario).

Print a `PASS/FAIL` tally like `verify-cutover.sh`. Keep every assertion content-free (counts, hashes — never note text).

**Step 1: Write the harness.** **Step 2: Run it.** Run: `./scripts/verify-rebuild.sh`. Expected: all scenarios PASS. **Step 3: Commit.** `git commit -m "test(rebuild): verify-rebuild.sh e2e harness (happy + both rollbacks + crash-resume + facts-untouched)"`

---

## Task 9: Operator guide — `docs/guides/features/releases.md`

**Files:** Modify `docs/guides/features/releases.md`.

**Step 1: Add a "Rebuilding the derived database (`rebuild`)" section** after the cutover runbook. Cover, verifying each claim against the code just written: when to use it (prompt/model upgrade, recovery, experimentation), dev usage (`SELENE_ENV=development npx ts-node scripts/rebuild.ts`), prod usage (`./scripts/rebuild-prod.sh` — server stays up, only derivation agents pause), the validation gate (95%/20%, env-overridable), what auto-rollback does, and the known limitation (truncate recovers data, not structural schema corruption). Note Claude never runs it against prod.

**Step 2: Verify no other guide claim is now stale** (the `releases.md` "what auto-deploys" section is unaffected — rebuild is manual). **Step 3: Commit.** `git commit -m "docs(releases): document the rebuild command (operator guide)"`

---

## Task 10: Full verification gate

**Step 1:** `npx tsc --noEmit` → clean.
**Step 2:** `npx jest` → full suite green (includes new `rebuild-core.*` tests).
**Step 3:** `DRY_RUN=1 ./scripts/verify-cutover.sh` → **45/45** (proves the `prod-agents.sh` extraction didn't regress cutover).
**Step 4:** `./scripts/verify-rebuild.sh` → all scenarios PASS.
**Step 5:** Update `docs/plans/INDEX.md`: move this design from **Ready** toward **In Progress/Done** per the GitOps stage reached. Commit.

---

## Notes for the executor
- **Never import `src/lib/db.ts`** from `rebuild.ts` — it opens the singleton with side effects on import. Use `openSeleneConnection` exclusively.
- **Content-free always:** every probe is a COUNT or a file hash. Mirrors the `selene-inspect`/`cutover-probe` discipline so the prod-data guard is satisfied by construction.
- **Claude builds + /tmp-tests this; the operator runs `rebuild-prod.sh` against prod.** Do not run the prod wrapper against the real prod data dir.
- **DRY:** reuse `prod-agents.sh`, `openSeleneConnection`, the `dev-process-batch` invocation pattern, and `cutover-prod.sh`'s backup/verify idiom rather than re-implementing.
