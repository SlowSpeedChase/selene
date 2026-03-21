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
