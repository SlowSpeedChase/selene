#!/bin/bash
# check-task-status.sh
# Shell wrapper for get-task-status.scpt
#
# Usage: ./check-task-status.sh <task_id>
#
# Returns JSON with task status from Things 3

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate argument
if [ $# -lt 1 ]; then
    echo '{"error": "Missing task_id argument"}'
    exit 1
fi

TASK_ID="$1"

# Validate task ID is not empty
if [ -z "$TASK_ID" ]; then
    echo '{"error": "task_id cannot be empty"}'
    exit 1
fi

# Run the AppleScript
osascript "$SCRIPT_DIR/get-task-status.scpt" "$TASK_ID"
