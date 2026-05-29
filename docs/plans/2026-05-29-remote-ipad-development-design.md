# Remote iPad Development for Selene

**Date:** 2026-05-29
**Status:** Ready
**Topic:** ipad, tailscale, dev-environment, travel, infra

---

## Problem

The owner will be out of town with an iPad + a MacBook Air (Xcode installed) and
wants to keep developing the SeleneMarkup iPad app **without physically connecting
to the home Mac mini**. Two hidden proximity dependencies block this today:

1. **Build + install** — `SeleneMarkup/redeploy.sh` builds on a Mac and installs to
   a **USB-connected iPad** via `devicectl`. Needs a Mac with Xcode + the iPad.
2. **Server reachability** — the app talks to the Selene server at the Mac mini's
   **LAN IP** (`192.168.1.239:5678/5679`), which only exists on home wifi.

A third, latent dependency surfaced during design: the iPad app's POSTs create real
`raw_notes`. Pointing it at the live prod server would pollute the real knowledge
base with un-cleanable test data — violating the project rule *"Never use production
database for testing"* (`CLAUDE.md`).

## Constraints / decisions made

- **Hardware:** iPad + MacBook Air (Xcode-capable). Mac mini stays home, powered on,
  on the internet. → The laptop + iPad are a self-contained build/deploy station.
- **Server access:** Approach A — Tailscale to the home Mac mini (not a laptop-local
  server). All three devices already share one tailnet under `chase8732@`.
- **Code transfer:** private GitHub repo (SeleneMarkup has no remote today).
- **Feature scope:** everything (notes + worksheets), so the server must serve all routes.
- **Database:** **dev DB seeded from a prod snapshot** — realistic data, writes isolated
  from prod, honors the no-prod-testing rule.

## Key facts verified (2026-05-29)

- **The prod/dev split shipped and cut over today.** Prod runs from `~/selene-prod`
  (compiled `dist/`) on **:5678** against `~/selene-data/selene.db`. Dev is `~/selene`
  (ts-node) on **:5679** against `~/selene-data-dev/selene.db`. The dev sandbox runs
  **no scheduled agents** by design; dev data is intended to be **fictional fixtures**.
- **A Dev iPad app already exists.** `~/SeleneMarkup` has a `SeleneMarkup-Dev` scheme
  (`SWIFT_ACTIVE_COMPILATION_CONDITIONS: SELENE_DEV`, bundle `…selenemarkup.dev`) whose
  `AppConfig` `#if SELENE_DEV` branch already targets **:5679**. `./redeploy.sh --dev`
  builds and installs it. So no port changes or app-repurposing are needed — only the
  baked-in IP changes.
- This dev Mac is `chases-mac-mini`, Tailscale IP **`100.111.6.10`** (online), MagicDNS
  `chases-mac-mini.taila69703.ts.net`. MacBook Air (`chases-macbook-air`) and an iPad
  (`ipad1610`) are already tailnet nodes. Tailscale CLI installed at `/opt/homebrew/bin/tailscale`.
- Tailscale IPs are **stable per-device** and follow the Mac anywhere — unlike the LAN IP.
- The server already accepts LAN connections, proving it binds all interfaces
  (`0.0.0.0`), so tailnet (`100.x`) traffic reaches it with **no server change**.
- `src/server.ts` registers **all** routes on one server: `notesRoutes`,
  `worksheetRoutes`, `agentRoutes`, `dashboardRoutes` (PR #50 landed — the old
  "worksheets on a separate :5679 worktree" note is stale).
- `src/lib/config.ts`: `SELENE_ENV=development` → uses the **dev DB**
  (`~/selene-data-dev/selene.db`) and defaults to **port 5679**.
- Dev DB today: 500 raw notes, but `processed_notes = 0`, **no `topic_clusters`**, no
  worksheets table → the app's cluster-browse entry point would be empty.
  `source_note_id` column is present.
- Prod DB (`~/selene-data/selene.db`, 8.5M): 293 notes, 302 processed, 83 clusters,
  `source_note_id` present. No `worksheets` table (worksheets are computed from note
  tables on the fly, not stored), so a prod snapshot serves worksheets too.
- `AppConfig.swift` reads `selene_base_url` / `selene_main_url` from `UserDefaults`,
  falling back to a baked-in URL — so the server address can change without a rebuild,
  or be baked in for durability.

## Architecture

```
  MacBook Air  ──build + deploy via USB──▶  iPad (ipad1610)
   (Xcode, GitHub clone)                        │
                                                │ HTTP over Tailscale
                                                ▼
  Mac mini (chases-mac-mini, 100.111.6.10) ── dev-mode server :5679 ── dev DB
   • stays home, awake, on internet                (writes isolated from prod)
   • prod server :5678 keeps running untouched
```

The MacBook Air + iPad together replicate the home desk (USB cable). The Mac mini is
purely the **server host**. Tailscale makes the iPad↔Mac-mini link work from any network.

## Components / changes

### Code (SeleneMarkup) — use the existing **Dev** app
- Deploy with `./redeploy.sh --dev` (the `SeleneMarkup-Dev` scheme), which already
  targets `:5679`/dev via `#if SELENE_DEV`. The **only** change: in `AppConfig.swift`,
  the `#if SELENE_DEV` branch's baked-in fallback `192.168.1.239` → `100.111.6.10`
  (Tailscale IP). Both `baseURL` and `mainBaseURL` resolve to `:5679`. (Updating the
  prod branch's IP too is optional symmetry; not needed for dev work. Or override at
  runtime via the `selene_base_url` / `selene_main_url` UserDefaults keys.)

### Server / ops (Mac mini, dev sandbox `~/selene`)
- **Snapshot prod → dev DB**: copy `~/selene-data/selene.db` (the live prod DB, 293 notes
  / 83 clusters / 302 processed) → `~/selene-data-dev/selene.db` (back up the existing
  dev DB first). Confirm `source_note_id` + schema after. **Note:** this overrides the
  split's "dev = fictional fixtures" default — a deliberate exception for realistic
  travel development (see Risks).
- **Persistent dev-mode server**: new launchd agent `com.selene.dev.server` running
  `SELENE_ENV=development` ts-node `src/server.ts` from `~/selene` on :5679,
  `KeepAlive=true`, surviving reboot/sleep. (The dev sandbox runs no agents today by
  design; this adds a single server agent — a server, not a scheduled workflow.) Model
  on `launchd/com.selene.prod.server.plist`.
- **Keep the Mac mini reachable**: persistent sleep-disable via `pmset`/System Settings
  + "wake for network access" (NOT a `caffeinate` tied to an SSH session — it dies with
  the session). Enable **Remote Login (SSH)** for restart-over-Tailscale.

### Code transfer
- Create a **private GitHub repo**, push `SeleneMarkup` (no remote today) and `~/selene`
  if not already remote. Laptop clones from GitHub; also a real backup.

## Pre-trip checklist (must be done before leaving — ordered; cannot be fixed remotely)

1. Push `SeleneMarkup` (+ `~/selene` if not already remote) to a private GitHub repo.
2. Clone on the MacBook Air, open `SeleneMarkup.xcodeproj`, confirm Apple-ID signing,
   run `./redeploy.sh --dev` to the iPad once — a successful local build+install of the
   **Dev** app is the make-or-break test (signing is per-machine).
3. Snapshot prod → dev DB; verify schema/migrations.
4. Install + start the `com.selene.dev.server` launchd agent on :5679; confirm
   `curl http://localhost:5679/health` and the cluster list endpoint return data.
5. Set the Mac mini to never sleep + wake-for-network; enable Remote Login (SSH).
6. Edit `AppConfig.swift` `#if SELENE_DEV` IP → `100.111.6.10`, `./redeploy.sh --dev`.
7. **Pre-flight test:** iPad on **cellular (home wifi off)** — the Dev app loads the
   cluster list and a test annotation round-trips into the dev DB. This proves the away path.

## Risks / mitigations

- **Home internet / power blip** → Mac mini unreachable. Mitigation: SSH-over-Tailscale
  to restart; `KeepAlive` agent auto-restarts the server; consider a UPS. (Approach B —
  a laptop-local server — is the fallback if home connectivity proves unreliable.)
- **Free Apple ID signing expires after 7 days** → app stops launching. Mitigation:
  re-run `./redeploy.sh` (laptop + iPad travel together, so trivial). A paid Apple
  Developer account extends this to 1 year.
- **Annotations created while away live only in dev** → not synced to prod. Accepted:
  this is test/dev data by design. A later reconcile is out of scope.
- **Overrides "dev = fictional fixtures"** (a deliberate prod/dev-split decision) by
  seeding dev with real prod data. Accepted exception: it's the owner's own data on the
  owner's own devices, and realism matters for exercising cluster-browse during travel.
  To revert, restore the fixture dev DB (backed up in step 3) after the trip.
- **Dev DB drift** (manual ALTERs not in `create-dev-db.sh`) → re-running that script
  would rebuild without `source_note_id`. Mitigation: prod snapshot carries the column;
  document not to rebuild dev from scratch during the trip.

## Acceptance criteria

- [ ] SeleneMarkup + selene pushed to a private GitHub repo.
- [ ] MacBook Air builds + installs SeleneMarkup to the iPad via `./redeploy.sh`.
- [ ] `com.selene.dev.server` runs on :5679 against a prod-seeded dev DB and survives a reboot.
- [ ] Mac mini stays awake/reachable; SSH-over-Tailscale works.
- [ ] From the iPad on **cellular**, the app loads the cluster list and an annotation
      round-trips into the dev DB (not prod).

## ADHD check

Reduces friction (one durable Tailscale-IP config replaces fragile network-dependent
setup), makes the dev setup visible/repeatable (a launchd agent + checklist instead of
remembered manual steps), and externalizes the "is it working?" question into a single
cellular round-trip test. Passes.

## Scope check

A one-line code change + a launchd agent + a DB copy + a documented checklist. Well
under a week. Passes.

## User-facing change?

No end-user feature change to the shipped app. This is **dev-environment / infra** —
remote development capability. No feature guide required (note in wrap-up).
The operator-facing capability could optionally be captured in `docs/guides/features/`
as a "remote development" runbook if desired.
