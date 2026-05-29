#!/bin/bash
# deploy-prod.sh — build-gated, clean-source, env-preserving production deploy.
#
# Deploys origin/main (or a given ref) into a production directory by:
#   1. building from a scratch clone (never the live target),
#   2. gating on a successful `npm run build && npm run build:check`,
#   3. archiving the current dist for rollback,
#   4. shipping ONLY dist/ + manifests via rsync (the target's .env is never touched),
#   5. (re)loading prod launchd agents, and
#   6. probing /health.
#
# A failed build leaves the live deployment payload (.env, dist/, package.json,
# .deployed-sha) untouched — only deploy.log is written (the FAILED notice).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/notify.sh
source "$HERE/lib/notify.sh"

# --- Defaults / CLI flags ----------------------------------------------------
TARGET="${HOME}/selene-prod"
REF="origin/main"
BUILD_DIR="${HOME}/selene-build"
LABEL_PFX="com.selene.prod."
SKIP_AGENTS=0
SKIP_HEALTH=0

usage() {
    cat <<'EOF'
Usage: deploy-prod.sh [options]

Build-gated, env-preserving production deploy.

Options:
  --target DIR          Production deploy dir (default: $HOME/selene-prod)
  --ref REF             Git ref to deploy (default: origin/main)
  --build-dir DIR       Scratch build clone dir (default: $HOME/selene-build)
  --label-prefix PFX    Prod launchd label prefix (default: com.selene.prod.)
  --skip-agents         Do not (re)load prod launchd agents
  --skip-health         Do not probe http://localhost:5678/health
  -h, --help            Show this help
EOF
}

# --- Parse args FIRST, before any side effects (clone/build/etc.) -----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)        TARGET="$2"; shift 2 ;;
        --ref)           REF="$2"; shift 2 ;;
        --build-dir)     BUILD_DIR="$2"; shift 2 ;;
        --label-prefix)  LABEL_PFX="$2"; shift 2 ;;
        --skip-agents)   SKIP_AGENTS=1; shift ;;
        --skip-health)   SKIP_HEALTH=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Log lives WITH the target so the test target (Task 6) gets its own log.
export SELENE_DEPLOY_LOG="${TARGET}/deploy.log"

# --- 1. Resolve the repo URL from this worktree's origin remote -------------
REPO_URL="$(git -C "$HERE" remote get-url origin)"
echo "Deploying ref '$REF' from $REPO_URL -> $TARGET"

# --- 2. Ensure scratch build clone, then sync it to REF ---------------------
if [[ ! -d "$BUILD_DIR/.git" ]]; then
    echo "Cloning $REPO_URL -> $BUILD_DIR"
    git clone "$REPO_URL" "$BUILD_DIR"
fi
git -C "$BUILD_DIR" fetch origin --quiet
git -C "$BUILD_DIR" reset --hard "$REF" --quiet
git -C "$BUILD_DIR" clean -fdx -e node_modules --quiet
NEW_SHA="$(git -C "$BUILD_DIR" rev-parse --short HEAD)"

# --- 3. Current deployed sha (for rollback archive + messaging) -------------
OLD_SHA="$(cat "$TARGET/.deployed-sha" 2>/dev/null || echo none)"
echo "Current: $OLD_SHA   New: $NEW_SHA"

# --- 4. BUILD GATE (install + build + check) in the scratch clone -----------
# Wrapped in `if ! ( ... )` so a failure does NOT trip `set -e` before we get
# the chance to notify + exit cleanly, and BEFORE anything in $TARGET changes.
if ! ( cd "$BUILD_DIR" \
        && npm install --no-audit --no-fund --silent \
        && npm run build \
        && npm run build:check ); then
    selene_notify "Selene deploy FAILED" "build of $NEW_SHA failed — prod still on $OLD_SHA"
    echo "BUILD FAILED for $NEW_SHA — target $TARGET left untouched (still on $OLD_SHA)" >&2
    exit 1
fi

# --- 5. Archive current target dist for rollback ----------------------------
if [[ -d "$TARGET/dist" && "$OLD_SHA" != "none" ]]; then
    mkdir -p "$TARGET/releases"
    rm -rf "$TARGET/releases/$OLD_SHA"
    cp -R "$TARGET/dist" "$TARGET/releases/$OLD_SHA"
    echo "Archived current dist -> releases/$OLD_SHA"
    # Keep only the 5 newest archived releases; prune the rest. Safe here because
    # the cp above guarantees releases/ holds >=1 dir, so the glob is non-empty
    # (an empty glob would make ls exit 1 and pipefail abort the script).
    ls -1dt "$TARGET/releases/"*/ 2>/dev/null | tail -n +6 | while IFS= read -r old; do
        rm -rf "$old"
    done
fi

# --- 6. Ship: rsync ONLY dist/ -> dist/. The target's .env (at the target
#        root) is a sibling of dist/ and is therefore never touched. We never
#        rsync the repo root over the target root. ---------------------------
mkdir -p "$TARGET/dist"
rsync -a --delete "$BUILD_DIR/dist/" "$TARGET/dist/"

cp "$BUILD_DIR/package.json" "$TARGET/package.json"
if [[ -f "$BUILD_DIR/package-lock.json" ]]; then
    cp "$BUILD_DIR/package-lock.json" "$TARGET/package-lock.json"
fi

# Ship-phase failures happen AFTER dist/ is already updated, so prod can be left
# incoherent. .deployed-sha is written last (step 9), so on failure here it stays
# on OLD_SHA and the watcher will retry — but we must NOT fail silently. Notify.
if ! ( cd "$TARGET" && npm install --omit=dev --no-audit --no-fund --silent ); then
    selene_notify "Selene deploy WARN" "shipped $NEW_SHA dist but prod npm install failed — prod may be incoherent (still recorded on $OLD_SHA); consider rollback-prod.sh"
    echo "ERROR: prod npm install failed after shipping dist for $NEW_SHA" >&2
    exit 1
fi

# --- 7. Restart prod agents to pick up the new dist/ ------------------------
# Use `launchctl kickstart -k` (restart-in-place), NOT install-prod.sh's
# bootout+bootstrap. Re-bootstrapping the running KeepAlive server races its
# own teardown ("Bootstrap failed: 5: Input/output error") and can leave prod
# DOWN. kickstart never unloads anything, so a failure leaves the OLD process
# still serving — prod stays up (on old code) instead of going dark.
#
# Workflow agents (StartInterval) re-exec `node dist/...` each tick, so they
# pick up new code on their next run regardless; kickstart just makes it
# immediate. The long-running server MUST be kicked to load new code.
#
# NOTE: this only RESTARTS already-loaded agents. The initial cutover, and any
# change to the agent SET or plist content, still uses install-prod.sh (run
# interactively, not from the launchd-spawned watcher).
if [[ "$SKIP_AGENTS" -eq 0 ]]; then
    restart_failed=()
    PROD_AGENTS="$(launchctl list | awk '{print $3}' | grep "^${LABEL_PFX}" | grep -v "${LABEL_PFX}deploy-watcher" || true)"
    for label in $PROD_AGENTS; do
        launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null || restart_failed+=("$label")
    done
    if [[ ${#restart_failed[@]} -gt 0 ]]; then
        selene_notify "Selene deploy WARN" "shipped $NEW_SHA but restart failed for: ${restart_failed[*]} — prod may be serving old code; check launchctl"
        echo "WARNING: kickstart failed for: ${restart_failed[*]} (prod stayed up on old code)" >&2
    fi
else
    echo "--skip-agents: leaving launchd agents untouched"
fi

# --- 8. Health probe (warn-only; no automatic rollback) ---------------------
if [[ "$SKIP_HEALTH" -eq 0 ]]; then
    sleep 3
    if ! curl -fsS http://localhost:5678/health >/dev/null; then
        selene_notify "Selene deploy WARN" "shipped $NEW_SHA but /health failed — check the prod server"
        echo "WARNING: /health did not respond OK after deploy (shipped $NEW_SHA)" >&2
    else
        echo "Health OK"
    fi
else
    echo "--skip-health: skipping /health probe"
fi

# --- 9. Record + announce success -------------------------------------------
printf '%s' "$NEW_SHA" > "$TARGET/.deployed-sha"
selene_notify "Selene deployed" "$OLD_SHA -> $NEW_SHA @ $(date '+%H:%M')"
echo "DEPLOYED $OLD_SHA -> $NEW_SHA to $TARGET"
