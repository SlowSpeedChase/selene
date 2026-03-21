#!/bin/bash
set -e

echo "=== Setting up test isolation ==="

# Create production data directory
if [ ! -d "$HOME/selene-data" ]; then
  echo "Creating ~/selene-data/"
  mkdir -p "$HOME/selene-data/obsidian-vault"
else
  echo "~/selene-data/ already exists"
fi

# Move production database (if exists in repo)
if [ -f "./data/selene.db" ]; then
  echo "Moving production database to ~/selene-data/"
  # Backup first, then move
  cp ./data/selene.db "$HOME/selene-data/selene.db.backup"
  mv ./data/selene.db "$HOME/selene-data/"
  echo "  ✓ Moved selene.db (backup at selene.db.backup)"
else
  echo "  ℹ No database at ./data/selene.db (already moved or doesn't exist)"
fi

# Move Obsidian vault contents (if exists and not empty)
if [ -d "./vault" ] && [ "$(ls -A ./vault 2>/dev/null)" ]; then
  echo "Moving Obsidian vault to ~/selene-data/obsidian-vault/"
  mv ./vault/* "$HOME/selene-data/obsidian-vault/"
  echo "  ✓ Moved vault contents"
else
  echo "  ℹ No vault contents to move"
fi

# Ensure test directories exist
mkdir -p ./data-test ./vault-test

echo ""
echo "=== Setup complete ==="
echo "Production data: ~/selene-data/"
echo "Test data: ./data-test/ and ./vault-test/"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/seed-test-data.sh to create test database"
echo "  2. Restart n8n with ./scripts/start-n8n-local.sh"
