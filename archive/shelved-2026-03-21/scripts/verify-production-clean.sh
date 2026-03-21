#!/bin/bash
# Verify Production Database is Clean
# This script checks that production has no test notes

PROD_DB="/Users/chaseeasterling/selene/data/selene.db"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Checking production database cleanliness..."
echo ""

# Check if database exists
if [ ! -f "$PROD_DB" ]; then
    echo -e "${RED}✗ Production database not found at $PROD_DB${NC}"
    exit 1
fi

# Count test notes
TEST_COUNT=$(sqlite3 "$PROD_DB" "SELECT COUNT(*) FROM raw_notes WHERE test_run IS NOT NULL;")

if [ "$TEST_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ Production database is CLEAN${NC}"
    echo -e "${GREEN}✓ No test notes found${NC}"

    # Show production stats
    echo ""
    echo "Production statistics:"
    sqlite3 "$PROD_DB" <<EOF
.mode column
.headers on
SELECT
  COUNT(*) as total_production_notes,
  SUM(CASE WHEN status = 'processed' THEN 1 ELSE 0 END) as processed,
  SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
  SUM(CASE WHEN exported_to_obsidian = 1 THEN 1 ELSE 0 END) as exported
FROM raw_notes
WHERE test_run IS NULL;
EOF
    exit 0
else
    echo -e "${RED}✗ CONTAMINATED: Found $TEST_COUNT test note(s) in production!${NC}"
    echo ""
    echo "Test notes in production:"
    sqlite3 "$PROD_DB" <<EOF
.mode column
.headers on
SELECT id, title, test_run, created_at FROM raw_notes WHERE test_run IS NOT NULL;
EOF
    echo ""
    echo -e "${YELLOW}Run ./scripts/clean-production-database.sh to remove them${NC}"
    exit 1
fi
