#!/bin/bash
#
# test-dev-process-batch.sh — contract test for dev-process-batch.sh.
#
# The dev batch processor must drive the CURRENT pipeline, not the pre-2026-03-21
# one. This test asserts, structurally and at runtime, that:
#   1. it references NONE of the workflows archived in the simplification, and
#   2. it references every workflow in the current active pipeline, and
#   3. `--status` runs clean against the dev schema (no dead table/column refs).
#
# Pure-structural checks need no Ollama; the `--status` check only reads the dev
# DB (fast). exit 0 = all pass, exit 1 = at least one failure.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/dev-process-batch.sh"
fail=0

pass() { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# 1) Must NOT reference any workflow archived on 2026-03-21.
for w in index-vectors compute-associations compute-relationships detect-threads reconsolidate-threads; do
  if grep -q "$w" "$SCRIPT"; then bad "references archived workflow: $w"; else pass "no archived workflow: $w"; fi
done

# 2) Must reference every workflow in the current active pipeline, in dependency order.
for w in process-llm distill-essences synthesize-topics export-obsidian; do
  if grep -q "src/workflows/$w\.ts" "$SCRIPT"; then pass "drives current workflow: $w"; else bad "missing current workflow: $w"; fi
done

# 3) --status must run clean against the dev schema (no dead table/column references).
status_out="$(SELENE_ENV=development bash "$SCRIPT" --status 2>&1)"
status_code=$?
if [ "$status_code" -eq 0 ]; then pass "--status exits 0"; else bad "--status exited $status_code"; fi
if printf '%s' "$status_out" | grep -qiE "no such (table|column)|sqlite3.*error|parse error"; then
  bad "--status hit a missing table/column: $(printf '%s' "$status_out" | grep -iE 'no such|error' | head -1)"
else
  pass "--status references only live schema"
fi

# 4) --status should surface CURRENT synthesis signals, not archived-feature noise.
#    Topic clusters + essences are what the current pipeline produces and what the
#    showcase corpus is validated against; relationships/threads were archived.
if printf '%s' "$status_out" | grep -qiE "cluster"; then pass "--status reports topic clusters"; else bad "--status omits topic clusters"; fi
if printf '%s' "$status_out" | grep -qiE "essence"; then pass "--status reports essences"; else bad "--status omits essences"; fi
if printf '%s' "$status_out" | grep -qiE "^ *Relationships:|^ *Threads:"; then bad "--status still shows archived thread/relationship metrics"; else pass "--status drops archived metrics"; fi

# 5) The --all drain loops must have a no-progress safeguard so a note that never
#    leaves the queried state (e.g. a persistently-failing LLM extraction) cannot
#    spin the loop forever.
if grep -qiE "No progress" "$SCRIPT" && grep -qE "\bbreak\b" "$SCRIPT"; then
  pass "--all drain has a no-progress safeguard"
else
  bad "--all drain loop has no termination safeguard (could spin forever)"
fi

exit $fail
