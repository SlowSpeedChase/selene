#!/bin/bash
# Setup script: Install git hooks for selene

set -e
set -u

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SOURCE="$REPO_ROOT/scripts/hooks"
HOOKS_TARGET="$(git rev-parse --git-common-dir)/hooks"

echo "Installing git hooks..."

# Install post-merge hook
if [ -f "$HOOKS_SOURCE/post-merge" ]; then
    if [ -L "$HOOKS_TARGET/post-merge" ] || [ -f "$HOOKS_TARGET/post-merge" ]; then
        echo "  post-merge: already exists (skipping)"
    else
        ln -s "$HOOKS_SOURCE/post-merge" "$HOOKS_TARGET/post-merge"
        echo "  post-merge: installed ✓"
    fi
else
    echo "  post-merge: source not found (skipping)"
fi

ln -sf "../../scripts/hooks/pre-commit" "$PROJECT_ROOT/.git/hooks/pre-commit"

echo "✓ Pre-commit hook installed"

# Create symlink for post-commit hook
if [ -f "$PROJECT_ROOT/.git/hooks/post-commit" ] && [ ! -L "$PROJECT_ROOT/.git/hooks/post-commit" ]; then
    echo "Backing up existing post-commit hook..."
    mv "$PROJECT_ROOT/.git/hooks/post-commit" "$PROJECT_ROOT/.git/hooks/post-commit.backup"
fi

ln -sf "../../scripts/hooks/post-commit" "$PROJECT_ROOT/.git/hooks/post-commit"

echo "✓ Post-commit hook installed (plan archival)"

echo ""
echo "Hook setup complete!"
echo "Hooks installed:"
echo "  - pre-commit: documentation validation"
echo "  - post-commit: archive stale plans"
echo "  - post-merge: auto-build SeleneChat when its files change"
