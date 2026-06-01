#!/bin/bash
# Cleanup test data from the database by test_run marker.
#
# Fact-store aware: captured notes live in facts.captured_notes (facts.db); derived rows
# (processed_notes, note_embeddings, note_associations) + bookkeeping (note_state) live in selene.db.
# A LEGACY single-file DB (raw_notes still physical, no facts.db) is handled too.
#
# Usage: ./scripts/cleanup-tests.sh [--list | --all | <test-run-id>]

set -e

DB_PATH="${SELENE_DB_PATH:-./data/selene.db}"
# facts.db sits beside selene.db (mirrors config.getFactsDbPath); override with SELENE_FACTS_DB_PATH.
FACTS_PATH="${SELENE_FACTS_DB_PATH:-$(dirname "$DB_PATH")/facts.db}"

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found: $DB_PATH"
    exit 1
fi

# Where captured notes live: two-file (facts.captured_notes) if facts.db exists, else legacy raw_notes.
if [ -f "$FACTS_PATH" ]; then
    CAPTURES_DB="$FACTS_PATH"
    CAPTURES_TABLE="captured_notes"
else
    CAPTURES_DB="$DB_PATH"
    CAPTURES_TABLE="raw_notes"
fi

list_test_runs() {
    echo "Test runs in database (${CAPTURES_TABLE}):"
    echo "----------------------"
    sqlite3 "$CAPTURES_DB" "
        SELECT test_run, COUNT(*) as count
        FROM ${CAPTURES_TABLE}
        WHERE test_run IS NOT NULL
        GROUP BY test_run
        ORDER BY test_run DESC;
    "
}

# Delete derived rows (selene.db) matching a test_run predicate, then prune orphaned note_state.
# $1 = a SQL predicate on the `test_run` column (e.g. "test_run = 'x'" or "test_run IS NOT NULL").
cleanup_derived() {
    local where="$1"
    sqlite3 "$DB_PATH" "DELETE FROM processed_notes WHERE ${where};" 2>/dev/null || true
    sqlite3 "$DB_PATH" "DELETE FROM note_embeddings WHERE ${where};" 2>/dev/null || true
    sqlite3 "$DB_PATH" "DELETE FROM note_associations WHERE ${where};" 2>/dev/null || true
    # note_state has no test_run (it's keyed by raw_note_id); prune rows whose capture was just
    # deleted. Two-file only — needs facts.captured_notes attached to see surviving ids.
    if [ "$CAPTURES_TABLE" = "captured_notes" ]; then
        sqlite3 "$DB_PATH" "ATTACH '${FACTS_PATH}' AS facts; DELETE FROM note_state WHERE raw_note_id NOT IN (SELECT id FROM facts.captured_notes);" 2>/dev/null || true
    fi
}

cleanup_test_run() {
    local test_run=$1
    echo "Cleaning test run: $test_run"
    # Captured notes are FACTS; only test_run-marked rows (never real notes, which have test_run=NULL).
    sqlite3 "$CAPTURES_DB" "DELETE FROM ${CAPTURES_TABLE} WHERE test_run = '${test_run}';"
    cleanup_derived "test_run = '${test_run}'"
    echo "Cleanup complete"
}

cleanup_all() {
    echo "Cleaning ALL test data..."
    sqlite3 "$CAPTURES_DB" "DELETE FROM ${CAPTURES_TABLE} WHERE test_run IS NOT NULL;"
    cleanup_derived "test_run IS NOT NULL"
    echo "All test data cleaned"
}

case "${1:---list}" in
    --list)
        list_test_runs
        ;;
    --all)
        read -p "Delete ALL test data? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cleanup_all
        fi
        ;;
    *)
        cleanup_test_run "$1"
        ;;
esac
