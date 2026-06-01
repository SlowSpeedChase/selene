# Fact-store Phase 2 — the `rebuild` command

**Date:** 2026-06-01
**Status:** Ready
**Topic:** architecture, data-integrity, regeneration, sqlite, ops
**Branch:** `feat/fact-store`
**Parent design:** [2026-05-31-fact-store-design.md](2026-05-31-fact-store-design.md) (Phase 1 — the split, ✅ DONE + LIVE in prod 2026-06-01)
**Sibling:** [2026-05-31-fact-store-cutover-design.md](2026-05-31-fact-store-cutover-design.md) (the one-time migration; rebuild reuses its prod-orchestration muscle)

---

## Problem

Phase 1 split the single DB into a **precious** `facts.db` (`captured_notes` + `review_state`, Time-Machine-backed) and a **disposable** `selene.db` (everything LLM/derived). The split made `selene.db` *rebuildable in principle* — but there is no command to actually do it.

Without `rebuild`:
- **Reprocess-on-upgrade is manual and scary.** Improving a prompt or swapping the Ollama model can't be applied to the existing corpus without hand-running four workflows and hoping nothing half-finishes.
- **Disaster recovery is unproven.** "`selene.db` is disposable" is only true if there's a tested path that re-derives it from facts.
- **Experimentation carries a fear tax.** Trying pipeline changes on dev means worrying about leaving the DB in a weird state.

The Phase 1 design sketched Phase 2's acceptance criteria; this doc promotes that sketch to a full, approved design.

---

## Goals & non-goals

**Goals** (all three drivers weighted equally — see brainstorm):
- One robust, **whole-corpus** `rebuild` primitive: wipe `selene.db`, re-derive everything from `facts.db`, end-to-end **through Obsidian/vault export** so what the user sees reflects the rebuild.
- **Dev-first, prod-capable:** the everyday tool on dev (no ceremony); a deliberate, gated maintenance op on prod (operator-run).
- **Safe by construction:** backup before the destructive wipe, a validation gate, and **auto-rollback** to the pre-rebuild `selene.db` on failure.

**Non-goals (deferred to Phase 3 or out of scope):**
- `category_overrides` — the human-correction *feature* (no override data, route, or UI exists today). In Phase 2 the "human layer" is just `review_state`, which survives automatically (it lives in `facts.db`, never wiped).
- Partial / per-stage / per-note rebuilds — whole-corpus only. The "re-run just synthesize/export" case is already a direct, idempotent workflow run today.
- A launchd schedule — `rebuild` is a deliberate manual op, never automated.

---

## Architecture (Approach B — TS core + thin bash for prod-only orchestration)

All decision logic lives in typed, unit-tested TS. Bash is confined to what only bash does well: `launchctl` agent control on the prod path.

```
scripts/rebuild.ts            the brain — dev runs this directly
  1. snapshot()   read selene.db: pre-rebuild derived counts  → PRE
  2. backup()     cp selene.db → BACKUP_DIR/pre-rebuild-<ts>.db ; verify the copy
  3. wipe()       TRUNCATE every main-schema table in selene.db (DELETE FROM each, in a txn,
                  FK-safe) via a short-lived connection — NOT a file delete. facts.db (ATTACHed,
                  separate schema namespace) is never touched. Emptying note_state makes every
                  fact read "pending" (derivation-absence) → re-derivation is automatic.
  4. rederive()   drain the pipeline: process-llm (loop) → distill-essences (loop)
                  → synthesize-topics (once) → export-obsidian (once)
  5. validate()   read selene.db → POST ; verdict(PRE, POST, thresholds)
        ├─ PASS → prune old backups (keep newest N) ; print verdict
        └─ FAIL → rollback(): restore backup over selene.db → reopen

src/lib/rebuild-core.ts       pure, unit-tested: snapshot reader, verdict(), backup-path naming,
                              the truncate table-list query (main schema only, sqlite_% excluded)
scripts/rebuild-prod.sh       thin wrapper: source prod-agents.sh → stop DERIVATION agents only
                              (server stays UP) → rebuild.ts → restart derivation agents → resume watcher.
                              An EXIT trap restarts agents + resumes the watcher on ANY exit (incl. crash).
scripts/lib/prod-agents.sh    NEW shared lib EXTRACTED from cutover-prod.sh: pause_watcher /
                              resume_watcher / restart_agents + a NEW granular stop_derivation_agents
                              (all com.selene.prod.* EXCEPT the webhook server + the watcher).
                              cutover keeps using stop-ALL; rebuild uses the derivation-only subset.
```

### Why `wipe()` truncates instead of deleting the file (resolved feasibility finding)

The original sketch said "rm `selene.db` → reopen → db.ts recreates the schema." **Empirically false:** `processed_notes` and `note_embeddings` have **no runtime `CREATE TABLE IF NOT EXISTS`** anywhere in `src/` — their DDL lives only in `create-dev-db.sh` and `migrate-to-fact-store.ts`. `db.ts` on open ensures only `note_state` (`db.ts:38`); the synthesis tables self-create when `synthesize-topics` runs. A file-delete + reopen would come back **missing `processed_notes`/`note_embeddings`**, crashing `process-llm`'s first INSERT.

Truncating (DELETE FROM each existing main-schema table, enumerated from `sqlite_master`) avoids this entirely — the tables already exist, we just empty them — and additive schema evolution stays covered by the existing `ensure*`/ALTER-add-column guards on open/run. It also has two free wins: (a) **no file unlink**, so a live webhook-server handle on `selene.db` stays valid → the server can stay UP during rebuild; (b) no singleton-handle hazard (nothing is `rm`'d out from under an open connection). `ensureMigrated` is safe across this — it only fails loud on a *physical `raw_notes` table*, which truncation never creates.

> Known limitation: truncate preserves the existing schema, so it does **not** recover from structural schema *corruption* (vs. data loss/staleness, which it fully handles). The verified backup + a manual `create-dev-db`/cutover rebuild covers that rare nuclear case.

This is the same TS-core / thin-bash seam the cutover landed on (`ensure-migrated.ts` guard + `cutover-prod.sh`). Rebuild inherits the cutover's *tested* prod muscle — verified backup, agent pause, `DRY_RUN` stubbing — instead of growing a parallel one.

### The two seams

1. **Driving the pipeline (step 4).** `rebuild.ts` drives the same four-workflow sequence `dev-process-batch.sh --all` already drains: drain-loop the two LLM stages (`process-llm`, `distill-essences`) until no progress, then run `synthesize-topics` and `export-obsidian` once over the full corpus. `rebuild.ts` owns the drain loop itself (typed control over iteration + counts) while reusing the exact command/`SELENE_ENV` invocation pattern.

2. **Shared agent helpers.** `pause_watcher` / `resume_watcher` / `stop_agents` / `restart_agents` are **extracted** from `cutover-prod.sh` into `scripts/lib/prod-agents.sh`; both scripts source it. This is a mechanical refactor of live, working code — its regression net is re-running `verify-cutover.sh` (must stay 45/45).

---

## The rebuild sequence (data flow)

Bracketed steps are **prod-only** (the bash wrapper adds them; dev runs straight through the TS core):

```
[prod] pause_watcher              stop the deploy-watcher reacting mid-rebuild
[prod] stop_derivation_agents     stop com.selene.prod.{process-llm,distill,synthesize,export} so none
                                  races the drain. The WEBHOOK SERVER STAYS UP — capture writes only
                                  facts.db (pending = absence), which rebuild never touches → zero
                                  capture outage (preserves the #1 ADHD principle).
[prod] (trap installed)           an EXIT trap will restart_agents + resume_watcher on ANY exit
       ──────────────────────────────────────────────────────────────────
       snapshot()             selene.db counts {processed_notes, embeddings, clusters,
                              cluster_links, essences, exported}                 → PRE
       backup()               cp selene.db → BACKUP_DIR/pre-rebuild-<ts>.db ; verify
                              (facts.db NOT backed up — precious, TM-backed, never modified)
       wipe()                 short-lived conn → DELETE FROM each main-schema table (txn, FK-safe)
                              → every fact now reads "pending" (derivation-absence). No file unlink.
       rederive()             drain process-llm → distill → synthesize → export
       validate()             POST counts → coverage% + drift vs PRE → verdict
              ┌── PASS ──→  prune backups (keep newest N) ; report
              └── FAIL ──→  rollback(): restore backup over selene.db → reopen
       ──────────────────────────────────────────────────────────────────
[prod] restart_agents (via trap)  bring the derivation agents back UP
[prod] resume_watcher (via trap)  re-arm the deploy-watcher
```

### Three properties

- **The human layer needs no explicit re-apply in Phase 2.** `review_state` lives in `facts.db`, which `wipe()` never touches — review flags survive automatically and still join by note id (stable, because `captured_notes.id` is never regenerated). The parent design's "re-apply human layer last" becomes real work only in Phase 3 (`category_overrides` must *win* over re-derived categories). Phase 2's `validate()` merely **confirms** `review_state` still joins cleanly.
- **`rollback()` restores `selene.db` only** — never touches `facts.db`. The prod wrapper's **EXIT trap** guarantees `restart_agents`/`resume_watcher` run on *any* exit, including a hard crash of `rebuild.ts` — so a failure never leaves prod with its derivation agents stopped. Cutover's hard lesson applies to the restore path itself: **`set +e` at the top** (do not rely on bash errexit to let the tail run; behavior inside `||`-lists + nested funcs is bash-version-dependent).
- **Crash between wipe and validate is safe-by-construction.** Un-derived notes read as pending; the trap resumes the agents, and the normal pipeline finishes them. The backup remains for a manual clean restore.
- **`rebuild.ts` never holds the `db.ts` module singleton across the wipe.** It uses short-lived `openSeleneConnection()` for snapshot / wipe / validate, so there is no stale long-lived handle. (Truncation, unlike a file delete, would be safe even if a handle were held — but short-lived connections keep the contract clean.)

---

## The validation gate

A pure function in `rebuild-core.ts`: `verdict(PRE, POST, thresholds) → { pass, reasons[] }`. Two independent checks; **both must pass to KEEP**.

**1. Coverage (hard floor):**
```
coverage = processed_notes_count / captured_notes_count        (denominator from facts.db)
PASS if coverage >= COVERAGE_MIN          default 0.95
```
Catches a broken re-derivation (Ollama down, crashed drain). The 5% slack absorbs notes the LLM legitimately fails on, which the live pipeline retries later.

**2. Bounded drift (sanity band):** for each derived metric — `processed_notes`, `note_embeddings`, `topic_clusters`, `topic_note_links`, essences, exported:
```
drift = (POST - PRE) / PRE
PASS if drift >= -DRIFT_TOLERANCE         default -0.20  (no metric collapses >20% below baseline)
```
Asymmetric on purpose: **more** clusters/links is fine (a better prompt); a catastrophic drop signals breakage.

**Thresholds are env-overridable config**, not magic numbers: `COVERAGE_MIN`, `DRIFT_TOLERANCE`. A deliberately-disruptive reprocess loosens them with eyes open (e.g. `DRIFT_TOLERANCE=0.9 rebuild`).

**Zero/near-empty baseline edge case:** if `PRE == 0` for a metric (fresh dev DB), that metric's drift check is **skipped** (coverage still applies) — a rebuild from nothing can't "drop below" nothing.

**Verdict output:** a structured report (PRE/POST table, coverage %, per-metric drift, pass/fail with reasons) printed for the operator; `--json` emits it machine-readable. On FAIL it names exactly which check tripped before rolling back.

Splitting the gate into a pure `verdict()` is the direct application of the cutover's most expensive lesson — *"a green test claiming a false guard is worse than none."* Every branch (coverage-fail, drift-fail, zero-baseline-skip, all-pass) is unit-testable with hand-built inputs, so the guard can't claim protection it doesn't provide. The bash wrapper just reads its boolean verdict.

---

## Safety & prod-guard compliance

- **Claude never runs `rebuild` against prod.** Built and tested entirely against `/tmp` copies and `.backup` snapshots of dev; the operator runs the prod path. Every check rebuild makes is content-free by construction (counts, ratios — never note text), composing with the `selene-inspect` discipline.
- **`--dry-run`** reuses the cutover's `DRY_RUN` convention: stubs `launchctl`, the backup `cp`, the wipe, and the drain, then prints the plan + a simulated verdict. Lets the operator (and `verify-rebuild.sh`) rehearse the full sequence — both rollback paths included — without destroying anything.
- **Failure-injection hooks** (mirroring cutover's `SIMULATE_*`): `SIMULATE_COVERAGE_FAIL`, `SIMULATE_DRIFT_FAIL`, `SIMULATE_REDERIVE_FAIL` force a specific gate to fail so auto-rollback is *proven* in a test, not merely asserted.

---

## Testing strategy

- **jest unit** on `rebuild-core.ts`: `verdict()` truth table (coverage pass/fail, drift pass/fail, zero-baseline skip, all-pass), snapshot reader, backup-path naming.
- **`scripts/verify-rebuild.sh`** (analog of `verify-cutover.sh`): drives the *real* `rebuild.ts` against a `/tmp` two-file DB seeded from a dev `.backup`, small corpus, real Ollama drain — exercising happy path (PASS → keep), coverage-fail (→ rollback restores PRE), drift-fail (→ rollback), and the crash-resume property.
- **`prod-agents.sh` extraction regression-covered** by re-running `verify-cutover.sh` after the refactor (must stay 45/45).
- **tsc clean + full jest suite green** before done.

The strategy leans on a pattern this codebase proved twice (cutover's `ALTER RENAME` FK-repoint; the dev-boundary A5 no-op-drain bug): the unit suite verifies the *logic*, but only an **end-to-end run against a real `.backup` snapshot** catches integration bugs. `verify-rebuild.sh` exists so rebuild doesn't relearn that lesson.

---

## Affected files

- `scripts/rebuild.ts` — NEW: the orchestrator brain (snapshot → backup → wipe → rederive → validate → keep/rollback).
- `src/lib/rebuild-core.ts` — NEW: pure helpers (`snapshot()` reader, `verdict()`, backup-path naming).
- `scripts/rebuild-prod.sh` — NEW: thin prod wrapper (source `prod-agents.sh`; pause watcher + stop *derivation* agents → `rebuild.ts` → restart via EXIT trap). Server stays up.
- `scripts/lib/prod-agents.sh` — NEW: shared agent-control helpers extracted from `cutover-prod.sh`, plus a NEW granular `stop_derivation_agents` (derivation agents only, not the server/watcher).
- `scripts/cutover-prod.sh` — MODIFIED: source the extracted `prod-agents.sh` instead of its inline copies; keeps using `stop_agents` (stop-ALL) (regression: `verify-cutover.sh` stays 45/45).
- `scripts/verify-rebuild.sh` — NEW: end-to-end rehearsal harness. Seeds a `/tmp` two-file DB from a dev `.backup`; **migrates it first if the snapshot is still legacy single-file** (the on-disk dev `selene.db` currently has a physical `raw_notes`), mirroring `reset-dev-data.sh`.
- `src/lib/__tests__/rebuild-core.test.ts` — NEW: jest unit suite.
- `docs/guides/features/releases.md` — MODIFIED: add the `rebuild` operator section (lives here, alongside the cutover runbook it mirrors — same "prod maintenance ops" surface).

---

## Acceptance criteria

- [ ] `rebuild` (dev) truncates the derived tables in `selene.db`, re-derives from `facts.db` through Obsidian export; afterward every fact has a `processed_notes` row (within the coverage floor) and `review_state` flags are intact.
- [ ] The validation gate KEEPs on a healthy rebuild and AUTO-ROLLS-BACK (restoring the pre-rebuild `selene.db`) when coverage < `COVERAGE_MIN` or any metric drifts below `-DRIFT_TOLERANCE`; thresholds are env-overridable.
- [ ] `facts.db` is never modified by `rebuild` (verified before/after).
- [ ] On the prod path the **webhook server stays up** for the whole rebuild (capture never refused); only derivation agents stop, and the EXIT trap restarts them + resumes the watcher on any exit.
- [ ] A mid-rebuild crash leaves the DB self-healing (pending remainder finished by the normal pipeline); the backup is available for a manual clean restore.
- [ ] `--dry-run` rehearses the full sequence (incl. both rollback paths) without destroying anything.
- [ ] `prod-agents.sh` extraction leaves `verify-cutover.sh` at 45/45.
- [ ] `verify-rebuild.sh` passes: happy path, coverage-fail rollback, drift-fail rollback, crash-resume.
- [ ] tsc clean; full jest suite green.
- [ ] `docs/guides/features/releases.md` documents the operator `rebuild` flow.

---

## ADHD check

- **Reduces friction?** Yes — removes the fear tax on experimentation and upgrades. "I can always rebuild from facts" turns scary changes into routine ones, so they actually happen.
- **Visible / externalized?** Yes — the verdict report makes the rebuild's effect legible (what changed, by how much) instead of an opaque reprocess.

---

## Scope check

Single command, one new pure module, one extracted shared lib, one verify harness. Reuses the existing drain sequence and the cutover's prod-orchestration helpers. < 1 week of focused work.

---

## Related

- [2026-05-31-fact-store-design.md](2026-05-31-fact-store-design.md) — Phase 1 (the split); this is its Phase 2.
- [2026-05-31-fact-store-cutover-design.md](2026-05-31-fact-store-cutover-design.md) — the one-time migration; rebuild reuses its TS-core/thin-bash pattern, `DRY_RUN`/`SIMULATE_*` conventions, and (via extraction) its agent-control helpers.
- [2026-05-30-idempotent-obsidian-reexport-design.md](2026-05-30-idempotent-obsidian-reexport-design.md) — idempotent export composes with rebuild (the export stage self-heals rather than duplicating).
- [2026-05-28-prod-dev-split-design.md](2026-05-28-prod-dev-split-design.md) — the two-env layout rebuild runs within.
