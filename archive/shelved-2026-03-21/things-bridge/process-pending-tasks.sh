#!/bin/bash
# process-pending-tasks.sh
# Processes pending task JSON files and sends them to Things 3
#
# Usage: ./process-pending-tasks.sh
#
# This script:
# 1. Looks for JSON files in vault/things-pending/
# 2. Calls add-task-to-things.scpt for each file
# 3. On success: adds things_task_id to JSON, moves to things-processed/
# 4. On failure: adds error info to JSON, moves with "error-" prefix

set -e

# Paths (absolute)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PENDING_DIR="$PROJECT_DIR/vault/things-pending"
PROCESSED_DIR="$PROJECT_DIR/vault/things-processed"
LOG_FILE="$PROJECT_DIR/logs/things-bridge.log"
APPLESCRIPT="$SCRIPT_DIR/add-task-to-things.scpt"
ASSIGN_SCRIPT="$SCRIPT_DIR/assign-to-project.scpt"

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

log_error() {
    log "ERROR: $1"
}

log_info() {
    log "INFO: $1"
}

# Check if jq is available
JQ_PATH=""
for path in /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    if [ -x "$path" ]; then
        JQ_PATH="$path"
        break
    fi
done

# Check if AppleScript exists
if [ ! -f "$APPLESCRIPT" ]; then
    log_error "AppleScript not found: $APPLESCRIPT"
    exit 1
fi

# Check if pending directory exists
if [ ! -d "$PENDING_DIR" ]; then
    log_info "Pending directory does not exist: $PENDING_DIR"
    exit 0
fi

# Create processed directory if it doesn't exist
mkdir -p "$PROCESSED_DIR"

# Count JSON files
json_files=("$PENDING_DIR"/*.json)

# Handle case where no JSON files exist (glob returns literal *.json if no matches)
if [ ! -e "${json_files[0]}" ]; then
    log_info "No pending JSON files found"
    exit 0
fi

log_info "Found ${#json_files[@]} pending file(s) to process"

# Process each JSON file
processed_count=0
error_count=0

for json_file in "${json_files[@]}"; do
    filename=$(basename "$json_file")
    log_info "Processing: $filename"

    # Call AppleScript and capture output
    result=""
    exit_code=0
    result=$(osascript "$APPLESCRIPT" "$json_file" 2>&1) || exit_code=$?

    # Check for success (exit code 0 and no ERROR prefix)
    if [ $exit_code -eq 0 ] && [[ ! "$result" =~ ^ERROR: ]]; then
        # Success - result contains the Things task ID
        things_task_id="$result"
        processed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

        log_info "Success: $filename -> Things ID: $things_task_id"

        # Check if task should be assigned to a project
        project_id=""
        if [ -n "$JQ_PATH" ]; then
            project_id=$("$JQ_PATH" -r '.project_id // empty' "$json_file")
        fi

        # Assign to project if specified
        if [ -n "$project_id" ]; then
            log_info "Assigning task to project: $project_id"
            assign_result=""
            assign_exit=0
            assign_result=$(osascript "$ASSIGN_SCRIPT" "$things_task_id" "$project_id" 2>&1) || assign_exit=$?

            if [ $assign_exit -eq 0 ] && [[ "$assign_result" == "SUCCESS" ]]; then
                log_info "Successfully assigned to project"
            else
                log_error "Failed to assign to project: $assign_result (task remains in inbox)"
            fi
        fi

        # Add things_task_id and processed_at to JSON
        if [ -n "$JQ_PATH" ]; then
            # Use jq to update JSON
            temp_file=$(mktemp)
            "$JQ_PATH" --arg tid "$things_task_id" --arg pat "$processed_at" \
                '. + {things_task_id: $tid, processed_at: $pat}' "$json_file" > "$temp_file"
            mv "$temp_file" "$json_file"
        else
            # Fallback: just copy the file (no modification)
            log_info "jq not available, skipping JSON update for $filename"
        fi

        # Move to processed directory
        mv "$json_file" "$PROCESSED_DIR/$filename"
        ((processed_count++))

    else
        # Failure
        error_message="$result"
        failed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

        log_error "Failed: $filename - $error_message"

        # Add error info to JSON
        if [ -n "$JQ_PATH" ]; then
            temp_file=$(mktemp)
            "$JQ_PATH" --arg err "$error_message" --arg fat "$failed_at" \
                '. + {error: $err, failed_at: $fat}' "$json_file" > "$temp_file"
            mv "$temp_file" "$json_file"
        else
            log_info "jq not available, skipping JSON update for $filename"
        fi

        # Move to processed directory with error- prefix
        mv "$json_file" "$PROCESSED_DIR/error-$filename"
        ((error_count++))
    fi
done

log_info "Processing complete: $processed_count succeeded, $error_count failed"
