#!/bin/bash
# Query similar notes for a given note ID
# Usage: ./scripts/query-similar-notes.sh <note_id> [limit]

set -e

NOTE_ID="${1:-}"
LIMIT="${2:-10}"
DB_PATH="${SELENE_DB_PATH:-$HOME/selene-data/selene.db}"

if [ -z "$NOTE_ID" ]; then
    echo "Usage: $0 <note_id> [limit]"
    echo ""
    echo "Examples:"
    echo "  $0 21         # Find notes similar to note 21"
    echo "  $0 21 5       # Top 5 similar notes"
    echo ""
    echo "Environment:"
    echo "  SELENE_DB_PATH  Database path (default: ~/selene-data/selene.db)"
    exit 1
fi

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found: $DB_PATH"
    exit 1
fi

echo "=== Similar Notes for Note $NOTE_ID ==="
echo ""

# Get the source note info
SOURCE_INFO=$(sqlite3 "$DB_PATH" "
    SELECT id, title, substr(content, 1, 100) as preview
    FROM raw_notes
    WHERE id = $NOTE_ID
")

if [ -z "$SOURCE_INFO" ]; then
    echo "ERROR: Note $NOTE_ID not found"
    exit 1
fi

echo "Source Note:"
echo "$SOURCE_INFO" | awk -F'|' '{
    printf "  ID: %s\n", $1
    printf "  Title: %s\n", $2
    printf "  Preview: %s...\n", $3
}'
echo ""

# Check if note has embedding
HAS_EMBEDDING=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM note_embeddings WHERE raw_note_id = $NOTE_ID
")

if [ "$HAS_EMBEDDING" -eq 0 ]; then
    echo "WARNING: Note $NOTE_ID has no embedding"
    echo "Run the embedding workflow first:"
    echo "  curl -X POST http://localhost:5678/webhook/api/embed -d '{\"note_id\": $NOTE_ID}'"
    exit 1
fi

# Query associations (note_a_id < note_b_id convention)
echo "Similar Notes (top $LIMIT, threshold >= 0.7):"
echo "---"

sqlite3 -header -column "$DB_PATH" "
    SELECT
        CASE
            WHEN na.note_a_id = $NOTE_ID THEN na.note_b_id
            ELSE na.note_a_id
        END as similar_note_id,
        printf('%.3f', na.similarity_score) as similarity,
        rn.title,
        substr(rn.content, 1, 80) as preview
    FROM note_associations na
    JOIN raw_notes rn ON rn.id = CASE
        WHEN na.note_a_id = $NOTE_ID THEN na.note_b_id
        ELSE na.note_a_id
    END
    WHERE na.note_a_id = $NOTE_ID OR na.note_b_id = $NOTE_ID
    ORDER BY na.similarity_score DESC
    LIMIT $LIMIT;
"

echo ""
echo "---"

# Count total associations
TOTAL=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM note_associations
    WHERE note_a_id = $NOTE_ID OR note_b_id = $NOTE_ID
")
echo "Total associations: $TOTAL"
