#!/usr/bin/env bash
# rebuild-prod.sh — operator-run prod rebuild. Keeps the webhook server UP so
# capture never blocks (it writes only facts.db, which rebuild never touches);
# stops ONLY the derivation agents so none races the drain; restarts them and
# resumes the deploy-watcher via an EXIT trap so ANY exit (success, FAIL verdict,
# or crash) restores prod to its running state. Claude NEVER runs this vs prod —
# all dev/test runs go through scripts/rebuild.ts directly with SELENE_ENV=development.
#
# Usage (on the prod box):
#   ./scripts/rebuild-prod.sh --dry-run     # rehearse: stop/start agents, rebuild dry-run, no wipe
#   ./scripts/rebuild-prod.sh               # live: wipe + re-derive + validate + keep/rollback
# Env:
#   DRY_RUN=1   # echo every side-effecting command (launchctl AND the rebuild) — touches nothing.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN="${DRY_RUN:-}"
# run_or_echo: live-exec "$@", or echo it under DRY_RUN. A VAR=value prefix must be
# carried by `env` (a real command) — a bare `SELENE_ENV=… npx …` would be treated
# as the command NAME once it flows through "$@", not as an assignment.
run_or_echo() { if [ -n "$DRY_RUN" ]; then echo "  [dry] $*"; else "$@"; fi; }
info() { echo "[..] $*"; }
source "$REPO_ROOT/scripts/lib/prod-agents.sh"

restored=0
cleanup() {                       # runs on ANY exit; set +e so the whole tail runs even after a failure
  set +e
  [ "$restored" = 1 ] && return   # idempotent: trap can fire once
  restored=1
  info "restoring prod: restart derivation agents + resume watcher"
  restart_derivation_agents
  resume_watcher
}
trap cleanup EXIT

info "pausing watcher + stopping derivation agents (server stays up)"
pause_watcher
stop_derivation_agents

info "running rebuild (SELENE_ENV=production)"
# Wrapped in run_or_echo so DRY_RUN=1 echoes the rebuild too (a fully inert smoke that
# never opens the prod DB). The operator's real rehearsal is `--dry-run` WITHOUT DRY_RUN:
# launchctl actually cycles the agents and rebuild.ts runs its own --dry-run (reads prod
# counts, no wipe). `env` carries SELENE_ENV across the run_or_echo boundary (see above).
run_or_echo env SELENE_ENV=production npx ts-node "$REPO_ROOT/scripts/rebuild.ts" "$@"
# trap cleanup runs here on success AND on failure/crash (rebuild.ts exit 1 → set -e → trap).
