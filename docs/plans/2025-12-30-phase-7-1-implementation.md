# Phase 7.1 Task Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the Task Extraction workflow to classify notes and route actionable tasks to Things via file-based handoff.

**Architecture:** n8n workflow writes task JSON files to `/obsidian/things-pending/`. A launchd job on Mac watches this folder and runs an AppleScript to add tasks to Things, then moves files to `/obsidian/things-processed/`.

**Tech Stack:** n8n (Docker), SQLite, Ollama, launchd, AppleScript, Things 3

---

## Current State

| Component | Status |
|-----------|--------|
| Database schema | ✅ Ready (classification, planning_status, task_metadata, discussion_threads) |
| Workflow 07 JSON | ✅ 90% complete (needs Things integration change) |
| Classification prompt | ✅ Complete |
| Task extraction prompt | ✅ Complete |
| Things integration | ❌ Uses HTTP (needs file-based) |
| Mac bridge | ❌ Not created |

---

## Task 1: Create Things Pending Directories

**Files:**
- Create: `vault/things-pending/` (directory)
- Create: `vault/things-processed/` (directory)
- Create: `vault/things-pending/.gitkeep`
- Create: `vault/things-processed/.gitkeep`

**Step 1: Create directories**

```bash
mkdir -p /Users/chaseeasterling/selene/vault/things-pending
mkdir -p /Users/chaseeasterling/selene/vault/things-processed
touch /Users/chaseeasterling/selene/vault/things-pending/.gitkeep
touch /Users/chaseeasterling/selene/vault/things-processed/.gitkeep
```

**Step 2: Verify directories exist**

```bash
ls -la /Users/chaseeasterling/selene/vault/things-*
```

Expected: Both directories exist with .gitkeep files

**Step 3: Commit**

```bash
git add vault/things-pending/.gitkeep vault/things-processed/.gitkeep
git commit -m "chore: add Things task handoff directories"
```

---

## Task 2: Create AppleScript for Things Integration

**Files:**
- Create: `scripts/things-bridge/add-task-to-things.scpt`

**Step 1: Create the bridge directory**

```bash
mkdir -p /Users/chaseeasterling/selene/scripts/things-bridge
```

**Step 2: Create the AppleScript**

Create file `scripts/things-bridge/add-task-to-things.scpt`:

```applescript
-- add-task-to-things.scpt
-- Reads a JSON file and creates a task in Things 3
-- Usage: osascript add-task-to-things.scpt /path/to/task.json

on run argv
    if (count of argv) < 1 then
        error "Usage: osascript add-task-to-things.scpt <json-file-path>"
    end if

    set jsonPath to item 1 of argv

    -- Read JSON file
    set jsonContent to do shell script "cat " & quoted form of jsonPath

    -- Parse JSON using shell (jq)
    set taskTitle to do shell script "echo " & quoted form of jsonContent & " | /opt/homebrew/bin/jq -r '.title // empty'"
    set taskNotes to do shell script "echo " & quoted form of jsonContent & " | /opt/homebrew/bin/jq -r '.notes // empty'"
    set taskTags to do shell script "echo " & quoted form of jsonContent & " | /opt/homebrew/bin/jq -r '.tags // [] | join(\",\")'"

    if taskTitle is "" then
        error "Task title is required"
    end if

    -- Create task in Things
    tell application "Things3"
        set newToDo to make new to do with properties {name:taskTitle, notes:taskNotes}

        -- Add tags if present
        if taskTags is not "" then
            set tagList to my splitString(taskTags, ",")
            repeat with tagName in tagList
                set tagName to my trim(tagName)
                if tagName is not "" then
                    set tag of newToDo to tag of newToDo & {tagName}
                end if
            end repeat
        end if

        -- Return the task ID
        return id of newToDo
    end tell
end run

on splitString(theString, theDelimiter)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to theDelimiter
    set theArray to every text item of theString
    set AppleScript's text item delimiters to oldDelimiters
    return theArray
end splitString

on trim(theText)
    set theText to theText as text
    repeat while theText begins with " "
        set theText to text 2 thru -1 of theText
    end repeat
    repeat while theText ends with " "
        set theText to text 1 thru -2 of theText
    end repeat
    return theText
end trim
```

**Step 3: Test the AppleScript manually**

Create a test JSON file:
```bash
echo '{"title": "Test task from Selene", "notes": "This is a test", "tags": ["test"]}' > /tmp/test-task.json
osascript /Users/chaseeasterling/selene/scripts/things-bridge/add-task-to-things.scpt /tmp/test-task.json
```

Expected: Task appears in Things inbox, script returns task ID

**Step 4: Delete test task from Things manually**

**Step 5: Commit**

```bash
git add scripts/things-bridge/add-task-to-things.scpt
git commit -m "feat: add AppleScript for Things task creation"
```

---

## Task 3: Create Shell Wrapper Script

**Files:**
- Create: `scripts/things-bridge/process-pending-tasks.sh`

**Step 1: Create the wrapper script**

Create file `scripts/things-bridge/process-pending-tasks.sh`:

```bash
#!/bin/bash
# process-pending-tasks.sh
# Watches things-pending folder and processes task JSON files
# Run by launchd or manually

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PENDING_DIR="/Users/chaseeasterling/selene/vault/things-pending"
PROCESSED_DIR="/Users/chaseeasterling/selene/vault/things-processed"
LOG_FILE="/Users/chaseeasterling/selene/logs/things-bridge.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Checking for pending tasks..."

# Process each JSON file in pending directory
for json_file in "$PENDING_DIR"/*.json; do
    # Check if any files exist (glob returns literal if no match)
    [ -e "$json_file" ] || continue

    filename=$(basename "$json_file")
    log "Processing: $filename"

    # Run AppleScript to create task in Things
    task_id=$(osascript "$SCRIPT_DIR/add-task-to-things.scpt" "$json_file" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log "SUCCESS: Created task $task_id from $filename"

        # Add task_id to JSON and move to processed
        if command -v jq &> /dev/null; then
            jq --arg id "$task_id" '. + {things_task_id: $id, processed_at: now | todate}' "$json_file" > "$PROCESSED_DIR/$filename"
        else
            # Fallback: just copy the file
            cp "$json_file" "$PROCESSED_DIR/$filename"
        fi

        # Remove from pending
        rm "$json_file"
    else
        log "ERROR: Failed to create task from $filename: $task_id"
        # Move to processed with error flag
        if command -v jq &> /dev/null; then
            jq --arg err "$task_id" '. + {error: $err, failed_at: now | todate}' "$json_file" > "$PROCESSED_DIR/error-$filename"
        else
            mv "$json_file" "$PROCESSED_DIR/error-$filename"
        fi
        rm -f "$json_file"
    fi
done

log "Done processing pending tasks"
```

**Step 2: Make executable**

```bash
chmod +x /Users/chaseeasterling/selene/scripts/things-bridge/process-pending-tasks.sh
```

**Step 3: Create logs directory**

```bash
mkdir -p /Users/chaseeasterling/selene/logs
touch /Users/chaseeasterling/selene/logs/.gitkeep
echo "logs/*.log" >> /Users/chaseeasterling/selene/.gitignore
```

**Step 4: Test the wrapper script**

```bash
# Create test task
echo '{"title": "Wrapper test task", "notes": "Testing wrapper", "tags": ["test"]}' > /Users/chaseeasterling/selene/vault/things-pending/test-001.json

# Run wrapper
/Users/chaseeasterling/selene/scripts/things-bridge/process-pending-tasks.sh

# Check results
cat /Users/chaseeasterling/selene/logs/things-bridge.log
ls /Users/chaseeasterling/selene/vault/things-processed/
```

Expected: Task in Things, file moved to processed with things_task_id added

**Step 5: Delete test task from Things manually**

**Step 6: Commit**

```bash
git add scripts/things-bridge/process-pending-tasks.sh logs/.gitkeep .gitignore
git commit -m "feat: add shell wrapper for Things bridge"
```

---

## Task 4: Create launchd Plist

**Files:**
- Create: `scripts/things-bridge/com.selene.things-bridge.plist`

**Step 1: Create the launchd plist**

Create file `scripts/things-bridge/com.selene.things-bridge.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.things-bridge</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/chaseeasterling/selene/scripts/things-bridge/process-pending-tasks.sh</string>
    </array>

    <key>WatchPaths</key>
    <array>
        <string>/Users/chaseeasterling/selene/vault/things-pending</string>
    </array>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/things-bridge-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/things-bridge-stderr.log</string>
</dict>
</plist>
```

**Step 2: Install the launchd job**

```bash
cp /Users/chaseeasterling/selene/scripts/things-bridge/com.selene.things-bridge.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.selene.things-bridge.plist
```

**Step 3: Verify launchd job is loaded**

```bash
launchctl list | grep selene
```

Expected: `com.selene.things-bridge` appears in list

**Step 4: Test the file watcher**

```bash
# Create a task file
echo '{"title": "LaunchD test", "notes": "Testing file watcher", "tags": ["test"]}' > /Users/chaseeasterling/selene/vault/things-pending/launchd-test.json

# Wait 2-3 seconds for launchd to trigger

# Check if processed
ls /Users/chaseeasterling/selene/vault/things-processed/
cat /Users/chaseeasterling/selene/logs/things-bridge.log | tail -5
```

Expected: File moved to processed, task appears in Things

**Step 5: Delete test task from Things manually**

**Step 6: Commit**

```bash
git add scripts/things-bridge/com.selene.things-bridge.plist
git commit -m "feat: add launchd plist for Things file watcher"
```

---

## Task 5: Modify Workflow to Write JSON Files

**Files:**
- Modify: `workflows/07-task-extraction/workflow.json`

**Step 1: Export current workflow (backup)**

```bash
./scripts/manage-workflow.sh export 07
```

**Step 2: Read current workflow and identify the node to modify**

The node "Create Things Task" (id: create-things-task) currently calls HTTP. We need to replace it with a Function node that writes JSON files.

**Step 3: Modify the workflow JSON**

Replace the "Create Things Task" node with a new Function node that writes to the file system:

Find this node (around line 126-146):
```json
{
  "parameters": {
    "method": "POST",
    "url": "http://host.docker.internal:3456/create-task",
    ...
  },
  "id": "create-things-task",
  "name": "Create Things Task",
  "type": "n8n-nodes-base.httpRequest",
  ...
}
```

Replace with:
```json
{
  "parameters": {
    "functionCode": "const fs = require('fs');\nconst path = require('path');\n\n// Get task data from split output\nconst task = $input.item.json;\n\nconsole.log('[Write Things Task] Processing task:', task.task_text);\nconsole.log('[Write Things Task] raw_note_id:', task.raw_note_id);\n\n// Generate unique filename\nconst timestamp = Date.now();\nconst random = Math.floor(Math.random() * 10000);\nconst filename = `task-${task.raw_note_id}-${timestamp}-${random}.json`;\n\n// Build task JSON for Things\nconst thingsTask = {\n  title: task.task_text,\n  notes: `Extracted from Selene note #${task.raw_note_id}\\n\\nEnergy: ${task.energy_required}\\nEstimated: ${task.estimated_minutes}min\\nOverwhelm: ${task.overwhelm_factor}/10\\nType: ${task.task_type}\\n\\nOriginal note:\\n${task.original_note || '(not available)'}`,\n  tags: task.context_tags || [],\n  selene_metadata: {\n    raw_note_id: task.raw_note_id,\n    processed_note_id: task.processed_note_id,\n    energy_required: task.energy_required,\n    estimated_minutes: task.estimated_minutes,\n    overwhelm_factor: task.overwhelm_factor,\n    task_type: task.task_type,\n    concepts: task.concepts,\n    themes: task.themes,\n    test_run: task.test_run\n  }\n};\n\n// Write to pending directory\nconst pendingDir = '/obsidian/things-pending';\nconst filePath = path.join(pendingDir, filename);\n\ntry {\n  fs.writeFileSync(filePath, JSON.stringify(thingsTask, null, 2));\n  console.log('[Write Things Task] Wrote file:', filePath);\n} catch (err) {\n  console.error('[Write Things Task] Error writing file:', err);\n  throw err;\n}\n\n// Return data for next node (Store Task Metadata)\nreturn {\n  json: {\n    task: task,\n    raw_note_id: task.raw_note_id,\n    processed_note_id: task.processed_note_id,\n    things_file: filename,\n    concepts: task.concepts,\n    themes: task.themes,\n    test_run: task.test_run\n  }\n};"
  },
  "id": "create-things-task",
  "name": "Write Things Task File",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [2250, 100]
}
```

**Step 4: Update "Store Task Metadata" node**

The Store Task Metadata node references `$json.task_id` from the HTTP response. Update it to use the filename instead:

Find line with:
```javascript
const thingsTaskId = $json.task_id;
```

Replace with:
```javascript
const thingsTaskId = inputData.things_file || generateUniqueId();
```

And update the data extraction to handle the new format:
```javascript
if (inputData.task) {
    task = inputData.task;
    rawNoteId = inputData.raw_note_id;
    processedNoteId = inputData.processed_note_id;
    concepts = inputData.concepts;
    themes = inputData.themes;
    testRun = inputData.test_run;
}
```

**Step 5: Import updated workflow**

```bash
./scripts/manage-workflow.sh update <workflow-id> workflows/07-task-extraction/workflow.json
```

Note: Get the workflow ID from `./scripts/manage-workflow.sh list`

**Step 6: Commit**

```bash
git add workflows/07-task-extraction/workflow.json
git commit -m "feat: change Things integration to file-based handoff"
```

---

## Task 6: End-to-End Test

**Files:**
- Modify: `workflows/07-task-extraction/scripts/test-with-markers.sh` (verify/update)

**Step 1: Ensure Docker is running and n8n is up**

```bash
docker-compose ps
```

**Step 2: Ensure launchd bridge is running**

```bash
launchctl list | grep selene
```

**Step 3: Create a test note in the database**

```bash
TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
echo "Test run: $TEST_RUN"

sqlite3 /Users/chaseeasterling/selene/data/selene.db "
INSERT INTO raw_notes (title, content, content_hash, source_type, created_at, status, test_run)
VALUES (
  'E2E Test - Actionable Task',
  'I need to call the dentist tomorrow to reschedule my appointment. Also send the report to Sarah by Friday.',
  'e2e-test-$(date +%s)',
  'test',
  datetime('now'),
  'pending',
  '$TEST_RUN'
);
"

# Get the note ID
NOTE_ID=$(sqlite3 /Users/chaseeasterling/selene/data/selene.db "SELECT id FROM raw_notes WHERE test_run = '$TEST_RUN' ORDER BY id DESC LIMIT 1;")
echo "Created note ID: $NOTE_ID"

# Create processed_notes entry (required for workflow)
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
INSERT INTO processed_notes (raw_note_id, concepts, primary_theme, processed_at)
VALUES ($NOTE_ID, '[\"health\", \"communication\"]', 'personal-tasks', datetime('now'));
"
```

**Step 4: Trigger the workflow**

```bash
curl -X POST http://localhost:5678/webhook/task-extraction \
  -H "Content-Type: application/json" \
  -d "{\"raw_note_id\": $NOTE_ID, \"test_run\": \"$TEST_RUN\"}"
```

**Step 5: Wait and verify**

```bash
# Wait for processing
sleep 10

# Check classification was stored
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
SELECT classification, planning_status, things_integration_status
FROM processed_notes
WHERE raw_note_id = $NOTE_ID;
"

# Check task metadata was stored
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
SELECT * FROM task_metadata WHERE raw_note_id = $NOTE_ID;
"

# Check file was written
ls -la /Users/chaseeasterling/selene/vault/things-pending/
ls -la /Users/chaseeasterling/selene/vault/things-processed/

# Check Things bridge log
cat /Users/chaseeasterling/selene/logs/things-bridge.log | tail -10
```

Expected:
- Classification: `actionable`
- Task(s) in task_metadata table
- File moved to things-processed
- Task(s) visible in Things inbox

**Step 6: Cleanup test data**

```bash
# Delete from Things manually (the test tasks)

# Cleanup database
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
DELETE FROM task_metadata WHERE test_run = '$TEST_RUN';
DELETE FROM processed_notes WHERE raw_note_id IN (SELECT id FROM raw_notes WHERE test_run = '$TEST_RUN');
DELETE FROM raw_notes WHERE test_run = '$TEST_RUN';
"

# Cleanup processed files
rm -f /Users/chaseeasterling/selene/vault/things-processed/*test*
```

---

## Task 7: Test needs_planning Path

**Step 1: Create a note that should be classified as needs_planning**

```bash
TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"

sqlite3 /Users/chaseeasterling/selene/data/selene.db "
INSERT INTO raw_notes (title, content, content_hash, source_type, created_at, status, test_run)
VALUES (
  'E2E Test - Needs Planning',
  'I want to completely redo my personal website. Need to figure out hosting, design, content strategy, maybe add a blog. Not sure where to start.',
  'e2e-planning-$(date +%s)',
  'test',
  datetime('now'),
  'pending',
  '$TEST_RUN'
);
"

NOTE_ID=$(sqlite3 /Users/chaseeasterling/selene/data/selene.db "SELECT id FROM raw_notes WHERE test_run = '$TEST_RUN' ORDER BY id DESC LIMIT 1;")

sqlite3 /Users/chaseeasterling/selene/data/selene.db "
INSERT INTO processed_notes (raw_note_id, concepts, primary_theme, processed_at)
VALUES ($NOTE_ID, '[\"web-design\", \"planning\"]', 'creative-projects', datetime('now'));
"
```

**Step 2: Trigger workflow**

```bash
curl -X POST http://localhost:5678/webhook/task-extraction \
  -H "Content-Type: application/json" \
  -d "{\"raw_note_id\": $NOTE_ID, \"test_run\": \"$TEST_RUN\"}"
```

**Step 3: Verify needs_planning classification**

```bash
sleep 5

# Should be needs_planning with pending_review status
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
SELECT classification, planning_status
FROM processed_notes
WHERE raw_note_id = $NOTE_ID;
"

# Should have a discussion_thread
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
SELECT id, thread_type, status, prompt
FROM discussion_threads
WHERE raw_note_id = $NOTE_ID;
"

# Should NOT have task_metadata (not actionable)
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
SELECT COUNT(*) FROM task_metadata WHERE raw_note_id = $NOTE_ID;
"
```

Expected:
- Classification: `needs_planning`
- Planning status: `pending_review`
- Discussion thread created
- No tasks in Things

**Step 4: Cleanup**

```bash
sqlite3 /Users/chaseeasterling/selene/data/selene.db "
DELETE FROM discussion_threads WHERE test_run = '$TEST_RUN';
DELETE FROM processed_notes WHERE raw_note_id IN (SELECT id FROM raw_notes WHERE test_run = '$TEST_RUN');
DELETE FROM raw_notes WHERE test_run = '$TEST_RUN';
"
```

---

## Task 8: Update Documentation

**Files:**
- Modify: `workflows/07-task-extraction/STATUS.md`
- Modify: `workflows/07-task-extraction/README.md`

**Step 1: Update STATUS.md with test results**

Add section documenting:
- E2E tests passing
- Things integration working
- Classification accuracy observations

**Step 2: Update README.md with usage instructions**

Document:
- How to trigger the workflow
- Prerequisites (launchd running)
- Expected behavior for each classification

**Step 3: Commit**

```bash
git add workflows/07-task-extraction/STATUS.md workflows/07-task-extraction/README.md
git commit -m "docs: update workflow 07 documentation with test results"
```

---

## Task 9: Final Commit and Status Update

**Files:**
- Modify: `.claude/PROJECT-STATUS.md`
- Modify: `ROADMAP.md`

**Step 1: Update PROJECT-STATUS.md**

Mark Phase 7.1 as complete with date and achievements.

**Step 2: Update ROADMAP.md**

Update Phase 7.1 status from "PLANNING COMPLETE" to "COMPLETE".

**Step 3: Commit**

```bash
git add .claude/PROJECT-STATUS.md ROADMAP.md
git commit -m "docs: mark Phase 7.1 Task Extraction as complete"
```

---

## Summary

| Task | Description | Est. Time |
|------|-------------|-----------|
| 1 | Create directories | 2 min |
| 2 | Create AppleScript | 10 min |
| 3 | Create shell wrapper | 10 min |
| 4 | Create launchd plist | 5 min |
| 5 | Modify workflow JSON | 15 min |
| 6 | E2E test (actionable) | 10 min |
| 7 | E2E test (needs_planning) | 5 min |
| 8 | Update documentation | 10 min |
| 9 | Final status update | 5 min |

**Total estimated time:** ~70 minutes

---

## Rollback Plan

If Things integration doesn't work:

1. Unload launchd job: `launchctl unload ~/Library/LaunchAgents/com.selene.things-bridge.plist`
2. Revert workflow: `git checkout workflows/07-task-extraction/workflow.json`
3. Re-import workflow: `./scripts/manage-workflow.sh update <id> workflows/07-task-extraction/workflow.json`

The classification and database storage will still work; only Things integration would be disabled.
