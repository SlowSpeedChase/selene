#!/bin/bash
#
# verify-cutover.sh — Task 5: validate the FULL cutover ORCHESTRATION (scripts/cutover-prod.sh
# main()) end-to-end, in --dry-run, against a /tmp COPY of the real dev DB.
#
# Why --dry-run + /tmp: the cutover mutates the REAL prod DB and stops/starts REAL launchd agents.
# We must prove the orchestration WITHOUT touching either. --dry-run stubs ONLY the launchctl /
# deploy / notify side effects (they PRINT "[dry-run] ..." instead of executing). Crucially the
# DB-surgery core (backup → migrate → gate1 → rollback) still runs FOR REAL against the /tmp copy,
# so this validation actually proves the migration and the auto-rollback — not a no-op.
#
# Contact with the real world:
#   - the ONLY contact with real dev is a single read-only `.backup` snapshot (never written)
#   - everything else is /tmp-isolated (SELENE_DB_PATH / SELENE_FACTS_DB_PATH / BACKUP_DIR /
#     SELENE_VAULT_PATH all under /tmp)
#   - NO com.selene.prod.* agent is touched (dry-run guarantees it; we also grep-assert that no
#     un-stubbed launchctl / deploy-prod.sh / rollback-prod.sh actually executed)
#   - real dev DB mtime is asserted unchanged at the end
#
# Scenarios:
#   1. HAPPY PATH      — full main() --dry-run → /tmp copy ends MIGRATED, gate1 PASS, probe clean,
#                        launchctl/deploy lines PRINTED (not run), "CUTOVER COMPLETE" printed.
#   2. ALREADY-MIGRATED — re-run main() --dry-run on that same (now migrated) copy → exits 0 with
#                        "already migrated" (proves Fix #1: preflight returns 2, not exit-on-source).
#   3. ROLLBACK (gate1) — fresh snapshot, SIMULATE_GATE1_FAIL=1 → PRE-deploy failure: rollback_all
#                        runs but SKIPS the code-rollback ("no deploy happened"); /tmp copy is
#                        byte-for-byte single-file again; restore tail completes ("ROLLED BACK").
#   4. ROLLBACK (gate2) — fresh snapshot, SIMULATE_GATE2_FAIL=1 → POST-deploy failure: DEPLOYED is
#                        set so rollback_all ATTEMPTS the code-rollback ([dry-run] rollback-prod.sh);
#                        /tmp copy single-file again; restore tail completes ("ROLLED BACK").
#                        Scenarios 3+4 together prove the DEPLOYED gate (the rollback-tail fix).
#   5. CODE-ROLLBACK FAILS — SIMULATE_GATE2_FAIL=1 + SIMULATE_CODE_ROLLBACK_FAIL=1 → the code-rollback
#                        returns non-zero; the restore tail (restart/resume/notify) must STILL complete
#                        ("ROLLED BACK" prints). Guaranteed by `set +e` at the top of rollback_all
#                        (best-effort teardown). 3/4 cover branch selection with code-rollback OK.
#
#   bash scripts/verify-cutover.sh
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

REAL_DEV_DB="$HOME/selene-data-dev/selene.db"

# /tmp isolation paths — main() runs entirely against these.
CTV_DB=/tmp/ctv-selene.db
CTV_FACTS=/tmp/ctv-facts.db
CTV_BACKUPS=/tmp/ctv-backups
CTV_VAULT=/tmp/ctv-vault

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS_ALL=1
note_fail() { PASS_ALL=0; echo -e "${RED}  [FAIL] $1${NC}"; }
note_pass() { echo -e "${GREEN}  [PASS] $1${NC}"; }
section()   { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Hard guard: this harness must only ever drive /tmp paths.
for p in "$CTV_DB" "$CTV_FACTS" "$CTV_BACKUPS" "$CTV_VAULT"; do
  case "$p" in /tmp/*) ;; *) echo -e "${RED}ABORT: path '$p' is not under /tmp${NC}"; exit 2;; esac
done

if [ ! -f "$REAL_DEV_DB" ]; then
  echo -e "${RED}ABORT: real dev DB not found at $REAL_DEV_DB${NC}"; exit 2
fi

# Baseline mtime of the real dev DB — must be identical at the end (we never write it).
DEV_MTIME_BEFORE="$(/usr/bin/stat -f '%m' "$REAL_DEV_DB")"

clean_tmp() {
  rm -f /tmp/ctv-selene.db /tmp/ctv-selene.db-wal /tmp/ctv-selene.db-shm
  rm -f /tmp/ctv-facts.db /tmp/ctv-facts.db-wal /tmp/ctv-facts.db-shm
  rm -rf /tmp/ctv-backups /tmp/ctv-vault /tmp/cutover-probe-vault
}

snapshot() {
  # The ONLY contact with the real dev DB: a read-only, transactionally-consistent snapshot.
  sqlite3 "$REAL_DEV_DB" ".backup '$CTV_DB'"
  if [ ! -f "$CTV_DB" ]; then echo -e "${RED}ABORT: snapshot failed${NC}"; exit 2; fi
}

# Content-free sqlite helpers.
otype()    { sqlite3 "$1" "SELECT type FROM sqlite_master WHERE name='$2';" 2>/dev/null; }
rowcount() { sqlite3 "$1" "SELECT COUNT(*) FROM $2;" 2>/dev/null; }

# Run main() by EXECUTING the script (not sourcing) so we exercise the real executed-path main()
# and capture its full stdout+stderr for grep assertions. The /tmp isolation + DRY_RUN are passed
# as ENV so the script's own arg-parsing isn't involved (we still pass --dry-run as the belt). Any
# extra env (e.g. SIMULATE_GATE1_FAIL) is supplied by the caller via the environment.
run_cutover() {
  env SELENE_DB_PATH="$CTV_DB" \
      SELENE_FACTS_DB_PATH="$CTV_FACTS" \
      BACKUP_DIR="$CTV_BACKUPS" \
      SELENE_VAULT_PATH="$CTV_VAULT" \
      DRY_RUN=1 \
      "$@" \
      bash "$REPO_ROOT/scripts/cutover-prod.sh" --dry-run
}

# =====================================================================================
section "Setup — clean stale /tmp/ctv-* and snapshot real dev (read-only .backup)"
# =====================================================================================
clean_tmp
echo "  cleaned /tmp/ctv-* artifacts"
snapshot
PRE_TYPE="$(otype "$CTV_DB" raw_notes)"
PRE_RAW_SNAP="$(rowcount "$CTV_DB" raw_notes)"
echo "  snapshot ready: raw_notes type='${PRE_TYPE:-absent}', raw_notes rows=$PRE_RAW_SNAP"
if [ "$PRE_TYPE" != "table" ]; then
  note_fail "snapshot raw_notes is not a physical table (got '${PRE_TYPE:-absent}') — cannot exercise migration"
fi

# =====================================================================================
section "SCENARIO 1 — HAPPY PATH: full main() --dry-run against the /tmp copy"
# =====================================================================================
HAPPY_OUT="$(run_cutover 2>&1)"; HAPPY_RC=$?
echo "$HAPPY_OUT"

section "SCENARIO 1 — assertions"
# (rc)
if [ "$HAPPY_RC" -eq 0 ]; then note_pass "main() exited 0"; else note_fail "main() exited $HAPPY_RC (expected 0)"; fi
# "CUTOVER COMPLETE" printed.
echo "$HAPPY_OUT" | grep -q "CUTOVER COMPLETE" && note_pass "'CUTOVER COMPLETE' printed" || note_fail "'CUTOVER COMPLETE' not printed"
# gate1 PASS.
echo "$HAPPY_OUT" | grep -q "gate1: ALL checks passed" && note_pass "gate1 PASS" || note_fail "gate1 did not report ALL checks passed"
# Visibility line (Fix #2): the operator saw which DB/facts the cutover operates on.
echo "$HAPPY_OUT" | grep -q "Cutover will operate on: DB=$CTV_DB FACTS=$CTV_FACTS" \
  && note_pass "visibility line printed the target DB/facts (Fix #2)" || note_fail "visibility line missing/incorrect"

# --- launchctl/deploy were STUBBED (printed, NOT executed). Grep the [dry-run] markers. ---
echo "$HAPPY_OUT" | grep -q "\[dry-run\] launchctl bootout gui/$(id -u)/com.selene.prod.deploy-watcher" \
  && note_pass "watcher pause was STUBBED ([dry-run] launchctl bootout ...deploy-watcher)" \
  || note_fail "watcher-pause dry-run line missing"
echo "$HAPPY_OUT" | grep -q "\[dry-run\] launchctl bootstrap" \
  && note_pass "watcher resume was STUBBED ([dry-run] launchctl bootstrap ...)" \
  || note_fail "watcher-resume dry-run line missing"
echo "$HAPPY_OUT" | grep -q "\[dry-run\] .*deploy-prod.sh --ref" \
  && note_pass "deploy was STUBBED ([dry-run] deploy-prod.sh --ref ...)" \
  || note_fail "deploy dry-run line missing"
echo "$HAPPY_OUT" | grep -q "\[dry-run\] gate2:" \
  && note_pass "gate2 was STUBBED in dry-run (no live /health/probe)" \
  || note_fail "gate2 dry-run line missing"
echo "$HAPPY_OUT" | grep -q "\[dry-run\] .*selene_notify .*cutover complete" \
  && note_pass "completion notify was STUBBED ([dry-run] selene_notify ...)" \
  || note_fail "completion-notify dry-run line missing"
echo "$HAPPY_OUT" | grep -q "\[dry-run\] build-gate" \
  && note_pass "build-gate was print-skipped in dry-run" \
  || note_fail "build-gate dry-run line missing"

# --- The /tmp copy ended MIGRATED for real (the DB surgery is NOT stubbed). ---
[ -f "$CTV_FACTS" ] && note_pass "facts.db created at $CTV_FACTS (real migration ran)" || note_fail "facts.db missing — migration did not run"
NOW_RAW_TYPE="$(otype "$CTV_DB" raw_notes)"
LEGACY_PRESENT="$(otype "$CTV_DB" raw_notes_legacy_backup)"
if [ "$NOW_RAW_TYPE" != "table" ] && [ "$LEGACY_PRESENT" = "table" ]; then
  note_pass "raw_notes no longer a physical table (type='${NOW_RAW_TYPE:-absent}') + raw_notes_legacy_backup present"
else
  note_fail "post-migrate shape wrong: raw_notes type='${NOW_RAW_TYPE:-absent}', legacy_backup='${LEGACY_PRESENT:-absent}'"
fi
# Counts preserved: legacy_backup holds exactly the pre-migration raw_notes rows.
MIG_RAW="$(rowcount "$CTV_DB" raw_notes_legacy_backup)"
if [ "$MIG_RAW" = "$PRE_RAW_SNAP" ]; then
  note_pass "counts preserved (raw_notes_legacy_backup=$MIG_RAW == snapshot $PRE_RAW_SNAP)"
else
  note_fail "count mismatch (legacy_backup=$MIG_RAW vs snapshot=$PRE_RAW_SNAP)"
fi
# Probe cleaned: NO test_run='cutover-probe' rows survive in facts.captured_notes.
PROBE_LEFTOVERS="$(sqlite3 "$CTV_FACTS" "SELECT COUNT(*) FROM captured_notes WHERE test_run='cutover-probe';" 2>/dev/null)"
if [ "${PROBE_LEFTOVERS:-0}" = "0" ]; then
  note_pass "gate1 probe left no rows (captured_notes test_run='cutover-probe' = 0)"
else
  note_fail "probe leftover rows: $PROBE_LEFTOVERS (expected 0)"
fi

# =====================================================================================
section "SCENARIO 2 — ALREADY-MIGRATED re-run (proves Fix #1: preflight returns 2)"
# =====================================================================================
# Re-run main() --dry-run on the SAME copy (now migrated). Fix #1 makes preflight return 2 and
# main() exit 0 with "already migrated". (Before the fix, a sourced `exit 0` would have been a
# footgun; executed, the behavior must be a clean rc=0 + message and NOTHING torn down.)
AGAIN_OUT="$(run_cutover 2>&1)"; AGAIN_RC=$?
echo "$AGAIN_OUT"
section "SCENARIO 2 — assertions"
if [ "$AGAIN_RC" -eq 0 ]; then note_pass "re-run exited 0 (already-migrated is a clean no-op)"; else note_fail "re-run exited $AGAIN_RC (expected 0)"; fi
echo "$AGAIN_OUT" | grep -q "already migrated — nothing to do" \
  && note_pass "'already migrated — nothing to do' printed (Fix #1)" \
  || note_fail "already-migrated message missing"
# It must have stopped at preflight — NO migrate / deploy / CUTOVER COMPLETE this time.
echo "$AGAIN_OUT" | grep -q "CUTOVER COMPLETE" && note_fail "re-run wrongly reached CUTOVER COMPLETE" || note_pass "re-run did NOT proceed past preflight (no second cutover)"
echo "$AGAIN_OUT" | grep -q "\[dry-run\] .*deploy-prod.sh" && note_fail "re-run wrongly attempted deploy" || note_pass "re-run did NOT attempt deploy"

# =====================================================================================
section "SCENARIO 3 — ROLLBACK PATH: SIMULATE_GATE1_FAIL=1 --dry-run, fresh snapshot"
# =====================================================================================
clean_tmp
snapshot
RB_PRE_RAW="$(rowcount "$CTV_DB" raw_notes)"
echo "  fresh snapshot: raw_notes rows=$RB_PRE_RAW"

RB_OUT="$(run_cutover SIMULATE_GATE1_FAIL=1 2>&1)"; RB_RC=$?
echo "$RB_OUT"

section "SCENARIO 3 — assertions (byte-for-byte single-file again)"
# main() must exit non-zero on the gate-fail path.
if [ "$RB_RC" -ne 0 ]; then note_pass "main() exited non-zero on gate1 fail ($RB_RC)"; else note_fail "main() exited 0 despite SIMULATE_GATE1_FAIL"; fi
# rollback_all ran.
echo "$RB_OUT" | grep -q "!! ROLLBACK" && note_pass "'!! ROLLBACK' printed (rollback_all entered)" || note_fail "rollback_all banner missing"
echo "$RB_OUT" | grep -q "gate1 (simulated)" && note_pass "gate1 failed as simulated" || note_fail "simulated gate1 failure not observed"
# gate1 is a PRE-DEPLOY failure: no deploy happened, so the code-rollback must be SKIPPED (the running
# code never changed). Asserting absence here is the heart of the DEPLOYED-gating fix — blindly
# code-rolling-back at gate1 was the bug (on a first-ever cutover rollback-prod.sh hard-exits 1 with no
# archived release, which under `set -e` would skip the restore tail and leave prod DOWN).
echo "$RB_OUT" | grep -q "no deploy happened" \
  && note_pass "code-rollback SKIPPED pre-deploy ('no deploy happened' printed)" \
  || note_fail "expected 'no deploy happened' skip message (DEPLOYED-gating)"
echo "$RB_OUT" | grep -q "rollback-prod.sh" \
  && note_fail "rollback-prod.sh wrongly invoked at a PRE-deploy (gate1) failure" \
  || note_pass "no rollback-prod.sh at gate1 failure (correct — nothing was deployed)"
# "ROLLED BACK" notify printed = the restore TAIL (restart_agents → resume_watcher → notify) ran to the
# end. This is the regression guard: even with the code-rollback skipped, the tail must still complete.
echo "$RB_OUT" | grep -q "ROLLED BACK" && note_pass "'ROLLED BACK' printed (restore tail ran to completion)" || note_fail "'ROLLED BACK' message missing — restore tail did NOT finish"
# rollback_db ran for REAL: raw_notes is a physical table again, original count, NO facts.db.
RB_RAW_TYPE="$(otype "$CTV_DB" raw_notes)"
RB_RAW_COUNT="$(rowcount "$CTV_DB" raw_notes)"
if [ "$RB_RAW_TYPE" = "table" ]; then note_pass "raw_notes is a physical table again (type='table')"; else note_fail "raw_notes type after rollback='${RB_RAW_TYPE:-absent}' (expected 'table')"; fi
if [ "$RB_RAW_COUNT" = "$RB_PRE_RAW" ]; then note_pass "raw_notes row count restored ($RB_RAW_COUNT == $RB_PRE_RAW)"; else note_fail "raw_notes count after rollback=$RB_RAW_COUNT (expected $RB_PRE_RAW)"; fi
if [ ! -f "$CTV_FACTS" ]; then note_pass "no facts.db after rollback (removed)"; else note_fail "facts.db still present after rollback ($CTV_FACTS)"; fi

# =====================================================================================
section "SCENARIO 4 — POST-DEPLOY ROLLBACK: SIMULATE_GATE2_FAIL=1 (code-rollback path)"
# =====================================================================================
# gate2 fails AFTER migrate + deploy, so DEPLOYED is set → rollback_all MUST attempt the code-rollback
# (this is the complement of Scenario 3: here the [dry-run] rollback-prod.sh line MUST appear). Proves
# the DEPLOYED gate opens on the post-deploy side, and the restore tail still completes.
clean_tmp
snapshot
RB2_PRE_RAW="$(rowcount "$CTV_DB" raw_notes)"
echo "  fresh snapshot: raw_notes rows=$RB2_PRE_RAW"

RB2_OUT="$(run_cutover SIMULATE_GATE2_FAIL=1 2>&1)"; RB2_RC=$?
echo "$RB2_OUT"

section "SCENARIO 4 — assertions (code-rollback attempted + single-file restored)"
if [ "$RB2_RC" -ne 0 ]; then note_pass "main() exited non-zero on gate2 fail ($RB2_RC)"; else note_fail "main() exited 0 despite SIMULATE_GATE2_FAIL"; fi
echo "$RB2_OUT" | grep -q "!! ROLLBACK" && note_pass "'!! ROLLBACK' printed (rollback_all entered)" || note_fail "rollback_all banner missing"
echo "$RB2_OUT" | grep -q "gate2 (simulated)" && note_pass "gate2 failed as simulated" || note_fail "simulated gate2 failure not observed"
# Deploy DID happen (stubbed) before gate2 → DEPLOYED set → code-rollback MUST be attempted.
echo "$RB2_OUT" | grep -q "\[dry-run\] .*rollback-prod.sh" \
  && note_pass "code-rollback ATTEMPTED post-deploy ([dry-run] rollback-prod.sh ...)" \
  || note_fail "rollback-prod.sh line missing at a POST-deploy (gate2) failure"
echo "$RB2_OUT" | grep -q "no deploy happened" \
  && note_fail "wrongly printed 'no deploy happened' after a deploy" \
  || note_pass "did NOT skip code-rollback (deploy had happened)"
echo "$RB2_OUT" | grep -q "ROLLED BACK" && note_pass "'ROLLED BACK' printed (restore tail ran to completion)" || note_fail "'ROLLED BACK' message missing — restore tail did NOT finish"
# rollback_db ran for REAL: single-file again, original count, no facts.db.
RB2_RAW_TYPE="$(otype "$CTV_DB" raw_notes)"
RB2_RAW_COUNT="$(rowcount "$CTV_DB" raw_notes)"
if [ "$RB2_RAW_TYPE" = "table" ]; then note_pass "raw_notes is a physical table again (type='table')"; else note_fail "raw_notes type after rollback='${RB2_RAW_TYPE:-absent}' (expected 'table')"; fi
if [ "$RB2_RAW_COUNT" = "$RB2_PRE_RAW" ]; then note_pass "raw_notes row count restored ($RB2_RAW_COUNT == $RB2_PRE_RAW)"; else note_fail "raw_notes count after rollback=$RB2_RAW_COUNT (expected $RB2_PRE_RAW)"; fi
if [ ! -f "$CTV_FACTS" ]; then note_pass "no facts.db after rollback (removed)"; else note_fail "facts.db still present after rollback ($CTV_FACTS)"; fi

# =====================================================================================
section "SCENARIO 5 — code-rollback itself FAILS: restore tail must still complete"
# =====================================================================================
# Behavior check: when the code-rollback errors (SIMULATE_CODE_ROLLBACK_FAIL=1), rollback_all must
# still run its restore TAIL (restart_agents → resume_watcher → notify) to the end. This is guaranteed
# by the `set +e` at the top of rollback_all (best-effort teardown), so it holds regardless of bash's
# errexit-in-||-list quirks. (Scenarios 3/4 cover the DEPLOYED branch selection with code-rollback
# succeeding; this covers the failing-code-rollback path.)
clean_tmp
snapshot
RB3_PRE_RAW="$(rowcount "$CTV_DB" raw_notes)"
echo "  fresh snapshot: raw_notes rows=$RB3_PRE_RAW"

RB3_OUT="$(run_cutover SIMULATE_GATE2_FAIL=1 SIMULATE_CODE_ROLLBACK_FAIL=1 2>&1)"; RB3_RC=$?
echo "$RB3_OUT"

section "SCENARIO 5 — assertions (tail completes despite a failing code-rollback)"
if [ "$RB3_RC" -ne 0 ]; then note_pass "main() exited non-zero ($RB3_RC)"; else note_fail "main() exited 0 despite gate2 fail"; fi
echo "$RB3_OUT" | grep -q "!! ROLLBACK" && note_pass "'!! ROLLBACK' printed (rollback_all entered)" || note_fail "rollback_all banner missing"
echo "$RB3_OUT" | grep -q "code-rollback failed — restoring agents anyway" \
  && note_pass "code-rollback FAILED path taken (WARN fired)" \
  || note_fail "expected the code-rollback-failed WARN (SIMULATE_CODE_ROLLBACK_FAIL not exercised)"
# The crux: despite the non-zero code-rollback, the restore tail still completed.
echo "$RB3_OUT" | grep -q "ROLLED BACK" \
  && note_pass "'ROLLED BACK' printed — restore tail completed despite a failing code-rollback" \
  || note_fail "'ROLLED BACK' missing — restore tail did NOT complete after a failing code-rollback"
# DB restored to single-file (the DB-surgery rollback ran before the failing code-rollback).
RB3_RAW_TYPE="$(otype "$CTV_DB" raw_notes)"
RB3_RAW_COUNT="$(rowcount "$CTV_DB" raw_notes)"
if [ "$RB3_RAW_TYPE" = "table" ]; then note_pass "raw_notes is a physical table again (type='table')"; else note_fail "raw_notes type after rollback='${RB3_RAW_TYPE:-absent}' (expected 'table')"; fi
if [ "$RB3_RAW_COUNT" = "$RB3_PRE_RAW" ]; then note_pass "raw_notes row count restored ($RB3_RAW_COUNT == $RB3_PRE_RAW)"; else note_fail "raw_notes count after rollback=$RB3_RAW_COUNT (expected $RB3_PRE_RAW)"; fi
if [ ! -f "$CTV_FACTS" ]; then note_pass "no facts.db after rollback (removed)"; else note_fail "facts.db still present after rollback ($CTV_FACTS)"; fi

# =====================================================================================
section "SAFETY — real dev DB untouched + no un-stubbed launchctl/deploy executed"
# =====================================================================================
DEV_MTIME_AFTER="$(/usr/bin/stat -f '%m' "$REAL_DEV_DB")"
if [ "$DEV_MTIME_BEFORE" = "$DEV_MTIME_AFTER" ]; then
  note_pass "real dev DB mtime unchanged ($DEV_MTIME_BEFORE) — never written"
else
  note_fail "real dev DB mtime CHANGED ($DEV_MTIME_BEFORE -> $DEV_MTIME_AFTER)"
fi

# Belt-and-suspenders: EVERY launchctl / deploy-prod.sh / rollback-prod.sh occurrence in ALL the
# captured output must be prefixed with "[dry-run]" — i.e. nothing un-stubbed actually executed.
ALL_OUT="$HAPPY_OUT
$AGAIN_OUT
$RB_OUT
$RB2_OUT
$RB3_OUT"
UNSTUBBED="$(echo "$ALL_OUT" | grep -E 'launchctl|deploy-prod\.sh|rollback-prod\.sh' | grep -v '\[dry-run\]' | grep -v 'would ' || true)"
if [ -z "$UNSTUBBED" ]; then
  note_pass "no un-stubbed launchctl/deploy/rollback action ran (all occurrences are [dry-run])"
else
  note_fail "found apparently un-stubbed action line(s):"
  echo "$UNSTUBBED" | sed 's/^/      > /'
fi
# Direct proof no prod agent was touched: the agent set loaded now is unchanged (we never call
# bootout/kickstart for real). We can only assert the dry-run guarantee here; the grep above is
# the actual evidence. Print the current prod-agent labels for the record (read-only list).
LIVE_AGENTS="$(launchctl list 2>/dev/null | awk '{print $3}' | grep '^com.selene.prod' || true)"
echo "  prod agents currently loaded (untouched by this dry-run): ${LIVE_AGENTS:-<none>}"

# Tidy up /tmp artifacts (leave nothing behind).
clean_tmp

# =====================================================================================
section "SUMMARY"
# =====================================================================================
echo "  Snapshot:       $PRE_RAW_SNAP raw_notes (read-only .backup of real dev)"
echo "  Happy path:     $( echo "$HAPPY_OUT" | grep -q 'CUTOVER COMPLETE' && echo 'migrated + CUTOVER COMPLETE' || echo FAIL )"
echo "  Already-migr.:  $( echo "$AGAIN_OUT" | grep -q 'already migrated' && echo 'clean no-op (Fix #1)' || echo FAIL )"
echo "  Rollback (g1):  $( echo "$RB_OUT"  | grep -q 'ROLLED BACK' && echo 'pre-deploy: code-rollback skipped + ROLLED BACK' || echo FAIL )"
echo "  Rollback (g2):  $( echo "$RB2_OUT" | grep -q 'ROLLED BACK' && echo 'post-deploy: code-rollback attempted + ROLLED BACK' || echo FAIL )"
echo "  Code-rb fails:  $( echo "$RB3_OUT" | grep -q 'ROLLED BACK' && echo 'restore tail completes despite a failing code-rollback' || echo 'FAIL — restore tail did not complete' )"
echo "  Dev DB mtime:   $( [ "$DEV_MTIME_BEFORE" = "$DEV_MTIME_AFTER" ] && echo unchanged || echo CHANGED )"
echo "  Stubs:          $( [ -z "$UNSTUBBED" ] && echo 'launchctl/deploy/rollback all [dry-run] (nothing executed)' || echo 'UN-STUBBED ACTION RAN' )"
if [ "$PASS_ALL" = "1" ]; then
  echo -e "\n${GREEN}========== VERIFY-CUTOVER: ALL PASSED ==========${NC}"
  exit 0
else
  echo -e "\n${RED}========== VERIFY-CUTOVER: FAILURES ==========${NC}"
  exit 1
fi
