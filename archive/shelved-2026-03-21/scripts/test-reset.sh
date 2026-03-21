#!/bin/bash
# Reset test environment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=================================================="
echo "  Selene Test Environment Reset"
echo -e "==================================================${NC}"
echo ""
echo "This will:"
echo "  1. Delete all test notes from test database"
echo "  2. Clean test Obsidian vault"
echo "  3. Preserve production data (untouched)"
echo ""

# Show current test data
TEST_COUNT=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM raw_notes;" 2>/dev/null || echo "0")
echo "Current test notes: $TEST_COUNT"
echo ""

read -p "Continue with reset? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Reset cancelled."
  exit 0
fi

# Backup test database (optional)
if [ -f "data-test/selene-test.db" ] && [ "$TEST_COUNT" -gt 0 ]; then
  mkdir -p data-test/backups
  BACKUP_FILE="data-test/backups/selene-test-$(date +%Y%m%d-%H%M%S).db"
  echo -e "${YELLOW}Creating backup: $BACKUP_FILE${NC}"
  cp data-test/selene-test.db "$BACKUP_FILE"
  echo -e "${GREEN}✓ Backup created${NC}"
  echo ""
fi

# Delete test database
echo -e "${YELLOW}Resetting test database...${NC}"
rm -f data-test/selene-test.db

# Recreate test database
sqlite3 data-test/selene-test.db < database/schema.sql
echo -e "${GREEN}✓ Test database recreated${NC}"

# Clean test vault
echo ""
echo -e "${YELLOW}Cleaning test vault...${NC}"
rm -rf vault-test/Selene/Timeline/*/*.md 2>/dev/null || true
rm -rf vault-test/Selene/Concepts/*.md 2>/dev/null || true
rm -rf vault-test/Selene/Themes/*.md 2>/dev/null || true
rm -rf vault-test/Selene/Patterns/*.md 2>/dev/null || true
echo -e "${GREEN}✓ Test vault cleaned${NC}"

# Verify production is untouched
echo ""
echo -e "${YELLOW}Verifying production data...${NC}"
PROD_COUNT=$(sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes;" 2>/dev/null || echo "0")
echo "Production notes: $PROD_COUNT (unchanged)"

# Verify no test notes in production
PROD_TEST=$(sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE test_run IS NOT NULL;" 2>/dev/null || echo "0")
if [ "$PROD_TEST" -eq 0 ]; then
  echo -e "${GREEN}✓ Production is clean (no test notes)${NC}"
else
  echo -e "${RED}✗ WARNING: Found $PROD_TEST test notes in production!${NC}"
  echo "  Run: ./scripts/clean-production-database.sh"
fi

echo ""
echo -e "${GREEN}=================================================="
echo "  Test environment reset complete!"
echo ""
echo "  Next steps:"
echo "    1. Submit test note: ./scripts/test-ingest.sh"
echo "    2. Verify results: ./scripts/test-verify.sh <test_run>"
echo -e "==================================================${NC}"
