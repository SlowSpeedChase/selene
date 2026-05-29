# Releases (Prod/Dev Split)

**What this does for you:** lets you develop freely in `~/selene` without touching what's running, then ship a tested, compiled build to production simply by merging to `main` — automatically, with a notification when it's done.

> **Status: built & tested, not yet live.** The release tooling on this branch is complete and integration-tested, but it **activates at a one-time cutover** that has not run yet. Until then, production still runs the old `com.selene.*` agents from `~/selene` via ts-node, exactly as before. Everything below describes how releases work **once the cutover happens** — see the design doc in [Related](#related). The backend architecture diagram (`docs/backend-block-diagrams.md`) is intentionally not updated yet; it changes at cutover, when the live launchd layout actually changes.

## Using it

*(All of this applies after the one-time cutover.)*

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

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **Prod isn't updating after I merged** | Check `~/selene-prod/deploy.log` for the latest summary line, and `~/selene-prod/logs/deploy-watcher.out.log` / `deploy-watcher.err.log` for the watcher's run output. A **FAILED** line means the build broke — prod is still on the last-good release; fix the code and merge again. |
| **I got a "deploy FAILED" notification** | The new commit didn't build. Production was not changed — it's still on the last-good release. Fix the build error and merge again; the watcher re-deploys on the next poll. |
| **I got a "deploy WARN" notification** | The build passed and `dist/` shipped, but a later step (prod `npm install`, agent load, or `/health`) failed. Prod may be incoherent and is still recorded on the old sha. Check `deploy.log`, and consider `./scripts/rollback-prod.sh`. |
| **Force a redeploy** (watcher says "up to date" but I want to re-ship) | Run the deployer directly — it deploys the ref unconditionally (the sha-equality gate is only in the watcher): `./scripts/deploy-prod.sh --ref origin/main` |
| **A release built fine but behaves badly at runtime** | Roll back: `./scripts/rollback-prod.sh` (newest archived release) or `./scripts/rollback-prod.sh <sha>`. |

## Related

- Design doc: [`docs/plans/2026-05-28-prod-dev-split-design.md`](../../plans/2026-05-28-prod-dev-split-design.md)
- Scripts: `scripts/deploy-watch.sh`, `scripts/deploy-prod.sh`, `scripts/install-prod.sh`, `scripts/rollback-prod.sh`, `scripts/lib/notify.sh`
- Watcher agent: `launchd/com.selene.prod.deploy-watcher.plist`

---
*Last updated: 2026-05-28*
