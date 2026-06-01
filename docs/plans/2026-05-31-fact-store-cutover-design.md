# Fact Store — Prod Cutover Runbook Design

**Status:** Ready
**Created:** 2026-05-31
**Updated:** 2026-05-31

> Companion to [2026-05-31-fact-store-design.md](2026-05-31-fact-store-design.md). The fact-store Phase 1 split is implemented + e2e-validated on `feat/fact-store` but **not merged**, because moving it to prod safely needs a deliberate cutover. This doc designs that cutover.

---

## Problem

The fact-store split changes prod's DB layout (single-file → `facts.db` + `selene.db`, `raw_notes` becomes a per-connection temp view). But the prod release path can't carry that change:

- **`deploy-prod.sh` is code-only.** It build-gates, archives the old `dist/`, `rsync`s only `dist/`, `npm install`s, and `launchctl kickstart -k`s the `com.selene.prod.*` agents. It never touches the prod DB or runs a migration.
- **Merging to `main` auto-deploys** (the `com.selene.prod.deploy-watcher` reacts to the `origin/main` sha). So a plain merge ships the new code onto the **un-migrated** prod DB.
- **The failure mode is silent incoherence, not a crash.** New code on an un-migrated DB: `ensureRawNotesView` no-ops on the physical `raw_notes`, so the server runs with captures going to `facts.captured_notes` while reads still hit the old physical table. Data silently splits.

So we need a **one-time, controlled cutover** of an irreplaceable ~294-note prod DB, with backup, verification, and rollback — not an uncontrolled auto-deploy.

---

## Solution

**Hybrid** (operator-chosen): a self-healing guard in the code for lasting robustness, plus a controlled one-shot orchestrator for the irreplaceable one-time event.

**Piece A — `ensure-migrated` guard at `db.ts` startup.** On startup, detect an un-migrated DB (physical `raw_notes` + no `facts.db`/`captured_notes`) and branch on environment:
- **dev / test / fresh clone → auto-migrate** (self-heal; future clones, dev resets, and disaster-restores fix themselves).
- **production → do NOT auto-migrate; FAIL LOUD** — throw and refuse to serve ("prod DB not migrated — run cutover-prod.sh"). This *enforces* the controlled path: prod can never silently auto-migrate or run in the incoherent split state. The `KeepAlive` server crashlooping + a `selene_notify` is the loud signal.

**Piece B — `scripts/cutover-prod.sh`.** One orchestrated, operator-run script (Claude writes it; Claude never runs it against prod — the prod-data guard blocks that by design) that does pre-flight → pause watcher → stop agents → verified backup → migrate → **Gate 1** → deploy → restart → **Gate 2** → resume watcher, with **auto-rollback** on either gate.

---

## Design

### Inherent constraint: a brief downtime window

Old code can't run on a *migrated* DB (it reads `raw_notes`, which the migration renames away); new code can't safely run on an *un-migrated* DB (silent split). So there is an unavoidable swap window where the `com.selene.prod.*` agents are stopped — minutes, not hours. Webhook captures arriving during it are dropped (server off), so pre-flight tells the operator to pick a quiet moment.

### Version consistency

`cutover-prod.sh` runs from `~/selene` checked out to the **target sha** (the fact-store commit, or `main` after merge), so the migration script (`migrate-to-fact-store.ts`) and the deployed `dist/` are the same code version.

### The sequence

```
PRE-FLIGHT  (no changes yet — abort cleanly on any failure)
  0a. Build-gate the target sha (npm run build && build:check)   → proven deployable before touching prod
  0b. Ollama reachable
  0c. Prod DB is actually un-migrated (raw_notes physical, no raw_notes_legacy_backup) — else "already done", exit 0
  0d. Disk headroom for facts.db + a full DB backup
  0e. Record current .deployed-sha → OLD_SHA; capture pre-migration raw_notes/processed/cluster counts

PAUSE AUTOMATION
  1. bootout com.selene.prod.deploy-watcher   → cannot auto-deploy mid-cutover

╔═ PROD DOWNTIME BEGINS ═══════════════════════════════════════╗
  2. Stop all com.selene.prod.* agents (server + workflows)     → DB quiesced
  3. BACKUP + VERIFY: cp selene.db → backups/pre-cutover-<sha>-<ts>.db; open it read-only and confirm
     its raw_notes count == live count BEFORE proceeding (an unverified backup is not a rollback target)
  4. MIGRATE: migrate-to-fact-store.ts on the prod DB (id-preserving, transactional, crash-atomic, FK-safe)

  ┌─ GATE 1: verify migration (content-free, via selene-inspect) ──────────────┐
  │  rawNotes(view) == pre-count · processedNotes & clusters preserved ·       │
  │  raw_notes_legacy_backup present w/ matching count · facts.db + captured_  │
  │  notes count match · PRAGMA foreign_key_check empty ·                      │
  │  capture→pending smoke: insert one test_run-marked probe via insertNote,    │
  │  confirm status='pending' through the view, then DELETE it                 │
  │  ANY fail → AUTO-ROLLBACK ↓                                                │
  └────────────────────────────────────────────────────────────────────────────┘

  5. DEPLOY: deploy-prod.sh --ref <sha>   (build-gate already green; ships dist/ + npm install)
  6. RESTART com.selene.prod.* agents     → new code on migrated DB; ensure-migrated guard sees "done"
╚═ PROD DOWNTIME ENDS ═════════════════════════════════════════╝

  ┌─ GATE 2: verify live ──────────────────────────────────────────────────────┐
  │  /health 200 · insert a test_run probe, confirm the RUNNING server sees it │
  │  pending, delete it · selene-inspect coverage sane · logs free of SQLITE/  │
  │  FK errors                                                                 │
  │  ANY fail → AUTO-ROLLBACK ↓                                                │
  └────────────────────────────────────────────────────────────────────────────┘

RESUME AUTOMATION
  7. Re-enable com.selene.prod.deploy-watcher (confirm .deployed-sha == target so it won't re-deploy)
  8. selene_notify "cutover complete"

AUTO-ROLLBACK (triggered by GATE 1 or GATE 2):
  stop agents → restore the verified pre-cutover backup over selene.db → rm facts.db
  → confirm raw_notes is again a physical table w/ expected count → rollback-prod.sh OLD_SHA
  → restart agents → re-enable watcher → selene_notify "cutover ROLLED BACK". Prod is back to single-file.
```

### Backup & rollback

- **Verified backup** (step 3): `~/selene-data/backups/pre-cutover-<sha>-<ts>.db`, integrity-checked (row-count match) before the migration runs. Keep the last 5, prune older. Time Machine (hourly) is the secondary net; this is the instant one.
- **Why a full backup when the migration is technically reversible** (`legacy_backup`→`raw_notes`): defense in depth — the rename-back is clean only if the migration committed cleanly; a verified whole-file copy is the unambiguous restore for any failure mode.
- **Rollback returns prod to byte-for-byte single-file:** restore backup, remove `facts.db`, roll the code back via `rollback-prod.sh`, restart, re-enable watcher.

### Verification is content-free by construction

Every check is counts + structure + a self-cleaning `test_run`-marked probe — no note text is read, so the prod-data guard stays satisfied and the operator (not Claude) runs it. Probes are inserted and deleted in the same gate (no test data left in prod, per the project's testing rules).

---

## Implementation Notes

### Affected files
- **`src/lib/db.ts`** — add the `ensureMigrated()` guard at startup (after the connection/attach wiring, before serving): un-migrated detection + env branch (dev auto-migrate via the existing `migrateToFactStore`; prod throw-loud). Must not fire in test env (test DBs are fresh/two-file already). Import `migrateToFactStore` from the migration module (it's pure — no db-singleton cycle).
- **`scripts/cutover-prod.sh`** — new orchestrator. Reuses `deploy-prod.sh` (deploy), `rollback-prod.sh` (code rollback), `migrate-to-fact-store.ts` (migration), `selene-inspect.ts` (content-free gates), and `selene_notify` (notifications). Sources the same agent-label prefix logic `deploy-prod.sh` uses to stop/restart `com.selene.prod.*`.
- **`scripts/migrate-to-fact-store.ts`** — already built (id-preserving, transactional, crash-atomic, FK-safe, idempotent). No change expected; the cutover calls it.
- **Guide:** add `docs/guides/features/releases.md` cutover section (operator-facing) on wrap-up.

### Boundaries / safety
- **Claude never runs the cutover against prod** — the prod-data guard blocks `~/selene-data` access from Claude's tools by design. Claude authors + unit-tests the script; the operator runs it. This is a feature, not a limitation: it forces every check content-free.
- The `ensure-migrated` guard's prod fail-loud is a *safety net*, not the primary path — the cutover migrates manually before deploying, so the new code always starts on an already-migrated prod DB.

### Testing
- `ensureMigrated()` unit-tested with the existing two-file test harness: (a) dev/test env + un-migrated DB → migrates; (b) "production" env + un-migrated DB → throws the loud error; (c) already-migrated DB (any env) → no-op fast path.
- `cutover-prod.sh` validated against a **/tmp copy of the dev DB** end-to-end (the same isolation `verify-fact-store.sh` uses): full happy path + a forced Gate-1 failure exercising auto-rollback (restore + code-rollback) → prod-copy returns to single-file. Never against real prod.

---

## Ready for Implementation Checklist

- [x] **Acceptance criteria defined** — below
- [x] **ADHD check passed** — below
- [x] **Scope check** — guard + one orchestrator script + tests; < 1 week
- [x] **No blockers** — depends only on the already-built migration; deploy/rollback scripts exist

### Acceptance Criteria
- [ ] `ensureMigrated()`: dev+un-migrated → auto-migrates; prod+un-migrated → throws loud + refuses to serve; already-migrated → fast no-op. Unit-tested; does not fire in test env.
- [ ] `cutover-prod.sh` runs the full sequence on a **/tmp copy of the dev DB** and leaves it migrated + coherent (fresh capture reads pending; counts preserved).
- [ ] A forced Gate-1 failure triggers auto-rollback that returns the prod-copy to byte-for-byte single-file (raw_notes physical, no facts.db, old counts).
- [ ] Pre-flight aborts cleanly (no changes) on: dirty build, already-migrated DB, missing disk, Ollama down.
- [ ] The watcher is paused for the whole window and re-enabled at the end with `.deployed-sha` matching (no immediate re-deploy).
- [ ] All gate checks are content-free (counts/structure/self-deleted probe); no note text read; probes cleaned up.

### ADHD Design Check
- [x] **Reduces friction?** One supervised command instead of a multi-step hand-followed checklist where a step can be missed; auto-rollback removes the "did I break prod?" dread.
- [x] **Visible?** Each step + gate prints PASS/FAIL; a notification on complete/rolled-back; nothing happens silently.
- [x] **Externalizes cognition?** The script (not the operator) remembers the order, the backup, the verification, and the rollback.

---

## Links
- **Branch:** `feat/fact-store` (cutover lands here, alongside Phase 1)
- **Companion:** [2026-05-31-fact-store-design.md](2026-05-31-fact-store-design.md) · [2026-05-31-fact-store-plan.md](2026-05-31-fact-store-plan.md)
- **Reuses:** `scripts/deploy-prod.sh`, `scripts/rollback-prod.sh`, `scripts/migrate-to-fact-store.ts`, `scripts/selene-inspect.ts`
