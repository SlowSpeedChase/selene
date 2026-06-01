# prod-agents.sh — shared launchd agent-control helpers for prod orchestration.
#
# SOURCEABLE library: no `set -e`, no `main`, just function definitions. Sourced
# by cutover-prod.sh and rebuild-prod.sh (which drive prod's com.selene.prod.*
# launch agents).
#
# CONTRACT — the sourcing script MUST define these BEFORE sourcing this file
# (exactly as cutover-prod.sh already does):
#   - run_or_echo   : the DRY_RUN stub ("$@" live, or echo "[dry-run] $*").
#   - REPO_ROOT     : absolute repo root (resume_watcher loads the repo's
#                     deploy-watcher plist from "$REPO_ROOT/launchd/...").
# (Some functions also emit via plain echo; no `info`/color vars are required.)

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
# pause_watcher — bootout the deploy-watcher so it can't auto-deploy mid-cutover. IDEMPOTENT: if the
# watcher is already unloaded (e.g. the operator pre-paused it to avert a bad auto-deploy), the goal
# state is already met — that's a success, not an abort. We only bootout when it's actually loaded,
# so a genuine bootout failure (while loaded) still surfaces as a safe early abort (nothing torn down).
pause_watcher() {
  local label="com.selene.prod.deploy-watcher"
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    run_or_echo launchctl bootout "gui/$(id -u)/$label"
  else
    echo "  watcher already not loaded — nothing to pause"
  fi
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

# Derivation agents only: every prod agent EXCEPT the webhook server and the
# deploy-watcher. Rebuild stops these (so none races the drain) while the SERVER
# stays up — capture writes only facts.db, which rebuild never touches.
stop_derivation_agents() {
  local a
  for a in $(prod_agents | grep -v '\.server$'); do
    run_or_echo launchctl bootout "gui/$(id -u)/$a" || true
  done
}

# Restart the derivation agents after a rebuild. Iterate installed plist FILES
# (post-bootout `launchctl list` is empty), EXCLUDING the watcher (resume_watcher
# owns it) and the server (never stopped → avoid double-bootstrap). Mirrors
# restart_agents but with the extra server exclusion.
restart_derivation_agents() {
  local plist base
  for plist in "$HOME/Library/LaunchAgents/com.selene.prod."*.plist; do
    [ -e "$plist" ] || continue
    base="$(basename "$plist")"
    case "$base" in
      *deploy-watcher.plist) continue ;;
      *server.plist) continue ;;
    esac
    run_or_echo launchctl bootstrap "gui/$(id -u)" "$plist" || true
  done
}
