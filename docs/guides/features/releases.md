# Releases (Prod/Dev Split)

**What this does for you:** lets you develop freely in `~/selene` without touching what's running, then ship a tested, compiled build to production simply by merging to `main` — automatically, with a notification when it's done.

> **Status: LIVE since 2026-05-29.** Production runs the `com.selene.prod.*` agents from compiled `dist/` in `~/selene-prod`; the old `com.selene.*` ts-node agents are retired. **Merging to `main` and pushing to origin auto-deploys within ~5 minutes.**

## Using it

**Cut a release — merge to `main`.** That's the whole gesture. A launchd deploy-watcher checks `origin/main` every ~5 minutes; when the commit on `main` moves, it builds the new code in a scratch clone, and **only if the build passes** ships it to production. You get a macOS notification either way:

- **"Selene deployed"** — `<old-sha> -> <new-sha>` — the new build is live.
- **"Selene deploy FAILED"** — the build of the new commit failed; **production was left untouched on the last-good release.** Fix the code, merge again.

There's nothing to run by hand. Merge, wait a few minutes, watch for the notification.

**Roll back — one command.** If a release that built fine turns out to be bad at runtime, revert to the previous archived build:

```bash
# From the dev repo. Roll back to the most recent archived release:
./scripts/rollback-prod.sh

# Or roll back to a specific archived sha:
./scripts/rollback-prod.sh <sha>
```

This restores the previous `dist/`, restarts the prod agents in place (`launchctl kickstart -k`), health-checks, and notifies (**"Selene ROLLED BACK"**). Rollback is always manual — a bad release never auto-reverts on its own.

## How it works

**Three directories, three jobs:**

| Directory | Role | Database | Runtime | Port | Agents |
|-----------|------|----------|---------|------|--------|
| `~/selene` | Dev sandbox — where you edit + experiment | dev DB (`~/selene-data-dev`) | `ts-node` (source) | 5679 | manual / dev |
| `~/selene-build` | Scratch build clone — never edited by hand | — | build only | — | — |
| `~/selene-prod` | Production — what actually runs for you | real DB (`~/selene-data/selene.db`), iCloud vault | compiled `dist/` (`node`) | 5678 | `com.selene.prod.*` |

**The gated deploy flow** (`scripts/deploy-watch.sh` → `scripts/deploy-prod.sh`):

1. **Poll.** The deploy-watcher (`scripts/deploy-watch.sh`, run by `com.selene.prod.deploy-watcher`) fetches `origin` and compares the short sha of `origin/main` against the sha currently live in prod (`~/selene-prod/.deployed-sha`). If they match, it logs "up to date" and stops. If they differ, it hands off to `deploy-prod.sh`.
2. **Build in a scratch clone.** `deploy-prod.sh` resets `~/selene-build` to the target ref and runs `npm install && npm run build && npm run build:check`. **This is the gate.** The live deployment is never the build site.
3. **Build-gate.** If the build or check fails, the script notifies **"Selene deploy FAILED"** and exits — `~/selene-prod` (its `.env`, `dist/`, `package.json`, `.deployed-sha`) is left **completely untouched on the last-good release**.
4. **Archive for rollback.** On a passing build, the current live `dist/` is copied to `~/selene-prod/releases/<old-sha>/` before anything is overwritten. Only the 5 newest archived releases are kept.
5. **Ship only `dist/`.** The compiled output is rsync'd into `~/selene-prod/dist/`. **The target's `.env` is a sibling of `dist/` and is never touched** — production secrets and config survive every deploy. `package.json`/`package-lock.json` are copied and `npm install --omit=dev` runs in prod.
6. **Restart prod agents.** `deploy-prod.sh` restarts the already-loaded `com.selene.prod.*` agents in place via `launchctl kickstart -k`, so they re-exec the new `dist/`. It does **not** bootout+bootstrap — re-bootstrapping the running KeepAlive server races its own teardown (`Bootstrap failed: 5: Input/output error`) and can take prod down; `kickstart` never unloads, so a restart failure leaves the old process serving (prod stays up, with a WARN). `install-prod.sh`'s generate-and-bootstrap is used only for the initial cutover and when the agent set or plist content changes (run interactively, not from the launchd watcher).
7. **Health probe.** It waits briefly and probes `http://localhost:5678/health`. **This is warn-only:** a failed health check sends a WARN notification but does **not** auto-roll-back. Use `rollback-prod.sh` if needed.
8. **Record + announce.** The new sha is written to `~/selene-prod/.deployed-sha` and a **"Selene deployed"** notification fires.

**Notifications** (`scripts/lib/notify.sh`) are sent on success *and* failure: each one appends a timestamped line to the deploy log and fires a macOS notification via `osascript` (best-effort — a missing `osascript` never fails the deploy).

**Prod plists are generated, not committed.** `install-prod.sh` renders `com.selene.prod.*` plists from the canonical `launchd/com.selene.*.plist` files by per-key substitution (compiled `node` entrypoint instead of the ts-node wrapper, `SELENE_ENV=production`, paths remapped into `~/selene-prod`). This keeps a single source of truth so the prod plists can't drift from the dev ones. The deploy-watcher plist is separate infra and is never pruned by this process.

## The one-time fact-store cutover

> **Separate from the prod/dev split above.** This is a **one-time DB migration**, not a code release. It moves production's database from a single `selene.db` to the two-file **fact-store** layout (`facts.db` = the precious append-only captured notes + your review state; `selene.db` = the regenerable derived layer). It is run **once, by hand, at a quiet moment**, then you never run it again. Status: **ran against prod — production is on the two-file layout** (verified content-free via `selene-inspect schema`: separate `facts.db`, `raw_notes_legacy_backup`, `note_state`). The procedure below is kept as the recovery path (e.g. a rolled-back deploy landing fact-store code on an un-migrated restore).

**Why it can't just be a merge.** The fact-store code reads `raw_notes` as a per-connection view over `facts.captured_notes`. If you merged the fact-store branch and let the deploy-watcher auto-ship it (code-only) onto an **un-migrated** prod DB, prod wouldn't crash — it would silently *split*: new captures would land in `facts.captured_notes` while reads still hit the old physical `raw_notes` table. So the DB must be migrated **in lockstep** with the code, by a supervised script — never by the auto-deploy path.

A startup guard (`src/lib/ensure-migrated.ts`, wired into `db.ts`) enforces this: dev/test/fresh-clone DBs **auto-migrate** themselves, but a **production** DB that is somehow un-migrated **fails loud and refuses to serve** rather than running in the split state. That guard is the safety net; the cutover below is the real path.

### Running the cutover

Run from `~/selene`. The order is **prove the migration on a copy of real prod → merge to `main` → cut over** — and that order is load-bearing (see the warning below).

```bash
# 1. REHEARSE the orchestration — full --dry-run against a /tmp copy of the DEV DB.
#    Stubs every launchctl/deploy/notify side effect; runs the REAL DB surgery on the copy.
#    Exercises happy path, already-migrated re-run, and all auto-rollback paths.
bash scripts/verify-cutover.sh        # expect "VERIFY-CUTOVER: ALL PASSED"

# 2. VALIDATE THE MIGRATION ON A COPY OF REAL PROD — content-free, zero-risk, and MANDATORY.
#    Real prod data carries referential cruft the dev DB doesn't (orphaned processed_notes,
#    dangling source_note_id refs from historical deletions). This proves migrate() is green on
#    YOUR actual data BEFORE you merge — so a post-merge failure (which would cause an outage,
#    see warning) can't happen. The output is counts + "preserved N …" logs only — no note text.
sqlite3 ~/selene-data/selene.db ".backup /tmp/prodcopy.db"
SELENE_DB_PATH=/tmp/prodcopy.db SELENE_FACTS_DB_PATH=/tmp/prodcopy-facts.db \
  npx ts-node scripts/migrate-to-fact-store.ts     # expect "migrated <N> note(s) → …"
rm -f /tmp/prodcopy.db /tmp/prodcopy-facts.db      # clean up the copy
#    If this FAILS, STOP — fix the migration and re-validate. Do NOT merge until it's green.

# 3. MERGE feat/fact-store → main and push  (only after step 2 is green).

# 4. GO LIVE — immediately after the merge, at a quiet moment (brief downtime, see below):
./scripts/cutover-prod.sh --ref origin/main
```

`cutover-prod.sh` is the single supervised command. It prints a `[PASS]`/`[FAIL]` line for every step and, on success, fires a **"Selene cutover complete"** notification.

> **⚠️ Why merge-first, and why step 2 is mandatory.** `cutover-prod.sh` deploys the code at `--ref` and, at the end, resumes the deploy-watcher — which only stays quiet if `.deployed-sha == origin/main`. That requires `origin/main` to already contain the fact-store code, so **`--ref origin/main` is correct only *after* the merge** (before it, you'd deploy the old single-file code onto the migrated DB). And the merge raises the stakes of a migrate failure: if the cutover fails *after* you've merged, its rollback resumes the watcher while `origin/main` now holds fact-store but `.deployed-sha` is still old → the watcher deploys fact-store onto the rolled-back, **un-migrated** DB → the `ensure-migrated` guard refuses to serve → **prod is down** until a successful cutover. Step 2 removes that risk by proving migrate() green on a copy of your real data *before* the merge. Do **not** pre-pause the watcher manually (the cutover's own `pause_watcher` would then abort).

### What it does (and how it protects the DB)

The script runs this ordered sequence, **aborting cleanly with nothing changed** on any pre-flight problem, and **auto-rolling-back** on any gate or deploy failure after surgery begins:

1. **Build-gate** — `npm run build && npm run build:check`. A broken build aborts before anything is touched.
2. **Pre-flight** — DB exists; DB is actually un-migrated (if already migrated, exits `0` "already migrated — nothing to do"); enough disk for a full backup (~2× the DB); captures baseline `raw_notes`/`processed_notes` counts. Any failure aborts with prod untouched.
3. **Pause the deploy-watcher** (`bootout`) so it can't auto-deploy mid-cutover.
4. **Stop the `com.selene.prod.*` agents** — *prod downtime begins.* The DB is now quiesced.
5. **Verified backup** — copies `selene.db` to `~/selene-data/backups/pre-cutover-<sha>-<ts>.db` and **re-opens it read-only to confirm its row count matches the live DB** before proceeding. An unverified backup is not a rollback target. (Keeps the newest 5; Time Machine is the secondary net.)
6. **Migrate** — `migrate-to-fact-store.ts`: id-preserving, transactional, crash-atomic (rollback-journal mode for the cross-file commit), FK-safe, idempotent.
7. **Gate 1 (content-free)** — structure + counts + a self-deleting capture→pending probe: `facts.db` present, `raw_notes_legacy_backup` holds the original rows, `raw_notes` is no longer a physical table, counts preserved, FK check clean. **Any failure → auto-rollback.**
8. **Deploy** — `deploy-prod.sh --ref <sha>` ships the compiled `dist/`.
9. **Restart the prod agents** — new code on the migrated DB; *downtime ends.*
10. **Gate 2 (live)** — `/health` 200 (with a ~30s readiness-wait so a slow cold start doesn't trip it), `facts.db` present, content-free coverage sane. **Any failure → auto-rollback.**
11. **Resume the deploy-watcher** and fire **"Selene cutover complete"**.

**Auto-rollback** (on a Gate 1 / Gate 2 / deploy failure) restores prod to **byte-for-byte single-file**: stop agents → restore the verified backup over `selene.db` → remove `facts.db` → (only if a deploy had already happened) roll the code back via `rollback-prod.sh` → restart agents → resume watcher → **"Selene cutover ROLLED BACK"**. The restore tail is best-effort by construction (`set +e`), so it always runs to completion even if a step within it errors.

**Brief downtime is inherent.** Old code can't read a migrated DB and new code can't safely read an un-migrated one, so the agents are stopped across the swap — minutes, not hours. Webhook captures arriving in that window are dropped (server off), which is why you pick a quiet moment.

**Claude never runs this against prod.** The prod-data guard blocks Claude's tools from `~/selene-data`; Claude authors and `/tmp`-validates the script, the operator runs it. Every gate is content-free (counts/structure + a self-deleting probe), so no note text is ever read.

## The `rebuild` command

> **What it's for.** The cutover above made `selene.db` *disposable*; `rebuild` is the command that actually disposes of it and regenerates it. It **wipes the derived tables, re-derives the whole corpus from `facts.db`** (`process-llm → distill-essences → synthesize-topics → export-obsidian`), validates the result, and **keeps it or auto-rolls-back**. `facts.db` — your precious captured notes + review state — is **never touched**. Use it to reprocess everything after a pipeline/model upgrade, to recover from a corrupted derived DB, or to safely experiment.

It only ever truncates a fixed **allowlist of derived tables** (`processed_notes`, `note_embeddings`, `note_state`, `topic_clusters`, …). Non-derived state in `selene.db` — the `_selene_metadata` environment marker, `device_tokens`, the `raw_notes_legacy_backup` migration net — is preserved by omission. (An allowlist fails *safe*: a table added later is left alone rather than silently destroyed.)

### Running it

```bash
# DEV (also how Claude validates it) — run directly, never touches prod:
SELENE_ENV=development npx ts-node scripts/rebuild.ts            # wipe + re-derive + validate
SELENE_ENV=development npx ts-node scripts/rebuild.ts --dry-run  # rehearse: read counts, NO wipe
#   add --json for a machine-readable {pre, post, coverage, pass, reasons} report

# PROD — the supervised wrapper (run on the prod box):
./scripts/rebuild-prod.sh --dry-run   # rehearse: cycles the derivation agents, rebuild dry-run, no wipe
./scripts/rebuild-prod.sh             # live: wipe + re-derive + validate + keep/rollback
DRY_RUN=1 ./scripts/rebuild-prod.sh   # fully inert smoke — echoes every launchctl + the rebuild, touches nothing
```

`rebuild-prod.sh` keeps the **webhook server UP** the whole time — captures write only `facts.db`, which `rebuild` never touches, so **capture never blocks** (unlike the cutover, which has brief downtime). It stops **only the derivation agents** so none races the drain, and an **EXIT trap restarts them + resumes the deploy-watcher on *any* exit** — success, a FAIL verdict, or a crash/Ctrl-C mid-rebuild.

### How it protects the DB

- **Verified backup first** — `selene.db` is snapshotted (WAL-safe `VACUUM INTO`) before the wipe; that backup is the rollback target.
- **Validation gate** — `verdict(pre, post)` requires **≥95% coverage** (every captured note has a processed row) and **≤20% downward drift** on each derived metric vs. the pre-rebuild snapshot. Fail either → **auto-rollback** to the backup (restored in-place, never a file swap, so the live server's handle is never corrupted).
- **Crash mid-rebuild self-heals** — a crash *after* the wipe restores the backup; if anything slips through, the normal pipeline finishes the pending remainder on its next run.

Validated end-to-end by `scripts/verify-rebuild.sh` (real Ollama on a `/tmp` copy of the dev DB: happy-path drain, both rollback paths, crash-resume, and `facts.db` asserted byte-identical throughout). **Claude runs `rebuild.ts` on dev/`/tmp` only — never `rebuild-prod.sh` against prod.**

## Configure & customize

**Poll interval** — `launchd/com.selene.prod.deploy-watcher.plist`, `StartInterval` = `300` (seconds, i.e. every 5 minutes). Change that integer and reload the agent to poll more/less often.

**`deploy-prod.sh` flags:**

| Flag | Default | Purpose |
|------|---------|---------|
| `--target DIR` | `$HOME/selene-prod` | Production deploy dir |
| `--ref REF` | `origin/main` | Git ref to deploy |
| `--build-dir DIR` | `$HOME/selene-build` | Scratch build clone dir |
| `--label-prefix PFX` | `com.selene.prod.` | Prod launchd label prefix |
| `--skip-agents` | off | Don't (re)load prod launchd agents |
| `--skip-health` | off | Don't probe `/health` |

**`install-prod.sh` flags** (this is where DB isolation lives — `--db-path` is on **install-prod.sh**, not `deploy-prod.sh`):

| Flag | Default | Purpose |
|------|---------|---------|
| `--prod-dir DIR` | `$HOME/selene-prod` | Production deploy dir |
| `--out DIR` | `$HOME/Library/LaunchAgents` | Where plists are written |
| `--label-prefix PFX` | `com.selene.prod.` | Label + filename prefix |
| `--db-path PATH` | (canonical prod DB) | Override `SELENE_DB_PATH` in every generated plist — for staging/test loads against an isolated DB |
| `--dry-run` | off | Print what would be written; write nothing |
| `--no-load` | off | Generate plists but don't run launchctl |

**Deploy log** lives at `~/selene-prod/deploy.log` — the timestamped success/FAILED/WARN summary lines.

**`rebuild` validation thresholds** (env vars on `rebuild.ts` / `rebuild-prod.sh`):

| Env var | Default | Purpose |
|---------|---------|---------|
| `COVERAGE_MIN` | `0.95` | Minimum fraction of captured notes that must have a processed row, or the rebuild rolls back |
| `DRIFT_TOLERANCE` | `0.20` | Max allowed *downward* drift per derived metric vs. the pre-rebuild snapshot (zero-baseline metrics are skipped) |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **Prod isn't updating after I merged** | Check `~/selene-prod/deploy.log` for the latest summary line, and `~/selene-prod/logs/deploy-watcher.out.log` / `deploy-watcher.err.log` for the watcher's run output. A **FAILED** line means the build broke — prod is still on the last-good release; fix the code and merge again. |
| **I got a "deploy FAILED" notification** | The new commit didn't build. Production was not changed — it's still on the last-good release. Fix the build error and merge again; the watcher re-deploys on the next poll. |
| **I got a "deploy WARN" notification** | The build passed and `dist/` shipped, but a later step (prod `npm install`, agent load, or `/health`) failed. Prod may be incoherent and is still recorded on the old sha. Check `deploy.log`, and consider `./scripts/rollback-prod.sh`. |
| **Force a redeploy** (watcher says "up to date" but I want to re-ship) | Run the deployer directly — it deploys the ref unconditionally (the sha-equality gate is only in the watcher): `./scripts/deploy-prod.sh --ref origin/main` |
| **A release built fine but behaves badly at runtime** | Roll back: `./scripts/rollback-prod.sh` (newest archived release) or `./scripts/rollback-prod.sh <sha>`. |
| **Prod crashlooping with "DB not migrated" after a fact-store deploy** | The fact-store code reached prod on an un-migrated DB (the `ensure-migrated` guard refusing to serve, by design — e.g. a cutover that rolled back *after* the merge). Don't patch around it — run the supervised cutover: `./scripts/cutover-prod.sh --ref origin/main`. |
| **`cutover-prod.sh` says "already migrated — nothing to do"** | The DB is already on the two-file layout; the cutover is a safe no-op. Nothing to do. |
| **Cutover hit a gate and rolled back** | Expected safety behavior — prod is restored to single-file on the last-good code (you'll have gotten **"Selene cutover ROLLED BACK"**). Check the `[FAIL]` line in the script output and `~/selene-data/backups/` for the verified pre-cutover backup, fix the cause, re-run. |
| **`rebuild` rolled back (coverage/drift verdict FAIL)** | The re-derived corpus didn't clear the gate — `selene.db` was auto-restored from the pre-rebuild backup; nothing lost. Re-run `rebuild.ts --json` and read `reasons` to see which gate fired (a transient Ollama hiccup is common — just re-run; a persistent shortfall means a pipeline regression to fix first). `facts.db` is untouched either way. |

## Related

- Design doc (prod/dev split): [`docs/plans/2026-05-28-prod-dev-split-design.md`](../../plans/2026-05-28-prod-dev-split-design.md)
- Design docs (fact-store cutover): [`docs/plans/2026-05-31-fact-store-cutover-design.md`](../../plans/2026-05-31-fact-store-cutover-design.md) · [`…-fact-store-design.md`](../../plans/2026-05-31-fact-store-design.md)
- Release scripts: `scripts/deploy-watch.sh`, `scripts/deploy-prod.sh`, `scripts/install-prod.sh`, `scripts/rollback-prod.sh`, `scripts/lib/notify.sh`
- Cutover scripts: `scripts/cutover-prod.sh` (orchestrator), `scripts/migrate-to-fact-store.ts` (migration), `scripts/verify-cutover.sh` (/tmp validation), `src/lib/ensure-migrated.ts` (startup guard)
- Watcher agent: `launchd/com.selene.prod.deploy-watcher.plist`

---
*Last updated: 2026-06-09*
