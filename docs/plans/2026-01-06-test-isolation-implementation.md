# Test Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Isolate production data from Claude Code by moving it outside the repo and adding a `use_test_db` flag to workflows.

**Architecture:** Production data moves to `~/selene-data/`. Workflows check `use_test_db` flag in payload to switch between production and test databases. Test scripts always pass this flag.

**Tech Stack:** Bash scripts, SQLite, n8n function nodes (JavaScript)

**Design Doc:** `docs/plans/2026-01-06-test-isolation-design.md`

---

## Task 1: Create Test Directories

**Files:**
- Create: `data-test/.gitkeep`
- Create: `vault-test/.gitkeep`
- Modify: `.gitignore`

**Step 1: Create directories with gitkeep files**

```bash
mkdir -p data-test vault-test
touch data-test/.gitkeep vault-test/.gitkeep
```

**Step 2: Update .gitignore to ignore test database but keep directory**

Add to `.gitignore`:
```
# Test data (keep directory, ignore contents except .gitkeep)
data-test/*
!data-test/.gitkeep
vault-test/*
!vault-test/.gitkeep
```

**Step 3: Verify structure**

Run: `ls -la data-test/ vault-test/`
Expected: Both directories exist with `.gitkeep` files

**Step 4: Commit**

```bash
git add data-test/.gitkeep vault-test/.gitkeep .gitignore
git commit -m "chore: add test data directories"
```

---

## Task 2: Create Migration Script

**Files:**
- Create: `scripts/setup-test-isolation.sh`

**Step 1: Write the migration script**

```bash
#!/bin/bash
set -e

echo "=== Setting up test isolation ==="

# Create production data directory
if [ ! -d "$HOME/selene-data" ]; then
  echo "Creating ~/selene-data/"
  mkdir -p "$HOME/selene-data/obsidian-vault"
else
  echo "~/selene-data/ already exists"
fi

# Move production database (if exists in repo)
if [ -f "./data/selene.db" ]; then
  echo "Moving production database to ~/selene-data/"
  mv ./data/selene.db "$HOME/selene-data/"
  echo "  ✓ Moved selene.db"
else
  echo "  ℹ No database at ./data/selene.db (already moved or doesn't exist)"
fi

# Move Obsidian vault contents (if exists and not empty)
if [ -d "./vault" ] && [ "$(ls -A ./vault 2>/dev/null)" ]; then
  echo "Moving Obsidian vault to ~/selene-data/obsidian-vault/"
  mv ./vault/* "$HOME/selene-data/obsidian-vault/"
  echo "  ✓ Moved vault contents"
else
  echo "  ℹ No vault contents to move"
fi

# Ensure test directories exist
mkdir -p ./data-test ./vault-test

echo ""
echo "=== Setup complete ==="
echo "Production data: ~/selene-data/"
echo "Test data: ./data-test/ and ./vault-test/"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/seed-test-data.sh to create test database"
echo "  2. Restart n8n with ./scripts/start-n8n-local.sh"
```

**Step 2: Make executable**

```bash
chmod +x scripts/setup-test-isolation.sh
```

**Step 3: Test script (dry run check)**

Run: `bash -n scripts/setup-test-isolation.sh`
Expected: No output (syntax OK)

**Step 4: Commit**

```bash
git add scripts/setup-test-isolation.sh
git commit -m "feat: add test isolation migration script"
```

---

## Task 3: Create Seed Script

**Files:**
- Create: `scripts/seed-test-data.sh`

**Step 1: Write the seed script**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DB="$PROJECT_DIR/data-test/selene-test.db"
SCHEMA_FILE="$PROJECT_DIR/database/schema.sql"

echo "=== Seeding test database ==="

# Check schema exists
if [ ! -f "$SCHEMA_FILE" ]; then
  echo "ERROR: Schema file not found at $SCHEMA_FILE"
  exit 1
fi

# Remove existing test database
if [ -f "$TEST_DB" ]; then
  echo "Removing existing test database..."
  rm "$TEST_DB"
fi

# Create database with schema
echo "Creating database with schema..."
sqlite3 "$TEST_DB" < "$SCHEMA_FILE"

# Insert synthetic notes
echo "Inserting 18 synthetic notes..."
sqlite3 "$TEST_DB" << 'SEED_SQL'
-- Note 1: Actionable
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Dentist and groceries',
  'Need to call the dentist tomorrow to reschedule my cleaning appointment. Also running low on coffee and oat milk - should grab those this weekend.',
  'testhash001',
  'drafts',
  27,
  147,
  '2026-01-04 09:15:00',
  '2026-01-04 09:15:00',
  'pending',
  'pending_apple'
);

-- Note 2: Needs Planning
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Kitchen renovation ideas',
  'Been thinking about redoing the kitchen. The cabinets are outdated and the layout doesn''t work well. Should probably figure out budget first, then maybe talk to a contractor? Not sure where to even start with permits.',
  'testhash002',
  'drafts',
  43,
  224,
  '2026-01-03 14:30:00',
  '2026-01-03 14:30:00',
  'pending',
  'pending_apple'
);

-- Note 3: Archive Only
INSERT INTO raw_notes (title, content, content_hash, source_type, source_uuid, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Good conversation with mom',
  'Had a nice call with mom today. She told me about her garden and the new tomato varieties she''s trying. Reminded me of summers at grandma''s house.',
  'testhash003',
  'drafts',
  'uuid-note-003',
  30,
  148,
  '2026-01-02 19:45:00',
  '2026-01-02 19:45:00',
  'pending',
  'pending_apple'
);

-- Note 4: Edge Case - Mixed
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Project reflection and next steps',
  'The website redesign went well overall. Learned a lot about CSS grid. Maybe I should write up what worked and what didn''t. Could be useful for the next project.',
  'testhash004',
  'drafts',
  34,
  167,
  '2026-01-01 11:00:00',
  '2026-01-01 11:00:00',
  'pending',
  'pending_apple'
);

-- Note 5: Positive / High Energy
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Finally figured it out',
  'YES! After three days of debugging, I finally found the issue - it was a race condition in the async handler. That feeling when the tests go green is unmatched. Feeling pumped to tackle the next feature.',
  'testhash005',
  'drafts',
  40,
  204,
  '2026-01-04 16:20:00',
  '2026-01-04 16:20:00',
  'pending',
  'pending_apple'
);

-- Note 6: Negative / Stressed
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Overwhelmed today',
  'Too many things competing for attention. The deadline moved up, inbox is overflowing, and I keep forgetting things. Feel like I''m dropping balls everywhere. Need to step back and prioritize but there''s no time to even do that.',
  'testhash006',
  'drafts',
  44,
  230,
  '2026-01-03 18:45:00',
  '2026-01-03 18:45:00',
  'pending',
  'pending_apple'
);

-- Note 7: Neutral / Contemplative
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Observations on routine',
  'Noticed I''m more productive in the morning before checking email. Afternoons tend to fragment. Not sure if this is a pattern worth optimizing for or just how some days go.',
  'testhash007',
  'drafts',
  33,
  175,
  '2026-01-02 21:00:00',
  '2026-01-02 21:00:00',
  'pending',
  'pending_apple'
);

-- Note 8: Mixed / Processing
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Difficult feedback',
  'Got some critical feedback on my proposal today. Initial reaction was defensive but sitting with it now, some points are valid. Still stings a bit. Need to separate the useful critique from the delivery.',
  'testhash008',
  'drafts',
  38,
  202,
  '2026-01-01 20:30:00',
  '2026-01-01 20:30:00',
  'pending',
  'pending_apple'
);

-- Note 9: Theme - Sleep (instance 1)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Tired again',
  'Woke up groggy despite 7 hours. Maybe it''s the late screen time. Should try the no-phone-after-9pm rule again.',
  'testhash009',
  'drafts',
  21,
  110,
  '2026-01-04 07:30:00',
  '2026-01-04 07:30:00',
  'pending',
  'pending_apple'
);

-- Note 10: Theme - Sleep (instance 2)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Sleep experiment',
  'Third night of no screens after 9. Sleep quality does seem better. Waking up feels less like climbing out of a hole.',
  'testhash010',
  'drafts',
  23,
  117,
  '2026-01-02 08:15:00',
  '2026-01-02 08:15:00',
  'pending',
  'pending_apple'
);

-- Note 11: Theme - Sleep (instance 3)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Morning energy',
  'Actually felt rested today. The consistent bedtime is helping. Energy held through the afternoon slump for once.',
  'testhash011',
  'drafts',
  18,
  107,
  '2025-12-30 09:00:00',
  '2025-12-30 09:00:00',
  'pending',
  'pending_apple'
);

-- Note 12: Theme - Work Boundaries
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Working late again',
  'Said I''d stop at 6 but it''s now 9pm. This keeps happening when there''s no clear stopping point. Need some kind of forcing function.',
  'testhash012',
  'drafts',
  27,
  133,
  '2026-01-03 21:15:00',
  '2026-01-03 21:15:00',
  'pending',
  'pending_apple'
);

-- Note 13: Concepts - Productivity + Tools
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Trying new task app',
  'Downloaded Things 3 to replace Reminders. The quick-entry feature is great for capturing tasks without context switching. Wondering if it''ll stick this time or end up abandoned like the others.',
  'testhash013',
  'drafts',
  34,
  192,
  '2026-01-04 12:00:00',
  '2026-01-04 12:00:00',
  'pending',
  'pending_apple'
);

-- Note 14: Concepts - Productivity + ADHD
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Why systems fail',
  'Realized my productivity systems fail when they require too much maintenance. The system needs to be lower friction than the problem it solves. ADHD brain won''t tolerate overhead.',
  'testhash014',
  'drafts',
  32,
  181,
  '2026-01-02 15:30:00',
  '2026-01-02 15:30:00',
  'pending',
  'pending_apple'
);

-- Note 15: Concepts - Tools + Learning
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'n8n learning curve',
  'Finally getting comfortable with n8n. The visual workflow builder clicks with how I think. Function nodes are powerful but easy to overcomplicate.',
  'testhash015',
  'drafts',
  25,
  145,
  '2026-01-01 14:00:00',
  '2026-01-01 14:00:00',
  'pending',
  'pending_apple'
);

-- Note 16: Feedback Note (has #selene-feedback tag)
INSERT INTO raw_notes (title, content, content_hash, source_type, tags, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Selene feedback',
  'The daily summary is helpful but arrives too late. Would be better at 7am instead of midnight. Also wish I could see which notes contributed to detected patterns. #selene-feedback',
  'testhash016',
  'drafts',
  '["selene-feedback"]',
  33,
  178,
  '2026-01-04 08:00:00',
  '2026-01-04 08:00:00',
  'pending',
  'pending_apple'
);

-- Note 17: Duplicate Test (same content as Note 1)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Dentist and groceries',
  'Need to call the dentist tomorrow to reschedule my cleaning appointment. Also running low on coffee and oat milk - should grab those this weekend.',
  'testhash001-dup',
  'drafts',
  27,
  147,
  '2026-01-04 09:15:00',
  '2026-01-04 09:16:00',
  'pending',
  'pending_apple'
);

-- Note 18: Edit Test (same UUID as Note 3, different content)
INSERT INTO raw_notes (title, content, content_hash, source_type, source_uuid, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Good conversation with mom (updated)',
  'Had a nice call with mom today. She told me about her garden and the new tomato varieties she''s trying. Reminded me of summers at grandma''s house. She''s also planning to visit next month - need to prep the guest room.',
  'testhash018',
  'drafts',
  'uuid-note-003-edit',
  43,
  218,
  '2026-01-02 19:45:00',
  '2026-01-02 20:00:00',
  'pending',
  'pending_apple'
);

SEED_SQL

# Verify
COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM raw_notes;")
echo ""
echo "=== Seed complete ==="
echo "Database: $TEST_DB"
echo "Notes inserted: $COUNT"
```

**Step 2: Make executable**

```bash
chmod +x scripts/seed-test-data.sh
```

**Step 3: Test script syntax**

Run: `bash -n scripts/seed-test-data.sh`
Expected: No output (syntax OK)

**Step 4: Commit**

```bash
git add scripts/seed-test-data.sh
git commit -m "feat: add test database seed script with 18 synthetic notes"
```

---

## Task 4: Update Startup Script

**Files:**
- Modify: `scripts/start-n8n-local.sh`

**Step 1: Read current script**

Run: `cat scripts/start-n8n-local.sh`

**Step 2: Add environment variable exports**

Add after shebang, before n8n start:

```bash
# Production paths (default)
export SELENE_DB_PATH="${SELENE_DB_PATH:-$HOME/selene-data/selene.db}"
export OBSIDIAN_VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/selene-data/obsidian-vault}"

# Test paths (available to workflows for use_test_db switching)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
export SELENE_TEST_DB_PATH="$PROJECT_DIR/data-test/selene-test.db"
export OBSIDIAN_TEST_VAULT_PATH="$PROJECT_DIR/vault-test"
```

**Step 3: Test script syntax**

Run: `bash -n scripts/start-n8n-local.sh`
Expected: No output (syntax OK)

**Step 4: Commit**

```bash
git add scripts/start-n8n-local.sh
git commit -m "feat: add production and test path environment variables to startup"
```

---

## Task 5: Create Helper Function for Workflows

**Files:**
- Create: `workflows/_shared/db-path-helper.js`

**Step 1: Create shared helper documentation**

This is a reference file - the code will be copied into each workflow function node (n8n doesn't support imports across nodes).

```javascript
// =============================================================
// DATABASE PATH HELPER - Copy this block to top of function nodes
// =============================================================
// Checks for use_test_db flag and returns appropriate database path
//
// Usage in function node:
//   const useTestDb = $json.use_test_db || false;
//   const dbPath = useTestDb
//     ? process.env.SELENE_TEST_DB_PATH
//     : process.env.SELENE_DB_PATH;
//   const db = new Database(dbPath);
//
// Pass flag to downstream nodes:
//   return {
//     json: {
//       ...result,
//       use_test_db: useTestDb
//     }
//   };
// =============================================================
```

**Step 2: Create the file**

```bash
mkdir -p workflows/_shared
```

Write the helper documentation to `workflows/_shared/db-path-helper.js`

**Step 3: Commit**

```bash
git add workflows/_shared/db-path-helper.js
git commit -m "docs: add database path helper reference for workflow nodes"
```

---

## Task 6: Update Workflow 01-Ingestion

**Files:**
- Modify: `workflows/01-ingestion/workflow.json`

**Step 1: Export current workflow**

```bash
./scripts/manage-workflow.sh list
# Note the ID for 01-ingestion
./scripts/manage-workflow.sh export <id>
```

**Step 2: Update all function nodes with database access**

For each function node that contains `new Database('/Users/chaseeasterling/selene/data/selene.db')`:

Replace:
```javascript
const db = new Database('/Users/chaseeasterling/selene/data/selene.db');
```

With:
```javascript
const useTestDb = $json.use_test_db || false;
const dbPath = useTestDb
  ? process.env.SELENE_TEST_DB_PATH
  : process.env.SELENE_DB_PATH;
const db = new Database(dbPath);
```

Also ensure `use_test_db` is passed through in return statements.

**Step 3: Update workflow in n8n**

```bash
./scripts/manage-workflow.sh update <id> workflows/01-ingestion/workflow.json
```

**Step 4: Commit**

```bash
git add workflows/01-ingestion/workflow.json
git commit -m "feat(01): add use_test_db flag support for database switching"
```

---

## Task 7: Update Workflow 02-LLM-Processing

**Files:**
- Modify: `workflows/02-llm-processing/workflow.json`

**Step 1: Export and identify function nodes**

```bash
./scripts/manage-workflow.sh export <id>
```

**Step 2: Apply same pattern as Task 6**

Replace hardcoded paths with `use_test_db` check pattern.

**Step 3: Update and commit**

```bash
./scripts/manage-workflow.sh update <id> workflows/02-llm-processing/workflow.json
git add workflows/02-llm-processing/workflow.json
git commit -m "feat(02): add use_test_db flag support for database switching"
```

---

## Task 8: Update Remaining Workflows (02_apple, 03, 05, 06, 07, 08, 10, 11)

**Files:**
- Modify: `workflows/02-llm-processing_apple/workflow.json`
- Modify: `workflows/03-pattern-detection/workflow.json`
- Modify: `workflows/05-sentiment-analysis/workflow.json`
- Modify: `workflows/06-connection-network/workflow.json`
- Modify: `workflows/07-task-extraction/workflow.json`
- Modify: `workflows/08-daily-summary/workflow.json`
- Modify: `workflows/10-embedding-generation/workflow.json`
- Modify: `workflows/11-association-computation/workflow.json`

**Step 1: For each workflow, repeat the pattern**

1. Export workflow
2. Find all function nodes with hardcoded database paths
3. Replace with `use_test_db` check pattern
4. Update workflow in n8n
5. Commit individually

**Step 2: Commit each workflow separately**

```bash
git commit -m "feat(XX): add use_test_db flag support for database switching"
```

---

## Task 9: Update Test Scripts

**Files:**
- Modify: `workflows/01-ingestion/scripts/test-with-markers.sh`
- Modify: All other `test-with-markers.sh` scripts

**Step 1: Add use_test_db to all curl commands**

Find all curl commands in test scripts and add `"use_test_db": true` to the JSON payload.

Before:
```bash
-d '{"title": "Test", "content": "Test", "test_run": "'"$TEST_RUN"'"}'
```

After:
```bash
-d '{"title": "Test", "content": "Test", "test_run": "'"$TEST_RUN"'", "use_test_db": true}'
```

**Step 2: Update cleanup scripts to use test database**

Modify cleanup scripts to target `./data-test/selene-test.db` instead of production.

**Step 3: Commit**

```bash
git add workflows/*/scripts/*.sh
git commit -m "feat: add use_test_db flag to all test scripts"
```

---

## Task 10: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/OPERATIONS.md`
- Modify: `workflows/CLAUDE.md`

**Step 1: Update CLAUDE.md**

Add section about test isolation:
- Production data location
- How to run migration
- How to seed test data

**Step 2: Update OPERATIONS.md**

Add commands for:
- `./scripts/setup-test-isolation.sh`
- `./scripts/seed-test-data.sh`

**Step 3: Update workflows/CLAUDE.md**

Update database pattern section to show `use_test_db` pattern.

**Step 4: Commit**

```bash
git add CLAUDE.md .claude/OPERATIONS.md workflows/CLAUDE.md
git commit -m "docs: add test isolation setup and usage documentation"
```

---

## Task 11: Final Verification

**Step 1: Run seed script**

```bash
./scripts/seed-test-data.sh
```

Expected: "Notes inserted: 18"

**Step 2: Verify test database**

```bash
sqlite3 data-test/selene-test.db "SELECT id, title FROM raw_notes LIMIT 5;"
```

Expected: First 5 synthetic notes displayed

**Step 3: Test a workflow with use_test_db**

```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Verify Test", "content": "This should go to test DB", "use_test_db": true}'
```

**Step 4: Verify note went to test DB (not production)**

```bash
sqlite3 data-test/selene-test.db "SELECT id, title FROM raw_notes ORDER BY id DESC LIMIT 1;"
```

Expected: "Verify Test" appears

```bash
# Production should NOT have this note (after migration)
sqlite3 ~/selene-data/selene.db "SELECT id, title FROM raw_notes WHERE title = 'Verify Test';"
```

Expected: No results

---

## Summary

| Task | Description | Estimated |
|------|-------------|-----------|
| 1 | Create test directories | 2 min |
| 2 | Create migration script | 5 min |
| 3 | Create seed script | 10 min |
| 4 | Update startup script | 3 min |
| 5 | Create helper reference | 2 min |
| 6 | Update workflow 01 | 10 min |
| 7 | Update workflow 02 | 5 min |
| 8 | Update remaining workflows | 30 min |
| 9 | Update test scripts | 15 min |
| 10 | Update documentation | 10 min |
| 11 | Final verification | 5 min |

**Total: ~97 minutes**

**User action required after implementation:**
```bash
./scripts/setup-test-isolation.sh
```
