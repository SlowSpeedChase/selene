#!/bin/bash
# Generate backlog markdown from database
# Uses feedback_notes with status='added_to_backlog'

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_PATH="${SELENE_DB_PATH:-$PROJECT_ROOT/data/selene.db}"
OUTPUT_FILE="$PROJECT_ROOT/docs/backlog/user-stories.md"

# Check database exists
if [ ! -f "$DB_PATH" ]; then
  echo "Error: Database not found at $DB_PATH"
  exit 1
fi

# Generate markdown
cat > "$OUTPUT_FILE" << 'HEADER'
# Selene Development Backlog

Auto-generated from feedback_notes database.

HEADER

echo "Last updated: $(date -u '+%Y-%m-%d %H:%M:%S') UTC" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# User Stories
echo "## User Stories" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| ID | Story | Priority | Status | Source Date |" >> "$OUTPUT_FILE"
echo "|----|-------|----------|--------|-------------|" >> "$OUTPUT_FILE"
sqlite3 "$DB_PATH" -separator '|' "
  SELECT
    backlog_id,
    REPLACE(substr(content, 1, 60), '|', '-'),
    '-',
    'Open',
    date(created_at)
  FROM feedback_notes
  WHERE category = 'user_story' AND status = 'added_to_backlog' AND test_run IS NULL
  ORDER BY backlog_id
" | while read line; do echo "| $line |" >> "$OUTPUT_FILE"; done
echo "" >> "$OUTPUT_FILE"

# Feature Requests
echo "## Feature Requests" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| ID | Request | Priority | Status | Source Date |" >> "$OUTPUT_FILE"
echo "|----|---------|----------|--------|-------------|" >> "$OUTPUT_FILE"
sqlite3 "$DB_PATH" -separator '|' "
  SELECT
    backlog_id,
    REPLACE(substr(content, 1, 60), '|', '-'),
    '-',
    'Open',
    date(created_at)
  FROM feedback_notes
  WHERE category = 'feature_request' AND status = 'added_to_backlog' AND test_run IS NULL
  ORDER BY backlog_id
" | while read line; do echo "| $line |" >> "$OUTPUT_FILE"; done
echo "" >> "$OUTPUT_FILE"

# Bugs
echo "## Bugs" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| ID | Issue | Priority | Status | Source Date |" >> "$OUTPUT_FILE"
echo "|----|-------|----------|--------|-------------|" >> "$OUTPUT_FILE"
sqlite3 "$DB_PATH" -separator '|' "
  SELECT
    backlog_id,
    REPLACE(substr(content, 1, 60), '|', '-'),
    '-',
    'Open',
    date(created_at)
  FROM feedback_notes
  WHERE category = 'bug' AND status = 'added_to_backlog' AND test_run IS NULL
  ORDER BY backlog_id
" | while read line; do echo "| $line |" >> "$OUTPUT_FILE"; done
echo "" >> "$OUTPUT_FILE"

# Improvements
echo "## Improvements" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| ID | Enhancement | Priority | Status | Source Date |" >> "$OUTPUT_FILE"
echo "|----|-------------|----------|--------|-------------|" >> "$OUTPUT_FILE"
sqlite3 "$DB_PATH" -separator '|' "
  SELECT
    backlog_id,
    REPLACE(substr(content, 1, 60), '|', '-'),
    '-',
    'Open',
    date(created_at)
  FROM feedback_notes
  WHERE category = 'improvement' AND status = 'added_to_backlog' AND test_run IS NULL
  ORDER BY backlog_id
" | while read line; do echo "| $line |" >> "$OUTPUT_FILE"; done
echo "" >> "$OUTPUT_FILE"

echo "## Completed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "| ID | Description | Completed | Reference |" >> "$OUTPUT_FILE"
echo "|----|-------------|-----------|-----------|" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Backlog generated: $OUTPUT_FILE"
