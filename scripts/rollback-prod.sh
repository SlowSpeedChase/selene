#!/bin/bash
# rollback-prod.sh — restore a production deploy's dist/ from an archived release.
#
# deploy-prod.sh archives the previous build to $TARGET/releases/<OLD_SHA>/ before
# shipping a new one. This script swaps the live dist/ back to one of those archived
# releases, repoints launchd at the restored dist, and probes /health.
#
#   1. Parse args (positional sha + optional --target).
#   2. Resolve the sha: explicit, or the NEWEST archived release by mtime.
#   3. Validate $TARGET/releases/<sha> exists.
#   4. rsync the archived release back over dist/ (the target's .env is never touched).
#   5. Record the rolled-back sha in $TARGET/.deployed-sha.
#   6. (Re)load prod launchd agents so they point at the restored dist.
#   7. Probe /health (warn-only).
#   8. Notify + summarize.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Defaults / CLI flags ----------------------------------------------------
TARGET="${HOME}/selene-prod"
SHA=""

usage() {
    cat <<'EOF'
Usage: rollback-prod.sh [sha] [--target DIR]

Restore a production deploy's dist/ from a previously archived release.

Arguments:
  sha               Archived release to roll back to (a dir under
                    $TARGET/releases/). If omitted, the NEWEST archived
                    release (by mtime) is used.

Options:
  --target DIR      Production deploy dir (default: $HOME/selene-prod)
  -h, --help        Show this help
EOF
}

# --- Parse args FIRST, before any side effects -----------------------------
# Order matters: --target, then help, then the -* catch-all (unknown flag ->
# error), then the bare positional sha. If the positional case preceded the -*
# catch, an unknown flag like --bogus would be silently treated as a sha.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)  TARGET="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*)        echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -n "$SHA" ]]; then
                echo "Unexpected extra argument: $1 (sha already set to '$SHA')" >&2
                usage >&2; exit 2
            fi
            SHA="$1"; shift
            ;;
    esac
done

# shellcheck source=lib/notify.sh
source "$HERE/lib/notify.sh"
# Log lives WITH the target so the test target gets its own log.
export SELENE_DEPLOY_LOG="${TARGET}/deploy.log"

RELEASES_DIR="${TARGET}/releases"

# --- 2. Resolve the sha -----------------------------------------------------
# If no sha was given, pick the newest archived release by mtime. Guard the glob
# explicitly: under `set -euo pipefail` a no-match glob would leave the literal
# pattern and abort with a raw ls error instead of our clean message.
if [[ -z "$SHA" ]]; then
    newest=""
    if [[ -d "$RELEASES_DIR" ]]; then
        newest="$(ls -1dt "$RELEASES_DIR"/*/ 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -z "$newest" ]]; then
        echo "ERROR: no archived release to roll back to under ${RELEASES_DIR}" >&2
        exit 1
    fi
    # ls -1dt yields a trailing slash (.../bbb222/); strip it for a clean sha.
    SHA="$(basename "$newest")"
    echo "No sha given; selected newest archived release: ${SHA}"
fi

# --- 3. Validate the chosen release -----------------------------------------
RELEASE_PATH="${RELEASES_DIR}/${SHA}"
if [[ ! -d "$RELEASE_PATH" ]]; then
    echo "ERROR: archived release not found: ${RELEASE_PATH}" >&2
    exit 1
fi

echo "Rolling back ${TARGET}/dist -> release ${SHA}"

# --- 4. Restore: rsync the archived release back over dist/. --delete clears
#        stale files; the target's .env (a sibling of dist/) is never touched. -
mkdir -p "${TARGET}/dist"
rsync -a --delete "${RELEASE_PATH}/" "${TARGET}/dist/"

# --- 5. Record the rolled-back sha (BEFORE reloading agents, so a launchd
#        failure still leaves .deployed-sha matching what is in dist/). -------
printf '%s' "$SHA" > "${TARGET}/.deployed-sha"

# --- 6. (Re)load prod launchd agents so they point at the restored dist. -----
if ! "$HERE/install-prod.sh" --prod-dir "$TARGET"; then
    selene_notify "Selene rollback WARN" "restored dist to $SHA but loading prod agents failed — check launchctl"
    echo "ERROR: install-prod.sh failed after restoring $SHA" >&2
    exit 1
fi

# --- 7. Health probe (warn-only; no hard failure) ---------------------------
sleep 3
if ! curl -fsS http://localhost:5678/health >/dev/null; then
    selene_notify "Selene rollback WARN" "rolled back to $SHA but /health failed — check the prod server"
    echo "WARNING: /health did not respond OK after rollback (now on $SHA)" >&2
else
    echo "Health OK"
fi

# --- 8. Record + announce ----------------------------------------------------
selene_notify "Selene ROLLED BACK" "prod reverted to $SHA"
echo "ROLLED BACK ${TARGET}/dist to release ${SHA}"
