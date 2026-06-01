#!/bin/bash
#
# cutover-prod.sh — the ONE-TIME prod cutover to the two-file fact-store layout.
#
# THIS FILE (Task 3) implements only the DB-surgery CORE: preflight → backup_and_verify → migrate
# → gate1 (content-free verification) → rollback_db (on failure). The watcher-stop / agent-stop /
# deploy / Gate-2 orchestration that wraps this core is the NEXT task — see the TODO stubs at the
# bottom. The `main` here intentionally runs ONLY the DB-critical sequence so the core can be
# driven/tested in isolation by scripts/cutover-core-check.sh.
#
# PATH-PARAMETERIZED so it can run against a /tmp COPY (the check harness does exactly that):
#   SELENE_DB_PATH        (default ~/selene-data/selene.db)
#   SELENE_FACTS_DB_PATH  (default ~/selene-data/facts.db)
#   BACKUP_DIR            (default ~/selene-data/backups)
#   SIMULATE_GATE1_FAIL   (set to 1 to force gate1 to fail — rollback test)
#
# Each step echoes a clear [PASS]/[FAIL] line. Sourced functions share a few shell GLOBALS
# (PRE_RAW, PRE_PROC, BACKUP) across calls — do NOT make them `local`.
#
set -euo pipefail

# --- config / args ---
DB="${SELENE_DB_PATH:-$HOME/selene-data/selene.db}"
FACTS="${SELENE_FACTS_DB_PATH:-$HOME/selene-data/facts.db}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/selene-data/backups}"
SIMULATE_GATE1_FAIL="${SIMULATE_GATE1_FAIL:-}"   # set to 1 to force gate1 to fail (rollback test)

# Resolve the repo root so ts-node scripts are found regardless of CWD.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cross-call shell globals (NOT local — gate1/rollback_db read them in the sourced sequence).
PRE_RAW=""     # pre-migration raw_notes row count (physical table)
PRE_PROC=""    # pre-migration processed_notes row count
BACKUP=""      # path to the verified pre-cutover backup

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[..]${NC} $1"; }

# Object type of a name in a single-file/main schema ("table"/"view"/empty). Content-free.
sqlite_object_type() {
  sqlite3 "$1" "SELECT type FROM sqlite_master WHERE name='$2';" 2>/dev/null
}

# ts-node prints a dotenv banner on STDOUT before its JSON; strip `^[dotenv@` lines, then read a
# single nested field from `selene-inspect <cmd>` JSON. Lifted from verify-fact-store.sh.
#   inspect_field <cmd> <subKey>
inspect_field() {
  ( cd "$REPO_ROOT" && npx ts-node scripts/selene-inspect.ts "$1" 2>/dev/null ) | grep -v '^\[dotenv@' \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const sec=j['$1']||{};const v=sec['$2']!==undefined?sec['$2']:'';process.stdout.write(String(v));}catch(e){process.stdout.write('');}});"
}

# ---------------------------------------------------------------------------
# preflight — step 0
# ---------------------------------------------------------------------------
preflight() {
  info "preflight: DB=$DB FACTS=$FACTS BACKUP_DIR=$BACKUP_DIR"

  if [ ! -f "$DB" ]; then
    fail "preflight: DB not found at $DB"
    return 1
  fi

  # 0c: already migrated? `raw_notes` is a PHYSICAL TABLE only in the legacy single-file shape. A
  # migrated DB has it as a per-connection TEMP view (so a fresh sqlite3 handle sees it ABSENT), or
  # the table is gone/renamed. A stale `note_state` table must NOT fool this — we key strictly on
  # the raw_notes object type, mirroring src/lib/ensure-migrated.ts.
  local raw_type
  raw_type="$(sqlite_object_type "$DB" raw_notes)"
  if [ "$raw_type" != "table" ]; then
    pass "preflight: raw_notes is not a physical table (type='${raw_type:-absent}') — already migrated, nothing to do"
    echo "already migrated"
    exit 0
  fi
  pass "preflight: raw_notes is a physical table — un-migrated, proceeding"

  # 0d: df check — BACKUP_DIR's filesystem must hold ~2x the DB file size (backup copy + headroom).
  local db_bytes avail_kb need_kb backup_fs
  db_bytes="$(/usr/bin/stat -f '%z' "$DB")"
  need_kb=$(( (db_bytes * 2 / 1024) + 1 ))
  mkdir -p "$BACKUP_DIR"
  # df -k reports 1K blocks; column 4 (Available) of the data row.
  avail_kb="$(/bin/df -k "$BACKUP_DIR" | awk 'NR==2 {print $4}')"
  if [ -z "$avail_kb" ] || [ "$avail_kb" -lt "$need_kb" ] 2>/dev/null; then
    fail "preflight: BACKUP_DIR filesystem has ${avail_kb:-?}KB free, need ~${need_kb}KB (2x DB)"
    return 1
  fi
  pass "preflight: disk OK (${avail_kb}KB free >= ~${need_kb}KB needed for 2x DB)"

  # 0e: capture pre-migration baselines from the PHYSICAL tables (real tables pre-migration, so the
  # sqlite3 CLI is fine — no view machinery needed). gate1 asserts these are preserved post-migration.
  PRE_RAW="$(sqlite3 "$DB" "SELECT COUNT(*) FROM raw_notes;" 2>/dev/null)"
  if [ -z "$PRE_RAW" ]; then
    fail "preflight: could not read raw_notes count"
    return 1
  fi
  # processed_notes may be absent on a minimal DB; treat absent as 0.
  if [ "$(sqlite_object_type "$DB" processed_notes)" = "table" ]; then
    PRE_PROC="$(sqlite3 "$DB" "SELECT COUNT(*) FROM processed_notes;" 2>/dev/null)"
  else
    PRE_PROC="0"
  fi
  pass "preflight: PRE_RAW=$PRE_RAW PRE_PROC=$PRE_PROC captured"
  return 0
}

# ---------------------------------------------------------------------------
# backup_and_verify — step 3
# ---------------------------------------------------------------------------
backup_and_verify() {
  mkdir -p "$BACKUP_DIR"
  local sha
  sha="$( cd "$REPO_ROOT" && git rev-parse --short HEAD )"
  BACKUP="$BACKUP_DIR/pre-cutover-$sha-$(/bin/date +%Y%m%d-%H%M%S).db"

  info "backup: $DB -> $BACKUP"
  cp "$DB" "$BACKUP"

  # Verify the backup is a faithful copy: its raw_notes count must equal PRE_RAW. If not, ABORT
  # BEFORE migrating — we never want to migrate without a known-good restore point.
  local bk_raw
  bk_raw="$(sqlite3 "$BACKUP" "SELECT COUNT(*) FROM raw_notes;" 2>/dev/null)"
  if [ "$bk_raw" != "$PRE_RAW" ]; then
    fail "backup: verify failed — backup raw_notes=$bk_raw != PRE_RAW=$PRE_RAW (aborting before migrate)"
    return 1
  fi
  pass "backup: created + verified ($bk_raw rows == PRE_RAW)"

  # Prune: keep only the newest 5 pre-cutover-*.db backups.
  local pruned=0
  # List newest-first by mtime; delete everything after the 5th. NUL-safe is overkill for our own
  # timestamped names (no spaces/newlines), so a simple ls -t is fine here.
  while IFS= read -r old; do
    [ -z "$old" ] && continue
    rm -f "$old"
    pruned=$((pruned + 1))
  done < <(ls -t "$BACKUP_DIR"/pre-cutover-*.db 2>/dev/null | tail -n +6)
  if [ "$pruned" -gt 0 ]; then
    info "backup: pruned $pruned old backup(s), keeping newest 5"
  fi
  pass "backup: retention OK (newest 5 kept)"
  return 0
}

# ---------------------------------------------------------------------------
# migrate — step 4
# ---------------------------------------------------------------------------
migrate() {
  info "migrate: running scripts/migrate-to-fact-store.ts (DB=$DB FACTS=$FACTS)"
  local out rc
  set +e
  out="$( cd "$REPO_ROOT" && SELENE_DB_PATH="$DB" SELENE_FACTS_DB_PATH="$FACTS" \
      npx ts-node scripts/migrate-to-fact-store.ts 2>&1 )"
  rc=$?
  set -e
  echo "$out" | grep -v '^\[dotenv@' || true
  if [ "$rc" -ne 0 ]; then
    fail "migrate: exited $rc"
    return 1
  fi
  pass "migrate: completed (rc=0)"
  return 0
}

# ---------------------------------------------------------------------------
# gate1 — content-free verification; returns non-zero on ANY failure
# ---------------------------------------------------------------------------
gate1() {
  # Simulated failure hook (rollback test): fail fast WITHOUT touching the DB.
  if [ -n "$SIMULATE_GATE1_FAIL" ]; then
    fail "gate1 (simulated)"
    return 1
  fi

  local ok=1

  # (a) Structural: facts.db exists, raw_notes_legacy_backup present, raw_notes no longer a table.
  if [ ! -f "$FACTS" ]; then fail "gate1: facts.db missing at $FACTS"; ok=0; fi
  if [ "$(sqlite_object_type "$DB" raw_notes_legacy_backup)" = "table" ]; then
    pass "gate1: raw_notes_legacy_backup present"
  else
    fail "gate1: raw_notes_legacy_backup absent (migration did not rename)"; ok=0
  fi
  if [ "$(sqlite_object_type "$DB" raw_notes)" = "table" ]; then
    fail "gate1: raw_notes is STILL a physical table (not migrated)"; ok=0
  else
    pass "gate1: raw_notes is no longer a physical table"
  fi

  # (b) Counts preserved (content-free, read through selene-inspect's raw_notes view):
  #     rawNotes(view) == PRE_RAW and processedNotes == PRE_PROC.
  local now_raw now_proc
  now_raw="$( SELENE_DB_PATH="$DB" SELENE_FACTS_DB_PATH="$FACTS" inspect_field coverage rawNotes )"
  now_proc="$( SELENE_DB_PATH="$DB" SELENE_FACTS_DB_PATH="$FACTS" inspect_field coverage processedNotes )"
  if [ "$now_raw" = "$PRE_RAW" ]; then
    pass "gate1: rawNotes(view)=$now_raw == PRE_RAW"
  else
    fail "gate1: rawNotes(view)=$now_raw != PRE_RAW=$PRE_RAW"; ok=0
  fi
  if [ "$now_proc" = "$PRE_PROC" ]; then
    pass "gate1: processedNotes=$now_proc == PRE_PROC (preserved)"
  else
    fail "gate1: processedNotes=$now_proc != PRE_PROC=$PRE_PROC"; ok=0
  fi

  # (c) Capture→pending probe (content-free, nets to zero rows). Vault redirected to /tmp belt-and-
  #     suspenders. The probe self-guards to /tmp-only paths.
  info "gate1: running cutover-probe (capture -> pending, then self-delete)"
  local probe_out probe_rc
  set +e
  probe_out="$( cd "$REPO_ROOT" && \
      SELENE_DB_PATH="$DB" SELENE_FACTS_DB_PATH="$FACTS" \
      SELENE_VAULT_PATH=/tmp/cutover-probe-vault \
      npx ts-node scripts/cutover-probe.ts 2>&1 )"
  probe_rc=$?
  set -e
  echo "$probe_out" | grep -v '^\[dotenv@' || true
  if [ "$probe_rc" -eq 0 ]; then
    pass "gate1: capture->pending probe PASS"
  else
    fail "gate1: capture->pending probe FAIL (rc=$probe_rc)"; ok=0
  fi

  # (d) Whole-DB foreign-key integrity. Live derived tables had their raw_notes FK stripped; dormant
  #     ones point (inertly) at raw_notes_legacy_backup and their existing rows still validate. Any
  #     row from foreign_key_check => a real integrity break.
  local fk_rows
  fk_rows="$(sqlite3 "$DB" "PRAGMA foreign_key_check;" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${fk_rows:-0}" = "0" ]; then
    pass "gate1: foreign_key_check clean (0 violations)"
  else
    fail "gate1: foreign_key_check returned $fk_rows violation(s)"; ok=0
  fi

  if [ "$ok" = "1" ]; then
    pass "gate1: ALL checks passed"
    return 0
  fi
  fail "gate1: one or more checks failed"
  return 1
}

# ---------------------------------------------------------------------------
# rollback_db — restore to the byte-for-byte single-file backup
# ---------------------------------------------------------------------------
rollback_db() {
  if [ -z "$BACKUP" ] || [ ! -f "$BACKUP" ]; then
    fail "rollback: no backup recorded — MANUAL RECOVERY NEEDED"
    return 1
  fi
  info "rollback: restoring $BACKUP -> $DB and removing $FACTS"
  cp "$BACKUP" "$DB"
  # Remove the facts file AND any stale WAL/SHM sidecars on both files, so a leftover WAL cannot
  # resurrect post-migration state under the byte-for-byte single-file check.
  rm -f "$FACTS" "$FACTS-wal" "$FACTS-shm" "$DB-wal" "$DB-shm"

  # Confirm the restore: raw_notes is a physical table again with exactly PRE_RAW rows.
  local restored_type restored_raw
  restored_type="$(sqlite_object_type "$DB" raw_notes)"
  restored_raw="$(sqlite3 "$DB" "SELECT COUNT(*) FROM raw_notes;" 2>/dev/null)"
  if [ "$restored_type" = "table" ] && [ "$restored_raw" = "$PRE_RAW" ]; then
    pass "rollback: restored single-file DB (raw_notes table, $restored_raw rows == PRE_RAW)"
    return 0
  fi
  # SHOUT: the restore did not produce the expected pre-migration shape.
  echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  fail "rollback: VERIFY FAILED — raw_notes type='${restored_type:-absent}' rows='$restored_raw' (expected table/$PRE_RAW). MANUAL RECOVERY NEEDED. Backup is at: $BACKUP"
  echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
  return 1
}

# ===========================================================================
# TODO (NEXT TASK — orchestration; NOT implemented here):
#   stop_deploy_watcher()  — pause com.selene.prod deploy-watcher so it can't redeploy mid-cutover
#   stop_prod_agents()     — bootout the running com.selene.prod.* agents before DB surgery
#   deploy_two_file_build()— build/deploy the dist/ that knows the two-file layout
#   gate2()                — post-deploy live-health verification (server up, agents green)
#   resume_or_rollback()   — on gate2 fail: rollback_db + redeploy previous release; else resume watcher
#   main()                 — full ordered cutover wrapping the DB core below
# This file (Task 3) implements ONLY the DB-surgery core above.
# ===========================================================================

# When executed directly (not sourced), run ONLY the DB-critical core sequence so it can be
# exercised standalone. The check harness sources this file and calls functions individually.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  preflight
  backup_and_verify
  migrate
  if gate1; then
    pass "cutover DB-core: SUCCESS"
  else
    fail "cutover DB-core: gate1 failed — rolling back DB"
    rollback_db
    exit 1
  fi
fi
