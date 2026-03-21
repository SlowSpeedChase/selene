#!/bin/bash
# Apply CLAUDE.md updates by staging modified files
# Called after user approves proposed updates

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if update list exists
if [ ! -f /tmp/claude-context-updates ]; then
    echo -e "${BLUE}No pending context updates${NC}"
    exit 0
fi

echo -e "${BLUE}Applying CLAUDE.md updates...${NC}"

# Stage all CLAUDE.md files that exist in affected components
while IFS= read -r component; do
    if [ "$component" = "." ]; then
        CLAUDE_FILE="CLAUDE.md"
    else
        CLAUDE_FILE="${component}/CLAUDE.md"
    fi

    if [ -f "$CLAUDE_FILE" ]; then
        echo -e "${GREEN}  Staging: $CLAUDE_FILE${NC}"
        git add "$CLAUDE_FILE"
    fi
done < /tmp/claude-context-updates

# Clean up temp file
rm -f /tmp/claude-context-updates

echo -e "${GREEN}CLAUDE.md files staged successfully${NC}"
