#!/bin/bash
#
# reset-dev-data.sh - Wipe and rebuild the Selene development sandbox from scratch.
#
# Steps:
#   1. Refuse if SELENE_ENV=production (never touch prod).
#   2. Wipe ~/selene-data-dev/ entirely.
#   3. Recreate the schema via create-dev-db.sh (non-interactive — dir is gone).
#   4. Seed fictional notes via seed-dev-data.ts (pending status).
#
# Idempotent: safe to run repeatedly; each run produces the same fixture
# (the generator is deterministically seeded).
#
# Usage:
#   ./scripts/reset-dev-data.sh             # 500 notes (default)
#   ./scripts/reset-dev-data.sh 300         # custom note count
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Resolve script + project directories (works regardless of cwd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEV_DIR="$HOME/selene-data-dev"
NOTE_COUNT="${1:-500}"

# Safety: never run against production.
if [ "${SELENE_ENV:-}" = "production" ]; then
  echo -e "${RED}Refusing to run: SELENE_ENV=production.${NC}"
  echo "reset-dev-data.sh only operates on the development sandbox (~/selene-data-dev)."
  exit 1
fi

echo -e "${GREEN}=== Selene Dev Data Reset ===${NC}"
echo ""

# Step 1: Wipe the dev directory so create-dev-db.sh runs non-interactively
# (it only prompts to overwrite when the DB file already exists).
echo -e "${YELLOW}Step 1: Wiping ${DEV_DIR}...${NC}"
rm -rf "$DEV_DIR"
echo -e "  ${GREEN}Removed${NC} $DEV_DIR"
echo ""

# Step 2: Recreate schema + environment marker.
echo -e "${YELLOW}Step 2: Recreating dev database...${NC}"
bash "$SCRIPT_DIR/create-dev-db.sh"
echo ""

# Step 3: Seed fictional notes. SELENE_ENV=development routes config.dbPath to
# ~/selene-data-dev/selene.db; seed-dev-data.ts independently verifies the
# 'development' marker before writing.
echo -e "${YELLOW}Step 3: Seeding ${NOTE_COUNT} fictional notes...${NC}"
SELENE_ENV=development npx ts-node "$SCRIPT_DIR/seed-dev-data.ts" --count "$NOTE_COUNT"
echo ""

echo -e "${GREEN}=== Reset complete ===${NC}"
echo "Run the pipeline with: SELENE_ENV=development ./scripts/dev-process-batch.sh"
