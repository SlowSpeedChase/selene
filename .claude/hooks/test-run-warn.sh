#!/bin/bash
# Claude Code PostToolUse(Bash) hook: warn on leftover test_run rows
#
# Enforces the "Always cleanup test data" rule from CLAUDE.md by counting rows
# in raw_notes with a non-null test_run marker. Prints a warning to stderr if
# any remain. Never blocks — this is advisory, not a gate.
#
# The hook is intentionally cheap: one COUNT(*) over an indexed column.

set -u

db="${CLAUDE_PROJECT_DIR:-/Users/chaseeasterling/selene}/data/selene.db"

if [ ! -f "$db" ] && [ ! -L "$db" ]; then
    exit 0
fi

count=$(sqlite3 "$db" "SELECT COUNT(*) FROM raw_notes WHERE test_run IS NOT NULL" 2>/dev/null || echo 0)

if [ "${count:-0}" -gt 0 ]; then
    echo "TEST-RUN WARNING: $count row(s) with test_run marker remain in raw_notes. Run './scripts/cleanup-tests.sh --list' to inspect, then './scripts/cleanup-tests.sh <id>' to clean." >&2
fi

exit 0
