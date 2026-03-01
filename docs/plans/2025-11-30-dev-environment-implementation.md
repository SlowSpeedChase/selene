# Development Environment Isolation - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a dual Docker stack that isolates development from production, with checklist-driven promotion.

**Architecture:** Two independent n8n instances sharing the same workflow JSON files from git. Production on port 5678, development on port 5679, each with its own database and n8n internal storage.

**Tech Stack:** Docker Compose, Bash scripts, SQLite

---

## Task 1: Add SELENE_ENV to Production Docker Compose

**Files:**
- Modify: `docker-compose.yml:66`

**Step 1: Add environment variable**

Add `SELENE_ENV=production` to the environment section after line 66 (after `SELENE_DB_PATH`):

```yaml
      # Custom environment variables for workflows
      - SELENE_DB_PATH=/selene/data/selene.db
      - SELENE_ENV=production
```

**Step 2: Verify syntax**

Run: `docker-compose config`

Expected: Valid YAML output, no errors

**Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "chore: add SELENE_ENV=production to docker-compose"
```

---

## Task 2: Create Development Docker Compose File

**Files:**
- Create: `docker-compose.dev.yml`

**Step 1: Create the file**

```yaml
# Development stack - isolated from production
# Usage: docker-compose -f docker-compose.dev.yml up -d

services:
  n8n-dev:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: selene-dev
    restart: unless-stopped
    ports:
      - "5679:5678"     # Dev on port 5679
    environment:
      # Host Configuration
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://localhost:5679/
      - N8N_EDITOR_BASE_URL=http://localhost:5679

      # Execution Settings
      - EXECUTIONS_MODE=regular
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168

      # Timezone
      - GENERIC_TIMEZONE=${TIMEZONE:-America/Los_Angeles}
      - TZ=${TIMEZONE:-America/Los_Angeles}

      # Performance
      - N8N_PAYLOAD_SIZE_MAX=16
      - N8N_METRICS=false

      # Database Configuration
      - DB_SQLITE_POOL_SIZE=5

      # Task Runners
      - N8N_RUNNERS_ENABLED=true

      # Disable telemetry
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_VERSION_NOTIFICATIONS_ENABLED=false
      - N8N_TEMPLATES_ENABLED=false

      # Community nodes
      - N8N_COMMUNITY_PACKAGES_ENABLED=true
      - N8N_COMMUNITY_PACKAGES_INSTALL=n8n-nodes-sqlite

      # Allow better-sqlite3 and crypto in Function nodes
      - NODE_FUNCTION_ALLOW_EXTERNAL=better-sqlite3,crypto
      - NODE_PATH=/home/node/.n8n/node_modules

      # Security
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      - N8N_SECURE_COOKIE=false

      # DEVELOPMENT environment variables
      - SELENE_DB_PATH=/selene/data/selene-dev.db
      - SELENE_ENV=development
      - OBSIDIAN_VAULT_PATH=/obsidian
      - OLLAMA_BASE_URL=http://localhost:11434
      - OLLAMA_MODEL=${OLLAMA_MODEL:-mistral:7b}

    volumes:
      # Separate n8n internal data for dev
      - n8n_dev_data:/home/node/.n8n

      # Shared data directory (dev database lives here)
      - ${SELENE_DATA_PATH:-./data}:/selene/data:rw

      # Shared Obsidian vault (dev can use same vault for testing)
      - ${OBSIDIAN_VAULT_PATH:-./vault}:/obsidian:rw

      # Mount workflows (same as production - git is source of truth)
      - ./:/workflows:ro

    extra_hosts:
      - "host.docker.internal:host-gateway"

    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  n8n_dev_data:
    driver: local
    name: selene_n8n_dev_data
```

**Step 2: Verify syntax**

Run: `docker-compose -f docker-compose.dev.yml config`

Expected: Valid YAML output, no errors

**Step 3: Commit**

```bash
git add docker-compose.dev.yml
git commit -m "feat: add development docker-compose file"
```

---

## Task 3: Create Environment Indicator File

**Files:**
- Create: `.claude/CURRENT-ENV.md`

**Step 1: Create the file**

```markdown
# Current Environment

**Status:** PRODUCTION

---

## What This Means

- **PRODUCTION**: Claude should NOT make changes to workflows or test against production database
- **DEVELOPMENT**: Claude can freely modify workflows and test against dev database

## Environment Details

| Environment | Port | Database | Container |
|-------------|------|----------|-----------|
| Production | 5678 | selene.db | selene |
| Development | 5679 | selene-dev.db | selene-dev |

## Switching Environments

Use the dev scripts:
- `./scripts/dev-start.sh` - Start dev environment (updates this file)
- `./scripts/dev-stop.sh` - Stop dev environment (updates this file)

## Current Status

- Production: Running (always on)
- Development: Not running

---

*This file is automatically updated by dev-start.sh and dev-stop.sh*
```

**Step 2: Commit**

```bash
git add .claude/CURRENT-ENV.md
git commit -m "feat: add environment indicator file for Claude"
```

---

## Task 4: Create dev-start.sh Script

**Files:**
- Create: `scripts/dev-start.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# Script Purpose: Start development n8n environment
# Usage: ./scripts/dev-start.sh

set -e
set -u

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Navigate to project root
cd "$(dirname "$0")/.."

# Check if dev database exists, create if not
if [ ! -f "data/selene-dev.db" ]; then
    log_step "Creating development database..."
    if [ -f "database/schema.sql" ]; then
        sqlite3 data/selene-dev.db < database/schema.sql
        log_info "Development database created from schema"
    else
        log_error "schema.sql not found - cannot create database"
        exit 1
    fi
fi

# Start dev stack
log_step "Starting development n8n stack..."
docker-compose -f docker-compose.dev.yml up -d

# Wait for health check
log_step "Waiting for n8n-dev to be healthy..."
for i in {1..30}; do
    if docker exec selene-dev wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        log_info "n8n-dev is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "n8n-dev failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Update environment indicator
log_step "Updating environment indicator..."
cat > .claude/CURRENT-ENV.md << 'EOF'
# Current Environment

**Status:** DEVELOPMENT

---

## What This Means

- **PRODUCTION**: Claude should NOT make changes to workflows or test against production database
- **DEVELOPMENT**: Claude can freely modify workflows and test against dev database

## Environment Details

| Environment | Port | Database | Container |
|-------------|------|----------|-----------|
| Production | 5678 | selene.db | selene |
| Development | 5679 | selene-dev.db | selene-dev |

## Switching Environments

Use the dev scripts:
- `./scripts/dev-start.sh` - Start dev environment (updates this file)
- `./scripts/dev-stop.sh` - Stop dev environment (updates this file)

## Current Status

- Production: Running (always on)
- Development: **RUNNING** (port 5679)

---

*This file is automatically updated by dev-start.sh and dev-stop.sh*
EOF

log_info "Development environment ready!"
log_info "  n8n UI: http://localhost:5679"
log_info "  Database: data/selene-dev.db"
log_info "  Container: selene-dev"
echo ""
log_info "To stop: ./scripts/dev-stop.sh"
```

**Step 2: Make executable**

Run: `chmod +x scripts/dev-start.sh`

**Step 3: Commit**

```bash
git add scripts/dev-start.sh
git commit -m "feat: add dev-start.sh script"
```

---

## Task 5: Create dev-stop.sh Script

**Files:**
- Create: `scripts/dev-stop.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# Script Purpose: Stop development n8n environment
# Usage: ./scripts/dev-stop.sh

set -e
set -u

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Navigate to project root
cd "$(dirname "$0")/.."

# Stop dev stack
log_step "Stopping development n8n stack..."
docker-compose -f docker-compose.dev.yml down

# Update environment indicator
log_step "Updating environment indicator..."
cat > .claude/CURRENT-ENV.md << 'EOF'
# Current Environment

**Status:** PRODUCTION

---

## What This Means

- **PRODUCTION**: Claude should NOT make changes to workflows or test against production database
- **DEVELOPMENT**: Claude can freely modify workflows and test against dev database

## Environment Details

| Environment | Port | Database | Container |
|-------------|------|----------|-----------|
| Production | 5678 | selene.db | selene |
| Development | 5679 | selene-dev.db | selene-dev |

## Switching Environments

Use the dev scripts:
- `./scripts/dev-start.sh` - Start dev environment (updates this file)
- `./scripts/dev-stop.sh` - Stop dev environment (updates this file)

## Current Status

- Production: Running (always on)
- Development: Not running

---

*This file is automatically updated by dev-start.sh and dev-stop.sh*
EOF

log_info "Development environment stopped"
log_info "Production remains on port 5678"
```

**Step 2: Make executable**

Run: `chmod +x scripts/dev-stop.sh`

**Step 3: Commit**

```bash
git add scripts/dev-stop.sh
git commit -m "feat: add dev-stop.sh script"
```

---

## Task 6: Create dev-reset-db.sh Script

**Files:**
- Create: `scripts/dev-reset-db.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# Script Purpose: Reset development database to clean state
# Usage: ./scripts/dev-reset-db.sh

set -e
set -u

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Navigate to project root
cd "$(dirname "$0")/.."

DEV_DB="data/selene-dev.db"

# Safety check - ensure we're targeting dev database
if [ ! -f "$DEV_DB" ]; then
    log_warn "Development database does not exist: $DEV_DB"
    log_step "Creating fresh development database..."
    sqlite3 "$DEV_DB" < database/schema.sql
    log_info "Development database created"
    exit 0
fi

# Confirm reset
echo ""
log_warn "This will DELETE ALL DATA in the development database!"
log_warn "Database: $DEV_DB"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirmation

if [ "$confirmation" != "yes" ]; then
    log_info "Reset cancelled"
    exit 0
fi

# Backup current dev database
BACKUP="data/selene-dev-backup-$(date +%Y%m%d-%H%M%S).db"
log_step "Creating backup: $BACKUP"
cp "$DEV_DB" "$BACKUP"

# Delete and recreate
log_step "Resetting development database..."
rm "$DEV_DB"
sqlite3 "$DEV_DB" < database/schema.sql

log_info "Development database reset complete"
log_info "Backup saved to: $BACKUP"
```

**Step 2: Make executable**

Run: `chmod +x scripts/dev-reset-db.sh`

**Step 3: Commit**

```bash
git add scripts/dev-reset-db.sh
git commit -m "feat: add dev-reset-db.sh script"
```

---

## Task 7: Create dev-seed-data.sh Script

**Files:**
- Create: `scripts/dev-seed-data.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# Script Purpose: Seed development database with sample test data
# Usage: ./scripts/dev-seed-data.sh

set -e
set -u

# Color output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Navigate to project root
cd "$(dirname "$0")/.."

DEV_DB="data/selene-dev.db"

# Check dev database exists
if [ ! -f "$DEV_DB" ]; then
    log_warn "Development database not found. Run dev-start.sh first."
    exit 1
fi

SEED_RUN="seed-$(date +%Y%m%d-%H%M%S)"

log_step "Seeding development database with sample data..."
log_info "Seed marker: $SEED_RUN"

# Insert sample notes
sqlite3 "$DEV_DB" << EOF
-- Sample notes for development testing
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, tags, created_at, status, test_run)
VALUES
    ('ADHD Morning Routine', 'Need to establish a morning routine that actually works. Key elements: minimal decisions, visual cues, time blocking. The problem is not knowing what to do, it is starting.', '$(echo -n "adhd-morning-routine-$SEED_RUN" | shasum -a 256 | cut -d' ' -f1)', 'drafts', 35, 198, '["adhd", "routine", "productivity"]', datetime('now', '-5 days'), 'pending', '$SEED_RUN'),

    ('Project Ideas Dump', 'Random ideas floating around: 1) Automate note capture 2) Build habit tracker 3) Create visual task board 4) Weekly review template. Need to pick ONE and focus.', '$(echo -n "project-ideas-$SEED_RUN" | shasum -a 256 | cut -d' ' -f1)', 'drafts', 32, 185, '["ideas", "projects"]', datetime('now', '-3 days'), 'pending', '$SEED_RUN'),

    ('Energy Levels Today', 'Feeling scattered but energetic. Good window for creative work between 10am-12pm. Afternoon slump hit hard around 2pm. Need to schedule admin tasks for low energy periods.', '$(echo -n "energy-levels-$SEED_RUN" | shasum -a 256 | cut -d' ' -f1)', 'drafts', 33, 190, '["energy", "adhd", "self-awareness"]', datetime('now', '-1 days'), 'pending', '$SEED_RUN'),

    ('Meeting Notes - Product Review', 'Discussed Q4 roadmap. Key decisions: prioritize mobile app, defer analytics dashboard. Action items: update Jira, schedule design review, draft user stories.', '$(echo -n "meeting-notes-$SEED_RUN" | shasum -a 256 | cut -d' ' -f1)', 'drafts', 26, 168, '["meeting", "work", "action-items"]', datetime('now'), 'pending', '$SEED_RUN'),

    ('Weekend Reflection', 'Actually managed to rest this weekend without guilt. Key insight: scheduling rest makes it feel legitimate. Need to add this to weekly planning ritual.', '$(echo -n "weekend-reflection-$SEED_RUN" | shasum -a 256 | cut -d' ' -f1)', 'drafts', 28, 162, '["reflection", "self-care", "adhd"]', datetime('now', '-2 days'), 'pending', '$SEED_RUN');
EOF

# Count inserted
COUNT=$(sqlite3 "$DEV_DB" "SELECT COUNT(*) FROM raw_notes WHERE test_run = '$SEED_RUN';")

log_info "Seeded $COUNT sample notes"
log_info "To cleanup: sqlite3 $DEV_DB \"DELETE FROM raw_notes WHERE test_run = '$SEED_RUN';\""
```

**Step 2: Make executable**

Run: `chmod +x scripts/dev-seed-data.sh`

**Step 3: Commit**

```bash
git add scripts/dev-seed-data.sh
git commit -m "feat: add dev-seed-data.sh script"
```

---

## Task 8: Create promote-workflow.sh Script

**Files:**
- Create: `scripts/promote-workflow.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# Script Purpose: Checklist-driven workflow promotion from dev to production
# Usage: ./scripts/promote-workflow.sh <workflow-name>
# Example: ./scripts/promote-workflow.sh 01-ingestion

set -e
set -u

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_gate() { echo -e "${CYAN}[GATE]${NC} $1"; }

# Navigate to project root
cd "$(dirname "$0")/.."

# Validate input
if [ $# -eq 0 ]; then
    log_error "Usage: $0 <workflow-name>"
    log_info "Example: $0 01-ingestion"
    log_info ""
    log_info "Available workflows:"
    ls -d workflows/*/ 2>/dev/null | xargs -I{} basename {} || echo "  No workflows found"
    exit 1
fi

WORKFLOW_NAME="$1"
WORKFLOW_DIR="workflows/$WORKFLOW_NAME"
WORKFLOW_JSON="$WORKFLOW_DIR/workflow.json"

# Validate workflow exists
if [ ! -d "$WORKFLOW_DIR" ]; then
    log_error "Workflow directory not found: $WORKFLOW_DIR"
    exit 1
fi

if [ ! -f "$WORKFLOW_JSON" ]; then
    log_error "Workflow JSON not found: $WORKFLOW_JSON"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           WORKFLOW PROMOTION CHECKLIST                         ║"
echo "║           Workflow: $WORKFLOW_NAME"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────────────────
# GATE 1: Verify dev tests pass
# ─────────────────────────────────────────────────────────────────────
log_step "1/7: Verify dev tests pass"

TEST_SCRIPT="$WORKFLOW_DIR/scripts/test-with-markers.sh"
if [ -f "$TEST_SCRIPT" ]; then
    log_info "Test script found: $TEST_SCRIPT"
    log_warn "Run the test script manually and verify all tests pass"
    log_info "Command: $TEST_SCRIPT"
else
    log_warn "No test script found at: $TEST_SCRIPT"
    log_warn "Manual testing required"
fi

echo ""
log_gate "Have all tests passed? (y/n)"
read -r gate1
if [ "$gate1" != "y" ]; then
    log_error "Promotion stopped: Tests not verified"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# GATE 2: Show diff
# ─────────────────────────────────────────────────────────────────────
log_step "2/7: Review changes"

echo ""
log_info "Changes in $WORKFLOW_JSON:"
git diff --stat "$WORKFLOW_JSON" 2>/dev/null || log_info "No uncommitted changes"
echo ""
git diff "$WORKFLOW_JSON" 2>/dev/null | head -50 || true

echo ""
log_gate "Do the changes look correct? (y/n)"
read -r gate2
if [ "$gate2" != "y" ]; then
    log_error "Promotion stopped: Changes not approved"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# GATE 3: Documentation check
# ─────────────────────────────────────────────────────────────────────
log_step "3/7: Verify documentation"

STATUS_MD="$WORKFLOW_DIR/docs/STATUS.md"
if [ -f "$STATUS_MD" ]; then
    log_info "STATUS.md found: $STATUS_MD"
    log_info "Last modified: $(stat -f '%Sm' "$STATUS_MD" 2>/dev/null || stat -c '%y' "$STATUS_MD" 2>/dev/null || echo 'unknown')"
else
    log_warn "STATUS.md not found: $STATUS_MD"
fi

echo ""
log_gate "Is the documentation current? (y/n)"
read -r gate3
if [ "$gate3" != "y" ]; then
    log_error "Promotion stopped: Documentation not current"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# GATE 4: Final approval
# ─────────────────────────────────────────────────────────────────────
log_step "4/7: Final approval"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  PROMOTION SUMMARY                                             ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Workflow: $WORKFLOW_NAME"
echo "║  Source: $WORKFLOW_JSON"
echo "║  Target: Production n8n (port 5678)"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_gate "Approve promotion to production? (type 'PROMOTE' to confirm)"
read -r gate4
if [ "$gate4" != "PROMOTE" ]; then
    log_error "Promotion stopped: Not approved"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# STEP 5: Import to production
# ─────────────────────────────────────────────────────────────────────
log_step "5/7: Importing to production..."

# Check production container is running
if ! docker ps --format '{{.Names}}' | grep -q "^selene$"; then
    log_error "Production container 'selene' is not running"
    log_info "Start with: docker-compose up -d"
    exit 1
fi

# Get workflow ID from n8n (by name matching)
log_info "Importing workflow to production n8n..."
docker exec selene n8n import:workflow --input="/workflows/$WORKFLOW_JSON" --separate

log_info "Workflow imported to production"

# ─────────────────────────────────────────────────────────────────────
# GATE 6: Verify production
# ─────────────────────────────────────────────────────────────────────
log_step "6/7: Verify production"

echo ""
log_warn "Please verify the workflow is working in production:"
log_info "  1. Open n8n at http://localhost:5678"
log_info "  2. Check the workflow is active"
log_info "  3. Run a quick smoke test if applicable"
echo ""

log_gate "Is production working correctly? (y/n)"
read -r gate6
if [ "$gate6" != "y" ]; then
    log_error "Promotion verification failed"
    log_warn "Consider rolling back by reimporting a backup"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────
# STEP 7: Commit
# ─────────────────────────────────────────────────────────────────────
log_step "7/7: Commit changes"

# Check if there are changes to commit
if git diff --quiet "$WORKFLOW_JSON" && git diff --quiet "$STATUS_MD" 2>/dev/null; then
    log_info "No uncommitted changes to commit"
else
    log_info "Staging changes..."
    git add "$WORKFLOW_JSON"
    [ -f "$STATUS_MD" ] && git add "$STATUS_MD"

    log_gate "Commit message (or press Enter for default):"
    read -r commit_msg
    if [ -z "$commit_msg" ]; then
        commit_msg="feat($WORKFLOW_NAME): promote workflow to production"
    fi

    git commit -m "$commit_msg"
    log_info "Changes committed"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  PROMOTION COMPLETE                                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Workflow $WORKFLOW_NAME has been promoted to production"
```

**Step 2: Make executable**

Run: `chmod +x scripts/promote-workflow.sh`

**Step 3: Commit**

```bash
git add scripts/promote-workflow.sh
git commit -m "feat: add promote-workflow.sh with checklist gates"
```

---

## Task 9: Add --dev Flag to manage-workflow.sh

**Files:**
- Modify: `scripts/manage-workflow.sh`

**Step 1: Add DEV_MODE variable after line 16**

After `WORKFLOWS_DIR="./workflows"`, add:

```bash
# Dev mode flag
DEV_MODE=false
DEV_CONTAINER_NAME="selene-dev"
```

**Step 2: Add flag parsing before main function call**

Before line 250 (before `main "$@"`), add:

```bash
# Parse global flags
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev)
            DEV_MODE=true
            CONTAINER_NAME="$DEV_CONTAINER_NAME"
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"
```

**Step 3: Update usage function**

In the usage function, add after the Notes section:

```bash
${YELLOW}Dev Mode:${NC}
  Add --dev flag to target development environment
  $0 --dev list
  $0 --dev export 1
  $0 --dev update 1 /workflows/01-ingestion/workflow.json
```

**Step 4: Test the changes**

Run: `./scripts/manage-workflow.sh --help`

Expected: Help output shows Dev Mode section

**Step 5: Commit**

```bash
git add scripts/manage-workflow.sh
git commit -m "feat: add --dev flag to manage-workflow.sh"
```

---

## Task 10: Update OPERATIONS.md Documentation

**Files:**
- Modify: `.claude/OPERATIONS.md`

**Step 1: Add Development Environment section**

Add a new section after the Docker Management section:

```markdown
## Development Environment

### Starting Development

```bash
# Start dev environment (creates dev database if needed)
./scripts/dev-start.sh

# Verify dev is running
docker ps | grep selene-dev

# Check current environment
cat .claude/CURRENT-ENV.md
```

### Development Workflow

```bash
# 1. Start dev environment
./scripts/dev-start.sh

# 2. Edit workflow JSON files
# (Use Read/Edit tools on workflows/XX-name/workflow.json)

# 3. Import to dev
./scripts/manage-workflow.sh --dev update <id> /workflows/XX-name/workflow.json

# 4. Test with dev database
./workflows/XX-name/scripts/test-with-markers.sh

# 5. When ready, promote to production
./scripts/promote-workflow.sh XX-name
```

### Dev Database Management

```bash
# Seed with sample data
./scripts/dev-seed-data.sh

# Reset to clean state (careful!)
./scripts/dev-reset-db.sh

# Query dev database
sqlite3 data/selene-dev.db "SELECT COUNT(*) FROM raw_notes;"
```

### Stopping Development

```bash
# Stop dev environment
./scripts/dev-stop.sh

# Production remains running on port 5678
```

### Environment Indicator

Claude should always check `.claude/CURRENT-ENV.md` before making changes:

- **PRODUCTION**: Do not modify workflows or test against production database
- **DEVELOPMENT**: Free to modify workflows and test against dev database
```

**Step 2: Commit**

```bash
git add .claude/OPERATIONS.md
git commit -m "docs: add development environment section to OPERATIONS.md"
```

---

## Task 11: Final Integration Test

**Step 1: Start dev environment**

Run: `./scripts/dev-start.sh`

Expected: Dev n8n starts on port 5679, CURRENT-ENV.md updated to DEVELOPMENT

**Step 2: Verify both environments running**

Run: `docker ps --format "table {{.Names}}\t{{.Ports}}"`

Expected:
```
NAMES              PORTS
selene         0.0.0.0:5678->5678/tcp
selene-dev     0.0.0.0:5679->5678/tcp
```

**Step 3: Seed dev database**

Run: `./scripts/dev-seed-data.sh`

Expected: Sample notes inserted into selene-dev.db

**Step 4: Verify data isolation**

Run:
```bash
echo "Production:" && sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE test_run LIKE 'seed-%';"
echo "Development:" && sqlite3 data/selene-dev.db "SELECT COUNT(*) FROM raw_notes WHERE test_run LIKE 'seed-%';"
```

Expected: Production = 0, Development = 5

**Step 5: Stop dev environment**

Run: `./scripts/dev-stop.sh`

Expected: Dev n8n stops, CURRENT-ENV.md updated to PRODUCTION

**Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete development environment isolation setup"
```

---

## Summary

| Task | Files | Purpose |
|------|-------|---------|
| 1 | docker-compose.yml | Add SELENE_ENV=production |
| 2 | docker-compose.dev.yml | Create dev stack config |
| 3 | .claude/CURRENT-ENV.md | Environment indicator |
| 4 | scripts/dev-start.sh | Start dev environment |
| 5 | scripts/dev-stop.sh | Stop dev environment |
| 6 | scripts/dev-reset-db.sh | Reset dev database |
| 7 | scripts/dev-seed-data.sh | Seed sample data |
| 8 | scripts/promote-workflow.sh | Checklist-driven promotion |
| 9 | scripts/manage-workflow.sh | Add --dev flag |
| 10 | .claude/OPERATIONS.md | Document dev workflow |
| 11 | Integration test | Verify everything works |
