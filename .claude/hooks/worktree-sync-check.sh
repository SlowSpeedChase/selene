#!/bin/bash
# Claude Code SessionStart hook: worktree sync check
#
# Enforces the "MANDATORY: Worktree Sync Check" rule from CLAUDE.md.
# If the current working directory is inside a .worktrees/ path, fetch origin
# and report how many commits the current branch is behind origin/main.
#
# Silent unless we are in a worktree. Never fails — a stale fetch or no network
# must not block the session.

set -u

cwd="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [[ "$cwd" != *".worktrees/"* ]]; then
    exit 0
fi

cd "$cwd" 2>/dev/null || exit 0

git fetch origin --quiet 2>/dev/null || true

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)

if [ "${behind:-0}" -gt 0 ]; then
    echo "WORKTREE SYNC CHECK: branch '$branch' is $behind commit(s) behind origin/main — consider rebasing before proceeding (see .claude/GITOPS.md Session Start Ritual)."
else
    echo "WORKTREE SYNC CHECK: branch '$branch' is up to date with origin/main."
fi
