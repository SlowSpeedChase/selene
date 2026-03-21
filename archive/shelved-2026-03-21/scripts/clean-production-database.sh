#!/bin/bash
# Clean Production Database - Remove all test notes
# This script removes test notes from production and ensures production stays clean

set -e  # Exit on error

PROD_DB="/Users/chaseeasterling/selene/data/selene.db"
BACKUP_DIR="/Users/chaseeasterling/selene/data/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "  Selene Production Database Cleanup"
echo "=================================================="
echo ""

# Check if database exists
if [ ! -f "$PROD_DB" ]; then
    echo -e "${RED}Error: Production database not found at $PROD_DB${NC}"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Show current state
echo -e "${YELLOW}Current database state:${NC}"
sqlite3 "$PROD_DB" <<EOF
.mode column
.headers on
SELECT
  COUNT(*) as total_notes,
  SUM(CASE WHEN test_run IS NULL THEN 1 ELSE 0 END) as production_notes,
  SUM(CASE WHEN test_run IS NOT NULL THEN 1 ELSE 0 END) as test_notes
FROM raw_notes;
EOF

echo ""

# Check if there are any test notes
TEST_COUNT=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM raw_notes WHERE test_run IS NOT NULL;")

if [ "$TEST_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ Production database is already clean! No test notes found.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found $TEST_COUNT test note(s) in production database${NC}"
echo ""
echo "Test notes to be removed:"
sqlite3 "$PROD_DB" <<EOF
.mode column
.headers on
SELECT id, title, test_run, created_at FROM raw_notes WHERE test_run IS NOT NULL;
EOF

echo ""
read -p "Do you want to remove these test notes? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Create backup
BACKUP_FILE="$BACKUP_DIR/selene-pre-cleanup-$(date +%Y%m%d-%H%M%S).db"
echo ""
echo -e "${YELLOW}Creating backup...${NC}"
cp "$PROD_DB" "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"

# Remove test notes
echo ""
echo -e "${YELLOW}Removing test notes from production...${NC}"

# Get IDs of test notes for cleanup
TEST_NOTE_IDS=$(sqlite3 "$PROD_DB" "SELECT id FROM raw_notes WHERE test_run IS NOT NULL;")

# Delete from processed_notes first (foreign key constraint)
for id in $TEST_NOTE_IDS; do
    sqlite3 "$PROD_DB" "DELETE FROM processed_notes WHERE raw_note_id = $id;"
done

# Delete from processed_notes_apple if exists
for id in $TEST_NOTE_IDS; do
    sqlite3 "$PROD_DB" "DELETE FROM processed_notes_apple WHERE raw_note_id = $id;" 2>/dev/null || true
done

# Delete from raw_notes
sqlite3 "$PROD_DB" "DELETE FROM raw_notes WHERE test_run IS NOT NULL;"

echo -e "${GREEN}✓ Test notes removed${NC}"

# Vacuum database to reclaim space
echo ""
echo -e "${YELLOW}Optimizing database...${NC}"
sqlite3 "$PROD_DB" "VACUUM;"
echo -e "${GREEN}✓ Database optimized${NC}"

# Show final state
echo ""
echo -e "${GREEN}Final database state:${NC}"
sqlite3 "$PROD_DB" <<EOF
.mode column
.headers on
SELECT
  COUNT(*) as total_notes,
  SUM(CASE WHEN test_run IS NULL THEN 1 ELSE 0 END) as production_notes,
  SUM(CASE WHEN test_run IS NOT NULL THEN 1 ELSE 0 END) as test_notes
FROM raw_notes;
EOF

# Verify no test notes remain
REMAINING_TEST=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM raw_notes WHERE test_run IS NOT NULL;")
if [ "$REMAINING_TEST" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=================================================="
    echo -e "  ✓ Production database is now clean!"
    echo -e "  ✓ All test notes removed"
    echo -e "  ✓ Backup saved to: $BACKUP_FILE"
    echo -e "==================================================${NC}"
else
    echo -e "${RED}Warning: Some test notes may still remain${NC}"
    exit 1
fi

echo ""
echo "Next steps:"
echo "1. Set up test environment with separate database (./data-test/selene-test.db)"
echo "2. Update workflows to reject test_run in production ingestion"
echo "3. Use test webhooks (/api/test/*) for all testing"
echo ""
