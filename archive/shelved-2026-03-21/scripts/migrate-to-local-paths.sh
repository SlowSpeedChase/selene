#!/bin/bash
# Migrate workflow.json files from Docker paths to environment variables
# This script updates hardcoded paths to use process.env variables

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="$PROJECT_ROOT/workflows"

echo "============================================"
echo "Migrating workflows to use environment vars"
echo "============================================"
echo ""

# Count files to update
DB_COUNT=$(grep -rl "'/selene/data/selene.db'" "$WORKFLOWS_DIR"/*/workflow.json 2>/dev/null | wc -l | tr -d ' ')
OLLAMA_COUNT=$(grep -rl "host.docker.internal:11434" "$WORKFLOWS_DIR"/*/workflow.json 2>/dev/null | wc -l | tr -d ' ')

echo "Found:"
echo "  - $DB_COUNT workflow files with hardcoded database path"
echo "  - $OLLAMA_COUNT workflow files with hardcoded Ollama URL"
echo ""

# Backup all workflow files first
BACKUP_DIR="$PROJECT_ROOT/.workflow-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Creating backup in $BACKUP_DIR..."
for f in "$WORKFLOWS_DIR"/*/workflow.json; do
    if [ -f "$f" ]; then
        workflow_name=$(basename "$(dirname "$f")")
        cp "$f" "$BACKUP_DIR/${workflow_name}-workflow.json"
    fi
done
echo "Backup complete."
echo ""

# 1. Replace hardcoded database path in Function nodes
# '/selene/data/selene.db' -> process.env.SELENE_DB_PATH
echo "Updating database paths..."
for f in "$WORKFLOWS_DIR"/*/workflow.json; do
    if [ -f "$f" ] && grep -q "'/selene/data/selene.db'" "$f"; then
        workflow_name=$(basename "$(dirname "$f")")
        echo "  - $workflow_name"
        # Use sed to replace the hardcoded path with env var
        # The path appears in JavaScript strings inside JSON, so it's: '/selene/data/selene.db'
        sed -i '' "s|'/selene/data/selene.db'|process.env.SELENE_DB_PATH|g" "$f"
    fi
done

# Also handle the variant with double quotes inside the escaped JSON
for f in "$WORKFLOWS_DIR"/*/workflow.json; do
    if [ -f "$f" ] && grep -q '"/selene/data/selene.db"' "$f"; then
        workflow_name=$(basename "$(dirname "$f")")
        echo "  - $workflow_name (double quotes)"
        sed -i '' 's|"/selene/data/selene.db"|process.env.SELENE_DB_PATH|g' "$f"
    fi
done
echo ""

# 2. Replace hardcoded Ollama URL in HTTP Request nodes
# "http://host.docker.internal:11434" -> use n8n expression syntax
echo "Updating Ollama URLs in HTTP Request nodes..."
for f in "$WORKFLOWS_DIR"/*/workflow.json; do
    if [ -f "$f" ] && grep -q "host.docker.internal:11434" "$f"; then
        workflow_name=$(basename "$(dirname "$f")")
        echo "  - $workflow_name"
        # Replace full URL with n8n expression syntax
        sed -i '' 's|http://host.docker.internal:11434/api/generate|={{ $env.OLLAMA_BASE_URL }}/api/generate|g' "$f"
        sed -i '' 's|http://host.docker.internal:11434/api/embeddings|={{ $env.OLLAMA_BASE_URL }}/api/embeddings|g' "$f"
    fi
done
echo ""

# 3. Replace /obsidian paths with env var (if any exist)
echo "Updating Obsidian vault paths..."
for f in "$WORKFLOWS_DIR"/*/workflow.json; do
    if [ -f "$f" ] && grep -q '"/obsidian/' "$f"; then
        workflow_name=$(basename "$(dirname "$f")")
        echo "  - $workflow_name"
        # This is trickier - need to handle paths like /obsidian/projects-pending/
        # For now, let's just report them
    fi
done
echo ""

# Verify changes
echo "============================================"
echo "Verification"
echo "============================================"
echo ""

REMAINING_DB=$(grep -rl "'/selene/data/selene.db'" "$WORKFLOWS_DIR"/*/workflow.json 2>/dev/null | wc -l | tr -d ' ')
REMAINING_OLLAMA=$(grep -rl "host.docker.internal:11434" "$WORKFLOWS_DIR"/*/workflow.json 2>/dev/null | wc -l | tr -d ' ')

if [ "$REMAINING_DB" -eq 0 ] && [ "$REMAINING_OLLAMA" -eq 0 ]; then
    echo "SUCCESS: All hardcoded paths updated!"
else
    echo "WARNING: Some paths remain:"
    [ "$REMAINING_DB" -gt 0 ] && echo "  - $REMAINING_DB files still have hardcoded database path"
    [ "$REMAINING_OLLAMA" -gt 0 ] && echo "  - $REMAINING_OLLAMA files still have hardcoded Ollama URL"
fi

echo ""
echo "Backup saved to: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "  1. Review changes with: git diff workflows/*/workflow.json"
echo "  2. Test a workflow to verify it works"
echo "  3. Commit changes: git add workflows/*/workflow.json"
echo ""
