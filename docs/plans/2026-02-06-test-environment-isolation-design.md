# Test Environment Isolation Design

**Date:** 2026-02-06
**Status:** Done
**Completed:** 2026-02-06
**Topic:** infrastructure

---

## Problem

Claude Code currently has access to the production database at `~/selene-data/selene.db` containing personal notes, threads, and conversations. Development and testing should never touch this data, but test data needs to be realistic enough to reproduce production bugs.

---

## Solution

A complete test environment with:
- Anonymized snapshot of production data (realistic patterns, no personal content)
- Separate paths for all data stores (SQLite, LanceDB, Obsidian vault, digests)
- Environment-based switching between production and test modes
- On-demand script to refresh anonymized data from production

---

## Test Environment Paths

| Component | Production | Test |
|-----------|------------|------|
| SQLite DB | `~/selene-data/selene.db` | `selene/data-test/selene.db` |
| LanceDB vectors | `~/selene-data/vectors.lance` | `selene/data-test/vectors.lance` |
| Obsidian vault | `selene/vault/` | `selene/data-test/vault/` |
| Digests | `selene/data/digests/` | `selene/data-test/digests/` |
| iMessage | Sends to phone | Writes to file only |

---

## Anonymization Script

**Script:** `scripts/create-test-db.sh`

**What it does:**
1. Copies production SQLite to `data-test/selene.db`
2. Runs SQL transformations to scrub personal content
3. Regenerates embeddings for anonymized content (via Ollama)
4. Copies LanceDB and rebuilds with anonymized vectors

### Anonymization Rules

| Table | Field | Transformation |
|-------|-------|----------------|
| `raw_notes` | title | `"Note " \|\| printf('%05d', id)` |
| `raw_notes` | content | Lorem ipsum matching original word count |
| `processed_notes` | concepts | `"concept_" \|\| row_number` |
| `processed_notes` | summary | Generic summary text |
| `threads` | name | `"Thread " \|\| printf('%03d', id)` |
| `threads` | summary | `"Thread about concept_X and concept_Y"` |
| `chat_sessions` | All fields | Truncate table entirely |
| `conversations` | All fields | Truncate table entirely |
| `conversation_memories` | All fields | Truncate table entirely |

### What Stays Intact
- All timestamps, IDs, foreign keys
- Status flags and processing states
- Association scores and relationships
- Note/thread counts and structure

### Runtime
~2-5 minutes depending on note count (embedding regeneration is the slow part)

---

## Environment Switching

A single environment variable controls everything:

```bash
SELENE_ENV=test  # or "production" (default)
```

### Config Behavior

When `SELENE_ENV=test`, `src/lib/config.ts` returns:
- `dbPath` → `selene/data-test/selene.db`
- `vectorsPath` → `selene/data-test/vectors.lance`
- `vaultPath` → `selene/data-test/vault/`
- `digestsPath` → `selene/data-test/digests/`
- `imessageEnabled` → `false` (writes to file instead)

### Usage

```bash
# Run any workflow in test mode
SELENE_ENV=test npx ts-node src/workflows/process-llm.ts

# Or export for entire session
export SELENE_ENV=test
```

### SeleneChat
Already uses `data-test/` path when running as CLI build (not .app bundle), so no changes needed.

---

## Claude Code Isolation

### Default to Test Mode

Create `.env.development` at project root:
```bash
SELENE_ENV=test
SELENE_DB_PATH=/Users/chaseeasterling/Documents/GitHub/selene/data-test/selene.db
```

Claude Code and development tools will source this automatically.

### Fail-Safe Protection

The anonymization script adds a marker to the test database:
- Table: `_selene_metadata`
- Row: `key = 'environment'`, `value = 'test'`

When `SELENE_ENV=test`, `config.ts` validates this marker exists. If you accidentally point test mode at production, it fails immediately with a clear error:

```
Error: SELENE_ENV=test but database is not a test database.
Expected _selene_metadata.environment = 'test'.
Run ./scripts/create-test-db.sh to create a test database.
```

---

## Implementation Tasks

### Files to Create
1. `scripts/create-test-db.sh` - Anonymization script
2. `.env.development` - Test environment variables
3. `data-test/.gitkeep` - Ensure directory exists (contents gitignored)

### Files to Modify
1. `src/lib/config.ts` - Add environment switching logic, test paths
2. `src/lib/lancedb.ts` - Use config for vector path instead of deriving
3. `src/workflows/send-digest.ts` - Write to file when iMessage disabled
4. `SeleneChat/.../ObsidianService.swift` - Use config-based vault path
5. `.gitignore` - Ensure `data-test/` contents are ignored

### Database Changes
1. Add `_selene_metadata` table with `environment` flag
2. Anonymization script sets `environment = 'test'`
3. Config validates this flag on startup in test mode

---

## Acceptance Criteria

- [ ] `./scripts/create-test-db.sh` creates anonymized copy in under 5 minutes
- [ ] All workflows work with `SELENE_ENV=test`
- [ ] SeleneChat dev builds use test database
- [ ] Running test workflows never touches `~/selene-data/`
- [ ] Digest workflow writes to file instead of sending iMessage
- [ ] Obsidian export goes to `data-test/vault/`
- [ ] Accidental production access fails fast with clear error

---

## ADHD Check

- [x] **Reduces friction?** Yes - one command to create test env, automatic switching
- [x] **Makes things visible?** Yes - clear error messages if misconfigured
- [x] **Externalizes cognition?** Yes - don't have to remember to switch modes

---

## Scope Check

- [x] Less than 1 week of focused work
- [x] No external dependencies
- [x] Clear boundaries (no feature creep)

---


## Quick Start Guide

### Mac Mini (has production database)

```bash
# Pull latest changes
git pull origin main

# Create anonymized test database from production
./scripts/create-test-db.sh

# Verify it works
npm run start
# Should show: dbPath: ".../data-test/selene.db", env: "test"
```

### MacBook (no production database)

```bash
# Pull latest changes
git pull origin main

# Create synthetic test database (fake data)
./scripts/create-synthetic-test-db.sh

# Verify it works
npm run start
# Should show: dbPath: ".../data-test/selene.db", env: "test"
```

### How It Works

1. `.env.development` sets `SELENE_ENV=test` automatically
2. All paths route to `data-test/` directory
3. Fail-safe prevents accidental production access
4. iMessage digest writes to file instead of sending

### Scripts

| Script | Use Case |
|--------|----------|
| `scripts/create-test-db.sh` | Mac Mini - anonymizes production data |
| `scripts/create-synthetic-test-db.sh` | MacBook - creates fake test data |

### Switching to Production (Mac Mini only)

```bash
# Temporarily use production
SELENE_ENV=production npx ts-node src/workflows/process-llm.ts

# Or remove .env.development to default to production
```

---

## Related

- `src/lib/config.ts` - Primary configuration
- `scripts/cleanup-tests.sh` - Existing test cleanup (will be superseded)
- `.claude/OPERATIONS.md` - Testing procedures documentation
