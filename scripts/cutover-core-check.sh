#!/bin/bash
#
# cutover-core-check.sh — the REAL proof for the cutover-prod.sh DB-surgery core (Task 3).
#
# Sources scripts/cutover-prod.sh against a /tmp COPY of the real dev DB and exercises BOTH the
# happy path (preflight→backup→migrate→gate1) and the rollback path (gate1 forced to fail →
# rollback_db restores a byte-for-byte single-file DB). NEVER writes a real DB:
#   - the ONLY contact with real dev is a single read-only `.backup` snapshot
#   - everything else is /tmp-isolated (SELENE_DB_PATH / SELENE_FACTS_DB_PATH / BACKUP_DIR under /tmp)
#   - confirms the real dev DB mtime is unchanged at the end
#
#   bash scripts/cutover-core-check.sh
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

REAL_DEV_DB="$HOME/selene-data-dev/selene.db"

# /tmp isolation paths — the core runs entirely against these.
CT_DB=/tmp/ct3-selene.db
CT_FACTS=/tmp/ct3-facts.db
CT_BACKUPS=/tmp/ct3-backups

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS_ALL=1
note_fail() { PASS_ALL=0; echo -e "${RED}  [FAIL] $1${NC}"; }
note_pass() { echo -e "${GREEN}  [PASS] $1${NC}"; }
section()   { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Hard guard: the harness must only ever drive /tmp paths.
for p in "$CT_DB" "$CT_FACTS" "$CT_BACKUPS"; do
  case "$p" in /tmp/*) ;; *) echo -e "${RED}ABORT: path '$p' is not under /tmp${NC}"; exit 2;; esac
done

if [ ! -f "$REAL_DEV_DB" ]; then
  echo -e "${RED}ABORT: real dev DB not found at $REAL_DEV_DB${NC}"; exit 2
fi

# Baseline mtime of the real dev DB — must be identical at the end (we never write it).
DEV_MTIME_BEFORE="$(/usr/bin/stat -f '%m' "$REAL_DEV_DB")"

clean_tmp() {
  rm -f /tmp/ct3-selene.db /tmp/ct3-selene.db-wal /tmp/ct3-selene.db-shm
  rm -f /tmp/ct3-facts.db /tmp/ct3-facts.db-wal /tmp/ct3-facts.db-shm
  rm -rf /tmp/ct3-backups /tmp/cutover-probe-vault
}

snapshot() {
  # The ONLY contact with the real dev DB: a read-only, transactionally-consistent snapshot.
  sqlite3 "$REAL_DEV_DB" ".backup '$CT_DB'"
  if [ ! -f "$CT_DB" ]; then echo -e "${RED}ABORT: snapshot failed${NC}"; exit 2; fi
}

# sqlite3 object type helper (content-free).
otype() { sqlite3 "$1" "SELECT type FROM sqlite_master WHERE name='$2';" 2>/dev/null; }
rowcount() { sqlite3 "$1" "SELECT COUNT(*) FROM $2;" 2>/dev/null; }

section "Setup — clean stale /tmp/ct3-* and snapshot real dev (read-only .backup)"
clean_tmp
echo "  cleaned /tmp/ct3-* artifacts"
snapshot
PRE_TYPE="$(otype "$CT_DB" raw_notes)"
PRE_RAW_SNAP="$(rowcount "$CT_DB" raw_notes)"
echo "  snapshot ready: raw_notes type='${PRE_TYPE:-absent}', raw_notes rows=$PRE_RAW_SNAP"
if [ "$PRE_TYPE" != "table" ]; then
  note_fail "snapshot raw_notes is not a physical table (got '${PRE_TYPE:-absent}') — cannot exercise migration"
fi

# Source the core ONCE, with env pointed at the /tmp copy. The sourced functions share globals
# (PRE_RAW/PRE_PROC/BACKUP), so we run the happy-path sequence in THIS shell.
export SELENE_DB_PATH="$CT_DB"
export SELENE_FACTS_DB_PATH="$CT_FACTS"
export BACKUP_DIR="$CT_BACKUPS"
# shellcheck source=scripts/cutover-prod.sh
source "$REPO_ROOT/scripts/cutover-prod.sh"
# cutover-prod.sh sets `set -euo pipefail`; sourcing flips `-e` on in THIS shell. The harness
# deliberately runs WITHOUT `-e` (it records failures via `|| note_fail` instead of aborting),
# so turn `-e` back off while keeping `-u`/pipefail.
set +e

# =====================================================================================
section "HAPPY PATH — preflight && backup_and_verify && migrate && gate1"
# =====================================================================================
HAPPY_OK=1
preflight        || { note_fail "preflight failed"; HAPPY_OK=0; }
backup_and_verify || { note_fail "backup_and_verify failed"; HAPPY_OK=0; }
migrate          || { note_fail "migrate failed"; HAPPY_OK=0; }
if [ "$HAPPY_OK" = "1" ]; then
  if gate1; then note_pass "gate1 PASS"; else note_fail "gate1 returned non-zero"; HAPPY_OK=0; fi
fi

section "HAPPY PATH — assertions"
# facts.db created
[ -f "$CT_FACTS" ] && note_pass "facts.db created at $CT_FACTS" || note_fail "facts.db missing"
# raw_notes now a view (or legacy_backup present). A fresh sqlite3 handle won't see the per-conn
# TEMP view, so the durable on-disk witness is the legacy_backup table.
NOW_RAW_TYPE="$(otype "$CT_DB" raw_notes)"
LEGACY_PRESENT="$(otype "$CT_DB" raw_notes_legacy_backup)"
if [ "$NOW_RAW_TYPE" != "table" ] && [ "$LEGACY_PRESENT" = "table" ]; then
  note_pass "raw_notes no longer a physical table (type='${NOW_RAW_TYPE:-absent}') + raw_notes_legacy_backup present"
else
  note_fail "post-migrate shape wrong: raw_notes type='${NOW_RAW_TYPE:-absent}', legacy_backup='${LEGACY_PRESENT:-absent}'"
fi
# backup exists + was verified (preflight/backup ran). BACKUP global should point at a real file.
if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ]; then
  BK_RAW="$(rowcount "$BACKUP" raw_notes)"
  if [ "$BK_RAW" = "$PRE_RAW_SNAP" ]; then
    note_pass "backup exists + verified ($BACKUP -> $BK_RAW rows == snapshot $PRE_RAW_SNAP)"
  else
    note_fail "backup row mismatch (backup=$BK_RAW vs snapshot=$PRE_RAW_SNAP)"
  fi
else
  note_fail "backup file not found (BACKUP='${BACKUP:-}')"
fi
# probe cleaned up: NO test_run='cutover-probe' rows survive. Read facts.db directly (the fact lives
# there; a plain sqlite3 handle on selene.db has no temp raw_notes view).
PROBE_LEFTOVERS="$(sqlite3 "$CT_FACTS" "SELECT COUNT(*) FROM captured_notes WHERE test_run='cutover-probe';" 2>/dev/null)"
if [ "${PROBE_LEFTOVERS:-0}" = "0" ]; then
  note_pass "probe left no rows (captured_notes test_run='cutover-probe' = 0)"
else
  note_fail "probe leftover rows: $PROBE_LEFTOVERS (expected 0)"
fi
if [ "$HAPPY_OK" = "1" ]; then note_pass "HAPPY PATH overall PASS"; else note_fail "HAPPY PATH overall FAIL"; fi

# =====================================================================================
section "ROLLBACK PATH — fresh snapshot, migrate, force gate1 fail, rollback_db"
# =====================================================================================
# Re-snapshot a fresh single-file copy and reset state globals by re-running preflight/backup/migrate.
clean_tmp
snapshot
RB_PRE_RAW="$(rowcount "$CT_DB" raw_notes)"
echo "  fresh snapshot: raw_notes rows=$RB_PRE_RAW"

RB_OK=1
preflight        || { note_fail "rollback-path preflight failed"; RB_OK=0; }
backup_and_verify || { note_fail "rollback-path backup_and_verify failed"; RB_OK=0; }
migrate          || { note_fail "rollback-path migrate failed"; RB_OK=0; }
# Sanity: it really migrated before we roll back.
[ -f "$CT_FACTS" ] && note_pass "rollback-path: migration produced facts.db (pre-rollback)" \
  || note_fail "rollback-path: facts.db missing pre-rollback"

# Force gate1 to fail, then roll back — mirrors the core's `if gate1; then ... else rollback_db`.
if SIMULATE_GATE1_FAIL=1 gate1; then
  note_fail "rollback-path: SIMULATE_GATE1_FAIL=1 gate1 unexpectedly PASSED"
  RB_OK=0
else
  note_pass "rollback-path: gate1 failed as simulated"
  if rollback_db; then note_pass "rollback_db reported success"; else note_fail "rollback_db reported failure"; RB_OK=0; fi
fi

section "ROLLBACK PATH — assertions (byte-for-byte single-file again)"
# raw_notes type='table' with the original count, NO facts.db.
RB_RAW_TYPE="$(otype "$CT_DB" raw_notes)"
RB_RAW_COUNT="$(rowcount "$CT_DB" raw_notes)"
if [ "$RB_RAW_TYPE" = "table" ]; then
  note_pass "raw_notes is a physical table again (type='table')"
else
  note_fail "raw_notes type after rollback = '${RB_RAW_TYPE:-absent}' (expected 'table')"
fi
if [ "$RB_RAW_COUNT" = "$RB_PRE_RAW" ]; then
  note_pass "raw_notes row count restored ($RB_RAW_COUNT == $RB_PRE_RAW)"
else
  note_fail "raw_notes row count after rollback = $RB_RAW_COUNT (expected $RB_PRE_RAW)"
fi
if [ ! -f "$CT_FACTS" ]; then
  note_pass "no facts.db after rollback (removed)"
else
  note_fail "facts.db still present after rollback ($CT_FACTS)"
fi
# Byte-for-byte: the restored DB must be identical to the fresh snapshot's backup. Compare the
# restored DB to BACKUP (the copy taken just before THIS migration).
if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ]; then
  if cmp -s "$BACKUP" "$CT_DB"; then
    note_pass "restored DB is byte-for-byte identical to the pre-migration backup"
  else
    note_fail "restored DB differs byte-for-byte from the pre-migration backup"
  fi
fi
if [ "$RB_OK" = "1" ]; then note_pass "ROLLBACK PATH overall PASS"; else note_fail "ROLLBACK PATH overall FAIL"; fi

# =====================================================================================
section "Real dev DB untouched"
# =====================================================================================
DEV_MTIME_AFTER="$(/usr/bin/stat -f '%m' "$REAL_DEV_DB")"
if [ "$DEV_MTIME_BEFORE" = "$DEV_MTIME_AFTER" ]; then
  note_pass "real dev DB mtime unchanged ($DEV_MTIME_BEFORE) — never written"
else
  note_fail "real dev DB mtime CHANGED ($DEV_MTIME_BEFORE -> $DEV_MTIME_AFTER)"
fi

# Tidy up /tmp artifacts (leave nothing behind).
clean_tmp

# =====================================================================================
section "SUMMARY"
# =====================================================================================
echo "  Happy path:    $( [ "$HAPPY_OK" = 1 ] && echo PASS || echo FAIL )"
echo "  Rollback path: $( [ "$RB_OK" = 1 ] && echo PASS || echo FAIL )"
echo "  Dev DB mtime:  $( [ "$DEV_MTIME_BEFORE" = "$DEV_MTIME_AFTER" ] && echo unchanged || echo CHANGED )"
if [ "$PASS_ALL" = "1" ]; then
  echo -e "\n${GREEN}========== CUTOVER CORE CHECK: ALL PASSED ==========${NC}"
  exit 0
else
  echo -e "\n${RED}========== CUTOVER CORE CHECK: FAILURES ==========${NC}"
  exit 1
fi
