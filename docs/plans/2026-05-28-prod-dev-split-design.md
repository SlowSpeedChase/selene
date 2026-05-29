# Production / Development Split — Design

**Date:** 2026-05-28
**Status:** Ready (design approved; next step: implementation plan)
**Branch:** feat/note-annotation (design committed here; implementation on its own branch)

---

## Problem

Selene's **config** is environment-aware (`test` / `development` / `production` with separate DB, vault, digest, and log paths, and separate server ports 5678/5679). But its **deployment** is not. All 11 `com.selene.*` launchd agents run `npx ts-node src/workflows/...` **directly from the working repo** (`~/selene`) against the **real** production database (`~/selene-data/selene.db`).

**Consequence:** the moment a workflow file is edited in this repo, the next launchd tick runs that half-finished code against real notes. Today, *this working repo IS production.* There is no insulation layer between "code I'm editing" and "code serving real data."

## Goal

Establish a **release boundary**:

- **`~/selene` (this repo)** becomes a true dev sandbox — runs only against the dev database and a scratch vault.
- **`~/selene-prod`** becomes production — runs a **compiled, frozen build artifact** against the real database and the real iCloud Obsidian vault.
- Code reaches prod via **auto-deploy on merge to `main`**, gated on a successful build.
- Two coexisting iPad apps: **Selene** (prod, :5678) and **Selene Dev** (dev, :5679).

This is the standard professional pattern (local dev → CI/CD → prod, with environment isolation), right-sized for a single person on a single Mac. We deliberately **skip a separate staging environment** (YAGNI for a solo system); the dev sandbox, loaded with anonymized real data, serves as the rehearsal environment.

---

## Architecture

```
┌─ DEV (~/selene — this repo) ──────────────────┐   ┌─ PROD (~/selene-prod) ────────────────────┐
│ Code you edit, via ts-node (no build)          │   │ Compiled dist/ only — never hand-edited     │
│ SELENE_ENV=development                          │   │ SELENE_ENV=production                       │
│ DB:    ~/selene-data-dev/selene.db (anon copy)  │   │ DB:    ~/selene-data/selene.db (REAL)       │
│ Vault: ~/selene-data-dev/vault (scratch)        │   │ Vault: ~/…/iCloud/…/Selene (REAL)           │
│ Server: :5679 (started manually when testing)   │   │ Server: :5678 (launchd, always on)          │
│ Workflows: MANUAL (dev-process-batch.sh)        │   │ Workflows: SCHEDULED (com.selene.prod.*)    │
│ Digest/TRMNL/AppleNotes: OFF (config default)   │   │ Digest/TRMNL/AppleNotes: ON                 │
│ Scheduled launchd agents: NONE                  │   │ 11 scheduled agents + deploy-watcher        │
└─────────────────────────────────────────────────┘   └─────────────────────────────────────────────┘
```

**Key decision:** dev runs **no scheduled launchd agents**. Workflows fire manually via the existing `scripts/dev-process-batch.sh`; the dev server is started by hand only while testing. This keeps dev a true sandbox and avoids grinding anonymized notes through Ollama every 5 minutes. Only **prod** is scheduled.

### Why a compiled artifact (not a worktree or git clone)

`tsconfig.json` already targets `outDir: ./dist`, `rootDir: ./src`. No bundled non-TS assets exist in `src/` (the `readFileSync` calls all read *runtime* data — images, digests, APNs keys — not templates needing copy). So `tsc` alone emits a complete `dist/`. Prod runs `node dist/...`. Prod gets its own `npm install` so the native `better-sqlite3` addon is built for the machine (same Mac/arch — fine).

**Known edge case:** `src/lib/calendar.ts` references a sibling `SeleneChat/.build/release/selene-calendar` binary by relative path, which won't resolve under `~/selene-prod/dist/`. Audit at build time; if a core workflow needs it, resolve via a `SELENE_*` env var; otherwise leave (non-core).

---

## Deploy: auto-deploy on merge to main (gated)

A git `post-merge` hook only fires on *local* merges/pulls — it would **silently miss every GitHub PR merge** (the repo's `main` history shows a mix of PR merges and local merges). So the trigger is **not** a git hook. (This also avoids disturbing the existing `.githooks/post-commit` Kindle hook and the prior `core.hooksPath` fragility.)

Instead: a **launchd deploy-watcher** that polls `origin/main`. It catches both paths uniformly — a local merge that gets pushed, or a PR merged on GitHub, both move `origin/main`. Trade-off vs. a hook: deploy happens on the poll interval (~5 min), not the instant of merge — invisible for a personal system.

```
launchd: com.selene.prod.deploy-watcher  (every 5 min)
   │
   ├─ git fetch origin
   ├─ origin/main SHA == ~/selene-prod/.deployed-sha ?  ── yes ──▶ do nothing
   │                                                   ── no ───┐
   ▼                                                            ▼
   Build from a CLEAN export of origin/main (git archive → temp dir → npm ci → tsc)
   │   (NEVER the dirty dev working tree)
   ▼
   Build succeeded? ── NO ──▶ ABORT. Prod keeps last-good dist/. Notify "DEPLOY FAILED — prod still on <old sha>".
        │ YES
        ▼
   Archive current dist/ → ~/selene-prod/releases/<old-sha>/
   rsync dist/ + package.json + lock → ~/selene-prod   (rsync EXCLUDES .env — never clobbered)
   npm install --omit=dev in ~/selene-prod
   restart com.selene.prod.* agents → health check :5678
   write new SHA to .deployed-sha → notify "deployed <sha> @ HH:MM"
```

### Safety properties

1. **Build-gated** — broken code never reaches prod; prod stays on last-known-good `dist/`.
2. **Clean-source build** — builds from `origin/main`, never uncommitted dev edits.
3. **`.env` preserved** — prod secrets/paths (`SELENE_VAULT_PATH`, `SELENE_API_TOKEN`, APNs, TRMNL) survive every deploy untouched (rsync exclude).
4. **Observable** — every deploy, success *or* failure, sends a notification. Prod can never silently stop updating without you knowing. (This is the key mitigation for "non-engineer + auto-deploy": the likeliest failure is prod *silently not updating*, not broken code reaching it.)

---

## One-time cutover (retiring today's agents safely)

Today there are **11** loaded `com.selene.*` agents (server, process-llm, distill-essences, export-obsidian, daily-summary, send-digest, eink-ingest, voice-ingest, synthesize-topics, folio-feedback, agent-manager), all running from `~/selene` via ts-node against the real DB. The unrelated `com.chaseeasterling.selene-docs` is left alone.

```
Step 0  Build initial ~/selene-prod from current origin/main (tsc → dist/, npm install, write .env via script)
Step 1  Generate parallel prod plists: com.selene.*  ──▶  com.selene.prod.*
            • ProgramArguments:  npx ts-node src/x.ts   ──▶   node ~/selene-prod/dist/x.js
            • WorkingDirectory:  ~/selene               ──▶   ~/selene-prod
            • Std{Out,Err}Path:  ~/selene/logs          ──▶   ~/selene-prod/logs
            • EnvironmentVariables: + SELENE_ENV=production
Step 2  ATOMIC SWAP (port-5678 danger zone):
            launchctl bootout  ALL old com.selene.*       ← unload OLD first
            launchctl bootstrap ALL new com.selene.prod.* ← then load NEW
        (never both bound to :5678 / both processing real DB simultaneously)
Step 3  Verify: curl :5678/health  +  launchctl list | grep selene.prod  (expect 11 + watcher)
Step 4  ~/selene is now free — edit it freely; it only touches the dev DB.
```

**Single source of truth for the agent inventory:** rather than committing 11 duplicate `*.prod.plist` files (which drift), `install-prod.sh` *generates* prod plists from the canonical `launchd/*.plist` by string-substitution at deploy time. The committed plists keep their `~/selene` + ts-node + src form (so the existing `launchd-auditor` checks remain valid for the source form); `install-prod.sh` transforms them. This respects the existing `launchd-auditor` sync invariant instead of doubling it.

---

## Dev sandbox data

> **Revised during implementation (2026-05-28).** The original design said the dev DB
> would be a *sanitized copy of real data*. Implementation found this is **infeasible
> and unsafe** in this codebase, so the dev sandbox uses **fictional fixtures** instead.
> Three independent reasons:
> 1. **Startup guard** — `src/lib/db.ts:14-15` throws unless `_selene_metadata.environment='development'`; the real DB has no such marker, so a literal copy of real→dev fails to boot by design.
> 2. **Schema divergence** — the real DB has ~45 tables; `create-dev-db.sh` builds ~20 bespoke ones. They are not interchangeable.
> 3. **Anonymizer scope** — `src/lib/anonymize.ts` only scrubs *structured* PII (email/phone/URL/UUID + optional NER names). It cannot remove the *substance* of a personal ADHD journal, which is the sensitive part. Wrapping it would ship a false sense of safety.

- **DB:** `~/selene-data-dev/selene.db` — **fictional fixtures**, not real data. A 541-note fictional dev DB already exists and works (created 2026-02-21, marked `environment='development'`).
  - *Gap (pre-existing):* the fixture generators documented in `scripts/CLAUDE.md` (`seed-dev-data.ts`, `generate-dev-fixture.py`, `reset-dev-data.sh`) **do not exist on disk** — so the dev DB cannot currently be regenerated. Reconstructing the fictional-fixture generators is a **separate follow-up** (not part of the prod/dev split). `scripts/CLAUDE.md` is stale and should be corrected when that happens.
- **Vault:** `~/selene-data-dev/vault` — a throwaway scratch vault. Dev Obsidian export never writes the real iCloud vault.
- Config routes all dev paths to `~/selene-data-dev/*` and disables digest/TRMNL/Apple Notes in dev (verified: `SELENE_ENV=development` → dev DB + scratch vault, `appleNotes=false`, `trmnl=false`).
- *Aside:* the `test` env tier is effectively dead — `config.ts:10-11` loads `.env.development` with `override:true` whenever `SELENE_ENV !== 'production'`, clobbering a CLI `SELENE_ENV=test`. `development` and `production` both work; the split does not rely on `test`.

---

## iPad apps (work in `~/SeleneMarkup` — a SEPARATE repo)

| | Prod app | Dev app |
|---|---|---|
| Bundle ID | `com.selene.markup` | `com.selene.markup.dev` |
| Display name | **Selene** | **Selene Dev** |
| Default `baseURL` | `http://<Mac-LAN-IP>:5678` | `http://<Mac-LAN-IP>:5679` |
| Icon | normal | tinted/badged to distinguish |
| Coexist on iPad | ✅ | ✅ |

Implemented via a second **xcodegen target** in `~/SeleneMarkup/project.yml`; `redeploy.sh` gains a `--prod` / `--dev` flag (default `--prod`). **This is the only part of the design outside the `selene` repo** — the design records *what* and *where*; the edits happen in `~/SeleneMarkup`, preserving the deliberate repo boundary.

---

## Rollback

```
~/selene-prod/
  dist/                  ← current live build
  releases/<sha>/        ← last N built dist/ snapshots (archived on each deploy)
  .deployed-sha          ← what's live now

./scripts/rollback-prod.sh [sha]
  → swap dist/ back to releases/<sha>/ (default: previous), restart agents, health check, notify
```

Because every deploy archives the prior `dist/`, recovering from a bad release is a ~5-second `dist/` swap — no rebuild, no git surgery.

---

## Claude Code hooks affected

| Hook | Status | Action |
|---|---|---|
| **PreToolUse** — blocks Edit/Write on `\.env$` / `selene\.db` | keep as-is | Prod `.env` must be created by the cutover *script* (heredoc/`cp`), not Claude's Edit/Write tool (the hook rejects it). Implementation constraint, not a change. |
| **PostToolUse** `launchd-sync` reminder (matcher `launchd/.*\.plist` / `install-launchd.sh`) | **update** | Add `scripts/install-prod.sh` to the matcher. The new `deploy-watcher.plist` is already caught by `launchd/.*\.plist$`. |
| **`launchd-auditor`** agent (`.claude/agents/launchd-auditor.md`) | **update** | Teach it the prod/dev model: `deploy-watcher` is infra with **no** workflow (exclude from 1:1 cross-check); prod plists are **generated, not committed**; `install-prod.sh` is a second sync target. Otherwise it reports false drift. |

---

## Risk table

| Risk | Mitigation |
|---|---|
| Deploy clobbers prod `.env` | `rsync` excludes `.env`; cutover writes it once, deploys never touch it |
| Double-bind on :5678 during cutover | `bootout` old agents *before* `bootstrap` new (atomic swap) |
| Build from dirty dev tree | Watcher builds from `git archive origin/main`, never the working tree |
| Prod silently stops updating | Every deploy success **and** failure sends a notification |
| `calendar.ts` sibling-binary path breaks under `dist/` | Audit at build time; resolve via env var if core, else leave |
| Native `better-sqlite3` arch mismatch | Prod `npm install` on same Mac/arch — addon rebuilds correctly |
| Dev accidentally writes real vault/DB | Dev `.env` pins `SELENE_ENV=development`; config routes all paths to `~/selene-data-dev/*` |
| Deploy machinery itself is buggy | Deploy script takes `--target`; first prove the full cycle against `~/selene-prod-test` (fake DB) before the real cutover |

---

## Scope (what gets built)

1. `npm run build` script; verify `tsc` emits a complete `dist/`.
2. `scripts/deploy-prod.sh` — build-gate, clean-source build, archive prior release, rsync (preserve `.env`), `npm install`, restart prod agents, health check, notify. Supports `--target` for testing.
3. `scripts/rollback-prod.sh`.
4. `scripts/install-prod.sh` — generate `com.selene.prod.*` plists from canonical `launchd/*.plist`.
5. `launchd/com.selene.prod.deploy-watcher.plist` — the poller (every 5 min).
6. One-time cutover runbook (build initial `~/selene-prod` → bootout old → bootstrap prod → verify).
7. Initial `~/selene-prod/.env` (prod paths/secrets) — created by script, not Claude Edit/Write.
8. **(separate repo `~/SeleneMarkup`)** second xcodegen target + `redeploy.sh --prod/--dev`.
9. Docs: user guide for "how releases work"; update PROJECT-STATUS; diagram sync.
10. Update `.claude/settings.json` launchd-sync matcher + `launchd-auditor` agent to understand the prod/dev model.

---

## How this maps to industry practice (for context)

| Concept | Typical team | Selene (this design) |
|---|---|---|
| Environment separation | dev / staging / prod | dev / prod (staging skipped — YAGNI for solo) |
| Where prod runs | cloud servers, many machines | one Mac, via launchd |
| CI/CD engine | GitHub Actions / Jenkins on rented servers | launchd poller on the Mac |
| Build artifact | compiled/bundled, frozen | `tsc → dist/`, frozen in `~/selene-prod` |
| Deploy on merge | yes (CD) | yes (gated deploy-watcher) |
| Anonymized prod data in dev | common, often legally required | yes |
| Dev/prod mobile builds | yes (separate bundle IDs) | yes (`com.selene.markup[.dev]`) |
| Rollback | automated | scripted (`rollback-prod.sh`) |

The architecture would be immediately familiar to any professional developer as "local dev → CI/CD → prod with environment isolation," collapsed onto one machine.
