#!/usr/bin/env bash
# Rebuild the combined Selene user guide (hub + 5 feature guides) and email it to Kindle.
# Reads docs from this repo, writes the combined markdown into the folio repo, then uses
# folio's send-report.ts to render a PDF and email it to KINDLE_EMAIL.
#
# Usage: scripts/send-selene-guide-to-kindle.sh
# Safe to run anytime. Logs to logs/selene-guide-kindle.log.

set -euo pipefail

SELENE_DIR="/Users/chaseeasterling/selene"
FOLIO_DIR="/Users/chaseeasterling/folio"
COMBINED_REL="reports/selene-complete-user-guide.md"
LOG="$SELENE_DIR/logs/selene-guide-kindle.log"

mkdir -p "$SELENE_DIR/logs"
exec >>"$LOG" 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') regenerating Selene guide ====="

# 1. Build the combined markdown (output path is hard-coded in the assembler to the folio reports dir).
node "$SELENE_DIR/scripts/build-selene-guide.js"

# 2. Render to PDF and email to Kindle via folio.
cd "$FOLIO_DIR"
npx ts-node scripts/send-report.ts "$COMBINED_REL"

echo "done."
