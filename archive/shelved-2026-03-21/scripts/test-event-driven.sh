#!/bin/bash

# Test script for event-driven architecture
# This script sends a test note to the ingestion webhook and verifies processing

echo "=== Testing Event-Driven Architecture ==="
echo ""

# Create a test note
TEST_TITLE="Event-Driven Test $(date +%s)"
TEST_CONTENT="This is a test note to verify the event-driven architecture works correctly. Docker and n8n are being tested for webhook triggers. Testing concepts extraction and sentiment analysis."

echo "1. Sending test note to ingestion webhook..."
RESPONSE=$(curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"$TEST_TITLE\",
    \"content\": \"$TEST_CONTENT\",
    \"source_type\": \"test\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }")

echo "Response: $RESPONSE"
echo ""

# Extract note ID from response
NOTE_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('noteId', 'N/A'))")

if [ "$NOTE_ID" = "N/A" ]; then
  echo "❌ Failed to create note"
  exit 1
fi

echo "✓ Note created with ID: $NOTE_ID"
echo ""

# Wait a moment for processing to complete
echo "2. Waiting 5 seconds for processing to complete..."
sleep 5
echo ""

# Check database for the note status
echo "3. Checking database status..."
sqlite3 /Users/chaseeasterling/selene/data/selene.db << EOF
.mode column
.headers on
SELECT
  rn.id,
  rn.status as raw_status,
  pn.id as processed_id,
  json_array_length(pn.concepts) as concept_count,
  pn.primary_theme,
  pn.overall_sentiment
FROM raw_notes rn
LEFT JOIN processed_notes pn ON pn.raw_note_id = rn.id
WHERE rn.id = $NOTE_ID;
EOF

echo ""
echo "4. Verification complete!"
echo ""
echo "Expected results:"
echo "  - raw_status should be 'processed'"
echo "  - processed_id should be set"
echo "  - concept_count should be 3-5"
echo "  - primary_theme should be 'technical' or similar"
echo "  - overall_sentiment should be set"
