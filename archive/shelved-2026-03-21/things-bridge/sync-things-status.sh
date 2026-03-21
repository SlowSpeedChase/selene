#!/bin/bash
# sync-things-status.sh
# Batch sync task statuses from Things 3 to Selene database
#
# Usage: ./sync-things-status.sh [--dry-run]
#
# Queries all tasks with things_task_id in task_links table,
# checks their status in Things 3, and updates the database.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DB_PATH="${SELENE_DB_PATH:-$PROJECT_ROOT/data/selene.db}"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/things-sync.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    echo -e "${YELLOW}[DRY RUN]${NC} No database changes will be made"
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

# Check database exists
if [ ! -f "$DB_PATH" ]; then
    log "ERROR" "Database not found: $DB_PATH"
    exit 1
fi

# Check if task_links table exists
if ! sqlite3 "$DB_PATH" ".schema task_links" > /dev/null 2>&1; then
    log "ERROR" "task_links table not found in database"
    exit 1
fi

log "INFO" "Starting Things status sync..."

# Get all tasks with things_task_id
TASK_IDS=$(sqlite3 "$DB_PATH" "SELECT things_task_id FROM task_links WHERE things_task_id IS NOT NULL AND things_task_id != '';")

if [ -z "$TASK_IDS" ]; then
    log "INFO" "No tasks with Things IDs found"
    exit 0
fi

TOTAL=0
UPDATED=0
COMPLETED=0
NOT_FOUND=0
ERRORS=0

while IFS= read -r things_id; do
    [ -z "$things_id" ] && continue

    TOTAL=$((TOTAL + 1))

    # Get status from Things
    STATUS_JSON=$("$SCRIPT_DIR/check-task-status.sh" "$things_id" 2>/dev/null || echo '{"error": "Script failed"}')

    # Check for error
    if echo "$STATUS_JSON" | grep -q '"error"'; then
        ERROR_MSG=$(echo "$STATUS_JSON" | grep -o '"error": "[^"]*"' | cut -d'"' -f4)
        if echo "$ERROR_MSG" | grep -q "not found"; then
            NOT_FOUND=$((NOT_FOUND + 1))
            log "WARN" "Task not found in Things: $things_id"
        else
            ERRORS=$((ERRORS + 1))
            log "ERROR" "Failed to get status for $things_id: $ERROR_MSG"
        fi
        continue
    fi

    # Extract status from JSON
    THINGS_STATUS=$(echo "$STATUS_JSON" | grep -o '"status": "[^"]*"' | cut -d'"' -f4)
    COMPLETION_DATE=$(echo "$STATUS_JSON" | grep -o '"completion_date": [^,}]*' | cut -d':' -f2 | tr -d ' "')

    if [ "$THINGS_STATUS" = "completed" ]; then
        COMPLETED=$((COMPLETED + 1))

        if [ "$DRY_RUN" = false ]; then
            # Update database with completion status
            sqlite3 "$DB_PATH" "UPDATE task_links SET
                things_status = 'completed',
                things_completed_at = '${COMPLETION_DATE}',
                updated_at = datetime('now')
                WHERE things_task_id = '$things_id';"
            UPDATED=$((UPDATED + 1))
        fi

        log "INFO" "Task completed: $things_id (${COMPLETION_DATE:-unknown date})"
    fi

done <<< "$TASK_IDS"

log "INFO" "Sync complete: $TOTAL tasks checked, $COMPLETED completed, $UPDATED updated, $NOT_FOUND not found, $ERRORS errors"

# Summary
echo ""
echo "=== Sync Summary ==="
echo "Total tasks checked: $TOTAL"
echo "Completed in Things: $COMPLETED"
echo "Database updated:    $UPDATED"
echo "Not found in Things: $NOT_FOUND"
echo "Errors:              $ERRORS"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${YELLOW}This was a dry run. Run without --dry-run to update the database.${NC}"
fi

# Check for project completion (7.2f.5)
# A project is complete when all its tasks are completed
log "INFO" "Checking for project completion..."

PROJECTS_COMPLETED=0

# Get active projects with tasks
ACTIVE_PROJECTS=$(sqlite3 "$DB_PATH" "
    SELECT p.id, p.things_project_id, p.name,
           (SELECT COUNT(*) FROM task_links tl WHERE tl.things_project_id = p.things_project_id) as total_tasks,
           (SELECT COUNT(*) FROM task_links tl WHERE tl.things_project_id = p.things_project_id AND tl.things_status = 'completed') as completed_tasks
    FROM projects p
    WHERE p.status = 'active'
    AND p.things_project_id IS NOT NULL;
")

while IFS='|' read -r project_id things_project_id project_name total_tasks completed_tasks; do
    [ -z "$project_id" ] && continue
    [ "$total_tasks" -eq 0 ] && continue

    if [ "$total_tasks" -eq "$completed_tasks" ]; then
        log "INFO" "Project completed: $project_name ($completed_tasks/$total_tasks tasks)"

        if [ "$DRY_RUN" = false ]; then
            # Mark project as completed
            sqlite3 "$DB_PATH" "
                UPDATE projects SET
                    status = 'completed',
                    completed_at = datetime('now')
                WHERE id = $project_id;
            "

            # Log to detected_patterns for productivity analysis
            sqlite3 "$DB_PATH" "
                INSERT INTO detected_patterns (pattern_type, pattern_name, description, confidence, data_points, pattern_data, discovered_at, is_active)
                VALUES (
                    'project_completion',
                    'Project Completed: $project_name',
                    'All $total_tasks tasks in project were completed',
                    1.0,
                    $total_tasks,
                    json_object('project_id', $project_id, 'things_project_id', '$things_project_id', 'task_count', $total_tasks),
                    datetime('now'),
                    1
                );
            "

            PROJECTS_COMPLETED=$((PROJECTS_COMPLETED + 1))
        fi
    fi
done <<< "$ACTIVE_PROJECTS"

if [ "$PROJECTS_COMPLETED" -gt 0 ]; then
    log "INFO" "Marked $PROJECTS_COMPLETED project(s) as completed"
    echo "Projects completed:  $PROJECTS_COMPLETED"
fi

# Check for sub-project suggestions (7.2f.6)
# When a heading has 5+ tasks, suggest spinning off as separate project
log "INFO" "Checking for sub-project suggestions..."

SUGGESTIONS_CREATED=0

# Find headings with 5+ tasks (grouped by project + heading)
HEADING_CLUSTERS=$(sqlite3 "$DB_PATH" "
    SELECT tl.things_project_id, tl.heading, COUNT(*) as task_count,
           GROUP_CONCAT(tl.things_task_id) as task_ids
    FROM task_links tl
    WHERE tl.things_project_id IS NOT NULL
    AND tl.heading IS NOT NULL
    AND tl.things_status != 'completed'
    GROUP BY tl.things_project_id, tl.heading
    HAVING COUNT(*) >= 5;
")

while IFS='|' read -r things_project_id heading task_count task_ids; do
    [ -z "$things_project_id" ] && continue

    # Check if suggestion already exists
    EXISTS=$(sqlite3 "$DB_PATH" "
        SELECT COUNT(*) FROM subproject_suggestions
        WHERE source_project_id = '$things_project_id'
        AND suggested_concept = '$heading';
    ")

    if [ "$EXISTS" -eq 0 ]; then
        log "INFO" "Suggesting sub-project: '$heading' ($task_count tasks)"

        if [ "$DRY_RUN" = false ]; then
            # Create suggestion (JSON array from comma-separated)
            TASK_IDS_JSON=$(echo "$task_ids" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')

            sqlite3 "$DB_PATH" "
                INSERT INTO subproject_suggestions
                    (source_project_id, suggested_concept, task_count, task_ids)
                VALUES
                    ('$things_project_id', '$heading', $task_count, '$TASK_IDS_JSON');
            "

            SUGGESTIONS_CREATED=$((SUGGESTIONS_CREATED + 1))
        fi
    fi
done <<< "$HEADING_CLUSTERS"

if [ "$SUGGESTIONS_CREATED" -gt 0 ]; then
    log "INFO" "Created $SUGGESTIONS_CREATED sub-project suggestion(s)"
    echo "Sub-project suggestions: $SUGGESTIONS_CREATED"
fi
