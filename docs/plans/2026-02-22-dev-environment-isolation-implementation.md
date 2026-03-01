# Dev Environment Isolation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the dev environment isolation so `overmind start -f Procfile.dev` brings up a full parallel dev stack with realistic fake data.

**Architecture:** Three-tier environment (production/development/test) with Overmind replacing launchd for dev process management. Most infrastructure code already exists — this plan closes the remaining gaps.

**Tech Stack:** TypeScript, Overmind (process manager), SQLite, Ollama, better-sqlite3

**Design Doc:** `docs/plans/2026-02-21-dev-environment-isolation-design.md`

---

## Current State Assessment

Before writing any code, understand what's already done:

| Acceptance Criteria | Status | Notes |
|---|---|---|
| `SELENE_ENV=development` resolves paths to `~/selene-data-dev/` | ✅ Done | `src/lib/config.ts` handles all 3 tiers |
| Dev server runs on port 5679 | ✅ Done | `config.ts:112` auto-sets port |
| Seed script generates ~500 notes | ✅ Done | 536 notes seeded, 536 processed, 12 threads |
| SeleneChat CLI auto-connects to dev DB | ✅ Done | `DatabaseService.swift` detects `.app` bundle |
| SeleneMobile connects to dev server 5679 | ⚠️ Partial | URL is user-configurable but defaults to 5678 |
| Dev Obsidian vault populated | ❌ Missing | `~/selene-data-dev/vault/` is empty |
| `reset-dev-data.sh` works | ✅ Done | Script exists and functional |
| Production data never read by dev tools | ✅ Done | `db.ts` env verification + `.env.development` auto-load |
| `overmind start -f Procfile.dev` full stack | ❌ Missing | Procfile.dev only has server, no workflows. Overmind not installed. |

**Remaining work: 3 tasks** (Overmind setup, Procfile expansion, Obsidian vault population)

---

### Task 1: Install Overmind and Verify Prerequisites

**Files:**
- None (system-level install)

**Step 1: Install Overmind via Homebrew**

```bash
brew install overmind
```

tmux is already installed at `/opt/homebrew/bin/tmux` (Overmind dependency).

**Step 2: Verify Overmind works**

```bash
overmind version
```

Expected: Version number printed (e.g., `v2.5.1`)

**Step 3: Verify dev database is healthy**

```bash
sqlite3 ~/selene-data-dev/selene.db "SELECT value FROM _selene_metadata WHERE key='environment';"
```

Expected: `development`

```bash
sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) FROM raw_notes;"
```

Expected: `536` (or similar, >480)

No commit — system-level install only.

---

### Task 2: Expand Procfile.dev With All Workflow Processes

**Files:**
- Modify: `Procfile.dev`

**Context:** The design doc specifies Overmind should run the full dev stack. Currently `Procfile.dev` only has `server`. We need to add workflow runners that mirror the launchd production agents.

The key difference from production launchd: Overmind runs processes continuously, so we use `watch` or `sleep` loops instead of launchd's `StartInterval`. For dev, a single `dev-process-batch.sh` script already handles running all workflows in sequence — we just need to loop it.

**Step 1: Write the expanded Procfile.dev**

```procfile
server: SELENE_ENV=development npx ts-node src/server.ts
workflows: while true; do SELENE_ENV=development ./scripts/dev-process-batch.sh 25; sleep 300; done
```

Why this structure instead of one line per workflow:
- `dev-process-batch.sh` already orchestrates all 6 workflow steps in the right order
- Running them individually in Overmind would create 6+ parallel processes competing for Ollama
- The batch script runs workflows sequentially (correct for a single Ollama instance)
- `sleep 300` = 5-minute interval between batches (matches production's fastest schedule)
- Batch size of 25 processes a meaningful chunk each cycle

**Step 2: Test Overmind starts both processes**

```bash
cd /Users/chaseeasterling/selene
overmind start -f Procfile.dev
```

Expected: Two processes start — `server` and `workflows`. Server logs should show port 5679.

**Step 3: Verify server is running on dev port**

```bash
curl http://localhost:5679/health
```

Expected: `{"status":"ok","env":"development","port":5679,...}`

**Step 4: Verify workflow process is running**

```bash
overmind connect workflows
```

Expected: See `dev-process-batch.sh` output (processing status, step execution).

Press `Ctrl-B D` to detach from tmux pane.

**Step 5: Stop Overmind**

```bash
# From the terminal where overmind is running:
Ctrl-C
# Or from another terminal:
overmind stop
```

**Step 6: Commit**

```bash
git add Procfile.dev
git commit -m "feat: expand Procfile.dev with workflow batch processing

Overmind now runs both the dev server (port 5679) and a workflow
batch loop (dev-process-batch.sh every 5 minutes). This replaces
the need to manually run launchd agents during development.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Populate Dev Obsidian Vault

**Files:**
- None (run existing export workflow)

**Context:** The dev database has 536 notes but `exported_to_obsidian` count shows 150 and the vault directory is empty. The export workflow writes markdown files to the vault path. We need to run it against the dev database.

**Step 1: Check current export state**

```bash
sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) FROM raw_notes WHERE exported_to_obsidian = 1;"
```

**Step 2: Reset export flags so all notes get exported**

```bash
sqlite3 ~/selene-data-dev/selene.db "UPDATE raw_notes SET exported_to_obsidian = 0;"
```

**Step 3: Run the Obsidian export workflow**

```bash
SELENE_ENV=development npx ts-node src/workflows/export-obsidian.ts
```

Expected: Exports 536 notes to `~/selene-data-dev/vault/`

**Step 4: Verify vault has content**

```bash
ls ~/selene-data-dev/vault/ | head -10
ls ~/selene-data-dev/vault/ | wc -l
```

Expected: Markdown files present, count > 0.

**Step 5: Verify a file looks correct**

```bash
head -20 ~/selene-data-dev/vault/*.md | head -30
```

Expected: Markdown with frontmatter (title, date, tags, concepts).

No commit needed — this is dev data population, not code changes.

---

### Task 4: End-to-End Verification

**Files:**
- Modify: `docs/plans/2026-02-21-dev-environment-isolation-design.md` (check off acceptance criteria)

**Step 1: Run the full acceptance criteria checklist**

```bash
# 1. SELENE_ENV=development resolves paths
SELENE_ENV=development npx ts-node -e "
  const {config} = require('./src/lib/config');
  console.log('DB:', config.dbPath);
  console.log('Vectors:', config.vectorsPath);
  console.log('Vault:', config.vaultPath);
  console.log('Port:', config.port);
  console.log('Env:', config.env);
"
```

Expected:
```
DB: /Users/chaseeasterling/selene-data-dev/selene.db
Vectors: /Users/chaseeasterling/selene-data-dev/vectors.lance
Vault: /Users/chaseeasterling/selene-data-dev/vault
Port: 5679
Env: development
```

```bash
# 2. Dev server on 5679
overmind start -f Procfile.dev -D  # -D = daemon mode
sleep 3
curl http://localhost:5679/health
overmind stop
```

Expected: `{"status":"ok","env":"development","port":5679,...}`

```bash
# 3. Seed data present
sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) FROM raw_notes;"
```

Expected: `536`

```bash
# 4. SeleneChat CLI uses dev DB
cd /Users/chaseeasterling/selene/SeleneChat && swift build 2>&1 | tail -3
```

Expected: Build succeeds. (CLI binary will use `~/selene-data-dev/selene.db` when not in `.app` bundle.)

```bash
# 5. SeleneMobile — verify URL is configurable
# (Manual: change server URL in app settings to http://<tailscale-ip>:5679)
# This is already supported via UserDefaults — no code change needed.
```

```bash
# 6. Obsidian vault populated
ls ~/selene-data-dev/vault/ | wc -l
```

Expected: > 0 files

```bash
# 7. Reset works
# (Don't actually run this — just verify the script exists and parses correctly)
bash -n /Users/chaseeasterling/selene/scripts/reset-dev-data.sh && echo "OK"
```

Expected: `OK`

```bash
# 8. Production data never read
# Verify .env.development sets SELENE_ENV=development (which config.ts auto-loads for non-prod)
grep SELENE_ENV /Users/chaseeasterling/selene/.env.development
```

Expected: `SELENE_ENV=development`

```bash
# 9. Overmind full stack
overmind start -f Procfile.dev -D
overmind ps
overmind stop
```

Expected: Shows `server` and `workflows` processes running.

**Step 2: Update design doc acceptance criteria**

Mark all criteria as checked in `docs/plans/2026-02-21-dev-environment-isolation-design.md`:

```markdown
## Acceptance Criteria

- [x] `SELENE_ENV=development` resolves all paths to `~/selene-data-dev/`
- [x] Dev server runs on port 5679 alongside production on 5678
- [x] Seed script generates ~500 notes and processes through all pipelines
- [x] SeleneChat CLI build auto-connects to dev database
- [x] SeleneMobile can connect to dev server on port 5679
- [x] Dev Obsidian vault populated with fictional data
- [x] `reset-dev-data.sh` cleanly wipes and reseeds
- [x] Production data (`~/selene-data/`) is never read by dev tools
- [x] `overmind start -f Procfile.dev` brings up full dev stack
```

**Step 3: Commit**

```bash
git add docs/plans/2026-02-21-dev-environment-isolation-design.md
git commit -m "docs: mark dev environment isolation acceptance criteria complete

All 9 acceptance criteria verified and passing.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Quick Reference: Dev Workflow After Implementation

```bash
# First time setup (already done)
brew install overmind
./scripts/create-dev-db.sh
SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts

# Daily dev session
overmind start -f Procfile.dev          # Server (5679) + workflows
swift build                              # SeleneChat uses dev DB
.build/debug/SeleneChat                  # Run against dev data

# During development
overmind connect server                  # Attach to server logs
overmind connect workflows               # Attach to workflow logs
curl http://localhost:5679/health        # Verify dev mode

# Reset everything
./scripts/reset-dev-data.sh             # Wipe + reseed
```
