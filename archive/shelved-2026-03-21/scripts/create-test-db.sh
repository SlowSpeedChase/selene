#!/bin/bash
#
# create-test-db.sh - Create anonymized test database from production
#
# This script:
# 1. Copies production SQLite to data-test/
# 2. Anonymizes all personal content while preserving structure
# 3. Regenerates embeddings for anonymized content
# 4. Marks database as test environment
#
# Usage: ./scripts/create-test-db.sh [--skip-embeddings]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Paths
PROD_DB="${SELENE_DB_PATH:-$HOME/selene-data/selene.db}"
TEST_DIR="$PROJECT_ROOT/data-test"
TEST_DB="$TEST_DIR/selene.db"
TEST_VECTORS="$TEST_DIR/vectors.lance"
TEST_VAULT="$TEST_DIR/vault"
TEST_DIGESTS="$TEST_DIR/digests"

# Parse arguments
SKIP_EMBEDDINGS=false
for arg in "$@"; do
  case $arg in
    --skip-embeddings)
      SKIP_EMBEDDINGS=true
      shift
      ;;
  esac
done

echo -e "${GREEN}=== Selene Test Database Creator ===${NC}"
echo ""

# Check production database exists
if [ ! -f "$PROD_DB" ]; then
  echo -e "${RED}Error: Production database not found at $PROD_DB${NC}"
  echo "Set SELENE_DB_PATH environment variable if it's in a different location."
  exit 1
fi

# Confirm with user
echo -e "${YELLOW}This will:${NC}"
echo "  1. Copy production database from: $PROD_DB"
echo "  2. Anonymize all personal content"
echo "  3. Create test database at: $TEST_DB"
if [ "$SKIP_EMBEDDINGS" = false ]; then
  echo "  4. Regenerate embeddings (this takes a few minutes)"
fi
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Create test directories
echo -e "${GREEN}Creating test directories...${NC}"
mkdir -p "$TEST_DIR"
mkdir -p "$TEST_VAULT"
mkdir -p "$TEST_DIGESTS"

# Remove old test database if exists
if [ -f "$TEST_DB" ]; then
  echo "Removing old test database..."
  rm -f "$TEST_DB" "$TEST_DB-journal" "$TEST_DB-wal" "$TEST_DB-shm"
fi

# Remove old vector store
if [ -d "$TEST_VECTORS" ]; then
  echo "Removing old vector store..."
  rm -rf "$TEST_VECTORS"
fi

# Copy production database
echo -e "${GREEN}Copying production database...${NC}"
cp "$PROD_DB" "$TEST_DB"

# Create metadata table and mark as test
echo -e "${GREEN}Creating metadata table...${NC}"
sqlite3 "$TEST_DB" <<'SQL'
-- Create metadata table if not exists
CREATE TABLE IF NOT EXISTS _selene_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Mark as test environment
INSERT OR REPLACE INTO _selene_metadata (key, value, updated_at)
VALUES ('environment', 'test', datetime('now'));

INSERT OR REPLACE INTO _selene_metadata (key, value, updated_at)
VALUES ('anonymized_at', datetime('now'), datetime('now'));

INSERT OR REPLACE INTO _selene_metadata (key, value, updated_at)
VALUES ('source', 'production_anonymized', datetime('now'));
SQL

# Generate lorem ipsum content based on word count
generate_lorem() {
  local words=$1
  local lorem="Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua Ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum"

  # Repeat and truncate to approximate word count
  local result=""
  while [ $(echo "$result" | wc -w) -lt "$words" ]; do
    result="$result $lorem"
  done
  echo "$result" | tr -s ' ' | cut -d' ' -f1-"$words"
}

# Anonymize content
echo -e "${GREEN}Anonymizing content...${NC}"

# Step 1: Anonymize raw_notes
echo "  - Anonymizing raw_notes..."
sqlite3 "$TEST_DB" <<'SQL'
-- Anonymize titles
UPDATE raw_notes SET title = 'Note ' || printf('%05d', id);

-- Anonymize tags (keep structure, replace values)
UPDATE raw_notes SET tags =
  CASE
    WHEN tags IS NULL THEN NULL
    WHEN tags = '[]' THEN '[]'
    ELSE (
      SELECT json_group_array('tag_' || value)
      FROM (
        SELECT key as value FROM json_each(tags)
      )
    )
  END;

-- Clear source_uuid (personal identifier)
UPDATE raw_notes SET source_uuid = NULL;

-- Clear test_run markers
UPDATE raw_notes SET test_run = NULL;
SQL

# Step 2: Generate lorem ipsum content based on word counts
# This is done in a separate step because we need to generate variable-length content
echo "  - Generating anonymized content..."
sqlite3 "$TEST_DB" "SELECT id, word_count FROM raw_notes" | while IFS='|' read -r id word_count; do
  if [ -z "$word_count" ] || [ "$word_count" -eq 0 ]; then
    word_count=50
  fi

  # Generate lorem content
  content=$(generate_lorem "$word_count")

  # Escape for SQLite
  escaped_content=$(echo "$content" | sed "s/'/''/g")

  # Update the note
  sqlite3 "$TEST_DB" "UPDATE raw_notes SET content = '$escaped_content' WHERE id = $id"

  # Recalculate content hash
  hash=$(echo "$content" | shasum -a 256 | cut -d' ' -f1)
  sqlite3 "$TEST_DB" "UPDATE raw_notes SET content_hash = '$hash' WHERE id = $id"
done

# Step 3: Anonymize processed_notes
echo "  - Anonymizing processed_notes..."
sqlite3 "$TEST_DB" <<'SQL'
-- Anonymize concepts
UPDATE processed_notes SET concepts =
  CASE
    WHEN concepts IS NULL THEN NULL
    WHEN concepts = '[]' THEN '[]'
    ELSE (
      SELECT json_group_array('concept_' || (key + 1))
      FROM json_each(concepts)
    )
  END;

-- Anonymize concept_confidence
UPDATE processed_notes SET concept_confidence =
  CASE
    WHEN concept_confidence IS NULL THEN NULL
    ELSE '{}'
  END;

-- Anonymize primary_theme
UPDATE processed_notes SET primary_theme = 'theme_' || id
WHERE primary_theme IS NOT NULL;

-- Anonymize secondary_themes
UPDATE processed_notes SET secondary_themes =
  CASE
    WHEN secondary_themes IS NULL THEN NULL
    WHEN secondary_themes = '[]' THEN '[]'
    ELSE '["secondary_theme_1", "secondary_theme_2"]'
  END;

-- Clear sentiment data (personal emotional content)
UPDATE processed_notes SET
  sentiment_data = NULL,
  overall_sentiment = CASE
    WHEN overall_sentiment IS NOT NULL
    THEN (CASE (id % 3) WHEN 0 THEN 'positive' WHEN 1 THEN 'neutral' ELSE 'negative' END)
    ELSE NULL
  END,
  emotional_tone = NULL,
  energy_level = CASE
    WHEN energy_level IS NOT NULL
    THEN (CASE (id % 3) WHEN 0 THEN 'high' WHEN 1 THEN 'medium' ELSE 'low' END)
    ELSE NULL
  END;
SQL

# Step 4: Anonymize threads
echo "  - Anonymizing threads..."
sqlite3 "$TEST_DB" <<'SQL'
UPDATE threads SET
  name = 'Thread ' || printf('%03d', id),
  why = 'Underlying motivation for thread ' || id,
  summary = 'This thread contains notes about concept_' || id || ' and related topics.';
SQL

# Step 5: Anonymize thread_history
echo "  - Anonymizing thread_history..."
sqlite3 "$TEST_DB" <<'SQL'
UPDATE thread_history SET
  summary_before = CASE WHEN summary_before IS NOT NULL THEN 'Previous summary for thread.' ELSE NULL END,
  summary_after = CASE WHEN summary_after IS NOT NULL THEN 'Updated summary for thread.' ELSE NULL END;
SQL

# Step 6: Clear chat sessions entirely (personal conversations)
echo "  - Clearing chat sessions..."
sqlite3 "$TEST_DB" <<'SQL'
DELETE FROM chat_sessions;
SQL

# Step 7: Clear conversations and memories (highly personal)
echo "  - Clearing conversations and memories..."
sqlite3 "$TEST_DB" <<'SQL'
DELETE FROM conversations WHERE 1=1;
DELETE FROM conversation_memories WHERE 1=1;
SQL

# Step 8: Anonymize feedback_notes
echo "  - Anonymizing feedback_notes..."
sqlite3 "$TEST_DB" <<'SQL'
UPDATE feedback_notes SET
  content = 'Anonymized feedback content ' || id,
  content_hash = 'anon_hash_' || id,
  user_story = CASE WHEN user_story IS NOT NULL THEN 'As a user, I want feature ' || id ELSE NULL END,
  test_run = NULL;
SQL

# Step 9: Anonymize detected_patterns
echo "  - Anonymizing detected_patterns..."
sqlite3 "$TEST_DB" <<'SQL'
UPDATE detected_patterns SET
  pattern_name = 'pattern_' || id,
  description = 'Anonymized pattern description',
  pattern_data = '{}',
  insights = 'Anonymized insight for pattern ' || id;
SQL

# Step 10: Anonymize sentiment_history
echo "  - Anonymizing sentiment_history..."
sqlite3 "$TEST_DB" <<'SQL'
UPDATE sentiment_history SET
  key_emotions = '["emotion_1", "emotion_2"]',
  adhd_markers = '{}';
SQL

# Step 11: Clear embeddings (will regenerate)
if [ "$SKIP_EMBEDDINGS" = false ]; then
  echo "  - Clearing embeddings (will regenerate)..."
  sqlite3 "$TEST_DB" "DELETE FROM note_embeddings"
fi

# Summary
echo ""
echo -e "${GREEN}=== Anonymization Complete ===${NC}"
echo ""
echo "Statistics:"
sqlite3 "$TEST_DB" <<'SQL'
SELECT 'raw_notes: ' || COUNT(*) FROM raw_notes;
SELECT 'processed_notes: ' || COUNT(*) FROM processed_notes;
SELECT 'threads: ' || COUNT(*) FROM threads;
SELECT 'note_associations: ' || COUNT(*) FROM note_associations;
SQL

echo ""
echo -e "${GREEN}Test database created at: $TEST_DB${NC}"

# Regenerate embeddings
if [ "$SKIP_EMBEDDINGS" = false ]; then
  echo ""
  echo -e "${YELLOW}Regenerating embeddings (this may take a few minutes)...${NC}"
  cd "$PROJECT_ROOT"
  SELENE_ENV=test npx ts-node src/workflows/compute-embeddings.ts
  echo -e "${GREEN}Embeddings regenerated.${NC}"
fi

echo ""
echo -e "${GREEN}=== Test Environment Ready ===${NC}"
echo ""
echo "To use the test environment:"
echo "  export SELENE_ENV=test"
echo "  npx ts-node src/workflows/process-llm.ts"
echo ""
echo "Or use the .env.development file (auto-loaded)."
