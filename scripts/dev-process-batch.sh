#!/bin/bash
#
# dev-process-batch.sh - Drive dev notes through the CURRENT processing pipeline.
#
# Post-2026-03-21 simplification, the active pipeline is:
#   process-llm  ->  distill-essences  ->  synthesize-topics  ->  export-obsidian
# (the pre-simplification vector/association/relationship/thread steps were
#  archived; this script used to call them and silently did nothing useful.)
#
# process-llm and distill-essences each handle a small internal batch (~10 notes)
# per invocation, so a single pass nibbles the backlog. Use --all to drain it.
#
# Usage:
#   ./scripts/dev-process-batch.sh            # one pass of each step
#   ./scripts/dev-process-batch.sh --all      # loop LLM + essences until drained, then synth + export
#   ./scripts/dev-process-batch.sh --status   # show processing status only
#
# Requires SELENE_ENV=development (set here for the workflow calls). Touches only
# ~/selene-data-dev/ — never production.

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

DEV_DB="$HOME/selene-data-dev/selene.db"

# --- functions (defined before any env check so the script is sourceable by tests) ---

# Count helper that tolerates not-yet-created tables/columns. The synthesis tables
# (topic_clusters, note_connections, ...) and processed_notes.essence are migrated
# in lazily the first time their workflow runs, so a fresh DB legitimately lacks
# them — report 0 rather than crashing.
safe_count() {
  sqlite3 "$DEV_DB" "$1" 2>/dev/null || echo 0
}

show_status() {
  echo -e "${BLUE}=== Dev Database Processing Status ===${NC}"
  echo ""

  RAW=$(safe_count "SELECT COUNT(*) FROM raw_notes;")
  PROCESSED=$(safe_count "SELECT COUNT(*) FROM processed_notes;")
  PENDING=$(safe_count "SELECT COUNT(*) FROM raw_notes WHERE status = 'pending';")
  ESSENCES=$(safe_count "SELECT COUNT(*) FROM processed_notes WHERE essence IS NOT NULL AND essence != '';")
  CLUSTERS=$(safe_count "SELECT COUNT(*) FROM topic_clusters;")
  CLUSTER_LINKS=$(safe_count "SELECT COUNT(*) FROM topic_note_links;")
  CONNECTIONS=$(safe_count "SELECT COUNT(*) FROM note_connections;")
  EXPORTED=$(safe_count "SELECT COUNT(*) FROM raw_notes WHERE exported_to_obsidian = 1;")

  echo -e "  Raw notes:        ${GREEN}${RAW}${NC}"
  echo -e "  LLM processed:    ${GREEN}${PROCESSED}${NC} / ${RAW}"
  echo -e "  Pending LLM:      ${YELLOW}${PENDING}${NC}"
  echo -e "  Essences:         ${GREEN}${ESSENCES}${NC} / ${PROCESSED}"
  echo -e "  Topic clusters:   ${GREEN}${CLUSTERS}${NC}"
  echo -e "  Cluster links:    ${GREEN}${CLUSTER_LINKS}${NC}"
  echo -e "  Connections:      ${GREEN}${CONNECTIONS}${NC}"
  echo -e "  Obsidian export:  ${GREEN}${EXPORTED}${NC} / ${RAW}"
  echo ""
}

# Run one workflow step; never let a single bad note abort the whole pass.
run_step() {
  local label="$1" workflow_path="$2"
  echo -e "${YELLOW}${label}...${NC}"
  SELENE_ENV=development npx ts-node "$workflow_path" 2>&1 \
    | grep -E "(complete|error|Found|No |nothing to do|Exported|Synthesize)" || true
  echo ""
}

# Repeatedly run a per-batch workflow until the queried backlog reaches zero.
#
# Runs the workflow AT LEAST ONCE before checking the count. This is deliberate:
# the gating column may not exist until the workflow's first run migrates it in
# (distill-essences creates processed_notes.essence), so a pre-check would read 0
# via safe_count and skip the very run that creates the column. After each pass
# we re-count; stop when the backlog is empty OR a pass makes no progress (a note
# that never leaves the counted state — e.g. extraction failing on it — would
# otherwise spin forever). The no-progress check compares against the PREVIOUS
# real post-run count, not the artificial pre-column 0.  drain <count-sql> <wf> <label>
drain() {
  local count_sql="$1" workflow_path="$2" label="$3" before="" after
  while true; do
    run_step "$label" "$workflow_path"
    after=$(safe_count "$count_sql")
    if [ "$after" -eq 0 ]; then
      break
    fi
    if [ -n "$before" ] && [ "$after" -ge "$before" ]; then
      echo -e "${RED}No progress: ${after} item(s) remaining after a pass — stopping to avoid an infinite loop.${NC}" >&2
      break
    fi
    before="$after"
  done
}

# Sourced by a test? stop here with the functions defined, before env checks + main.
if [ "${DEV_BATCH_SOURCED:-}" = "1" ]; then return 0 2>/dev/null || exit 0; fi

# --- env checks ---
if [ ! -f "$DEV_DB" ]; then
  echo -e "${RED}Error: Dev database not found at $DEV_DB${NC}"
  echo "Run: ./scripts/reset-dev-data.sh first"
  exit 1
fi

ENV=$(sqlite3 "$DEV_DB" "SELECT value FROM _selene_metadata WHERE key='environment';")
if [ "$ENV" != "development" ]; then
  echo -e "${RED}Error: Database environment is '$ENV', expected 'development'${NC}"
  exit 1
fi

# Status-only mode
if [ "${1:-}" = "--status" ]; then
  show_status
  exit 0
fi

MODE="${1:-once}"

echo -e "${BLUE}=== Dev Batch Processing (mode: ${MODE}) ===${NC}"
echo ""
show_status

if [ "$MODE" = "--all" ]; then
  # Drain the LLM backlog, then backfill essences (each ~10 notes per invocation).
  drain "SELECT COUNT(*) FROM raw_notes WHERE status = 'pending';" \
        "src/workflows/process-llm.ts" "LLM concept extraction (draining)"
  drain "SELECT COUNT(*) FROM processed_notes WHERE essence IS NULL;" \
        "src/workflows/distill-essences.ts" "Essence distillation (draining)"
else
  run_step "Step 1: LLM concept extraction" "src/workflows/process-llm.ts"
  run_step "Step 2: Essence distillation" "src/workflows/distill-essences.ts"
fi

# Clustering + export reflect the full corpus, so run them once after the batch.
run_step "Step 3: Synthesize topics (clustering)" "src/workflows/synthesize-topics.ts"
run_step "Step 4: Export to Obsidian vault" "src/workflows/export-obsidian.ts"

echo -e "${BLUE}=== After Processing ===${NC}"
echo ""
show_status

if [ "$MODE" = "--all" ]; then
  echo -e "${GREEN}Done!${NC} Full corpus processed."
else
  echo -e "${GREEN}Done!${NC} Run again (or use --all) to process the next batch."
fi
