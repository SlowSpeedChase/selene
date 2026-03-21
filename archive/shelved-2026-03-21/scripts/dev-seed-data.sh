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
