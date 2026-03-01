#!/bin/bash

# Setup Git Hooks for Documentation Agent
# Run this after initializing Git repository

set -e

PROJECT_ROOT="/Users/chaseeasterling/selene"

echo "Setting up Git hooks for documentation agent..."

# Check if Git is initialized
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "⚠️  Git repository not found. Initializing..."
    cd "$PROJECT_ROOT"
    git init
    echo "✓ Git repository initialized"
fi

# Create post-commit hook
HOOK_FILE="$PROJECT_ROOT/.git/hooks/post-commit"

cat > "$HOOK_FILE" << 'EOF'
#!/bin/bash

# Post-commit hook: Check if documentation needs updating

# Only run if workflow files or database schema changed
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)

RELEVANT_CHANGES=$(echo "$CHANGED_FILES" | grep -E '(workflows/.*\.json|database/.*\.sql|docker-compose\.yml|Dockerfile|\.env)' || true)

if [ -n "$RELEVANT_CHANGES" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Documentation update recommended"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Changed files that may affect documentation:"
    echo "$RELEVANT_CHANGES" | sed 's/^/  - /'
    echo ""
    echo "Run: ./scripts/run-doc-agent.sh"
    echo "Or say in Claude Code: 'Run the documentation agent'"
    echo ""
fi
EOF

chmod +x "$HOOK_FILE"
echo "✓ Post-commit hook installed"

# Create pre-push hook (optional reminder)
HOOK_FILE="$PROJECT_ROOT/.git/hooks/pre-push"

cat > "$HOOK_FILE" << 'EOF'
#!/bin/bash

# Pre-push hook: Remind to update documentation

# Check if there are recent workflow changes without corresponding doc updates
WORKFLOW_CHANGES=$(git log --since="7 days ago" --name-only --pretty=format: -- 'workflows/*/*.json' | sort -u)
DOC_CHANGES=$(git log --since="7 days ago" --name-only --pretty=format: -- '*.md' 'docs/**/*.md' 'workflows/*/*.md' | sort -u)

if [ -n "$WORKFLOW_CHANGES" ] && [ -z "$DOC_CHANGES" ]; then
    echo ""
    echo "⚠️  Warning: Recent workflow changes but no documentation updates"
    echo ""
    echo "Workflow files changed:"
    echo "$WORKFLOW_CHANGES" | sed 's/^/  - /'
    echo ""
    echo "Consider running: ./scripts/run-doc-agent.sh"
    echo ""
    read -p "Continue with push? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
EOF

chmod +x "$HOOK_FILE"
echo "✓ Pre-push hook installed"

echo ""
echo "✅ Git hooks setup complete!"
echo ""
echo "Hooks installed:"
echo "  - post-commit: Notifies when docs may need updates"
echo "  - pre-push: Warns if pushing code without doc updates"
echo ""
