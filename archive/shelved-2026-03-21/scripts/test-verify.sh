#!/bin/bash
# Verify test note processing

set -e

TEST_RUN="${1}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$TEST_RUN" ]; then
  echo -e "${RED}Usage: $0 <test_run>${NC}"
  echo ""
  echo "Available test runs:"
  sqlite3 data-test/selene-test.db "SELECT DISTINCT test_run FROM raw_notes ORDER BY test_run;"
  exit 1
fi

echo -e "${BLUE}=================================================="
echo "  Test Verification: $TEST_RUN"
echo -e "==================================================${NC}"
echo ""

# Check raw notes
echo -e "${YELLOW}1. Raw Notes (Ingestion):${NC}"
sqlite3 data-test/selene-test.db <<EOF
.mode column
.headers on
SELECT id, title, status, word_count, created_at
FROM raw_notes
WHERE test_run = '$TEST_RUN'
ORDER BY id;
EOF

echo ""

# Check processed notes
echo -e "${YELLOW}2. Processed Notes (LLM Processing):${NC}"
HAS_PROCESSED=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM processed_notes pn JOIN raw_notes rn ON pn.raw_note_id = rn.id WHERE rn.test_run = '$TEST_RUN';")

if [ "$HAS_PROCESSED" -gt 0 ]; then
  sqlite3 data-test/selene-test.db <<EOF
.mode column
.headers on
SELECT
  pn.id,
  rn.title,
  substr(pn.concepts, 1, 40) as concepts,
  pn.primary_theme,
  pn.overall_sentiment
FROM processed_notes pn
JOIN raw_notes rn ON pn.raw_note_id = rn.id
WHERE rn.test_run = '$TEST_RUN'
ORDER BY pn.id;
EOF
else
  echo -e "${RED}  No processed notes found yet${NC}"
  echo "  LLM processing may still be running..."
fi

echo ""

# Check sentiment analysis
echo -e "${YELLOW}3. Sentiment Analysis:${NC}"
HAS_SENTIMENT=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM processed_notes pn JOIN raw_notes rn ON pn.raw_note_id = rn.id WHERE rn.test_run = '$TEST_RUN' AND pn.sentiment_analyzed = 1;")

if [ "$HAS_SENTIMENT" -gt 0 ]; then
  sqlite3 data-test/selene-test.db <<EOF
.mode column
.headers on
SELECT
  pn.overall_sentiment,
  pn.sentiment_score,
  pn.emotional_tone,
  pn.energy_level,
  pn.sentiment_analyzed
FROM processed_notes pn
JOIN raw_notes rn ON pn.raw_note_id = rn.id
WHERE rn.test_run = '$TEST_RUN'
ORDER BY pn.id;
EOF
else
  echo -e "${RED}  No sentiment analysis found yet${NC}"
  echo "  Sentiment analysis may still be running..."
fi

echo ""

# Check Obsidian export
echo -e "${YELLOW}4. Obsidian Export:${NC}"
HAS_EXPORTED=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM raw_notes WHERE test_run = '$TEST_RUN' AND exported_to_obsidian = 1;")

if [ "$HAS_EXPORTED" -gt 0 ]; then
  echo -e "${GREEN}  ✓ Exported to Obsidian${NC}"

  # Find exported files
  echo ""
  echo "  Exported files:"
  find vault-test/Selene -name "*.md" -type f -newer data-test/selene-test.db | head -5
else
  echo -e "${RED}  ✗ Not yet exported to Obsidian${NC}"
  echo "  Export may still be running..."
fi

echo ""
echo -e "${BLUE}=================================================="

# Summary
TOTAL=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM raw_notes WHERE test_run = '$TEST_RUN';")
PROCESSED=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM processed_notes pn JOIN raw_notes rn ON pn.raw_note_id = rn.id WHERE rn.test_run = '$TEST_RUN';")
SENTIMENT=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM processed_notes pn JOIN raw_notes rn ON pn.raw_note_id = rn.id WHERE rn.test_run = '$TEST_RUN' AND pn.sentiment_analyzed = 1;")
EXPORTED=$(sqlite3 data-test/selene-test.db "SELECT COUNT(*) FROM raw_notes WHERE test_run = '$TEST_RUN' AND exported_to_obsidian = 1;")

echo ""
echo -e "${GREEN}Summary for test run: $TEST_RUN${NC}"
echo "  Total notes: $TOTAL"
echo "  Processed: $PROCESSED / $TOTAL"
echo "  Sentiment analyzed: $SENTIMENT / $TOTAL"
echo "  Exported: $EXPORTED / $TOTAL"
echo ""

if [ "$TOTAL" -eq "$EXPORTED" ] && [ "$TOTAL" -gt 0 ]; then
  echo -e "${GREEN}  ✓ All notes fully processed!${NC}"
else
  echo -e "${YELLOW}  ⏳ Processing in progress...${NC}"
  echo "  Run this script again in 30-60 seconds"
fi

echo -e "${BLUE}==================================================${NC}"
