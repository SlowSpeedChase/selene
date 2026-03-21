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
  echo -e "${GREEN}Wipe complete. To reseed:${NC}"
  echo "  1. Generate fixture: paste scripts/dev-data-prompt.md into an LLM"
  echo "  2. Save output to: fixtures/dev-seed-notes.json"
  echo "  3. Run: SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts"
  exit 0
fi

# Check fixture exists
FIXTURE="$PROJECT_ROOT/fixtures/dev-seed-notes.json"
if [ ! -f "$FIXTURE" ]; then
  echo ""
  echo -e "${YELLOW}Fixture file not found: $FIXTURE${NC}"
  echo ""
  echo "To generate seed data:"
  echo "  1. Paste scripts/dev-data-prompt.md into an LLM (Claude, ChatGPT, etc.)"
  echo "  2. Save the JSON output to: fixtures/dev-seed-notes.json"
  echo "  3. Run: SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts"
  exit 0
fi

# Seed
echo ""
echo -e "${GREEN}Seeding dev database...${NC}"
cd "$PROJECT_ROOT"
SELENE_ENV=development npx ts-node scripts/seed-dev-data.ts

echo ""
echo -e "${GREEN}=== Dev Environment Reset Complete ===${NC}"
