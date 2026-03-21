#!/bin/bash
# Show cluster statistics for note associations
# Usage: ./scripts/cluster-stats.sh

set -e

DB_PATH="${SELENE_DB_PATH:-$HOME/selene-data/selene.db}"

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found: $DB_PATH"
    exit 1
fi

echo "=== Note Cluster Statistics ==="
echo ""
echo "Database: $DB_PATH"
echo ""

# Overall stats
echo "--- Overall ---"
sqlite3 "$DB_PATH" "
    SELECT
        (SELECT COUNT(*) FROM raw_notes WHERE test_run IS NULL) as total_notes,
        (SELECT COUNT(*) FROM note_embeddings) as notes_with_embeddings,
        (SELECT COUNT(*) FROM note_associations) as total_associations;
" | awk -F'|' '{
    printf "Total production notes: %s\n", $1
    printf "Notes with embeddings:  %s\n", $2
    printf "Total associations:     %s\n", $3
}'

echo ""

# Similarity distribution
echo "--- Similarity Score Distribution ---"
sqlite3 "$DB_PATH" "
    SELECT
        CASE
            WHEN similarity_score >= 0.9 THEN '0.90+'
            WHEN similarity_score >= 0.8 THEN '0.80-0.89'
            WHEN similarity_score >= 0.7 THEN '0.70-0.79'
            ELSE 'below threshold'
        END as range,
        COUNT(*) as count,
        printf('%.3f', AVG(similarity_score)) as avg_similarity
    FROM note_associations
    GROUP BY range
    ORDER BY range DESC;
" | awk -F'|' 'BEGIN {
    print "Range        Count  Avg Similarity"
    print "----------   -----  --------------"
}
{
    printf "%-12s %5s  %s\n", $1, $2, $3
}'

echo ""

# Notes by association count
echo "--- Notes by Association Count ---"
sqlite3 "$DB_PATH" "
    WITH note_counts AS (
        SELECT note_id, COUNT(*) as assoc_count
        FROM (
            SELECT note_a_id as note_id FROM note_associations
            UNION ALL
            SELECT note_b_id as note_id FROM note_associations
        )
        GROUP BY note_id
    )
    SELECT
        CASE
            WHEN assoc_count >= 5 THEN '5+ associations (highly connected)'
            WHEN assoc_count >= 3 THEN '3-4 associations (clustered)'
            WHEN assoc_count >= 1 THEN '1-2 associations (some connections)'
            ELSE '0 associations (isolated)'
        END as category,
        COUNT(*) as note_count
    FROM note_counts
    GROUP BY category
    ORDER BY category DESC;
" | awk -F'|' 'BEGIN {
    print "Category                        Notes"
    print "------------------------------  -----"
}
{
    printf "%-30s  %5s\n", $1, $2
}'

echo ""

# Top connected notes
echo "--- Most Connected Notes (Top 10) ---"
sqlite3 -header -column "$DB_PATH" "
    WITH note_counts AS (
        SELECT note_id, COUNT(*) as assoc_count
        FROM (
            SELECT note_a_id as note_id FROM note_associations
            UNION ALL
            SELECT note_b_id as note_id FROM note_associations
        )
        GROUP BY note_id
    )
    SELECT
        nc.note_id,
        nc.assoc_count as connections,
        rn.title
    FROM note_counts nc
    JOIN raw_notes rn ON rn.id = nc.note_id
    ORDER BY nc.assoc_count DESC
    LIMIT 10;
"

echo ""

# Highest similarity pairs
echo "--- Highest Similarity Pairs (Top 10) ---"
sqlite3 -header -column "$DB_PATH" "
    SELECT
        na.note_a_id,
        na.note_b_id,
        printf('%.3f', na.similarity_score) as similarity,
        substr(rn1.title, 1, 25) as note_a_title,
        substr(rn2.title, 1, 25) as note_b_title
    FROM note_associations na
    JOIN raw_notes rn1 ON rn1.id = na.note_a_id
    JOIN raw_notes rn2 ON rn2.id = na.note_b_id
    ORDER BY na.similarity_score DESC
    LIMIT 10;
"

echo ""
echo "=== Phase 1 Verification Complete ==="
