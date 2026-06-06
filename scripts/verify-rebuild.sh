#!/bin/bash
#
# verify-rebuild.sh — end-to-end rehearsal of scripts/rebuild.ts against a /tmp two-file
# DB seeded from a READ-ONLY snapshot of the dev DB. NEVER touches prod, NEVER touches the
# prod wrapper (no launchctl), NEVER reads note text (counts + hashes only).
#
# Why this exists: rebuild's pure pieces are unit-tested (rebuild-core.*.test.ts); this proves
# the ORCHESTRATION on real data — drain, the verdict gate, and (the precious part) auto-rollback
# + facts-untouched — end to end through real Ollama on a tiny corpus.
#
# Contact with the real world:
#   - ONE read-only `sqlite3 .backup` of the dev selene.db + facts.db (never written)
#   - everything else is /tmp-isolated (SELENE_DB_PATH / SELENE_FACTS_DB_PATH / SELENE_VAULT_PATH /
#     BACKUP_DIR all under /tmp); dev DB mtime is asserted unchanged at the end
#   - rebuild.ts is run DIRECTLY (never rebuild-prod.sh) so NO launchd agent is ever touched
#
# Scenarios (N = VERIFY_NOTES, single-digit default):
#   A HAPPY        — drain a pending corpus → exit 0, verdict PASS, coverage 1.0 (every captured
#                    note has a processed row), a pre-rebuild backup exists, facts byte-identical.
#   B COVERAGE-FAIL— SIMULATE_COVERAGE_FAIL=1 → exit 1 for the COVERAGE reason (asserted), derived
#                    tables rolled back to PRE. PRE is seeded with K dummy processed rows (K≠N) so
#                    the rollback is DISCRIMINATING: a no-op restore would leave the post-rederive
#                    N rows, not K.
#   C DRIFT-FAIL   — SIMULATE_DRIFT_FAIL=1 (post.embeddings=0) → exit 1 for the DRIFT reason
#                    (asserted, distinct from B). PRE seeds K note_embeddings rows so the drift has
#                    a NON-zero baseline — verdict() skips zero-baseline drift, so a zero-baseline
#                    metric would silently pass. Discriminating rollback to K.
#   D CRASH-RESUME — SIMULATE_REDERIVE_FAIL=1 throws AFTER the wipe → catch restores → exit 1, PRE
#                    restored (0 processed); then a plain process-llm run re-derives → self-heal.
#   E FACTS UNTOUCHED — facts.db shasum asserted identical before/after EVERY scenario.
#
#   ./scripts/verify-rebuild.sh           # N=5
#   VERIFY_NOTES=8 ./scripts/verify-rebuild.sh
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

REAL_DEV_DB="$HOME/selene-data-dev/selene.db"
REAL_DEV_FACTS="$HOME/selene-data-dev/facts.db"
N="${VERIFY_NOTES:-5}"      # corpus size — each drain runs real Ollama, so keep it single-digit
K=2                          # dummy PRE-derived rows for the discriminating rollback (must differ from N)

# /tmp isolation — rebuild.ts runs entirely against these.
PRISTINE_DB=/tmp/vr-pristine-selene.db
PRISTINE_FACTS=/tmp/vr-pristine-facts.db
VR_DB=/tmp/vr-selene.db
VR_FACTS=/tmp/vr-facts.db
VR_BACKUPS=/tmp/vr-backups
VR_VAULT=/tmp/vr-vault

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS_ALL=1
note_fail() { PASS_ALL=0; echo -e "${RED}  [FAIL] $1${NC}"; }
note_pass() { echo -e "${GREEN}  [PASS] $1${NC}"; }
section()   { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Hard guard: this harness must only ever drive /tmp paths.
for p in "$PRISTINE_DB" "$PRISTINE_FACTS" "$VR_DB" "$VR_FACTS" "$VR_BACKUPS" "$VR_VAULT"; do
  case "$p" in /tmp/*) ;; *) echo -e "${RED}ABORT: path '$p' is not under /tmp${NC}"; exit 2;; esac
done

[ -f "$REAL_DEV_DB" ] || { echo -e "${RED}ABORT: dev DB not found at $REAL_DEV_DB${NC}"; exit 2; }
[ -f "$REAL_DEV_FACTS" ] || { echo -e "${RED}ABORT: dev facts.db not found at $REAL_DEV_FACTS${NC}"; exit 2; }
[ "$K" -ne "$N" ] || { echo -e "${RED}ABORT: K must differ from N for a discriminating rollback${NC}"; exit 2; }

# --- counts (content-free) ---
count() { sqlite3 "$1" "$2" 2>/dev/null; }   # $1=db file, $2=SELECT COUNT(*)...
facts_hash() { shasum "$VR_FACTS" | awk '{print $1}'; }

# --- env for a /tmp rebuild run (paths override config; dev env, never prod) ---
rebuild_env() {
  env SELENE_ENV=development \
      SELENE_DB_PATH="$VR_DB" SELENE_FACTS_DB_PATH="$VR_FACTS" \
      SELENE_VAULT_PATH="$VR_VAULT" BACKUP_DIR="$VR_BACKUPS" \
      REBUILD_STAMP=verifyrun "$@"
}

# Reset the scenario DB to a clean trimmed copy of the pristine snapshot (N pending, 0 derived).
fresh_copy() {
  rm -rf "$VR_DB" "$VR_DB-wal" "$VR_DB-shm" "$VR_FACTS" "$VR_FACTS-wal" "$VR_FACTS-shm" "$VR_BACKUPS" "$VR_VAULT"
  cp "$PRISTINE_DB" "$VR_DB"
  cp "$PRISTINE_FACTS" "$VR_FACTS"
  mkdir -p "$VR_VAULT"
}

# ============================================================================
section "SETUP — seed /tmp from a read-only dev snapshot, trim to N=$N"
DEV_MTIME_BEFORE=$(stat -f %m "$REAL_DEV_DB")
rm -f "$PRISTINE_DB" "$PRISTINE_FACTS"
sqlite3 "$REAL_DEV_DB"    ".backup '$PRISTINE_DB'"    || { echo "dev selene .backup failed"; exit 2; }
sqlite3 "$REAL_DEV_FACTS" ".backup '$PRISTINE_FACTS'" || { echo "dev facts .backup failed"; exit 2; }

# Legacy single-file snapshot? (a physical raw_notes table) → migrate to two-file first.
LEGACY=$(count "$PRISTINE_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='raw_notes';")
if [ "${LEGACY:-0}" != "0" ]; then
  echo "  pristine is legacy single-file — migrating to two-file layout"
  env SELENE_DB_PATH="$PRISTINE_DB" SELENE_FACTS_DB_PATH="$PRISTINE_FACTS" \
    npx ts-node scripts/migrate-to-fact-store.ts || { echo "migrate failed"; exit 2; }
else
  echo "  pristine already two-file (no physical raw_notes) — no migrate needed"
fi

# Trim the captured corpus to N notes (keep the lowest N ids); clear any derived rows so PRE is clean.
sqlite3 "$PRISTINE_FACTS" "DELETE FROM captured_notes WHERE id NOT IN (SELECT id FROM captured_notes ORDER BY id LIMIT $N);"
sqlite3 "$PRISTINE_DB" "DELETE FROM processed_notes;" 2>/dev/null
TRIMMED=$(count "$PRISTINE_FACTS" "SELECT COUNT(*) FROM captured_notes;")
echo "  trimmed corpus: $TRIMMED captured notes"
[ "$TRIMMED" = "$N" ] || { echo -e "${RED}ABORT: trim produced $TRIMMED notes, expected $N${NC}"; exit 2; }

# ============================================================================
section "A — HAPPY PATH (drain → PASS, facts untouched)"
fresh_copy
A_FACTS_BEFORE=$(facts_hash)
rebuild_env npx ts-node scripts/rebuild.ts --json > /tmp/vr-A.json 2>/tmp/vr-A.log
A_EXIT=$?
A_PROCESSED=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
A_CAPTURED=$(count "$VR_FACTS" "SELECT COUNT(*) FROM captured_notes;")
A_FACTS_AFTER=$(facts_hash)
ls "$VR_BACKUPS"/pre-rebuild-*.db >/dev/null 2>&1 && A_BACKUP=1 || A_BACKUP=0

[ "$A_EXIT" = "0" ] && note_pass "exit 0" || note_fail "exit $A_EXIT (expected 0; see /tmp/vr-A.log)"
[ "${A_PROCESSED:-0}" = "$A_CAPTURED" ] && [ "${A_PROCESSED:-0}" = "$N" ] \
  && note_pass "coverage: all $N captured notes have a processed row" \
  || note_fail "coverage: processed=$A_PROCESSED captured=$A_CAPTURED (expected $N each)"
[ "$A_BACKUP" = "1" ] && note_pass "pre-rebuild backup exists" || note_fail "no pre-rebuild backup found"
[ "$A_FACTS_BEFORE" = "$A_FACTS_AFTER" ] && note_pass "facts.db byte-identical (E)" || note_fail "facts.db changed!"

# ============================================================================
section "B — COVERAGE-FAIL ROLLBACK (discriminating: PRE has K=$K dummy rows)"
fresh_copy
sqlite3 "$VR_DB" "INSERT INTO processed_notes (raw_note_id) VALUES $(seq 1 $K | sed 's/.*/(&)/' | paste -sd, -);"
B_PRE=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
B_FACTS_BEFORE=$(facts_hash)
rebuild_env SIMULATE_COVERAGE_FAIL=1 npx ts-node scripts/rebuild.ts --json > /tmp/vr-B.json 2>/tmp/vr-B.log
B_EXIT=$?
B_POST=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
B_FACTS_AFTER=$(facts_hash)

[ "${B_PRE:-0}" = "$K" ] && note_pass "PRE seeded with K=$K derived rows" || note_fail "PRE seed wrong: $B_PRE (expected $K)"
[ "$B_EXIT" = "1" ] && note_pass "exit 1 (verdict FAIL)" || note_fail "exit $B_EXIT (expected 1)"
# Reason-assert so B proves the COVERAGE gate fired specifically (not just "some gate"):
# the verdict reason string is "coverage X% < floor Y%". stdout is log-polluted, so grep a
# substring rather than parsing JSON (every check here is grep/DB, never jq).
grep -q "< floor" /tmp/vr-B.json && note_pass "failed for the COVERAGE reason" \
  || note_fail "no coverage reason in verdict (see /tmp/vr-B.json)"
[ "${B_POST:-0}" = "$K" ] && note_pass "rolled back to PRE (processed=$K, not the drained $N)" \
  || note_fail "rollback wrong: processed=$B_POST (expected $K; $N would mean no rollback)"
[ "$B_FACTS_BEFORE" = "$B_FACTS_AFTER" ] && note_pass "facts.db byte-identical (E)" || note_fail "facts.db changed!"

# ============================================================================
section "C — DRIFT-FAIL ROLLBACK (discriminating: PRE has K=$K dummy rows)"
fresh_copy
sqlite3 "$VR_DB" "INSERT INTO processed_notes (raw_note_id) VALUES $(seq 1 $K | sed 's/.*/(&)/' | paste -sd, -);"
# Seed a NON-coverage metric (note_embeddings) in PRE so SIMULATE_DRIFT_FAIL (post.embeddings=0)
# is a real downward drift the gate must catch. Zeroing a zero-baseline metric would be skipped
# by verdict() (rebuild-core.ts:135) — the bug an earlier version of this scenario masked.
sqlite3 "$VR_DB" "INSERT INTO note_embeddings (raw_note_id, embedding, model_version) VALUES $(seq 1 $K | sed "s/.*/(&, x'00', 'seed')/" | paste -sd, -);"
C_PRE=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
C_PRE_EMB=$(count "$VR_DB" "SELECT COUNT(*) FROM note_embeddings;")
C_FACTS_BEFORE=$(facts_hash)
rebuild_env SIMULATE_DRIFT_FAIL=1 npx ts-node scripts/rebuild.ts --json > /tmp/vr-C.json 2>/tmp/vr-C.log
C_EXIT=$?
C_POST=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
C_FACTS_AFTER=$(facts_hash)

[ "${C_PRE:-0}" = "$K" ] && [ "${C_PRE_EMB:-0}" = "$K" ] && note_pass "PRE seeded with K=$K processed + K=$K embeddings" || note_fail "PRE seed wrong: processed=$C_PRE embeddings=$C_PRE_EMB"
[ "$C_EXIT" = "1" ] && note_pass "exit 1 (verdict FAIL)" || note_fail "exit $C_EXIT (expected 1)"
# Reason-assert so C proves the DRIFT gate fired specifically (distinct from B's coverage gate):
grep -q "embeddings drift" /tmp/vr-C.json && note_pass "failed for the DRIFT reason" \
  || note_fail "no embeddings-drift reason in verdict (see /tmp/vr-C.json)"
[ "${C_POST:-0}" = "$K" ] && note_pass "rolled back to PRE (processed=$K)" \
  || note_fail "rollback wrong: processed=$C_POST (expected $K)"
[ "$C_FACTS_BEFORE" = "$C_FACTS_AFTER" ] && note_pass "facts.db byte-identical (E)" || note_fail "facts.db changed!"

# ============================================================================
section "D — CRASH-RESUME (throw after wipe → restore → self-heal via process-llm)"
fresh_copy
D_FACTS_BEFORE=$(facts_hash)
rebuild_env SIMULATE_REDERIVE_FAIL=1 npx ts-node scripts/rebuild.ts --json > /tmp/vr-D.json 2>/tmp/vr-D.log
D_EXIT=$?
D_POST=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
# "Corpus intact" = the precious captured_notes survived the crash. Query facts.db DIRECTLY
# (a separate file, physical table) — NOT the raw_notes view, which is a per-connection TEMP
# view a bare sqlite3 CLI can't see (it would error → empty count, the bug this scenario hit).
D_CAPTURED=$(count "$VR_FACTS" "SELECT COUNT(*) FROM captured_notes;")
D_FACTS_AFTER=$(facts_hash)

[ "$D_EXIT" = "1" ] && note_pass "exit 1 (crash → catch)" || note_fail "exit $D_EXIT (expected 1)"
[ "${D_POST:-0}" = "0" ] && note_pass "restored to PRE (0 processed after post-wipe crash)" \
  || note_fail "not restored: processed=$D_POST (expected 0)"
[ "${D_CAPTURED:-0}" = "$N" ] && note_pass "all $N notes intact in facts.db (corpus survives crash)" \
  || note_fail "captured=$D_CAPTURED (expected $N)"
# Self-heal: a plain process-llm run after the crash must make progress.
rebuild_env npx ts-node src/workflows/process-llm.ts > /tmp/vr-D-heal.log 2>&1
D_HEALED=$(count "$VR_DB" "SELECT COUNT(*) FROM processed_notes;")
[ "${D_HEALED:-0}" -gt 0 ] && note_pass "self-heal: process-llm processed $D_HEALED note(s) post-crash" \
  || note_fail "self-heal failed: processed still 0 (see /tmp/vr-D-heal.log)"
[ "$D_FACTS_BEFORE" = "$D_FACTS_AFTER" ] && note_pass "facts.db byte-identical (E)" || note_fail "facts.db changed!"

# ============================================================================
section "FINAL — dev DB untouched"
DEV_MTIME_AFTER=$(stat -f %m "$REAL_DEV_DB")
[ "$DEV_MTIME_BEFORE" = "$DEV_MTIME_AFTER" ] && note_pass "real dev DB mtime unchanged" \
  || note_fail "real dev DB mtime changed ($DEV_MTIME_BEFORE → $DEV_MTIME_AFTER)!"

# cleanup /tmp artifacts
rm -rf "$PRISTINE_DB" "$PRISTINE_FACTS" "$VR_DB" "$VR_DB-wal" "$VR_DB-shm" \
       "$VR_FACTS" "$VR_FACTS-wal" "$VR_FACTS-shm" "$VR_BACKUPS" "$VR_VAULT"

echo ""
if [ "$PASS_ALL" = "1" ]; then
  echo -e "${GREEN}=== ALL SCENARIOS PASSED ===${NC}"; exit 0
else
  echo -e "${RED}=== SOME SCENARIOS FAILED (logs in /tmp/vr-*.log) ===${NC}"; exit 1
fi
