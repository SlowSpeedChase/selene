#!/bin/bash
# process-pending-projects.sh
# Processes pending project JSON files and creates them in Things 3
#
# Usage: ./process-pending-projects.sh
#
# This script:
# 1. Looks for JSON files in vault/projects-pending/
# 2. Creates projects in Things via create-project.scpt
# 3. Assigns tasks to projects via assign-to-project.scpt
# 4. Updates database with project_metadata
# 5. On success: moves to projects-processed/
# 6. On failure: moves with "error-" prefix

set -e

# Paths (absolute)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PENDING_DIR="$PROJECT_DIR/vault/projects-pending"
PROCESSED_DIR="$PROJECT_DIR/vault/projects-processed"
LOG_FILE="$PROJECT_DIR/logs/things-bridge.log"
DB_PATH="$PROJECT_DIR/data/selene.db"
CREATE_SCRIPT="$SCRIPT_DIR/create-project.scpt"
ASSIGN_SCRIPT="$SCRIPT_DIR/assign-to-project.scpt"

# Create directories if needed
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$PROCESSED_DIR"

# Logging function
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo "[$timestamp] $1"
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

if [ -z "$JQ_PATH" ]; then
    log_error "jq not found. Please install jq: brew install jq"
    exit 1
fi

# Check if scripts exist
if [ ! -f "$CREATE_SCRIPT" ]; then
    log_error "create-project.scpt not found: $CREATE_SCRIPT"
    exit 1
fi

if [ ! -f "$ASSIGN_SCRIPT" ]; then
    log_error "assign-to-project.scpt not found: $ASSIGN_SCRIPT"
    exit 1
fi

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    log_error "Database not found: $DB_PATH"
    exit 1
fi

# Check if pending directory exists
if [ ! -d "$PENDING_DIR" ]; then
    log_info "Pending directory does not exist: $PENDING_DIR"
    exit 0
fi

# Count JSON files
shopt -s nullglob
json_files=("$PENDING_DIR"/*.json)
shopt -u nullglob

if [ ${#json_files[@]} -eq 0 ]; then
    log_info "No pending project files found"
    exit 0
fi

log_info "Found ${#json_files[@]} pending project file(s) to process"

# Process each JSON file
processed_count=0
error_count=0

for json_file in "${json_files[@]}"; do
    filename=$(basename "$json_file")
    log_info "Processing: $filename"

    # Extract project data
    project_name=$("$JQ_PATH" -r '.name // empty' "$json_file")
    if [ -z "$project_name" ]; then
        log_error "Missing project name in: $filename"
        mv "$json_file" "$PROCESSED_DIR/error-$filename"
        ((error_count++))
        continue
    fi

    # Create temp file with just project creation fields
    temp_project_json=$(mktemp)
    "$JQ_PATH" '{name: .name, notes: .notes, area: .area}' "$json_file" > "$temp_project_json"

    # Create project in Things
    result=""
    exit_code=0
    result=$(osascript "$CREATE_SCRIPT" "$temp_project_json" 2>&1) || exit_code=$?
    rm -f "$temp_project_json"

    if [ $exit_code -ne 0 ] || [[ "$result" =~ ^ERROR: ]]; then
        log_error "Failed to create project '$project_name': $result"

        # Update JSON with error
        temp_file=$(mktemp)
        "$JQ_PATH" --arg err "$result" --arg fat "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            '. + {error: $err, failed_at: $fat}' "$json_file" > "$temp_file"
        mv "$temp_file" "$json_file"
        mv "$json_file" "$PROCESSED_DIR/error-$filename"
        ((error_count++))
        continue
    fi

    things_project_id="$result"
    log_info "Created project '$project_name' with ID: $things_project_id"

    # Extract metadata
    primary_concept=$("$JQ_PATH" -r '.selene_metadata.primary_concept // empty' "$json_file")
    energy_profile=$("$JQ_PATH" -r '.selene_metadata.energy_profile // "mixed"' "$json_file")
    task_count=$("$JQ_PATH" -r '.selene_metadata.task_count // 0' "$json_file")
    total_minutes=$("$JQ_PATH" -r '.selene_metadata.total_estimated_minutes // 0' "$json_file")
    test_run=$("$JQ_PATH" -r '.selene_metadata.test_run // empty' "$json_file")

    # Handle test_run for SQL (NULL or quoted string)
    if [ -z "$test_run" ] || [ "$test_run" = "null" ]; then
        test_run_sql="NULL"
    else
        test_run_sql="'$test_run'"
    fi

    # Insert project_metadata
    sqlite3 "$DB_PATH" "
        INSERT INTO project_metadata (
            things_project_id,
            project_name,
            primary_concept,
            energy_profile,
            total_estimated_minutes,
            task_count,
            test_run
        ) VALUES (
            '$things_project_id',
            '${project_name//\'/\'\'}',
            '$primary_concept',
            '$energy_profile',
            $total_minutes,
            $task_count,
            $test_run_sql
        );
    "
    log_info "Stored project_metadata for: $project_name"

    # Assign tasks to project
    task_ids=$("$JQ_PATH" -r '.selene_metadata.task_ids[]? // empty' "$json_file")
    assigned_count=0
    failed_assignments=0

    if [ -n "$task_ids" ]; then
        while IFS= read -r task_id; do
            if [ -z "$task_id" ]; then
                continue
            fi

            log_info "Assigning task $task_id to project..."
            assign_result=""
            assign_exit=0
            assign_result=$(osascript "$ASSIGN_SCRIPT" "$task_id" "$things_project_id" 2>&1) || assign_exit=$?

            if [ $assign_exit -eq 0 ] && [[ "$assign_result" == "SUCCESS" ]]; then
                # Update task_metadata with project ID
                sqlite3 "$DB_PATH" "
                    UPDATE task_metadata
                    SET things_project_id = '$things_project_id'
                    WHERE things_task_id = '$task_id';
                "
                ((assigned_count++))
                log_info "Assigned task $task_id successfully"
            else
                log_error "Failed to assign task $task_id: $assign_result"
                ((failed_assignments++))
            fi
        done <<< "$task_ids"
    fi

    log_info "Assigned $assigned_count tasks, $failed_assignments failed"

    # Log to integration_logs
    sqlite3 "$DB_PATH" "
        INSERT INTO integration_logs (workflow, event, success, metadata)
        VALUES (
            '08-project-detection',
            'project_created_in_things',
            1,
            '{\"project_name\": \"${project_name//\"/\\\"}\", \"things_project_id\": \"$things_project_id\", \"tasks_assigned\": $assigned_count, \"tasks_failed\": $failed_assignments}'
        );
    "

    # Update JSON with success info and move to processed
    temp_file=$(mktemp)
    "$JQ_PATH" --arg tid "$things_project_id" --arg pat "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --argjson assigned "$assigned_count" --argjson failed "$failed_assignments" \
        '. + {things_project_id: $tid, processed_at: $pat, tasks_assigned: $assigned, tasks_failed: $failed}' \
        "$json_file" > "$temp_file"
    mv "$temp_file" "$json_file"
    mv "$json_file" "$PROCESSED_DIR/$filename"

    ((processed_count++))
    log_info "Completed processing: $filename"
done

log_info "Processing complete: $processed_count succeeded, $error_count failed"
