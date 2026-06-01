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

# --- orchestration config / args (Tasks 4+5) ---
DRY_RUN="${DRY_RUN:-}"                       # set (or --dry-run) to stub launchctl/deploy/notify
PROD_TARGET="${PROD_TARGET:-$HOME/selene-prod}"   # prod deploy dir (holds .deployed-sha); deploy-prod.sh's $TARGET
TARGET_SHA="${TARGET_SHA:-}"                 # ref to deploy (arg / --ref); defaults to origin/main below

# OLD_SHA = the code prod is currently on, for the rollback path. Read the prod target's
# .deployed-sha exactly as deploy-prod.sh does ($TARGET/.deployed-sha); "none" if absent.
OLD_SHA="$(cat "$PROD_TARGET/.deployed-sha" 2>/dev/null || echo none)"

# Parse orchestration args BEFORE any side effects. A bare positional or `--ref <sha>` sets
# TARGET_SHA; `--dry-run` flips DRY_RUN on. (The DB-surgery core reads its paths from env, not args.)
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1; shift ;;
    --ref)      TARGET_SHA="$2"; shift 2 ;;
    -h|--help)  echo "Usage: cutover-prod.sh [--dry-run] [--ref <sha>|<sha>]"; exit 0 ;;
    -*)         echo "Unknown argument: $1" >&2; exit 2 ;;
    *)          TARGET_SHA="$1"; shift ;;
  esac
done
TARGET_SHA="${TARGET_SHA:-origin/main}"

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
    # Fix #1: return a DISTINCT code (2) for already-migrated instead of `exit 0`. When this file
    # is SOURCED (the harnesses), `exit 0` would kill the harness's whole shell — a footgun. main()
    # maps rc==2 -> clean "already migrated" exit; harnesses just see a non-zero return and move on.
    return 2
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
# ORCHESTRATION (Tasks 4+5) — wraps the DB-surgery core above with the watcher /
# agent / deploy / Gate-2 / auto-rollback sequence.
#
# `--dry-run` stubs ONLY the launchctl + deploy + notify side effects (prints
# intentions). The DB surgery (backup/migrate/gate1/rollback) ALWAYS runs FOR
# REAL against whatever DB is configured — so the /tmp validation actually
# proves the migration + rollback, not a no-op.
# ===========================================================================

# notify helper (selene_notify): same source deploy-prod.sh / rollback-prod.sh use.
# Sourcing notify.sh must not mutate this shell's options. Thin fallback if absent.
if [ -f "$REPO_ROOT/scripts/lib/notify.sh" ]; then
  # shellcheck source=lib/notify.sh
  source "$REPO_ROOT/scripts/lib/notify.sh"
else
  selene_notify() { echo "[notify] ${1:-Selene}: ${2:-}"; }
fi

run_or_echo() {
  if [ -n "$DRY_RUN" ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# Discover the running prod agents EXACTLY as deploy-prod.sh does (label col 3,
# com.selene.prod.* minus the deploy-watcher). Empty when nothing is loaded.
prod_agents() {
  launchctl list | awk '{print $3}' | grep '^com.selene.prod' | grep -v 'deploy-watcher' || true
}

# launchd juggling is BEST-EFFORT (matches deploy-prod.sh's warn-not-die philosophy). Each
# launchctl is `|| true` so a stray non-zero NEVER aborts under `set -e`. This matters most for
# rollback_all(): it runs as the command after `gate* || { rollback_all; ... }` — the ONE position
# `set -e` does NOT exempt — so a non-zero `launchctl` in stop_agents could otherwise skip the
# irreplaceable rollback_db DB-restore. `|| true` protects both main() and rollback_all().
# (pause_watcher is intentionally NOT guarded: failing it before anything is torn down is a safe
# early abort.)
pause_watcher() {
  run_or_echo launchctl bootout "gui/$(id -u)/com.selene.prod.deploy-watcher"
}
resume_watcher() {
  run_or_echo launchctl bootstrap "gui/$(id -u)" "$REPO_ROOT/launchd/com.selene.prod.deploy-watcher.plist" || true
}
stop_agents() {
  local a
  for a in $(prod_agents); do
    run_or_echo launchctl bootout "gui/$(id -u)/$a" || true
  done
}
# restart_agents — bring the prod server + workflow agents back UP after stop_agents.
# Why BOOTSTRAP (not kickstart, which deploy-prod.sh uses): stop_agents() does a full
# `launchctl bootout`, so the agents are GONE from the domain. `kickstart -k` only
# restarts an ALREADY-LOADED service, so post-bootout it is a no-op → prod stays DOWN.
# The inverse of `bootout` is `bootstrap`. We therefore re-LOAD each agent, mirroring
# install-prod.sh's Pass 2 (bootstrap "gui/$(id -u)" <installed prod plist>).
#
# We must iterate the installed prod plist FILES, NOT prod_agents()/`launchctl list`:
# after the real bootout the agents are unloaded, so `launchctl list` shows nothing to
# loop over. The deployed prod plists live in install-prod.sh's OUT_DIR
# ($HOME/Library/LaunchAgents, the COMPILED-dist variants) — bootstrapping the canonical
# launchd/ sources would load dev (ts-node) code under prod labels.
#
# EXCLUDE the deploy-watcher: resume_watcher() owns it (from the repo plist). Bootstrapping
# an already-loaded service errors, so re-loading it here would double-bootstrap it.
restart_agents() {
  local plist
  for plist in "$HOME/Library/LaunchAgents/com.selene.prod."*.plist; do
    [ -e "$plist" ] || continue                       # nullglob-safe (no installed plists)
    case "$plist" in *deploy-watcher.plist) continue ;; esac   # resume_watcher owns the watcher
    run_or_echo launchctl bootstrap "gui/$(id -u)" "$plist" || true
  done
}
deploy() {
  run_or_echo "$REPO_ROOT/scripts/deploy-prod.sh" --ref "${TARGET_SHA:-origin/main}"
}

# gate2 — POST-deploy live-health verification (the new dist/ server is up and reads
# the two-file layout). NOTE: this must NOT reuse cutover-probe.ts — that probe
# self-refuses unless both DB paths are under /tmp, and morally it would write a note
# into REAL prod. gate1 already ran the capture->pending probe pre-deploy. Here we only
# read: /health + a content-free selene-inspect coverage sanity (rawNotes>0, facts.db present).
gate2() {
  if [ -n "$DRY_RUN" ]; then
    echo "  [dry-run] gate2: would curl /health + probe + inspect"
    return 0
  fi
  local ok=1
  # Readiness-wait: `launchctl bootstrap` (restart_agents) returns when the job is LOADED, not when
  # Node has bound port 5678 — so retry /health up to ~30s before declaring failure, else a slow
  # cold start spuriously trips gate2 → rollback_all (prod rolled back when it would have come up a
  # second later).
  local tries=30 health_ok=
  for _ in $(seq 1 "$tries"); do
    if curl -fsS http://localhost:5678/health >/dev/null 2>&1; then health_ok=1; break; fi
    sleep 1
  done
  if [ -n "$health_ok" ]; then
    pass "gate2: /health OK"
  else
    fail "gate2: /health not reachable after ${tries}s"; ok=0
  fi
  # facts.db must exist post-cutover.
  if [ -f "$FACTS" ]; then
    pass "gate2: facts.db present at $FACTS"
  else
    fail "gate2: facts.db missing at $FACTS"; ok=0
  fi
  # Content-free read-only coverage sanity: rawNotes (via the view) must be > 0.
  local g2_raw
  g2_raw="$( inspect_field coverage rawNotes )"
  if [ -n "$g2_raw" ] && [ "$g2_raw" -gt 0 ] 2>/dev/null; then
    pass "gate2: rawNotes(view)=$g2_raw (>0, server reads the two-file layout)"
  else
    fail "gate2: rawNotes(view)='$g2_raw' (expected >0 via the migrated view)"; ok=0
  fi
  [ "$ok" = "1" ] && return 0 || return 1
}

# rollback_all — GATE-failure path. Tears prod back to the pre-cutover state:
# stop agents -> restore the single-file DB -> roll the code back to OLD_SHA ->
# restart agents -> resume the watcher -> notify. In dry-run, the launchctl/deploy/
# notify steps print; rollback_db runs FOR REAL (it's the DB-surgery core).
rollback_all() {
  echo "!! ROLLBACK"
  stop_agents
  rollback_db || true
  # Roll the CODE back to OLD_SHA. If OLD_SHA is the "none" sentinel (no prior deploy recorded),
  # pass no sha so rollback-prod.sh selects the newest archived release instead of looking up a
  # bogus releases/none dir. Either way the rollback-prod.sh line is emitted (dry-run-visible).
  if [ -n "${OLD_SHA:-}" ] && [ "$OLD_SHA" != "none" ]; then
    run_or_echo "$REPO_ROOT/scripts/rollback-prod.sh" "$OLD_SHA"
  else
    run_or_echo "$REPO_ROOT/scripts/rollback-prod.sh"
  fi
  restart_agents
  resume_watcher
  run_or_echo selene_notify "Selene cutover ROLLED BACK" "restored single-file + code ${OLD_SHA:-none}"
}

# ---------------------------------------------------------------------------
# main — the full ordered cutover. Runs ONLY when this file is EXECUTED (the
# check/verify harnesses SOURCE it and call functions individually, so the
# BASH_SOURCE guard at the very bottom keeps main from firing under `source`).
# ---------------------------------------------------------------------------
main() {
  # 0a build-gate: a broken build must abort BEFORE anything is torn down. Run it
  # first, before pause_watcher/stop_agents. In dry-run, print-and-skip (keeps the
  # /tmp validation fast); live, the build must actually pass.
  if [ -n "$DRY_RUN" ]; then
    echo "  [dry-run] build-gate: would run 'npm run build && npm run build:check'"
  else
    info "build-gate: npm run build && npm run build:check"
    if ! ( cd "$REPO_ROOT" && npm run build && npm run build:check ); then
      fail "build-gate failed — aborting cutover (nothing torn down)"
      exit 1
    fi
    pass "build-gate: dist/ built + verified"
  fi

  # Fix #1: preflight returns 2 for the already-migrated case. Under `set -e` a bare
  # `preflight` that returns non-zero aborts before `rc=$?`; capture via `|| rc=$?`.
  local rc=0
  preflight || rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "already migrated — nothing to do"
    exit 0
  elif [ "$rc" -ne 0 ]; then
    exit 1
  fi

  # Fix #2 (visibility): this script MUTATES the real DB — make the operator SEE which
  # DB/facts paths it will operate on (prod, not a stale dev path) before any surgery.
  echo "Cutover will operate on: DB=$DB FACTS=$FACTS (backup->$BACKUP_DIR)"

  pause_watcher
  stop_agents

  # Pre-migrate abort: if backup fails, NOTHING was changed — just bring prod back up.
  if ! backup_and_verify; then
    fail "backup_and_verify failed — aborting BEFORE migrate (nothing changed)"
    resume_watcher
    restart_agents
    exit 1
  fi

  # From here the DB may be mutated, so every gate failure routes to full rollback.
  # Bare calls would trip `set -e` and abort with the watcher paused / agents down and
  # NO rollback — so guard each with `|| { rollback_all; exit 1; }`.
  migrate || { rollback_all; exit 1; }
  gate1   || { rollback_all; exit 1; }

  # A failed deploy AFTER a successful migrate leaves prod incoherent (two-file DB + old
  # single-file-expecting code) — exactly what rollback_all unwinds. So route deploy failure to
  # rollback too. (restart_agents stays bare: its launchctl calls are `|| true`, warn-not-die.)
  deploy || { rollback_all; exit 1; }
  restart_agents
  gate2 || { rollback_all; exit 1; }

  resume_watcher
  run_or_echo selene_notify "Selene cutover complete" "fact-store live on ${TARGET_SHA}"
  echo "✅ CUTOVER COMPLETE"
}

# Only run main when this file is EXECUTED, not when SOURCED (the harnesses source it
# to drive functions one-by-one; sourcing must never fire the full cutover).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
