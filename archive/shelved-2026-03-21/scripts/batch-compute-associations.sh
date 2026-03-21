#!/bin/bash
#
# batch-compute-associations.sh
# Backfill associations for all notes with embeddings
#
# Usage:
#   ./scripts/batch-compute-associations.sh              # Default (0.5 second delay)
#   DELAY_SECONDS=1 ./scripts/batch-compute-associations.sh  # Slower
#
# Environment variables:
#   WEBHOOK_URL     - Association webhook URL (default: http://localhost:5678/webhook/api/associate)
#   SELENE_DB_PATH  - Database path (default: ./data/selene.db)
#   DELAY_SECONDS   - Delay between requests (default: 0.5)
#

set -euo pipefail

# Configuration
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:5678/webhook/api/associate}"
DB_PATH="${SELENE_DB_PATH:-./data/selene.db}"
DELAY_SECONDS="${DELAY_SECONDS:-0.5}"

echo "=== Batch Compute Associations ==="
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
echo ""

# Get notes with embeddings but no associations yet
# Note: We check if the note appears in EITHER column due to our storage convention
NOTE_IDS=$(sqlite3 "$DB_PATH" "
  SELECT DISTINCT ne.raw_note_id
  FROM note_embeddings ne
  WHERE NOT EXISTS (
    SELECT 1 FROM note_associations na
    WHERE ne.raw_note_id = na.note_a_id
       OR ne.raw_note_id = na.note_b_id
  )
  ORDER BY ne.raw_note_id
")

if [[ -z "$NOTE_IDS" ]]; then
  echo "All notes with embeddings already have associations. Nothing to do."
  exit 0
fi

# Progress tracking
TOTAL=$(echo "$NOTE_IDS" | wc -l | tr -d ' ')
CURRENT=0
SUCCESS=0
FAILED=0

echo "Found $TOTAL notes needing associations"
echo "Delay between requests: ${DELAY_SECONDS}s"
echo ""

for NOTE_ID in $NOTE_IDS; do
  CURRENT=$((CURRENT + 1))
  printf "[%d/%d] Computing associations for note %d... " "$CURRENT" "$TOTAL" "$NOTE_ID"

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

# Show association stats
echo ""
echo "=== Association Stats ==="
sqlite3 "$DB_PATH" "
  SELECT
    COUNT(*) as total_associations,
    ROUND(AVG(similarity_score), 3) as avg_similarity,
    ROUND(MIN(similarity_score), 3) as min_similarity,
    ROUND(MAX(similarity_score), 3) as max_similarity
  FROM note_associations
"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
