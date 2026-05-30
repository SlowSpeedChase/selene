#!/bin/bash
# Test harness for prod-data-guard.sh
#
# Feeds mock PreToolUse(Bash) JSON to the guard and asserts the exit code:
#   exit 2 = deny (block + explain to Claude),  exit 0 = allow.
#
# This is the real proof the guard works — the hook loads at session start, so
# live interception can't be exercised mid-session; the unit matrix can.
#
# Run:  bash .claude/hooks/test-prod-data-guard.sh
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/prod-data-guard.sh"
pass=0; fail=0

if ! command -v jq >/dev/null 2>&1; then
    echo "FATAL: jq is required for this test harness" >&2
    exit 3
fi

run() {  # run "<command string>" -> echoes the hook's exit code
    jq -nc --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}' \
        | bash "$HOOK" >/dev/null 2>&1
    echo $?
}

expect() {  # expect <DENY|ALLOW> "<command>" "<label>"
    local want="$1" cmd="$2" label="$3" code wantcode
    code=$(run "$cmd")
    [ "$want" = DENY ] && wantcode=2 || wantcode=0
    if [ "$code" = "$wantcode" ]; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
        echo "FAIL [$label]: wanted $want (exit $wantcode), got exit $code"
        echo "      cmd: $cmd"
    fi
}

# --- DENY: commands that would surface real note content into Claude's context ---
expect DENY 'sqlite3 /Users/chaseeasterling/selene-data/selene.db "SELECT content FROM raw_notes"' "prod content select (absolute)"
expect DENY 'sqlite3 ~/selene-data/selene.db "SELECT title, content FROM raw_notes LIMIT 5"'        "prod content select (tilde)"
expect DENY 'SELENE_ENV=production sqlite3 /Users/chaseeasterling/selene-data/selene.db "SELECT essence FROM processed_notes"' "prod essence select"
expect DENY 'SELENE_DB_PATH=/Users/chaseeasterling/selene-data/selene.db npx ts-node -e "x"'        "ad-hoc ts-node on prod path"
expect DENY 'grep -ri secret /Users/chaseeasterling/selene-data/'                                   "grep prod data dir"
expect DENY 'cat "/Users/chaseeasterling/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene/Daily.md"' "read prod vault note"

# --- ALLOW: dev paths must be untouched (the selene-data/ vs selene-data-dev/ substring trap) ---
expect ALLOW 'sqlite3 ~/selene-data-dev/selene.db "SELECT content FROM raw_notes"' "dev content select (substring trap)"
expect ALLOW 'ls ~/selene-data-dev/'                                              "dev dir listing"

# --- ALLOW: sanctioned inspector + operational + snapshot + override ---
expect ALLOW 'npx ts-node scripts/selene-inspect.ts coverage'                          "selene-inspect (no path literal)"
expect ALLOW './scripts/deploy-prod.sh --ref origin/main'                              "deploy-prod"
expect ALLOW './scripts/rollback-prod.sh'                                              "rollback-prod"
expect ALLOW 'sqlite3 /Users/chaseeasterling/selene-data/selene.db ".backup /tmp/snap.db"' "prod snapshot .backup"
expect ALLOW 'SELENE_GUARD_OFF=1 sqlite3 ~/selene-data/selene.db "SELECT content FROM raw_notes"' "override lifts guard"

# --- ALLOW: unrelated commands ---
expect ALLOW 'git status'                          "unrelated git"
expect ALLOW 'curl -s http://localhost:5678/health' "health check"

echo "----------------------------------------"
echo "prod-data-guard: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
