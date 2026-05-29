#!/bin/bash
# deploy-watch.sh — poll origin/main and trigger a gated production deploy.
#
# Runs from the DEV repo (which holds the git remote). Fetches origin, compares
# the short sha of origin/main against the sha currently live in the prod target
# ($TARGET/.deployed-sha, written by deploy-prod.sh). When they differ, it hands
# off to deploy-prod.sh, which build-gates and only ships on success.
#
# SELENE_PROD_DIR overrides the prod target (used by tests to point at a fake dir).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TARGET="${SELENE_PROD_DIR:-$HOME/selene-prod}"

git -C "$REPO" fetch origin --quiet

REMOTE_SHA="$(git -C "$REPO" rev-parse --short origin/main)"
DEPLOYED_SHA="$(cat "$TARGET/.deployed-sha" 2>/dev/null || echo none)"

if [[ "$REMOTE_SHA" != "$DEPLOYED_SHA" ]]; then
    echo "origin/main moved ${DEPLOYED_SHA} -> ${REMOTE_SHA}; deploying"
    exec "$HERE/deploy-prod.sh" --target "$TARGET" --ref origin/main
else
    echo "up to date (${REMOTE_SHA})"
fi
