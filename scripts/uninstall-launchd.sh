#!/bin/bash
# Uninstall Selene launchd agents (replaced by SeleneChat menu bar orchestration)
# Usage: ./scripts/uninstall-launchd.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN — no changes will be made"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$PROJECT_DIR/launchd"
PLIST_DIR="$HOME/Library/LaunchAgents"

# Agent labels — derived from the plists in launchd/ (single source of truth),
# then acted upon as installed copies in $PLIST_DIR. Skips prod/dev agents
# (com.selene.prod.*, com.selene.dev.*): those are not managed by this dev installer.
PLISTS=()
for f in "$LAUNCHD_DIR"/com.selene.*.plist; do
    label="$(basename "$f" .plist)"
    case "$label" in com.selene.prod.*|com.selene.dev.*) continue;; esac
    PLISTS+=("$label")
done

echo "Uninstalling Selene launchd agents..."
echo ""

for label in "${PLISTS[@]}"; do
    plist_file="$PLIST_DIR/$label.plist"

    # Stop the agent if running
    if launchctl list | grep -q "$label"; then
        echo "  Stopping: $label"
        if [[ "$DRY_RUN" == false ]]; then
            launchctl stop "$label" 2>/dev/null || true
            launchctl unload "$plist_file" 2>/dev/null || true
        fi
    else
        echo "  Not running: $label"
    fi

    # Remove the plist
    if [[ -f "$plist_file" ]]; then
        echo "  Removing: $plist_file"
        if [[ "$DRY_RUN" == false ]]; then
            rm "$plist_file"
        fi
    else
        echo "  Not installed: $plist_file"
    fi
done

echo ""
echo "Done. SeleneChat now handles all workflow scheduling."
echo "Make sure SeleneChat is running (it should start automatically at login)."
