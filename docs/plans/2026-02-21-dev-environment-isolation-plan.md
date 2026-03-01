# Dev Environment Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a full parallel development environment with fake data so Claude Code never accesses production data.

**Architecture:** Three environment tiers (production/development/test) with separate data roots. Development uses `~/selene-data-dev/` with Overmind for process management. Seed script generates ~500 fictional notes and processes them through all pipelines.

**Tech Stack:** TypeScript, SQLite (better-sqlite3), Overmind, Bash, Ollama

---

### Task 1: Add `development` environment tier to config.ts

**Files:**
- Modify: `src/lib/config.ts`

**Step 1: Write the failing test**

Create a quick manual test plan. The current config only knows `test` and `production`. After changes, `SELENE_ENV=development` should resolve paths to `~/selene-data-dev/`.

Run: `SELENE_ENV=development npx ts-node -e "import { config } from './src/lib/config'; console.log(JSON.stringify({ env: config.env, dbPath: config.dbPath, vectorsPath: config.vectorsPath, vaultPath: config.vaultPath, digestsPath: config.digestsPath, port: config.port }, null, 2))"`

Expected: Currently fails or shows production paths (wrong).

**Step 2: Update config.ts to support three tiers**

In `src/lib/config.ts`, replace the current environment logic:

```typescript
import { join } from 'path';
import { homedir } from 'os';
import { config as loadEnv } from 'dotenv';

// Load environment variables from .env file
loadEnv();

// Load .env.development when not explicitly set to production
// (SeleneChat sets SELENE_ENV=production when launching workflows)
if (process.env.SELENE_ENV !== 'production') {
  loadEnv({ path: join(__dirname, '../..', '.env.development'), override: true });
}

const projectRoot = join(__dirname, '../..');

// Environment tiers: 'production', 'development', 'test'
const seleneEnv = process.env.SELENE_ENV || 'production';
const isTestEnv = seleneEnv === 'test';
const isDevEnv = seleneEnv === 'development';
const devDataRoot = join(homedir(), 'selene-data-dev');

// Path resolution based on environment tier
function getDbPath(): string {
  if (process.env.SELENE_DB_PATH) return process.env.SELENE_DB_PATH;
  if (isTestEnv) return join(projectRoot, 'data-test/selene.db');
  if (isDevEnv) return join(devDataRoot, 'selene.db');
  return join(homedir(), 'selene-data/selene.db');
}

function getVectorsPath(): string {
  if (process.env.SELENE_VECTORS_PATH) return process.env.SELENE_VECTORS_PATH;
  if (isTestEnv) return join(projectRoot, 'data-test/vectors.lance');
  if (isDevEnv) return join(devDataRoot, 'vectors.lance');
  return join(homedir(), 'selene-data/vectors.lance');
}

function getVaultPath(): string {
  if (process.env.SELENE_VAULT_PATH) return process.env.SELENE_VAULT_PATH;
  if (isTestEnv) return join(projectRoot, 'data-test/vault');
  if (isDevEnv) return join(devDataRoot, 'vault');
  return join(projectRoot, 'vault');
}

function getDigestsPath(): string {
  if (process.env.SELENE_DIGESTS_PATH) return process.env.SELENE_DIGESTS_PATH;
  if (isTestEnv) return join(projectRoot, 'data-test/digests');
  if (isDevEnv) return join(devDataRoot, 'digests');
  return join(projectRoot, 'data', 'digests');
}

function getLogsPath(): string {
  if (process.env.SELENE_LOGS_PATH) return process.env.SELENE_LOGS_PATH;
  if (isDevEnv) return join(devDataRoot, 'logs');
  return join(projectRoot, 'logs');
}
```

Update the `config` export object:

```typescript
export const config = {
  // Environment
  env: seleneEnv as 'production' | 'development' | 'test',
  isTestEnv,
  isDevEnv,

  // Paths - environment-aware
  dbPath: getDbPath(),
  vectorsPath: getVectorsPath(),
  vaultPath: getVaultPath(),
  digestsPath: getDigestsPath(),
  logsPath: getLogsPath(),
  projectRoot,

  // ... rest unchanged, but update port default:
  port: parseInt(process.env.PORT || (isDevEnv ? '5679' : '5678'), 10),

  // Apple Notes digest - disabled in test/dev mode
  appleNotesDigestEnabled: !isTestEnv && !isDevEnv && process.env.APPLE_NOTES_DIGEST_ENABLED !== 'false',

  // TRMNL - disabled in test/dev mode
  trmnlDigestEnabled: !isTestEnv && !isDevEnv && !!process.env.TRMNL_WEBHOOK_URL && process.env.TRMNL_DIGEST_ENABLED !== 'false',

  // ... everything else unchanged
};
```

**Step 3: Verify the changes work**

Run: `SELENE_ENV=development npx ts-node -e "import { config } from './src/lib/config'; console.log(JSON.stringify({ env: config.env, dbPath: config.dbPath, vectorsPath: config.vectorsPath, vaultPath: config.vaultPath, digestsPath: config.digestsPath, logsPath: config.logsPath, port: config.port }, null, 2))"`

Expected output (paths should point to `~/selene-data-dev/`):
```json
{
  "env": "development",
  "dbPath": "/Users/<user>/selene-data-dev/selene.db",
  "vectorsPath": "/Users/<user>/selene-data-dev/vectors.lance",
  "vaultPath": "/Users/<user>/selene-data-dev/vault",
  "digestsPath": "/Users/<user>/selene-data-dev/digests",
  "logsPath": "/Users/<user>/selene-data-dev/logs",
  "port": 5679
}
```

Also verify production still works:
Run: `SELENE_ENV=production npx ts-node -e "import { config } from './src/lib/config'; console.log(JSON.stringify({ env: config.env, dbPath: config.dbPath, port: config.port }, null, 2))"`

Expected: `env: "production"`, `dbPath` points to `~/selene-data/selene.db`, `port: 5678`

**Step 4: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat: add development environment tier to config

Three tiers: production (~/selene-data/), development (~/selene-data-dev/),
test (data-test/). Dev server defaults to port 5679."
```

---

### Task 2: Update .env.development

**Files:**
- Modify: `.env.development`

**Step 1: Update .env.development to use development tier**

Replace contents of `.env.development`:

```bash
# Development Environment Configuration
# Auto-loaded by config.ts for non-production environments
# Claude Code uses these settings by default

# Development environment — uses ~/selene-data-dev/ for all data
SELENE_ENV=development

# Dev server runs on port 5679 (production uses 5678)
# PORT=5679  # (auto-set by config.ts when SELENE_ENV=development)

# Explicit path overrides (optional — these are the defaults for development):
# SELENE_DB_PATH=~/selene-data-dev/selene.db
# SELENE_VECTORS_PATH=~/selene-data-dev/vectors.lance
# SELENE_VAULT_PATH=~/selene-data-dev/vault
# SELENE_DIGESTS_PATH=~/selene-data-dev/digests
# SELENE_LOGS_PATH=~/selene-data-dev/logs
```

**Step 2: Verify auto-loading works**

Run: `npx ts-node -e "import { config } from './src/lib/config'; console.log(config.env, config.dbPath)"`

Expected: `development /Users/<user>/selene-data-dev/selene.db` (because `.env.development` sets `SELENE_ENV=development` and config.ts auto-loads it for non-production)

**Step 3: Commit**

```bash
git add .env.development
git commit -m "chore: update .env.development to use development tier"
```

---

### Task 3: Update health endpoint to show environment

**Files:**
- Modify: `src/server.ts`

**Step 1: Update health endpoint**

In `src/server.ts`, change the health check handler:

```typescript
server.get('/health', async () => {
  return {
    status: 'ok',
    env: config.env,
    port: config.port,
    timestamp: new Date().toISOString(),
  };
});
```

Make sure `config` is imported at the top of server.ts (it likely already is).

**Step 2: Test it**

Start the dev server: `SELENE_ENV=development npx ts-node src/server.ts &`

Run: `curl -s http://localhost:5679/health | npx -y json`

Expected: `{ "status": "ok", "env": "development", "port": 5679, "timestamp": "..." }`

Kill the test server: `kill %1`

**Step 3: Commit**

```bash
git add src/server.ts
git commit -m "feat: include environment and port in health endpoint"
```

---

### Task 4: Update SeleneChat DatabaseService for dev paths

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`

**Step 1: Update defaultDatabasePath()**

Change the CLI detection to point to `~/selene-data-dev/` instead of `~/selene/data-test/`:

```swift
private static func defaultDatabasePath() -> String {
    if isRunningFromAppBundle() {
        // Production: user's real notes
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene-data/selene.db")
            .path
    } else {
        // Development: fake test data (never production)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene-data-dev/selene.db")
            .path
    }
}
```

**Step 2: Build and verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -5`

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift
git commit -m "feat: SeleneChat CLI builds use ~/selene-data-dev/ for dev data"
```

---

### Task 5: Update db.ts metadata check for development tier

**Files:**
- Modify: `src/lib/db.ts`

**Step 1: Update environment safety check**

The current `db.ts` has a safety check that verifies `_selene_metadata.environment = 'test'` when `SELENE_ENV=test`. We need the same check for `development`:

In `src/lib/db.ts`, update the safety check block (lines 14-48):

```typescript
// Fail-safe: Verify non-production environment is using correct database
if (config.isTestEnv || config.isDevEnv) {
  const expectedEnv = config.env; // 'test' or 'development'
  try {
    const result = db.prepare(
      "SELECT value FROM _selene_metadata WHERE key = 'environment'"
    ).get() as { value: string } | undefined;

    if (!result || result.value !== expectedEnv) {
      logger.error(
        { dbPath: config.dbPath, expected: expectedEnv, actual: result?.value },
        `SELENE_ENV=${expectedEnv} but database environment mismatch. Run scripts/create-dev-db.sh first.`
      );
      throw new Error(
        `SELENE_ENV=${expectedEnv} but database is not marked as ${expectedEnv} environment.\n` +
        `Expected _selene_metadata.environment = '${expectedEnv}'.\n` +
        `Run scripts/create-dev-db.sh to create the database.`
      );
    }

    logger.info({ env: expectedEnv }, 'Environment verified');
  } catch (err: unknown) {
    if (err instanceof Error && err.message.includes('no such table')) {
      logger.error(
        { dbPath: config.dbPath },
        `SELENE_ENV=${expectedEnv} but _selene_metadata table not found. Run scripts/create-dev-db.sh first.`
      );
      throw new Error(
        `SELENE_ENV=${expectedEnv} but _selene_metadata table not found.\n` +
        `Run scripts/create-dev-db.sh to create the database.`
      );
    }
    throw err;
  }
}
```

**Step 2: Commit**

```bash
git add src/lib/db.ts
git commit -m "feat: environment safety check supports development tier"
```

---

### Task 6: Create dev database initialization script

**Files:**
- Create: `scripts/create-dev-db.sh`

**Step 1: Write the script**

This creates a fresh database at `~/selene-data-dev/selene.db` with the full schema but no data. The schema is extracted from the production database structure.

```bash
#!/bin/bash
#
# create-dev-db.sh - Create empty development database with full schema
#
# Creates ~/selene-data-dev/ directory structure and initializes
# an empty SQLite database with all tables. Does NOT copy production data.
#
# Usage: ./scripts/create-dev-db.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEV_ROOT="$HOME/selene-data-dev"
DEV_DB="$DEV_ROOT/selene.db"

echo -e "${GREEN}=== Selene Dev Database Creator ===${NC}"
echo ""

# Check if dev DB already exists
if [ -f "$DEV_DB" ]; then
  echo -e "${YELLOW}Dev database already exists at $DEV_DB${NC}"
  read -p "Overwrite? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
  rm -f "$DEV_DB" "$DEV_DB-journal" "$DEV_DB-wal" "$DEV_DB-shm"
fi

# Create directory structure
echo -e "${GREEN}Creating directory structure...${NC}"
mkdir -p "$DEV_ROOT"
mkdir -p "$DEV_ROOT/vault"
mkdir -p "$DEV_ROOT/digests"
mkdir -p "$DEV_ROOT/logs"
mkdir -p "$DEV_ROOT/voice-memos"

# Create database with full schema
echo -e "${GREEN}Creating database schema...${NC}"
sqlite3 "$DEV_DB" <<'SQL'
-- Core tables
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    source_type TEXT DEFAULT 'drafts',
    word_count INTEGER DEFAULT 0,
    character_count INTEGER DEFAULT 0,
    tags TEXT,
    created_at DATETIME NOT NULL,
    imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME,
    exported_at DATETIME,
    status TEXT DEFAULT 'pending',
    exported_to_obsidian INTEGER DEFAULT 0,
    test_run TEXT DEFAULT NULL,
    status_apple TEXT DEFAULT 'pending_apple',
    processed_at_apple DATETIME,
    inbox_status TEXT DEFAULT 'pending',
    suggested_type TEXT,
    suggested_project_id INTEGER,
    tasks_extracted BOOLEAN DEFAULT 0,
    tasks_extracted_at TEXT,
    source_uuid TEXT DEFAULT NULL,
    calendar_event TEXT
);
CREATE INDEX idx_raw_notes_status ON raw_notes(status);
CREATE INDEX idx_raw_notes_content_hash ON raw_notes(content_hash);
CREATE INDEX idx_raw_notes_created_at ON raw_notes(created_at);
CREATE INDEX idx_raw_notes_exported ON raw_notes(exported_to_obsidian);
CREATE INDEX idx_raw_notes_test_run ON raw_notes(test_run);
CREATE INDEX idx_raw_notes_status_apple ON raw_notes(status_apple);
CREATE INDEX idx_raw_notes_inbox_status ON raw_notes(inbox_status);
CREATE INDEX idx_raw_notes_source_uuid ON raw_notes(source_uuid);

CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,
    concept_confidence TEXT,
    primary_theme TEXT,
    secondary_themes TEXT,
    theme_confidence REAL,
    sentiment_analyzed INTEGER DEFAULT 0,
    sentiment_data TEXT,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    sentiment_analyzed_at DATETIME,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    things_integration_status TEXT
        CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))
        DEFAULT 'pending',
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE INDEX idx_processed_notes_raw_id ON processed_notes(raw_note_id);
CREATE INDEX idx_processed_notes_sentiment ON processed_notes(sentiment_analyzed);

CREATE TABLE processed_notes_apple (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,
    concept_confidence TEXT,
    primary_theme TEXT,
    secondary_themes TEXT,
    theme_confidence REAL,
    sentiment_analyzed INTEGER DEFAULT 0,
    sentiment_data TEXT,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    sentiment_analyzed_at DATETIME,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processing_model TEXT DEFAULT 'apple_intelligence',
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE INDEX idx_processed_notes_apple_raw_id ON processed_notes_apple(raw_note_id);
CREATE INDEX idx_processed_notes_apple_sentiment ON processed_notes_apple(sentiment_analyzed);

CREATE TABLE note_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,
    model_version TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);
CREATE INDEX idx_embeddings_note ON note_embeddings(raw_note_id);

CREATE TABLE note_associations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    similarity_score REAL NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id),
    CHECK(note_a_id < note_b_id),
    CHECK(similarity_score >= 0.0 AND similarity_score <= 1.0)
);
CREATE INDEX idx_associations_a ON note_associations(note_a_id);
CREATE INDEX idx_associations_b ON note_associations(note_b_id);
CREATE INDEX idx_associations_score ON note_associations(similarity_score DESC);

-- Thread system
CREATE TABLE threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    why TEXT,
    summary TEXT,
    status TEXT DEFAULT 'active',
    note_count INTEGER DEFAULT 0,
    last_activity_at TEXT,
    emotional_charge REAL,
    momentum_score REAL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'paused', 'completed', 'abandoned'))
);
CREATE INDEX idx_threads_status ON threads(status);
CREATE INDEX idx_threads_activity ON threads(last_activity_at DESC);
CREATE INDEX idx_threads_momentum ON threads(momentum_score DESC);

CREATE TABLE thread_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    added_at TEXT DEFAULT CURRENT_TIMESTAMP,
    relevance_score REAL,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(thread_id, raw_note_id)
);
CREATE INDEX idx_thread_notes_thread ON thread_notes(thread_id);
CREATE INDEX idx_thread_notes_note ON thread_notes(raw_note_id);

CREATE TABLE thread_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,
    change_type TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (trigger_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL,
    CHECK(change_type IN ('note_added', 'merged', 'split', 'renamed', 'summarized', 'created'))
);
CREATE INDEX idx_thread_history_thread ON thread_history(thread_id);

CREATE TABLE thread_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    things_task_id TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    UNIQUE(thread_id, things_task_id)
);
CREATE INDEX idx_thread_tasks_thread ON thread_tasks(thread_id);
CREATE INDEX idx_thread_tasks_things ON thread_tasks(things_task_id);

-- Chat system
CREATE TABLE chat_sessions (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    message_count INTEGER NOT NULL,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    compression_state TEXT NOT NULL DEFAULT 'full',
    compressed_at TEXT,
    full_messages_json TEXT,
    summary_text TEXT
);
CREATE INDEX idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
CREATE INDEX idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);

CREATE TABLE conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_conversations_session ON conversations(session_id);
CREATE INDEX idx_conversations_created ON conversations(created_at);

CREATE TABLE conversation_memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    source_session_id TEXT,
    embedding BLOB,
    memory_type TEXT CHECK(memory_type IN ('preference', 'fact', 'pattern', 'context')),
    confidence REAL DEFAULT 1.0,
    last_accessed TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_memories_type ON conversation_memories(memory_type);
CREATE INDEX idx_memories_confidence ON conversation_memories(confidence);
CREATE INDEX idx_memories_last_accessed ON conversation_memories(last_accessed);

-- Analytics & patterns
CREATE TABLE sentiment_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    processed_note_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    stress_indicators INTEGER DEFAULT 0,
    key_emotions TEXT,
    adhd_markers TEXT,
    analysis_confidence REAL,
    analyzed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (processed_note_id) REFERENCES processed_notes(id),
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE INDEX idx_sentiment_history_note_ids ON sentiment_history(processed_note_id, raw_note_id);

CREATE TABLE detected_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_name TEXT,
    description TEXT,
    pattern_data TEXT,
    insights TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE note_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    note_id INTEGER NOT NULL,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    topic TEXT,
    token_count INTEGER NOT NULL,
    embedding BLOB,
    created_at TEXT NOT NULL,
    UNIQUE (note_id, chunk_index)
);
CREATE INDEX index_note_chunks_on_note_id ON note_chunks(note_id);

-- Device tokens
CREATE TABLE device_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'ios',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Environment metadata
CREATE TABLE _selene_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO _selene_metadata (key, value) VALUES ('environment', 'development');
INSERT INTO _selene_metadata (key, value) VALUES ('created_at', datetime('now'));
SQL

echo ""
echo -e "${GREEN}=== Dev Environment Ready ===${NC}"
echo ""
echo "Directory: $DEV_ROOT"
echo "Database:  $DEV_DB"
echo ""
sqlite3 "$DEV_DB" "SELECT 'Tables: ' || COUNT(*) FROM sqlite_master WHERE type='table';"
echo ""
echo "Next step: Run the seed script to populate with fake data:"
echo "  SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts"
```

**Step 2: Make executable and run**

Run: `chmod +x scripts/create-dev-db.sh && ./scripts/create-dev-db.sh`

Expected: Creates `~/selene-data-dev/` with empty database, all tables, metadata marked as `development`.

**Step 3: Verify the dev database works with config**

Run: `SELENE_ENV=development npx ts-node -e "import { db } from './src/lib/db'; console.log('DB connected'); const tables = db.prepare(\"SELECT name FROM sqlite_master WHERE type='table'\").all(); console.log('Tables:', tables.length)"`

Expected: `DB connected` then `Tables: <number>` (should be ~20+).

**Step 4: Commit**

```bash
git add scripts/create-dev-db.sh
git commit -m "feat: add dev database creation script

Creates ~/selene-data-dev/ directory structure and empty SQLite database
with full schema, marked as development environment."
```

---

### Task 7: Create Procfile.dev and .overmind.env

**Files:**
- Create: `Procfile.dev`
- Create: `.overmind.env`

**Step 1: Install Overmind**

Run: `brew install overmind tmux`

**Step 2: Create Procfile.dev**

```procfile
server: npx ts-node src/server.ts
```

Note: Workflows (process-llm, detect-threads, etc.) are run on-demand during dev, not as long-running processes. They're interval-based in production (launchd), and for dev you trigger them manually when needed.

**Step 3: Create .overmind.env**

```bash
SELENE_ENV=development
```

**Step 4: Test Overmind starts the dev server**

Run: `overmind start -f Procfile.dev -D` (starts in background/daemon mode)

Wait 3 seconds, then:
Run: `curl -s http://localhost:5679/health`

Expected: `{"status":"ok","env":"development","port":5679,"timestamp":"..."}`

Stop: `overmind quit`

**Step 5: Commit**

```bash
git add Procfile.dev .overmind.env
git commit -m "feat: add Overmind config for dev process management

Procfile.dev runs the dev server on port 5679.
Workflows are triggered manually during development."
```

---

### Task 8: Create seed data fixture generator

**Files:**
- Create: `scripts/generate-dev-fixture.ts`
- Modify: `.gitignore` (add `fixtures/`)

**Step 1: Update .gitignore**

Add to `.gitignore`:
```
# Dev data fixtures (generated, not committed)
fixtures/
```

**Step 2: Create the fixture generator script**

Create `scripts/generate-dev-fixture.ts`. This generates a JSON file with ~500 fictional notes. The notes should be realistic enough to exercise thread detection, relationship computation, and daily briefings.

```typescript
/**
 * generate-dev-fixture.ts
 *
 * Generates a JSON fixture file with ~500 fictional notes spanning 3 months.
 * The notes follow a fictional ADHD persona managing multiple life domains.
 *
 * Usage: npx ts-node scripts/generate-dev-fixture.ts
 * Output: fixtures/dev-seed-notes.json
 */

import { mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';

interface SeedNote {
  title: string;
  content: string;
  created_at: string;
  tags: string[];
}

// Fictional persona: Alex, a software engineer with ADHD
// Domains: work (recipe app), learning (ceramics), health, personal, random

const DOMAINS = {
  work: {
    weight: 0.30, // 30% of notes
    topics: [
      { title: 'Recipe API endpoint design', tags: ['#work', '#recipeapp', '#api'], contentTemplates: [
        'Been thinking about the recipe API. Need endpoints for: search by ingredient, filter by cuisine, and a recommendation engine. The search should support fuzzy matching.',
        'Recipe app progress: Got the ingredient parser working. It can now handle "2 cups flour" and "a pinch of salt". Edge cases with fractions still need work.',
        'Standup notes: Showed the team the recipe recommendation prototype. They loved the "cook with what you have" feature. Need to add nutritional data next.',
        'Spent all morning debugging the recipe image upload. Turns out the compression was too aggressive and making everything look blurry. Fixed by using quality=85.',
        'Architecture decision: Going with PostgreSQL for the recipe database instead of MongoDB. Relational queries for ingredient matching are way more natural.',
        'Finally got the recipe search ranking right. Combining text relevance with popularity score and freshness. The results feel much more natural now.',
        'Code review feedback on the recipe parser: need better error handling for malformed ingredient strings. Added a fallback that treats the whole line as a note.',
        'Thinking about the recipe app onboarding flow. Users should be able to import recipes from URLs on the first screen. That gives immediate value.',
        'Performance issue: recipe search was slow with 10k+ recipes. Added an index on ingredients array and brought it down from 800ms to 40ms.',
        'Meeting notes: Product wants to add meal planning to the recipe app. I think it is a good idea but we need to scope it carefully. V1 should just be a weekly grid.',
      ]},
      { title: 'Sprint planning', tags: ['#work', '#sprint'], contentTemplates: [
        'Sprint planning: 3 stories this week. Recipe search improvements, user profile page, and the ingredient substitution feature. Feeling good about the scope.',
        'Sprint retro: We shipped everything planned. The ingredient substitution feature took longer than expected because of the data normalization work.',
        'Backlog grooming: Too many items in the backlog. Going to archive anything older than 3 months that nobody has mentioned. Clean slate.',
      ]},
      { title: 'Side project ideas', tags: ['#work', '#ideas'], contentTemplates: [
        'Random idea: what if the recipe app could generate grocery lists automatically? Group by store aisle. Would save so much time.',
        'Another recipe app idea: social features where you can follow friends and see what they are cooking this week. Like Strava but for cooking.',
        'Idea for recipe app: integration with smart kitchen devices. Imagine the app sending temperatures to your oven automatically.',
      ]},
    ],
  },
  learning: {
    weight: 0.20, // 20% of notes
    topics: [
      { title: 'Ceramics class', tags: ['#learning', '#ceramics'], contentTemplates: [
        'First ceramics class today! Learned about wedging clay to remove air bubbles. My hands are covered in clay and I love it. The instructor says consistency is everything.',
        'Ceramics: Threw my first bowl on the wheel. It is lopsided and the walls are uneven but I made it myself. The centering is the hardest part.',
        'Practiced trimming today. You flip the piece upside down and carve away the bottom. It is meditative. Lost track of time completely.',
        'Glazing day! Applied a celadon glaze to my bowl. The instructor showed how different thicknesses create different effects. Science meets art.',
        'Ceramics class: learned about kiln temperatures. Cone 6 vs cone 10. The chemistry of how glazes melt and interact is fascinating.',
        'My bowl came out of the kiln and it is beautiful! The celadon glaze turned out exactly the color I wanted. Small crack on the lip though.',
        'Started working on a set of mugs. Making matching pieces is way harder than single items. Getting consistent wall thickness is the challenge.',
        'Ceramics: Tried a new technique called sgraffito. You scratch through colored slip to reveal the clay underneath. Very satisfying.',
        'Wheel throwing is getting easier. I can center the clay in about 30 seconds now instead of 5 minutes. Muscle memory is building.',
        'Class project: making a teapot. The spout and handle are separate pieces that get attached. Everything has to be the same dryness or it cracks.',
      ]},
      { title: 'Reading and courses', tags: ['#learning', '#reading'], contentTemplates: [
        'Started reading "Thinking, Fast and Slow" by Kahneman. The concept of System 1 and System 2 thinking is really clicking with my ADHD experience.',
        'Podcast episode on deliberate practice. Key insight: it is not about hours spent, it is about practicing at the edge of your ability with immediate feedback.',
        'Finished the online course on design systems. Main takeaway: constraints breed creativity. Having fewer choices makes better design decisions.',
        'Reading about Japanese wabi-sabi philosophy. The beauty of imperfection. Feels relevant to both ceramics and life in general.',
        'Article about spaced repetition for learning. Going to try Anki for the ceramics terminology. So many technical terms to remember.',
      ]},
    ],
  },
  health: {
    weight: 0.20, // 20% of notes
    topics: [
      { title: 'ADHD management', tags: ['#health', '#adhd'], contentTemplates: [
        'ADHD observation: I notice I am most productive between 10am and 1pm. After lunch there is a crash. Need to protect that morning window.',
        'Talked to my psychiatrist about medication timing. Moving my dose 30 minutes earlier to see if it kicks in before my first meeting.',
        'ADHD win today: used the body doubling technique on a video call and powered through my entire to-do list. Need to do this more often.',
        'Struggling with task initiation today. Everything feels equally important and I cannot pick where to start. Going to try the 2-minute rule.',
        'Noticed a pattern: I hyperfocus on ceramics for 3 hours straight but cannot do 15 minutes of expense reports. It is not about willpower.',
        'ADHD realization: my "laziness" with dishes is actually executive function. Broke dish washing into a 3-step routine and it is way easier now.',
        'Brain dump: feeling overwhelmed by the number of open projects. Need to do a weekly review and get everything out of my head and into a system.',
        'The pomodoro technique is not working for me. 25 minutes is too short when I am in flow and too long when I am stuck. Trying flexible intervals.',
        'Great ADHD day. Started medication on time, did my morning routine, got through three deep work sessions. What made today different?',
        'Noticed I have been doom scrolling more this week. Usually a sign of understimulation. Need more challenging work or a new creative project.',
      ]},
      { title: 'Exercise and sleep', tags: ['#health', '#fitness'], contentTemplates: [
        'Morning run: 3 miles in 28 minutes. Legs felt heavy but my mind was clear after. Running is the best ADHD medication that is not medication.',
        'Sleep tracking: average 6.5 hours this week. Not great. Going to try the no screens after 9pm rule again. Last time it helped a lot.',
        'Started doing yoga on YouTube. 20 minutes in the morning. The breathing exercises help with anxiety more than I expected.',
        'Gym session: squats, deadlifts, bench. Feeling stronger. The consistency of 3x/week is paying off. Key is going even when I do not feel like it.',
        'Terrible sleep last night. Hyperfocused on a ceramics video until 2am. Need to set an alarm that means "start winding down" not "be asleep".',
        'Tried a new running route through the park. 4 miles. Saw a family of ducks. Sometimes the best part of exercise is the random discoveries.',
      ]},
    ],
  },
  personal: {
    weight: 0.15, // 15% of notes
    topics: [
      { title: 'Camping trip', tags: ['#personal', '#camping', '#outdoors'], contentTemplates: [
        'Camping trip planning: researching spots in Joshua Tree. March looks ideal. Need to book the campsite soon since they fill up fast.',
        'Gear check for camping: tent is good, sleeping bag rated to 30F, need a new headlamp. Also want to try cooking on a camp stove this time.',
        'Found a great campsite: Jumbo Rocks at Joshua Tree. Has amazing sunset views and is close to the trailheads. Booked for March 15-17.',
        'Making a camping meal plan: first night is foil packet dinners (easy after the drive). Second night: actual camp stove cooking. Ambitious but fun.',
        'Camping packing list: tent, sleeping bag, pad, headlamp, camp stove, fuel, cooler, food, water (2 gal per person per day), first aid kit.',
        'Post-camping reflection: Joshua Tree was incredible. The stars at night without light pollution. I want to go every month.',
      ]},
      { title: 'Apartment renovation', tags: ['#personal', '#apartment', '#renovation'], contentTemplates: [
        'Apartment project: want to redo the kitchen backsplash. Thinking about handmade ceramic tiles (maybe I could make them in class?).',
        'Looked at paint colors for the living room. Leaning toward a warm white with sage green accent wall. Need to get samples.',
        'Renovation budget: $2000 for kitchen backsplash, $500 for paint, $300 for new shelving. Total $2800. Need to save for 2 more months.',
        'Measured the kitchen backsplash area: 24 sq ft. At $15/sq ft for handmade tiles, that is $360 in materials. Very doable.',
        'Installed the new floating shelves in the living room. They look amazing. Took 2 hours including finding the studs (the hard part).',
      ]},
      { title: 'Social and relationships', tags: ['#personal', '#social'], contentTemplates: [
        'Dinner with Sam and Jordan tonight. Sam is starting a pottery business. We talked about the parallels between ceramics and software craftsmanship.',
        'Birthday party for Mom next weekend. Need to figure out a gift. She mentioned wanting to learn watercolor painting. Art supply kit?',
        'Cancelled plans again this week. I need to be honest with myself about social energy and stop overcommitting. Quality over quantity.',
      ]},
    ],
  },
  random: {
    weight: 0.15, // 15% of notes
    topics: [
      { title: 'Shower thoughts', tags: ['#random', '#thoughts'], contentTemplates: [
        'Shower thought: the overlap between ADHD hyperfocus and "flow state" is interesting. Is hyperfocus just uncontrolled flow?',
        'Random observation: I organize my kitchen spices alphabetically but my books by color. What does that say about my brain?',
        'Thought about digital minimalism. What if I only kept apps that I used in the last 7 days? My phone would have like 8 apps.',
        'The concept of "productive procrastination": when I avoid one task by doing another useful task. Is that a bug or a feature?',
        'Why do I always have my best ideas right before falling asleep? Need to keep a notepad by the bed. Tried the phone but then I doom scroll.',
        'Observation: I work better in coffee shops than at home. The ambient noise and the social contract of being in public helps me focus.',
      ]},
      { title: 'Book and media notes', tags: ['#random', '#books', '#media'], contentTemplates: [
        'Movie: "Jiro Dreams of Sushi" - the obsession with mastering one thing. Apprentices spend years just learning to make rice. Beautiful patience.',
        'Book: "Atomic Habits" - the 1% improvement idea. What is my 1% for this week? I think it is putting my phone in another room while working.',
        'Documentary about the International Space Station. The planning that goes into every detail is insane. 16 sunrises per day.',
        'Podcast: interview with a neuroscientist about creativity. Key point: boredom is essential for creative thinking. We never let ourselves be bored anymore.',
        'Finished "The Midnight Library" by Matt Haig. The parallel lives concept hit hard. Every choice opens one door and closes another.',
      ]},
      { title: 'Quick captures', tags: ['#random', '#capture'], contentTemplates: [
        'Need to call the dentist for a cleaning.',
        'Look into noise cancelling headphones for the office. The open plan is killing my focus.',
        'Grocery list: avocados, eggs, sourdough, oat milk, bananas, that fancy hot sauce from the farmers market.',
        'Remember to water the plants before leaving for camping.',
        'Check if the library has that ceramics book Sam recommended.',
        'Cancel the streaming service I never use.',
        'Password for the wifi at the ceramics studio: claymaker2024.',
        'Return the wrong size shoes before the 30 day window.',
      ]},
    ],
  },
};

function randomBetween(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomChoice<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function generateTimestamp(dayOffset: number, isWeekday: boolean): string {
  const base = new Date('2025-11-15T00:00:00Z');
  base.setDate(base.getDate() + dayOffset);

  // More notes during weekday work hours, evenings for personal
  let hour: number;
  if (isWeekday) {
    // Weighted toward morning (10-13) and evening (19-22)
    const r = Math.random();
    if (r < 0.4) hour = randomBetween(9, 13);
    else if (r < 0.7) hour = randomBetween(14, 17);
    else hour = randomBetween(19, 23);
  } else {
    // Weekends: spread across the day
    hour = randomBetween(8, 23);
  }

  base.setHours(hour, randomBetween(0, 59), randomBetween(0, 59));
  return base.toISOString();
}

function generateNotes(): SeedNote[] {
  const notes: SeedNote[] = [];
  const totalDays = 90; // 3 months
  const targetNotes = 500;
  const notesPerDay = targetNotes / totalDays; // ~5.5

  for (let day = 0; day < totalDays; day++) {
    const dayDate = new Date('2025-11-15');
    dayDate.setDate(dayDate.getDate() + day);
    const dayOfWeek = dayDate.getDay();
    const isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5;

    // Vary notes per day (some busy, some quiet)
    const dailyNotes = randomBetween(
      Math.max(1, Math.floor(notesPerDay * 0.3)),
      Math.ceil(notesPerDay * 2)
    );

    for (let n = 0; n < dailyNotes; n++) {
      // Pick domain based on weights, with day-of-week influence
      const r = Math.random();
      let domain: keyof typeof DOMAINS;

      if (isWeekday && r < 0.4) {
        domain = 'work';
      } else if (!isWeekday && r < 0.3) {
        domain = 'personal';
      } else {
        // Weighted random from all domains
        let cumulative = 0;
        domain = 'random';
        for (const [key, val] of Object.entries(DOMAINS)) {
          cumulative += val.weight;
          if (r < cumulative) {
            domain = key as keyof typeof DOMAINS;
            break;
          }
        }
      }

      const topic = randomChoice(DOMAINS[domain].topics);
      const template = randomChoice(topic.contentTemplates);

      // Add some variation: sometimes prefix with date-like references
      let content = template;
      if (Math.random() < 0.1) {
        content = `Following up on yesterday's note: ${content}`;
      }

      const timestamp = generateTimestamp(day, isWeekday);

      notes.push({
        title: topic.title,
        content,
        created_at: timestamp,
        tags: topic.tags,
      });
    }
  }

  // Sort by created_at
  notes.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

  return notes;
}

// Main
const fixtureDir = join(__dirname, '..', 'fixtures');
mkdirSync(fixtureDir, { recursive: true });

const notes = generateNotes();
const outputPath = join(fixtureDir, 'dev-seed-notes.json');
writeFileSync(outputPath, JSON.stringify(notes, null, 2));

console.log(`Generated ${notes.length} notes`);
console.log(`Date range: ${notes[0].created_at} to ${notes[notes.length - 1].created_at}`);
console.log(`Output: ${outputPath}`);

// Print domain breakdown
const domainCounts: Record<string, number> = {};
for (const note of notes) {
  const domain = note.tags[0]?.replace('#', '') || 'unknown';
  domainCounts[domain] = (domainCounts[domain] || 0) + 1;
}
console.log('Domain breakdown:', domainCounts);
```

**Step 3: Run the generator**

Run: `npx ts-node scripts/generate-dev-fixture.ts`

Expected: `Generated ~500 notes`, output to `fixtures/dev-seed-notes.json`.

**Step 4: Commit**

```bash
git add scripts/generate-dev-fixture.ts .gitignore
git commit -m "feat: add dev data fixture generator

Generates ~500 fictional notes spanning 3 months for a fictional
ADHD persona. Covers work, learning, health, personal, and random domains."
```

---

### Task 9: Create seed-dev-data.ts

**Files:**
- Create: `scripts/seed-dev-data.ts`

**Step 1: Write the seed script**

This script reads the fixture and inserts notes through the ingest pipeline, then runs processing workflows.

```typescript
/**
 * seed-dev-data.ts
 *
 * Seeds the development database with fictional notes from the fixture file,
 * then runs all processing workflows to populate threads, vectors, etc.
 *
 * Prerequisites:
 *   - Dev database created: ./scripts/create-dev-db.sh
 *   - Fixture generated: npx ts-node scripts/generate-dev-fixture.ts
 *   - Ollama running with mistral:7b and nomic-embed-text
 *
 * Usage: SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts
 */

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';
import { config } from '../src/lib/config';
import { db, insertNote } from '../src/lib/db';
import { createWorkflowLogger } from '../src/lib';

const log = createWorkflowLogger('seed-dev-data');

interface SeedNote {
  title: string;
  content: string;
  created_at: string;
  tags: string[];
}

async function main() {
  // Safety check
  if (config.env !== 'development') {
    console.error('ERROR: This script must run with SELENE_ENV=development');
    console.error(`Current env: ${config.env}`);
    process.exit(1);
  }

  console.log('=== Selene Dev Data Seeder ===');
  console.log(`Environment: ${config.env}`);
  console.log(`Database: ${config.dbPath}`);
  console.log('');

  // Load fixture
  const fixturePath = join(__dirname, '..', 'fixtures', 'dev-seed-notes.json');
  if (!existsSync(fixturePath)) {
    console.error('ERROR: Fixture file not found. Run first:');
    console.error('  npx ts-node scripts/generate-dev-fixture.ts');
    process.exit(1);
  }

  const notes: SeedNote[] = JSON.parse(readFileSync(fixturePath, 'utf-8'));
  console.log(`Loaded ${notes.length} notes from fixture`);

  // Check if database already has notes
  const existingCount = (db.prepare('SELECT COUNT(*) as count FROM raw_notes').get() as { count: number }).count;
  if (existingCount > 0) {
    console.error(`ERROR: Database already has ${existingCount} notes.`);
    console.error('Run scripts/reset-dev-data.sh first to clear existing data.');
    process.exit(1);
  }

  // Insert notes
  console.log('');
  console.log('Phase 1: Inserting notes...');
  const insertTransaction = db.transaction(() => {
    for (let i = 0; i < notes.length; i++) {
      const note = notes[i];
      const contentHash = createHash('sha256')
        .update(note.title + note.content + note.created_at)
        .digest('hex');

      insertNote({
        title: note.title,
        content: note.content,
        contentHash,
        tags: note.tags,
        createdAt: note.created_at,
      });

      if ((i + 1) % 100 === 0) {
        console.log(`  Inserted ${i + 1}/${notes.length}`);
      }
    }
  });
  insertTransaction();

  const finalCount = (db.prepare('SELECT COUNT(*) as count FROM raw_notes').get() as { count: number }).count;
  console.log(`  Done: ${finalCount} notes inserted`);

  // Run processing workflows
  console.log('');
  console.log('Phase 2: Running processing pipelines...');
  console.log('  This may take several minutes (LLM processing + embeddings).');
  console.log('');

  const workflows = [
    { name: 'process-llm', path: '../src/workflows/process-llm.ts' },
    { name: 'extract-tasks', path: '../src/workflows/extract-tasks.ts' },
    { name: 'index-vectors', path: '../src/workflows/index-vectors.ts' },
    { name: 'compute-relationships', path: '../src/workflows/compute-relationships.ts' },
    { name: 'detect-threads', path: '../src/workflows/detect-threads.ts' },
    { name: 'reconsolidate-threads', path: '../src/workflows/reconsolidate-threads.ts' },
    { name: 'export-obsidian', path: '../src/workflows/export-obsidian.ts' },
  ];

  for (const wf of workflows) {
    console.log(`  Running ${wf.name}...`);
    try {
      // Import and run the workflow's main function
      // Each workflow checks for pending work and processes it
      const mod = require(wf.path);
      if (typeof mod.default === 'function') {
        await mod.default();
      } else if (typeof mod.main === 'function') {
        await mod.main();
      } else {
        // Workflow runs on import (CLI entry point)
        console.log(`    (${wf.name} runs on import)`);
      }
      console.log(`    ✓ ${wf.name} complete`);
    } catch (err) {
      console.error(`    ✗ ${wf.name} failed:`, (err as Error).message);
      console.log('    Continuing with remaining workflows...');
    }
  }

  // Print summary
  console.log('');
  console.log('=== Seed Complete ===');
  console.log('');

  const stats = {
    raw_notes: (db.prepare('SELECT COUNT(*) as c FROM raw_notes').get() as { c: number }).c,
    processed_notes: (db.prepare('SELECT COUNT(*) as c FROM processed_notes').get() as { c: number }).c,
    threads: (db.prepare('SELECT COUNT(*) as c FROM threads').get() as { c: number }).c,
    associations: (db.prepare('SELECT COUNT(*) as c FROM note_associations').get() as { c: number }).c,
    embeddings: (db.prepare('SELECT COUNT(*) as c FROM note_embeddings').get() as { c: number }).c,
  };

  console.log('Data summary:');
  for (const [table, count] of Object.entries(stats)) {
    console.log(`  ${table}: ${count}`);
  }
  console.log('');
  console.log('Next steps:');
  console.log('  1. Register ~/selene-data-dev/vault/ as "Selene-Dev" in Obsidian');
  console.log('  2. Start dev server: overmind start -f Procfile.dev');
  console.log('  3. Run SeleneChat: swift build && .build/debug/SeleneChat');
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
```

**Step 2: Test the seed script**

Ensure prerequisites:
- Dev DB exists: `ls ~/selene-data-dev/selene.db`
- Fixture exists: `ls fixtures/dev-seed-notes.json`
- Ollama running: `curl -s http://localhost:11434/api/tags | head -1`

Run: `SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts`

Expected: Notes are inserted, workflows run (may take 10-30 minutes for LLM processing of ~500 notes). Summary shows counts for all tables.

**Note:** If process-llm processes in batches (e.g., 10 at a time), you may need to run the seed script multiple times or modify the batch size. Check the workflow's batch limit and adjust if needed.

**Step 3: Commit**

```bash
git add scripts/seed-dev-data.ts
git commit -m "feat: add dev data seed script

Inserts fixture notes into dev database and runs all processing
pipelines (LLM, vectors, relationships, threads, Obsidian export)."
```

---

### Task 10: Create reset-dev-data.sh

**Files:**
- Create: `scripts/reset-dev-data.sh`

**Step 1: Write the reset script**

```bash
#!/bin/bash
#
# reset-dev-data.sh - Wipe and optionally reseed the dev environment
#
# Usage:
#   ./scripts/reset-dev-data.sh           # Wipe and reseed
#   ./scripts/reset-dev-data.sh --wipe    # Wipe only, no reseed
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEV_ROOT="$HOME/selene-data-dev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

WIPE_ONLY=false
if [ "$1" = "--wipe" ]; then
  WIPE_ONLY=true
fi

echo -e "${GREEN}=== Selene Dev Environment Reset ===${NC}"
echo ""
echo -e "${YELLOW}This will delete ALL data in:${NC}"
echo "  $DEV_ROOT"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Wipe
echo -e "${GREEN}Wiping dev data...${NC}"
rm -rf "$DEV_ROOT"
echo "  Done."

# Recreate
echo -e "${GREEN}Recreating dev database...${NC}"
"$SCRIPT_DIR/create-dev-db.sh"

if [ "$WIPE_ONLY" = true ]; then
  echo ""
  echo -e "${GREEN}Wipe complete. Run seed manually:${NC}"
  echo "  npx ts-node scripts/generate-dev-fixture.ts"
  echo "  SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts"
  exit 0
fi

# Regenerate fixture
echo ""
echo -e "${GREEN}Generating fixture data...${NC}"
cd "$PROJECT_ROOT"
npx ts-node scripts/generate-dev-fixture.ts

# Seed
echo ""
echo -e "${GREEN}Seeding dev database...${NC}"
SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts

echo ""
echo -e "${GREEN}=== Dev Environment Reset Complete ===${NC}"
```

**Step 2: Make executable**

Run: `chmod +x scripts/reset-dev-data.sh`

**Step 3: Commit**

```bash
git add scripts/reset-dev-data.sh
git commit -m "feat: add dev environment reset script

Wipes ~/selene-data-dev/, recreates database, regenerates fixture,
and reseeds all data through processing pipelines."
```

---

### Task 11: Update .gitignore for dev data safety

**Files:**
- Modify: `.gitignore`

**Step 1: Add dev data exclusions**

Add these entries to `.gitignore`:

```
# Dev data fixtures (generated, not committed)
fixtures/

# Dev data directory (should never be in repo)
selene-data-dev/
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore dev fixtures and data directory"
```

---

### Task 12: End-to-end verification

**Step 1: Verify production is untouched**

Run: `SELENE_ENV=production npx ts-node -e "import { config } from './src/lib/config'; console.log('Production DB:', config.dbPath); console.log('Production port:', config.port)"`

Expected: Points to `~/selene-data/selene.db`, port 5678.

**Step 2: Verify dev environment**

Run: `SELENE_ENV=development npx ts-node -e "import { config } from './src/lib/config'; console.log('Dev DB:', config.dbPath); console.log('Dev port:', config.port)"`

Expected: Points to `~/selene-data-dev/selene.db`, port 5679.

**Step 3: Start dev server and verify health**

Run: `overmind start -f Procfile.dev -D && sleep 3 && curl -s http://localhost:5679/health && overmind quit`

Expected: `{"status":"ok","env":"development","port":5679,"timestamp":"..."}`

**Step 4: Verify SeleneChat build**

Run: `cd SeleneChat && swift build 2>&1 | tail -3`

Expected: Build succeeds.

**Step 5: Verify database has seeded data**

Run: `sqlite3 ~/selene-data-dev/selene.db "SELECT 'notes: ' || COUNT(*) FROM raw_notes; SELECT 'processed: ' || COUNT(*) FROM processed_notes; SELECT 'threads: ' || COUNT(*) FROM threads;"`

Expected: notes count ~500, processed count > 0, threads count > 0.

**Step 6: Final commit with verification notes**

If all checks pass, no additional commit needed. If any adjustments were made during verification, commit them.

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | Add development tier to config | `src/lib/config.ts` |
| 2 | Update .env.development | `.env.development` |
| 3 | Health endpoint shows env | `src/server.ts` |
| 4 | SeleneChat dev paths | `DatabaseService.swift` |
| 5 | db.ts safety check | `src/lib/db.ts` |
| 6 | Dev database creation | `scripts/create-dev-db.sh` |
| 7 | Overmind setup | `Procfile.dev`, `.overmind.env` |
| 8 | Fixture generator | `scripts/generate-dev-fixture.ts` |
| 9 | Seed script | `scripts/seed-dev-data.ts` |
| 10 | Reset script | `scripts/reset-dev-data.sh` |
| 11 | Gitignore updates | `.gitignore` |
| 12 | End-to-end verification | — |
