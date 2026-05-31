#!/bin/bash
#
# Unit test for drain() control flow in dev-process-batch.sh.
#
# Sources the script (functions only, via DEV_BATCH_SOURCED=1) and stubs
# safe_count / run_step so the drain loop can be exercised without Ollama or a DB.
#
# Regression target: the --all distill drain on a FRESH DB. distill-essences
# creates its own essence column on first run, so before that run safe_count reads
# 0 (column missing). A pre-check drain (`while count > 0`) reads 0 and skips the
# workflow that would have created the column → distill never runs, synthesize then
# fails on pn.essence. drain() must run at least once and drain to zero anyway.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_BATCH_SOURCED=1 source "$DIR/dev-process-batch.sh"
set +e   # the sourced script enabled `set -e`; keep the test harness resilient

fail=0
pass() { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# --- Scenario 1: gating column doesn't exist until the workflow's first run ---
# safe_count reads 0 until run_step has fired once (column created), then a real
# decreasing backlog of 43 drained 10 at a time.
TRUE=43; PROCESSED=0; COL=0; RUN_COUNT=0
run_step() {
  RUN_COUNT=$((RUN_COUNT + 1))
  COL=1                                  # first run "creates the column"
  PROCESSED=$((PROCESSED + 10))
  [ "$PROCESSED" -gt "$TRUE" ] && PROCESSED="$TRUE"
}
safe_count() {
  if [ "$COL" -eq 0 ]; then echo 0; else echo $((TRUE - PROCESSED)); fi
}
drain "fake-count-sql" "fake-workflow" "fake-label"
if [ "$RUN_COUNT" -ge 1 ]; then pass "scenario1: ran the workflow despite initial count 0 (ran $RUN_COUNT)"; else bad "scenario1: workflow never ran — count short-circuit skips the column-creating run"; fi
if [ "$(safe_count x)" -eq 0 ]; then pass "scenario1: drained backlog to 0"; else bad "scenario1: backlog not drained (remaining $(safe_count x))"; fi

# --- Scenario 2: no-progress termination (a stuck note that never advances) ---
COL=0; RUN_COUNT=0
run_step() { RUN_COUNT=$((RUN_COUNT + 1)); COL=1; }   # never reduces the backlog
safe_count() { if [ "$COL" -eq 0 ]; then echo 0; else echo 43; fi; }
drain "fake-count-sql" "fake-workflow" "fake-label"   # must terminate, not spin
if [ "$RUN_COUNT" -ge 1 ] && [ "$RUN_COUNT" -le 3 ]; then pass "scenario2: stuck backlog terminated via no-progress guard (ran $RUN_COUNT)"; else bad "scenario2: unexpected run count $RUN_COUNT (spin or skip)"; fi

exit $fail
