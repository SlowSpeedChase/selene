# Test Data Isolation Design

**Created:** 2026-01-06
**Status:** Approved
**Purpose:** Prevent Claude Code from accessing production data during testing and debugging

---

## Problem

Claude Code has access to the entire repo directory, including:
- `data/selene.db` - Production database with real personal notes
- `vault/` - Obsidian vault with real exported notes

When running tests or debugging workflows, Claude can query and read this data, which then appears in conversation context and potentially leaves the local machine.

## Solution

Move production data outside the repo to a location Claude Code cannot access. Keep synthetic test data inside the repo for development and testing.

---

## Architecture

### Directory Structure

**Production data (outside repo - inaccessible to Claude):**
```
~/selene-data/
├── selene.db              # Real notes database
└── obsidian-vault/        # Real Obsidian exports
```

**Test data (inside repo - accessible to Claude):**
```
~/selene/
├── data-test/
│   └── selene-test.db     # 18 synthetic notes
├── vault-test/            # Synthetic Obsidian exports
└── ...
```

### Data Flow

```
                    ┌─────────────────────────┐
                    │   Webhook Request       │
                    │   use_test_db: true/false│
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼─────────────┐
                    │   Workflow Function     │
                    │   Check use_test_db     │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┴─────────────────┐
              │                                   │
    ┌─────────▼─────────┐             ┌──────────▼──────────┐
    │  use_test_db=true │             │ use_test_db=false   │
    │                   │             │ (or missing)        │
    └─────────┬─────────┘             └──────────┬──────────┘
              │                                   │
    ┌─────────▼─────────┐             ┌──────────▼──────────┐
    │ ./data-test/      │             │ ~/selene-data/      │
    │ selene-test.db    │             │ selene.db           │
    │ (synthetic)       │             │ (production)        │
    └───────────────────┘             └─────────────────────┘
```

---

## Components

### 1. Startup Script

**File:** `./scripts/start-n8n-local.sh`

```bash
#!/bin/bash

# Production paths (default)
export SELENE_DB_PATH="${SELENE_DB_PATH:-$HOME/selene-data/selene.db}"
export OBSIDIAN_VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/selene-data/obsidian-vault}"

# Test paths (for reference in workflows)
export SELENE_TEST_DB_PATH="$PWD/data-test/selene-test.db"
export OBSIDIAN_TEST_VAULT_PATH="$PWD/vault-test"

# Start n8n
export N8N_USER_FOLDER="$PWD/.n8n-local"
n8n start
```

**Behavior:**
- Production mode is the default (no flags needed)
- Test paths exported for workflow access
- Zero-friction startup for normal use

### 2. Workflow Modification Pattern

**Every function node accessing the database uses:**

```javascript
const Database = require('better-sqlite3');

// Check for test mode from incoming data
const useTestDb = $json.use_test_db || false;

// Select database path
const dbPath = useTestDb
  ? process.env.SELENE_TEST_DB_PATH
  : process.env.SELENE_DB_PATH;

const db = new Database(dbPath);

try {
  // ... existing database logic unchanged ...
} finally {
  db.close();
}
```

**Pass flag to downstream nodes:**
```javascript
return {
  json: {
    ...result,
    use_test_db: $json.use_test_db || false
  }
};
```

**Affected workflows:** 01, 02, 02_apple, 03, 05, 06, 07, 08, 10, 11

### 3. Test Script Pattern

**All test scripts include the flag:**

```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Note",
    "content": "Test content",
    "test_run": "'"$TEST_RUN"'",
    "use_test_db": true
  }'
```

### 4. Migration Script

**File:** `./scripts/setup-test-isolation.sh`

```bash
#!/bin/bash
set -e

echo "Setting up test isolation..."

# Create production data directory
mkdir -p ~/selene-data/obsidian-vault

# Move production data (if exists in repo)
if [ -f "./data/selene.db" ]; then
  echo "Moving production database to ~/selene-data/"
  mv ./data/selene.db ~/selene-data/
fi

if [ -d "./vault" ] && [ "$(ls -A ./vault 2>/dev/null)" ]; then
  echo "Moving Obsidian vault to ~/selene-data/obsidian-vault/"
  mv ./vault/* ~/selene-data/obsidian-vault/
fi

# Create test directories
mkdir -p ./data-test ./vault-test

# Create placeholder files for git
touch ./data-test/.gitkeep ./vault-test/.gitkeep

echo "Done. Production data is now at ~/selene-data/"
echo "Test data will be at ./data-test/ and ./vault-test/"
```

### 5. Seed Script

**File:** `./scripts/seed-test-data.sh`

Creates test database with 18 synthetic notes covering:
- 4 task extraction test cases (actionable, needs_planning, archive_only, edge case)
- 4 sentiment analysis test cases (positive, negative, neutral, mixed)
- 4 pattern detection test cases (recurring sleep theme, work-life theme)
- 3 connection network test cases (overlapping concepts)
- 3 special cases (feedback routing, duplicate detection, edit detection)

---

## Synthetic Test Data

### Note Set Overview

| Note | Primary Test | Classification | Sentiment | Theme |
|------|--------------|----------------|-----------|-------|
| 1 | Task extraction | actionable | neutral | errands |
| 2 | Task extraction | needs_planning | neutral | home |
| 3 | Task extraction | archive_only | positive | family |
| 4 | Task extraction | edge case | positive | work |
| 5 | Sentiment | - | positive/high | coding |
| 6 | Sentiment | - | negative/stressed | overwhelm |
| 7 | Sentiment | - | neutral | routine |
| 8 | Sentiment | - | mixed | feedback |
| 9 | Pattern | - | negative | sleep |
| 10 | Pattern | - | positive | sleep |
| 11 | Pattern | - | positive | sleep |
| 12 | Pattern | - | negative | work-life |
| 13 | Connections | - | neutral | productivity |
| 14 | Connections | - | neutral | productivity |
| 15 | Connections | - | neutral | tools |
| 16 | Feedback routing | - | neutral | meta |
| 17 | Deduplication | - | - | - |
| 18 | Edit detection | - | - | - |

### Full Note Content

**Note 1: Clearly Actionable**
- Title: "Dentist and groceries"
- Content: "Need to call the dentist tomorrow to reschedule my cleaning appointment. Also running low on coffee and oat milk - should grab those this weekend."
- Created: 2026-01-04 09:15:00

**Note 2: Needs Planning**
- Title: "Kitchen renovation ideas"
- Content: "Been thinking about redoing the kitchen. The cabinets are outdated and the layout doesn't work well. Should probably figure out budget first, then maybe talk to a contractor? Not sure where to even start with permits."
- Created: 2026-01-03 14:30:00

**Note 3: Archive Only**
- Title: "Good conversation with mom"
- Content: "Had a nice call with mom today. She told me about her garden and the new tomato varieties she's trying. Reminded me of summers at grandma's house."
- Created: 2026-01-02 19:45:00

**Note 4: Edge Case - Mixed**
- Title: "Project reflection and next steps"
- Content: "The website redesign went well overall. Learned a lot about CSS grid. Maybe I should write up what worked and what didn't. Could be useful for the next project."
- Created: 2026-01-01 11:00:00

**Note 5: Positive / High Energy**
- Title: "Finally figured it out"
- Content: "YES! After three days of debugging, I finally found the issue - it was a race condition in the async handler. That feeling when the tests go green is unmatched. Feeling pumped to tackle the next feature."
- Created: 2026-01-04 16:20:00

**Note 6: Negative / Stressed**
- Title: "Overwhelmed today"
- Content: "Too many things competing for attention. The deadline moved up, inbox is overflowing, and I keep forgetting things. Feel like I'm dropping balls everywhere. Need to step back and prioritize but there's no time to even do that."
- Created: 2026-01-03 18:45:00

**Note 7: Neutral / Contemplative**
- Title: "Observations on routine"
- Content: "Noticed I'm more productive in the morning before checking email. Afternoons tend to fragment. Not sure if this is a pattern worth optimizing for or just how some days go."
- Created: 2026-01-02 21:00:00

**Note 8: Mixed / Processing**
- Title: "Difficult feedback"
- Content: "Got some critical feedback on my proposal today. Initial reaction was defensive but sitting with it now, some points are valid. Still stings a bit. Need to separate the useful critique from the delivery."
- Created: 2026-01-01 20:30:00

**Note 9: Theme - Sleep (instance 1)**
- Title: "Tired again"
- Content: "Woke up groggy despite 7 hours. Maybe it's the late screen time. Should try the no-phone-after-9pm rule again."
- Created: 2026-01-04 07:30:00

**Note 10: Theme - Sleep (instance 2)**
- Title: "Sleep experiment"
- Content: "Third night of no screens after 9. Sleep quality does seem better. Waking up feels less like climbing out of a hole."
- Created: 2026-01-02 08:15:00

**Note 11: Theme - Sleep (instance 3)**
- Title: "Morning energy"
- Content: "Actually felt rested today. The consistent bedtime is helping. Energy held through the afternoon slump for once."
- Created: 2025-12-30 09:00:00

**Note 12: Theme - Work Boundaries**
- Title: "Working late again"
- Content: "Said I'd stop at 6 but it's now 9pm. This keeps happening when there's no clear stopping point. Need some kind of forcing function."
- Created: 2026-01-03 21:15:00

**Note 13: Concepts - Productivity + Tools**
- Title: "Trying new task app"
- Content: "Downloaded Things 3 to replace Reminders. The quick-entry feature is great for capturing tasks without context switching. Wondering if it'll stick this time or end up abandoned like the others."
- Created: 2026-01-04 12:00:00

**Note 14: Concepts - Productivity + ADHD**
- Title: "Why systems fail"
- Content: "Realized my productivity systems fail when they require too much maintenance. The system needs to be lower friction than the problem it solves. ADHD brain won't tolerate overhead."
- Created: 2026-01-02 15:30:00

**Note 15: Concepts - Tools + Learning**
- Title: "n8n learning curve"
- Content: "Finally getting comfortable with n8n. The visual workflow builder clicks with how I think. Function nodes are powerful but easy to overcomplicate."
- Created: 2026-01-01 14:00:00

**Note 16: Feedback Note**
- Title: "Selene feedback"
- Content: "The daily summary is helpful but arrives too late. Would be better at 7am instead of midnight. Also wish I could see which notes contributed to detected patterns. #selene-feedback"
- Created: 2026-01-04 08:00:00

**Note 17: Duplicate Test**
- Title: "Dentist and groceries"
- Content: "Need to call the dentist tomorrow to reschedule my cleaning appointment. Also running low on coffee and oat milk - should grab those this weekend."
- Created: 2026-01-04 09:15:00
- Purpose: Exact duplicate of Note 1

**Note 18: Edit Test**
- Title: "Good conversation with mom (updated)"
- Content: "Had a nice call with mom today. She told me about her garden and the new tomato varieties she's trying. Reminded me of summers at grandma's house. She's also planning to visit next month - need to prep the guest room."
- Source_UUID: [same as Note 3]
- Created: 2026-01-02 19:45:00
- Purpose: Same UUID as Note 3, different content

---

## Error Handling

### Missing Database Path
```javascript
const dbPath = useTestDb
  ? process.env.SELENE_TEST_DB_PATH
  : process.env.SELENE_DB_PATH;

if (!dbPath) {
  throw new Error('Database path not configured. Run ./scripts/start-n8n-local.sh');
}
```

### Missing Test Database
Seed script creates database if missing:
```bash
if [ ! -f "$TEST_DB" ]; then
  sqlite3 "$TEST_DB" < ./database/schema.sql
fi
```

### Forgotten Flag in Test
- Test still runs but hits production DB
- Mitigated by: all repo test scripts include flag by default
- Claude Code copies from existing scripts

---

## Implementation Tasks

1. Create migration script (`setup-test-isolation.sh`)
2. Create seed script (`seed-test-data.sh`)
3. Update startup script with environment variables
4. Modify all workflow function nodes (11 workflows)
5. Update all test scripts to include `use_test_db: true`
6. Update documentation (CLAUDE.md, OPERATIONS.md)
7. Run migration (user action)
8. Verify tests pass with isolated data

---

## Success Criteria

- [ ] Production data lives at `~/selene-data/`
- [ ] Claude Code cannot access production database
- [ ] `./scripts/start-n8n-local.sh` works without any flags
- [ ] All test scripts use `use_test_db: true`
- [ ] Seed script creates reproducible test data
- [ ] All existing tests pass against test database
