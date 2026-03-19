#!/bin/bash
#
# Install Selene launchd agents
#
# This script:
# 1. Unloads any existing com.selene.* agents
# 2. Copies plist files to ~/Library/LaunchAgents/
# 3. Loads the new agents
# 4. Shows installed agents
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$PROJECT_DIR/launchd"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Selene Launchd Agent Installer"
echo "========================================"
echo ""

# Ensure LaunchAgents directory exists
mkdir -p "$LAUNCH_AGENTS_DIR"

# Ensure logs directory exists
mkdir -p "$PROJECT_DIR/logs"

# List of agents
AGENTS=(
    "com.selene.server"
    "com.selene.process-llm"
    "com.selene.extract-tasks"
    "com.selene.index-vectors"
    "com.selene.compute-relationships"
    "com.selene.daily-summary"
    "com.selene.send-digest"
    "com.selene.export-obsidian"
    "com.selene.detect-threads"
    "com.selene.reconsolidate-threads"
    "com.selene.thread-lifecycle"
    "com.selene.transcribe-voice-memos"
    "com.selene.render-daily-sheet"
)

echo "Step 1: Unloading existing agents..."
echo "----------------------------------------"
for agent in "${AGENTS[@]}"; do
    plist_path="$LAUNCH_AGENTS_DIR/$agent.plist"
    if [ -f "$plist_path" ]; then
        echo -e "  ${YELLOW}Unloading${NC} $agent..."
        launchctl unload "$plist_path" 2>/dev/null || true
    fi
done
echo ""

echo "Step 2: Copying plist files..."
echo "----------------------------------------"
for agent in "${AGENTS[@]}"; do
    src_plist="$LAUNCHD_DIR/$agent.plist"
    dst_plist="$LAUNCH_AGENTS_DIR/$agent.plist"

    if [ -f "$src_plist" ]; then
        cp "$src_plist" "$dst_plist"
        echo -e "  ${GREEN}Copied${NC} $agent.plist"
    else
        echo -e "  ${RED}Missing${NC} $src_plist"
    fi
done
echo ""

echo "Step 3: Loading agents..."
echo "----------------------------------------"
for agent in "${AGENTS[@]}"; do
    plist_path="$LAUNCH_AGENTS_DIR/$agent.plist"
    if [ -f "$plist_path" ]; then
        launchctl load "$plist_path"
        echo -e "  ${GREEN}Loaded${NC} $agent"
    fi
done
echo ""

echo "Step 4: Verifying installed agents..."
echo "----------------------------------------"
echo ""
echo "Installed com.selene.* agents:"
launchctl list | grep "com.selene" || echo "  No agents found (this may indicate an error)"
echo ""

echo "========================================"
echo -e "  ${GREEN}Installation complete!${NC}"
echo "========================================"
echo ""
echo "Logs are written to: $PROJECT_DIR/logs/"
echo ""
echo "Useful commands:"
echo "  launchctl list | grep com.selene    # List agents"
echo "  launchctl stop com.selene.server    # Stop an agent"
echo "  launchctl start com.selene.server   # Start an agent"
echo "  tail -f $PROJECT_DIR/logs/*.log     # Watch logs"
echo ""
