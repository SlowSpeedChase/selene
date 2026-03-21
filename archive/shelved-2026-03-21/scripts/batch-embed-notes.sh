#!/bin/bash
#
# batch-embed-notes.sh
# Backfill embeddings for all existing processed notes
#
# Usage:
#   ./scripts/batch-embed-notes.sh              # Default (1 second delay)
#   DELAY_SECONDS=0.5 ./scripts/batch-embed-notes.sh  # Faster
#
# Environment variables:
#   WEBHOOK_URL     - Embedding webhook URL (default: http://localhost:5678/webhook/api/embed)
#   SELENE_DB_PATH  - Database path (default: ./data/selene.db)
#   DELAY_SECONDS   - Delay between requests (default: 1)
#

set -euo pipefail

# Configuration
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:5678/webhook/api/embed}"
DB_PATH="${SELENE_DB_PATH:-./data/selene.db}"
DELAY_SECONDS="${DELAY_SECONDS:-1}"

echo "=== Batch Embed Notes ==="
echo ""

# Pre-flight check: Database exists
if [[ ! -f "$DB_PATH" ]]; then
  echo "ERROR: Database not found at $DB_PATH"
  exit 1
fi
echo "Database: $DB_PATH"

# Pre-flight check: n8n reachable
if ! curl -s --max-time 5 "http://localhost:5678/healthz" > /dev/null 2>&1; then
  echo "ERROR: n8n not reachable at localhost:5678"
  exit 1
fi
echo "n8n: reachable"

# Pre-flight check: Ollama reachable
if ! curl -s --max-time 5 "http://localhost:11434/api/tags" > /dev/null 2>&1; then
  echo "ERROR: Ollama not reachable at localhost:11434"
  exit 1
fi
echo "Ollama: reachable"
echo ""

# Get notes needing embeddings
# Notes that have processed_notes entry but no embedding yet
NOTE_IDS=$(sqlite3 "$DB_PATH" "
  SELECT DISTINCT pn.raw_note_id
  FROM processed_notes pn
  LEFT JOIN note_embeddings ne ON pn.raw_note_id = ne.raw_note_id
  WHERE ne.id IS NULL
  ORDER BY pn.raw_note_id
")

if [[ -z "$NOTE_IDS" ]]; then
  echo "All notes already have embeddings. Nothing to do."
  exit 0
fi

# Progress tracking
TOTAL=$(echo "$NOTE_IDS" | wc -l | tr -d ' ')
CURRENT=0
SUCCESS=0
FAILED=0

echo "Found $TOTAL notes needing embeddings"
echo "Delay between requests: ${DELAY_SECONDS}s"
echo ""

for NOTE_ID in $NOTE_IDS; do
  CURRENT=$((CURRENT + 1))
  printf "[%d/%d] Embedding note %d... " "$CURRENT" "$TOTAL" "$NOTE_ID"

  # Call webhook, capture response and HTTP code
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"note_id\": $NOTE_ID}" 2>/dev/null || echo -e "\n000")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "done"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "FAILED (HTTP $HTTP_CODE)"
    FAILED=$((FAILED + 1))
  fi

  # Rate limit (skip on last item)
  if [[ "$CURRENT" -lt "$TOTAL" ]]; then
    sleep "$DELAY_SECONDS"
  fi
done

echo ""
echo "=== Complete ==="
echo "Success: $SUCCESS"
echo "Failed:  $FAILED"
echo "Total:   $TOTAL"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
