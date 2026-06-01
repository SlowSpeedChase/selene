#!/bin/bash
#
# verify-fact-store.sh — Task 10: FINAL end-to-end validation of the fact-store split.
#
# Validates the REAL migration + REAL pipeline (LLM) on a CONSISTENT, READ-ONLY snapshot of
# the real dev corpus, fully isolated to /tmp. Touches the real dev DB exactly ONCE (a
# read-only `.backup` snapshot) and NEVER touches the real iCloud Obsidian vault (every
# workflow runs with SELENE_VAULT_PATH=/tmp, the one bug the prod-data guard cannot catch).
#
# Phases:
#   0  fresh /tmp snapshot of real-dev selene.db  +  run the real migration  +  baseline coverage
#   1  insert ONE fresh note  ->  run the REAL pipeline (process-llm/distill/synthesize/export)
#      ->  assert it flowed capture->pending->processed->clustered->exported-to-/tmp-vault
#   2  concurrency stress: writer(facts) || reader(view) for a few seconds  ->  assert 0 SQLITE_BUSY
#
# Idempotent + self-isolating: safe to re-run. Requires Ollama up (mistral:7b, nomic-embed-text).
#
#   ./scripts/verify-fact-store.sh
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Isolation env — EVERY workflow/inspect/probe command inherits these. The vault/vectors/
# digests redirects are non-negotiable: export-obsidian resolves its vault from
# SELENE_VAULT_PATH (which .env sets to the PROD iCloud vault); the guard can't catch a
# runtime config path, so we MUST point it at /tmp here.
# ---------------------------------------------------------------------------
export SELENE_ENV=development
export SELENE_DB_PATH=/tmp/t10-selene.db
export SELENE_FACTS_DB_PATH=/tmp/t10-facts.db
export SELENE_VAULT_PATH=/tmp/t10-vault
export SELENE_VECTORS_PATH=/tmp/t10-vectors.lance
export SELENE_DIGESTS_PATH=/tmp/t10-digests

REAL_DEV_DB="$HOME/selene-data-dev/selene.db"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS_ALL=1
note_fail() { PASS_ALL=0; echo -e "${RED}  [FAIL] $1${NC}"; }
note_pass() { echo -e "${GREEN}  [PASS] $1${NC}"; }
section()   { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# ts-node prints a dotenv banner on STDOUT before the JSON, and its randomized "tip" lines can
# contain literal braces (e.g. `{ path: [...] }`), so a first-'{'/last-'}' slice is unsafe.
# Every parser below first strips `^[dotenv@` lines, leaving clean JSON to JSON.parse.
#
# Read a single nested field from `selene-inspect coverage` JSON (isolation env already exported).
# Usage: coverage_field <subKey>
coverage_field() {
  npx ts-node scripts/selene-inspect.ts coverage 2>/dev/null | grep -v '^\[dotenv@' \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const v=j.coverage&&j.coverage['$1']!==undefined?j.coverage['$1']:'';process.stdout.write(String(v));}catch(e){process.stdout.write('');}});"
}

# Hard guard: refuse if any isolation path is not under /tmp (belt-and-suspenders).
for p in "$SELENE_DB_PATH" "$SELENE_FACTS_DB_PATH" "$SELENE_VAULT_PATH" "$SELENE_VECTORS_PATH" "$SELENE_DIGESTS_PATH"; do
  case "$p" in /tmp/*) ;; *) echo -e "${RED}ABORT: isolation path '$p' is not under /tmp${NC}"; exit 2;; esac
done

# =====================================================================================
section "Phase 0 — fresh /tmp snapshot + migrate"
# =====================================================================================
rm -f /tmp/t10-selene.db /tmp/t10-facts.db
rm -f /tmp/t10-selene.db-wal /tmp/t10-selene.db-shm /tmp/t10-facts.db-wal /tmp/t10-facts.db-shm
rm -rf /tmp/t10-vault /tmp/t10-vectors.lance /tmp/t10-digests
echo "cleaned /tmp/t10-* artifacts"

if [ ! -f "$REAL_DEV_DB" ]; then
  echo -e "${RED}ABORT: real dev DB not found at $REAL_DEV_DB${NC}"; exit 2
fi
# The ONLY contact with the real dev DB: a read-only, transactionally-consistent snapshot.
# `.backup` (vs. cp) is robust to any WAL state and never writes the source.
echo "snapshotting real-dev selene.db -> /tmp/t10-selene.db (read-only .backup)"
sqlite3 "$REAL_DEV_DB" ".backup '/tmp/t10-selene.db'"
if [ ! -f /tmp/t10-selene.db ]; then echo -e "${RED}ABORT: snapshot failed${NC}"; exit 2; fi

# Snapshot must NOT already be in the two-file shape (it should carry a physical raw_notes).
PRE_TYPE=$(sqlite3 /tmp/t10-selene.db "SELECT type FROM sqlite_master WHERE name='raw_notes';" 2>/dev/null)
echo "snapshot raw_notes object type (pre-migration): ${PRE_TYPE:-<absent>}"

echo -e "${YELLOW}running migration: scripts/migrate-to-fact-store.ts${NC}"
MIG_OUT=$(npx ts-node scripts/migrate-to-fact-store.ts 2>&1)
MIG_RC=$?
echo "$MIG_OUT"
if [ $MIG_RC -ne 0 ]; then note_fail "migration exited $MIG_RC"; else note_pass "migration succeeded"; fi
# facts.db must now exist; raw_notes_legacy_backup must exist in selene.db.
[ -f /tmp/t10-facts.db ] && note_pass "facts.db created" || note_fail "facts.db missing after migration"
BK=$(sqlite3 /tmp/t10-selene.db "SELECT COUNT(*) FROM sqlite_master WHERE name='raw_notes_legacy_backup';" 2>/dev/null)
[ "$BK" = "1" ] && note_pass "raw_notes renamed to raw_notes_legacy_backup" || note_fail "legacy backup table absent"

# Idempotency: a second run must be a clean no-op.
echo -e "${YELLOW}re-running migration (idempotency check)${NC}"
MIG2_OUT=$(npx ts-node scripts/migrate-to-fact-store.ts 2>&1); MIG2_RC=$?
echo "$MIG2_OUT"
if [ $MIG2_RC -eq 0 ] && echo "$MIG2_OUT" | grep -qi "already migrated"; then
  note_pass "migration is idempotent (second run = no-op)"
else
  note_fail "second migration run was not a clean no-op (rc=$MIG2_RC)"
fi

# Baseline coverage on the migrated two-file DB (read through the raw_notes view).
section "Phase 0 — baseline coverage (two-file, post-migration)"
BASE_RAW=$(coverage_field rawNotes)
BASE_PROC=$(coverage_field processedNotes)
BASE_UNPROC=$(coverage_field unprocessed)
BASE_CLUST=$(coverage_field clusters)
BASE_LINKS=$(coverage_field noteLinks)
echo "  rawNotes=$BASE_RAW  processedNotes=$BASE_PROC  unprocessed=$BASE_UNPROC  clusters=$BASE_CLUST  noteLinks=$BASE_LINKS"
[ "${BASE_RAW:-0}" -ge 1 ] 2>/dev/null && note_pass "baseline rawNotes=$BASE_RAW (>0)" || note_fail "baseline rawNotes not read (got '$BASE_RAW')"
if [ "${BASE_UNPROC:-1}" = "0" ]; then note_pass "baseline unprocessed=0 (corpus fully processed)"; else note_fail "baseline unprocessed=$BASE_UNPROC (expected 0)"; fi

# =====================================================================================
section "Phase 1 — fresh capture flows through the REAL pipeline"
# =====================================================================================
PROBE_MARKER="T10-PROBE-$(date +%s)"
export T10_PROBE_MARKER="$PROBE_MARKER"
echo "inserting one fresh probe note (marker=$PROBE_MARKER) via the real capture write path"
# Probe prints a single JSON object on stdout (after the dotenv banner). Strip dotenv lines.
PROBE_JSON=$(npx ts-node scripts/fact-store-insert-probe.ts 2>/dev/null | grep -v '^\[dotenv@')
echo "  $(echo "$PROBE_JSON" | tr -d '\n')"
probe_val() { echo "$PROBE_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{process.stdout.write(String(JSON.parse(s)['$1']))}catch{process.stdout.write('')}});"; }
PROBE_ID=$(probe_val id)
PROBE_VIEWSTATUS=$(probe_val viewStatus)
if [ -z "$PROBE_ID" ]; then note_fail "probe insert produced no id"; fi
[ "$PROBE_VIEWSTATUS" = "pending" ] && note_pass "fresh note reads back as 'pending' via the view (derivation-absence)" \
  || note_fail "fresh note view status='$PROBE_VIEWSTATUS' (expected 'pending')"

AFTER_INSERT_UNPROC=$(coverage_field unprocessed)
AFTER_INSERT_RAW=$(coverage_field rawNotes)
echo "  after insert: rawNotes=$AFTER_INSERT_RAW  unprocessed=$AFTER_INSERT_UNPROC"
if [ "${AFTER_INSERT_UNPROC:-0}" -eq $(( ${BASE_UNPROC:-0} + 1 )) ] 2>/dev/null; then
  note_pass "unprocessed increased by exactly 1 ($BASE_UNPROC -> $AFTER_INSERT_UNPROC)"
else
  note_fail "unprocessed did not increase by 1 ($BASE_UNPROC -> $AFTER_INSERT_UNPROC)"
fi
if [ "${AFTER_INSERT_RAW:-0}" -eq $(( ${BASE_RAW:-0} + 1 )) ] 2>/dev/null; then
  note_pass "rawNotes increased by exactly 1 ($BASE_RAW -> $AFTER_INSERT_RAW)"
else
  note_fail "rawNotes did not increase by 1 ($BASE_RAW -> $AFTER_INSERT_RAW)"
fi

# Run the REAL pipeline via dev-process-batch.sh. That script hardcodes DEV_DB to the real
# dev path for its OWN status/env-check; we run a /tmp COPY with DEV_DB repointed at the
# snapshot so there is ZERO contact with real-dev here (the workflows it spawns already honor
# the exported SELENE_DB_PATH=/tmp/...). Same script body, only the path constant changed.
BATCH_TMP=/tmp/t10-dev-process-batch.sh
sed "s#^DEV_DB=.*#DEV_DB=\"/tmp/t10-selene.db\"#" scripts/dev-process-batch.sh > "$BATCH_TMP"
chmod +x "$BATCH_TMP"
echo -e "${YELLOW}running the REAL pipeline: $BATCH_TMP --all (process-llm -> distill -> synthesize -> export)${NC}"
echo -e "${YELLOW}(LLM steps against Ollama — this can take a few minutes)${NC}"
"$BATCH_TMP" --all 2>&1 | tail -40 || true

# Assert end-to-end outcome via the inspector (content-free).
section "Phase 1 — end-to-end assertions"
POST_RAW=$(coverage_field rawNotes)
POST_PROC=$(coverage_field processedNotes)
POST_UNPROC=$(coverage_field unprocessed)
POST_CLUST=$(coverage_field clusters)
POST_LINKS=$(coverage_field noteLinks)
echo "  post-batch: rawNotes=$POST_RAW  processedNotes=$POST_PROC  unprocessed=$POST_UNPROC  clusters=$POST_CLUST  noteLinks=$POST_LINKS"

if [ "${POST_UNPROC:-1}" = "0" ]; then note_pass "unprocessed=0 again (fresh note got processed)"; else note_fail "unprocessed=$POST_UNPROC (expected 0)"; fi
if [ "${POST_PROC:-0}" -eq $(( ${BASE_PROC:-0} + 1 )) ] 2>/dev/null; then
  note_pass "processedNotes increased by exactly 1 ($BASE_PROC -> $POST_PROC)"
else
  note_fail "processedNotes change unexpected ($BASE_PROC -> $POST_PROC, expected +1)"
fi
# No regression: existing corpus still present (rawNotes = baseline+1, processed = baseline+1).
if [ "${POST_RAW:-0}" -eq $(( ${BASE_RAW:-0} + 1 )) ] 2>/dev/null; then
  note_pass "no raw_notes regression (rawNotes = baseline+1)"
else
  note_fail "raw_notes regression ($BASE_RAW -> $POST_RAW, expected +1)"
fi
# Cluster band: must still have clusters, and the fresh note must be linked (links grew or
# the corpus was re-clustered). Assert clusters present and >= baseline, and links >= baseline.
if [ "${POST_CLUST:-0}" -ge 1 ] 2>/dev/null; then note_pass "clusters present post-batch ($POST_CLUST)"; else note_fail "no clusters after batch ($POST_CLUST)"; fi
if [ "${POST_LINKS:-0}" -ge "${BASE_LINKS:-0}" ] 2>/dev/null; then
  note_pass "topic_note_links did not shrink ($BASE_LINKS -> $POST_LINKS)"
else
  note_fail "topic_note_links shrank ($BASE_LINKS -> $POST_LINKS)"
fi

# Direct confirmation the fresh note is processed + has a note_state row + is in a cluster
# (id-targeted, content-free counts only).
if [ -n "$PROBE_ID" ]; then
  HAS_PROC=$(sqlite3 /tmp/t10-selene.db "SELECT COUNT(*) FROM processed_notes WHERE raw_note_id=$PROBE_ID;" 2>/dev/null)
  HAS_STATE=$(sqlite3 /tmp/t10-selene.db "SELECT COUNT(*) FROM note_state WHERE raw_note_id=$PROBE_ID AND status='processed';" 2>/dev/null)
  IN_CLUSTER=$(sqlite3 /tmp/t10-selene.db "SELECT COUNT(*) FROM topic_note_links WHERE note_id=$PROBE_ID;" 2>/dev/null)
  echo "  probe id=$PROBE_ID: processed_notes rows=$HAS_PROC  note_state(processed)=$HAS_STATE  cluster links=$IN_CLUSTER"
  [ "${HAS_PROC:-0}" -ge 1 ] && note_pass "fresh note has a processed_notes row" || note_fail "fresh note missing processed_notes row"
  [ "${HAS_STATE:-0}" -ge 1 ] && note_pass "fresh note has note_state.status='processed'" || note_fail "fresh note missing note_state processed row"
  [ "${IN_CLUSTER:-0}" -ge 1 ] && note_pass "fresh note appears in a cluster (topic_note_links)" || note_fail "fresh note not linked to any cluster"
fi

# export-obsidian wrote to /tmp/t10-vault (NOT the iCloud vault). Content-free: existence + .md count.
section "Phase 1 — Obsidian export landed in /tmp (not the real vault)"
if [ -d /tmp/t10-vault ]; then
  MD_COUNT=$(find /tmp/t10-vault -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "  /tmp/t10-vault exists with $MD_COUNT .md file(s)"
  [ "${MD_COUNT:-0}" -ge 1 ] && note_pass "export-obsidian wrote .md files to /tmp/t10-vault" || note_fail "/tmp/t10-vault has no .md files"
else
  note_fail "/tmp/t10-vault was not created (export-obsidian may have targeted elsewhere)"
fi

# =====================================================================================
section "Phase 2 — concurrency stress (WAL + busy_timeout across ATTACH)"
# =====================================================================================
echo "writer(facts.captured_notes) || reader(raw_notes view) for ~${T10_CONCURRENCY_MS:-4000}ms — asserting 0 SQLITE_BUSY"
CONC_OUT=$(npx ts-node scripts/fact-store-concurrency-check.ts 2>&1); CONC_RC=$?
echo "$CONC_OUT" | grep -v '^CONCURRENCY_RESULT' || true
CONC_LINE=$(echo "$CONC_OUT" | grep '^CONCURRENCY_RESULT' | tail -1 | sed 's/^CONCURRENCY_RESULT //')
echo "  result: ${CONC_LINE:-<none>}"
if [ $CONC_RC -eq 0 ] && [ -n "$CONC_LINE" ]; then
  CONC_BUSY=$(echo "$CONC_LINE" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(String(JSON.parse(s).totalBusy)));")
  CONC_OPS=$(echo "$CONC_LINE" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>process.stdout.write(String(JSON.parse(s).totalOps)));")
  if [ "$CONC_BUSY" = "0" ]; then note_pass "0 SQLITE_BUSY across $CONC_OPS concurrent ops"; else note_fail "$CONC_BUSY SQLITE_BUSY errors (must be 0)"; fi
else
  note_fail "concurrency harness failed (rc=$CONC_RC)"
fi

# =====================================================================================
section "Diagnostic — migration FK-rewrite check (root cause if Phase 1 failed)"
# =====================================================================================
# After `ALTER TABLE raw_notes RENAME TO raw_notes_legacy_backup`, SQLite (>=3.25, default
# legacy_alter_table=OFF) AUTO-REWRITES every child FK that referenced `raw_notes` to point at
# `raw_notes_legacy_backup` instead. That table is FROZEN at the migrated id set, so any
# POST-migration note (only in facts.captured_notes) violates the FK — `processed_notes` is the
# one that breaks the ACTIVE pipeline (process-llm INSERT). List every derived table still
# carrying that rewritten FK so the failure is attributed, not mistaken for flakiness.
FK_TABLES=$(sqlite3 /tmp/t10-selene.db "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null | while read -r t; do
  if sqlite3 /tmp/t10-selene.db ".schema $t" 2>/dev/null | grep -qiE 'REFERENCES .?raw_notes_legacy_backup'; then
    [ "$t" != "raw_notes_legacy_backup" ] && echo "$t"
  fi
done)
if [ -n "$FK_TABLES" ]; then
  echo -e "${RED}  Tables whose FK was rewritten to raw_notes_legacy_backup (block new-note inserts):${NC}"
  echo "$FK_TABLES" | sed 's/^/    - /'
  echo "$FK_TABLES" | grep -qx 'processed_notes' \
    && echo -e "${RED}  >> processed_notes is among them → the ACTIVE pipeline (process-llm) is broken for every new capture.${NC}"
  echo "  Fix belongs in scripts/migrate-to-fact-store.ts: rebuild these derived tables to DROP the"
  echo "  raw_notes FK (it can't reference the new view / cross-file facts.captured_notes). note_state"
  echo "  was correctly created FK-free — use it as the template. (Out of scope for Task 10: report only.)"
else
  echo -e "${GREEN}  No derived table carries a raw_notes_legacy_backup FK (migration FK-rewrite is clean).${NC}"
fi

# =====================================================================================
section "SUMMARY"
# =====================================================================================
echo "  Phase 0 migration:   migrated ${BASE_RAW} notes into the two-file layout (idempotent re-run = no-op)"
echo "  Baseline:            rawNotes=$BASE_RAW processed=$BASE_PROC unprocessed=$BASE_UNPROC clusters=$BASE_CLUST links=$BASE_LINKS"
echo "  After fresh capture: rawNotes=$POST_RAW processed=$POST_PROC unprocessed=$POST_UNPROC clusters=$POST_CLUST links=$POST_LINKS"
echo "  Concurrency:         ${CONC_LINE:-<none>}  (Phase 2 acceptance: totalBusy must be 0)"
echo "  Real-dev contact:    one read-only .backup snapshot (no writes); real iCloud vault never referenced."
if [ "$PASS_ALL" = "1" ]; then
  echo -e "\n${GREEN}========== ALL PHASES PASSED ==========${NC}"
  exit 0
else
  echo -e "\n${RED}========== ONE OR MORE PHASES FAILED ==========${NC}"
  if [ -n "$FK_TABLES" ]; then
    echo -e "${YELLOW}Phase 1 fresh-capture FAILURE is caused by the migration FK-rewrite bug above${NC}"
    echo -e "${YELLOW}(a real, ship-blocking defect in scripts/migrate-to-fact-store.ts), NOT a flaky test.${NC}"
  fi
  exit 1
fi
