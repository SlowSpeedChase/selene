# Phase 7.2f.1: Basic Project Creation - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically create Things projects when 3+ tasks share a concept, with AI-generated project names and deterministic script-driven CRUD operations.

**Architecture:** Script-driven design where AI only generates creative outputs (project names). AppleScript handles all Things 3 operations. n8n workflow orchestrates the pipeline with SQLite as the source of truth for Selene metadata.

**Tech Stack:** n8n workflows, SQLite (better-sqlite3), AppleScript, Ollama (mistral:7b), Bash

---

## Prerequisites

Before starting, ensure:
- [ ] Docker is running: `docker-compose ps`
- [ ] n8n is accessible: `curl -s http://localhost:5678`
- [ ] Ollama is running with mistral:7b: `ollama list`
- [ ] Things 3 is installed on macOS
- [ ] Working in worktree: `/Users/chaseeasterling/selene/.worktrees/project-grouping`

---

## Task 1: Create Database Migration for project_metadata

**Files:**
- Create: `database/migrations/008_project_metadata.sql`
- Test: Manual SQL verification

### Step 1: Write the migration SQL

Create the file with the full schema from design doc:

```sql
-- Migration 008: Project Metadata for Things Project Grouping
-- Created: 2026-01-01
-- Phase: 7.2f.1 - Basic Project Creation

BEGIN TRANSACTION;

-- Table: project_metadata
-- Stores Selene's metadata about Things projects
CREATE TABLE IF NOT EXISTS project_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Things integration
    things_project_id TEXT NOT NULL UNIQUE,
    project_name TEXT NOT NULL,

    -- Concept linkage
    primary_concept TEXT NOT NULL,
    related_concepts TEXT,  -- JSON array of secondary concepts

    -- ADHD optimization
    energy_profile TEXT CHECK(energy_profile IN ('high', 'mixed', 'low')),
    total_estimated_minutes INTEGER DEFAULT 0,

    -- Counts (denormalized for quick access)
    task_count INTEGER DEFAULT 0,
    completed_task_count INTEGER DEFAULT 0,

    -- Lifecycle
    status TEXT DEFAULT 'active'
        CHECK(status IN ('active', 'completed', 'archived')),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    last_synced_at TEXT,

    -- Things state (cached)
    things_status TEXT DEFAULT 'active'
        CHECK(things_status IN ('active', 'completed', 'canceled')),

    -- Test isolation
    test_run TEXT
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_project_metadata_concept ON project_metadata(primary_concept);
CREATE INDEX IF NOT EXISTS idx_project_metadata_things_id ON project_metadata(things_project_id);
CREATE INDEX IF NOT EXISTS idx_project_metadata_status ON project_metadata(status);
CREATE INDEX IF NOT EXISTS idx_project_metadata_test_run ON project_metadata(test_run);

COMMIT;
```

### Step 2: Apply migration to database

Run:
```bash
sqlite3 data/selene.db < database/migrations/008_project_metadata.sql
```

Expected: No output (success)

### Step 3: Verify migration applied correctly

Run:
```bash
sqlite3 data/selene.db ".schema project_metadata"
```

Expected: Schema output matching the CREATE TABLE statement

### Step 4: Commit migration

```bash
git add database/migrations/008_project_metadata.sql
git commit -m "feat(db): add project_metadata table for Things project grouping

- Stores Things project ID and Selene metadata
- Tracks primary/related concepts for project-task linking
- Includes energy_profile, task counts, lifecycle status
- Indexes for concept lookup and status filtering"
```

---

## Task 2: Create AppleScript create-project.scpt

**Files:**
- Create: `scripts/things-bridge/create-project.scpt`
- Test: Manual AppleScript execution

### Step 1: Write the AppleScript

Create `scripts/things-bridge/create-project.scpt`:

```applescript
#!/usr/bin/osascript
-- create-project.scpt
-- Creates a project in Things 3 from a JSON file
--
-- Usage: osascript create-project.scpt /path/to/project.json
--
-- JSON format:
-- {
--   "name": "Project name",           -- required
--   "notes": "Project description",   -- optional
--   "area": "Area name"               -- optional
-- }
--
-- Returns: The Things project ID on success, or error message on failure

on run argv
    -- Validate argument
    if (count of argv) < 1 then
        return "ERROR: Missing JSON file path argument"
    end if

    set jsonFilePath to item 1 of argv

    -- Check if file exists
    try
        do shell script "test -f " & quoted form of jsonFilePath
    on error
        return "ERROR: File not found: " & jsonFilePath
    end try

    -- Path to jq (try multiple locations)
    set jqPath to ""
    try
        do shell script "test -x /usr/bin/jq"
        set jqPath to "/usr/bin/jq"
    end try
    if jqPath is "" then
        try
            do shell script "test -x /opt/homebrew/bin/jq"
            set jqPath to "/opt/homebrew/bin/jq"
        end try
    end if
    if jqPath is "" then
        try
            do shell script "test -x /usr/local/bin/jq"
            set jqPath to "/usr/local/bin/jq"
        end try
    end if

    -- Check if jq was found
    if jqPath is "" then
        return "ERROR: jq not found in /usr/bin, /opt/homebrew/bin, or /usr/local/bin"
    end if

    -- Read and parse JSON fields
    try
        -- Extract name (required)
        set projectName to do shell script jqPath & " -r '.name // empty' " & quoted form of jsonFilePath
        if projectName is "" then
            return "ERROR: Missing required field 'name' in JSON"
        end if

        -- Extract notes (optional, default empty)
        set projectNotes to do shell script jqPath & " -r '.notes // \"\"' " & quoted form of jsonFilePath

        -- Extract area (optional)
        set areaName to do shell script jqPath & " -r '.area // empty' " & quoted form of jsonFilePath

    on error errMsg
        return "ERROR: Failed to parse JSON: " & errMsg
    end try

    -- Create the project in Things 3
    try
        tell application "Things3"
            -- Create new project
            if areaName is "" then
                set newProject to make new project with properties {name:projectName, notes:projectNotes}
            else
                -- Try to find the area
                try
                    set targetArea to area areaName
                    set newProject to make new project with properties {name:projectName, notes:projectNotes, area:targetArea}
                on error
                    -- Area not found, create project without area
                    set newProject to make new project with properties {name:projectName, notes:projectNotes}
                end try
            end if

            -- Return the project ID
            return id of newProject
        end tell
    on error errMsg
        return "ERROR: Failed to create project in Things: " & errMsg
    end try
end run
```

### Step 2: Make script executable

Run:
```bash
chmod +x scripts/things-bridge/create-project.scpt
```

Expected: No output

### Step 3: Test with a sample JSON file

Create test file:
```bash
echo '{"name": "Test Project from Selene", "notes": "Created by create-project.scpt test"}' > /tmp/test-project.json
```

Run:
```bash
osascript scripts/things-bridge/create-project.scpt /tmp/test-project.json
```

Expected: Returns a Things project ID (like `ABC123-DEF456-...`)

### Step 4: Verify project exists in Things 3

Open Things 3 app and confirm "Test Project from Selene" appears. Delete it after verification.

### Step 5: Commit script

```bash
git add scripts/things-bridge/create-project.scpt
git commit -m "feat(things-bridge): add create-project.scpt for project creation

- Accepts JSON input with name, notes, area fields
- Returns Things project ID on success
- Follows same pattern as add-task-to-things.scpt"
```

---

## Task 3: Create AppleScript assign-to-project.scpt

**Files:**
- Create: `scripts/things-bridge/assign-to-project.scpt`
- Test: Manual AppleScript execution

### Step 1: Write the AppleScript

Create `scripts/things-bridge/assign-to-project.scpt`:

```applescript
#!/usr/bin/osascript
-- assign-to-project.scpt
-- Moves a task to a project in Things 3
--
-- Usage: osascript assign-to-project.scpt <task_id> <project_id>
--
-- Arguments:
--   task_id    - The Things ID of the task to move
--   project_id - The Things ID of the target project
--
-- Returns: "SUCCESS" on success, or error message on failure

on run argv
    -- Validate arguments
    if (count of argv) < 2 then
        return "ERROR: Missing arguments. Usage: assign-to-project.scpt <task_id> <project_id>"
    end if

    set taskId to item 1 of argv
    set projectId to item 2 of argv

    -- Validate IDs are not empty
    if taskId is "" then
        return "ERROR: task_id cannot be empty"
    end if
    if projectId is "" then
        return "ERROR: project_id cannot be empty"
    end if

    -- Move task to project in Things 3
    try
        tell application "Things3"
            -- Find the task by ID
            set targetTask to to do id taskId

            -- Find the project by ID
            set targetProject to project id projectId

            -- Move task to project
            move targetTask to targetProject

            return "SUCCESS"
        end tell
    on error errMsg
        return "ERROR: Failed to assign task to project: " & errMsg
    end try
end run
```

### Step 2: Make script executable

Run:
```bash
chmod +x scripts/things-bridge/assign-to-project.scpt
```

Expected: No output

### Step 3: Test with real Things IDs (manual)

First, get a task ID and project ID from Things:
1. Create a test task in Things Inbox
2. Create a test project in Things
3. Use AppleScript to get their IDs (or note them from Things URL scheme)

Run (with your actual IDs):
```bash
osascript scripts/things-bridge/assign-to-project.scpt "TASK-ID-HERE" "PROJECT-ID-HERE"
```

Expected: `SUCCESS`

### Step 4: Verify task moved in Things 3

Open Things 3 app and confirm task is now inside the project.

### Step 5: Commit script

```bash
git add scripts/things-bridge/assign-to-project.scpt
git commit -m "feat(things-bridge): add assign-to-project.scpt for task-project assignment

- Moves existing task to target project
- Takes task_id and project_id as arguments
- Returns SUCCESS or detailed error message"
```

---

## Task 4: Create Workflow 08 Directory Structure

**Files:**
- Create: `workflows/08-project-detection/workflow.json`
- Create: `workflows/08-project-detection/README.md`
- Create: `workflows/08-project-detection/docs/STATUS.md`
- Create: `workflows/08-project-detection/scripts/test-with-markers.sh`

### Step 1: Create directory structure

Run:
```bash
mkdir -p workflows/08-project-detection/docs
mkdir -p workflows/08-project-detection/scripts
```

Expected: No output

### Step 2: Create README.md

Create `workflows/08-project-detection/README.md`:

```markdown
# Workflow 08: Project Detection & Creation

## Purpose

Automatically groups tasks into Things projects when 3+ tasks share a concept.

## Trigger

- **Daily Schedule:** 8:00 AM local time
- **Manual Webhook:** POST `/webhook/project-detection`

## Process Flow

1. Query task_metadata for concept clusters (3+ tasks sharing concept)
2. For each cluster without existing project:
   - Call Ollama to generate human-readable project name
   - Create project in Things via AppleScript
   - Move tasks to project
   - Calculate energy profile from task aggregation
3. Store project_metadata in SQLite
4. Log results to integration_logs

## Dependencies

- Workflow 07 (Task Extraction) must have created tasks
- Things 3 running on macOS
- Ollama with mistral:7b model

## Testing

```bash
./workflows/08-project-detection/scripts/test-with-markers.sh
```

## Files

- `workflow.json` - n8n workflow definition
- `docs/STATUS.md` - Current status and test results
- `scripts/test-with-markers.sh` - Automated test script
```

### Step 3: Create docs/STATUS.md

Create `workflows/08-project-detection/docs/STATUS.md`:

```markdown
# Workflow 08: Project Detection - Status

**Last Updated:** 2026-01-01
**Status:** In Development

## Test Results

| Test Case | Status | Notes |
|-----------|--------|-------|
| Concept cluster detection | Pending | |
| Project name generation | Pending | |
| Things project creation | Pending | |
| Task assignment | Pending | |
| Energy profile calculation | Pending | |
| Duplicate project prevention | Pending | |

## Known Issues

None yet.

## Change Log

- 2026-01-01: Initial creation
```

### Step 4: Create scripts/test-with-markers.sh

Create `workflows/08-project-detection/scripts/test-with-markers.sh`:

```bash
#!/bin/bash
# Test script for Workflow 08: Project Detection
# Usage: ./test-with-markers.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DB_PATH="$PROJECT_ROOT/data/selene.db"
WEBHOOK_URL="http://localhost:5678/webhook/project-detection"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Setup: Create test tasks with shared concept
setup_test_data() {
    log_info "Creating test data with marker: $TEST_RUN"

    # Insert 3 tasks with shared concept "website-redesign"
    sqlite3 "$DB_PATH" "
        INSERT INTO task_metadata (raw_note_id, things_task_id, energy_required, estimated_minutes, related_concepts, task_type, test_run)
        VALUES
            (1, 'test-task-1-$TEST_RUN', 'high', 60, '[\"website-redesign\", \"frontend\"]', 'action', '$TEST_RUN'),
            (2, 'test-task-2-$TEST_RUN', 'medium', 30, '[\"website-redesign\", \"design\"]', 'research', '$TEST_RUN'),
            (3, 'test-task-3-$TEST_RUN', 'low', 15, '[\"website-redesign\", \"content\"]', 'action', '$TEST_RUN');
    "

    log_info "Created 3 test tasks with shared concept 'website-redesign'"
}

# Test 1: Trigger workflow
test_workflow_trigger() {
    log_info "Test 1: Triggering project detection workflow"

    RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"test_run\": \"$TEST_RUN\"}")

    if echo "$RESPONSE" | grep -q "error"; then
        log_error "Workflow returned error: $RESPONSE"
        return 1
    fi

    log_info "Workflow triggered successfully"
}

# Test 2: Verify project created
test_project_created() {
    log_info "Test 2: Verifying project_metadata created"

    COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM project_metadata WHERE test_run = '$TEST_RUN';")

    if [ "$COUNT" -eq 0 ]; then
        log_error "No project created for test run"
        return 1
    fi

    PROJECT_NAME=$(sqlite3 "$DB_PATH" "SELECT project_name FROM project_metadata WHERE test_run = '$TEST_RUN' LIMIT 1;")
    log_info "Project created: $PROJECT_NAME"
}

# Test 3: Verify energy profile calculated
test_energy_profile() {
    log_info "Test 3: Verifying energy profile calculated"

    ENERGY=$(sqlite3 "$DB_PATH" "SELECT energy_profile FROM project_metadata WHERE test_run = '$TEST_RUN' LIMIT 1;")

    if [ -z "$ENERGY" ]; then
        log_error "Energy profile not calculated"
        return 1
    fi

    log_info "Energy profile: $ENERGY"
}

# Cleanup
cleanup() {
    log_info "Cleaning up test data"
    sqlite3 "$DB_PATH" "DELETE FROM task_metadata WHERE test_run = '$TEST_RUN';"
    sqlite3 "$DB_PATH" "DELETE FROM project_metadata WHERE test_run = '$TEST_RUN';"
    log_info "Cleanup complete"
}

# Main
main() {
    log_info "Starting Workflow 08 tests with marker: $TEST_RUN"
    echo ""

    setup_test_data

    # Run tests
    test_workflow_trigger || { cleanup; exit 1; }
    sleep 2  # Wait for workflow to complete
    test_project_created || { cleanup; exit 1; }
    test_energy_profile || { cleanup; exit 1; }

    echo ""
    log_info "All tests passed!"

    # Prompt for cleanup
    read -p "Cleanup test data? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    else
        log_warn "Test data retained with marker: $TEST_RUN"
    fi
}

main "$@"
```

### Step 5: Make test script executable

Run:
```bash
chmod +x workflows/08-project-detection/scripts/test-with-markers.sh
```

Expected: No output

### Step 6: Commit directory structure

```bash
git add workflows/08-project-detection/
git commit -m "feat(08): add workflow directory structure for project detection

- README with workflow overview
- STATUS.md for tracking test results
- test-with-markers.sh for automated testing"
```

---

## Task 5: Create Workflow 08 JSON - Query Concept Clusters

**Files:**
- Modify: `workflows/08-project-detection/workflow.json`

### Step 1: Create initial workflow with webhook and cluster query

Create `workflows/08-project-detection/workflow.json`:

```json
{
  "name": "08-Project-Detection",
  "active": true,
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "project-detection",
        "responseMode": "onReceived",
        "options": {}
      },
      "id": "webhook-trigger",
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "position": [250, 300],
      "webhookId": "selene-project-detection-webhook"
    },
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "hours",
              "triggerAtHour": 8
            }
          ]
        }
      },
      "id": "schedule-trigger",
      "name": "Daily 8AM Trigger",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1.2,
      "position": [250, 500]
    },
    {
      "parameters": {
        "functionCode": "const db = require('better-sqlite3')('/selene/data/selene.db');\n\ntry {\n  const body = $input.item.json.body || $input.item.json;\n  const testRun = body.test_run || null;\n\n  // Build WHERE clause for test isolation\n  const testCondition = testRun ? `AND tm.test_run = '${testRun}'` : 'AND tm.test_run IS NULL';\n\n  // Query for concept clusters with 3+ tasks not yet in a project\n  const query = `\n    WITH concept_counts AS (\n      SELECT \n        json_each.value as concept,\n        COUNT(DISTINCT tm.id) as task_count,\n        GROUP_CONCAT(tm.things_task_id) as task_ids,\n        GROUP_CONCAT(tm.energy_required) as energy_values,\n        SUM(tm.estimated_minutes) as total_minutes\n      FROM task_metadata tm,\n           json_each(tm.related_concepts)\n      WHERE tm.things_project_id IS NULL\n        ${testCondition}\n      GROUP BY json_each.value\n      HAVING COUNT(DISTINCT tm.id) >= 3\n    )\n    SELECT \n      cc.concept,\n      cc.task_count,\n      cc.task_ids,\n      cc.energy_values,\n      cc.total_minutes,\n      CASE \n        WHEN pm.id IS NOT NULL THEN 1\n        ELSE 0\n      END as project_exists\n    FROM concept_counts cc\n    LEFT JOIN project_metadata pm ON pm.primary_concept = cc.concept\n      AND (pm.test_run = '${testRun}' OR (pm.test_run IS NULL AND '${testRun}' IS NULL))\n    WHERE pm.id IS NULL\n    ORDER BY cc.task_count DESC\n  `;\n\n  const clusters = db.prepare(query).all();\n\n  console.log('[Query Clusters] Found', clusters.length, 'concept clusters needing projects');\n\n  if (clusters.length === 0) {\n    return {\n      json: {\n        clusters: [],\n        message: 'No concept clusters found needing projects',\n        test_run: testRun\n      }\n    };\n  }\n\n  return {\n    json: {\n      clusters: clusters,\n      cluster_count: clusters.length,\n      test_run: testRun\n    }\n  };\n} finally {\n  db.close();\n}"
      },
      "id": "query-clusters",
      "name": "Query Concept Clusters",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [500, 400]
    },
    {
      "parameters": {
        "conditions": {
          "number": [
            {
              "value1": "={{ $json.cluster_count }}",
              "operation": "largerEqual",
              "value2": 1
            }
          ]
        }
      },
      "id": "check-clusters-exist",
      "name": "Clusters Found?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [700, 400]
    },
    {
      "parameters": {
        "fieldToSplitOut": "clusters",
        "options": {}
      },
      "id": "split-clusters",
      "name": "Split Clusters",
      "type": "n8n-nodes-base.splitOut",
      "typeVersion": 1,
      "position": [900, 300]
    }
  ],
  "connections": {
    "Webhook Trigger": {
      "main": [[{ "node": "Query Concept Clusters", "type": "main", "index": 0 }]]
    },
    "Daily 8AM Trigger": {
      "main": [[{ "node": "Query Concept Clusters", "type": "main", "index": 0 }]]
    },
    "Query Concept Clusters": {
      "main": [[{ "node": "Clusters Found?", "type": "main", "index": 0 }]]
    },
    "Clusters Found?": {
      "main": [
        [{ "node": "Split Clusters", "type": "main", "index": 0 }],
        []
      ]
    }
  },
  "settings": {
    "executionOrder": "v1",
    "saveExecutionProgress": true,
    "saveManualExecutions": true,
    "executionTimeout": 300,
    "timezone": "America/Los_Angeles"
  },
  "staticData": null,
  "tags": [
    {
      "name": "Selene",
      "id": "selene-tag"
    }
  ],
  "triggerCount": 0,
  "updatedAt": "2026-01-01T00:00:00.000Z",
  "versionId": "1"
}
```

### Step 2: Verify JSON is valid

Run:
```bash
cat workflows/08-project-detection/workflow.json | jq . > /dev/null && echo "Valid JSON"
```

Expected: `Valid JSON`

### Step 3: Commit initial workflow

```bash
git add workflows/08-project-detection/workflow.json
git commit -m "feat(08): add initial workflow with cluster query

- Webhook and schedule triggers
- Query for concepts with 3+ unassigned tasks
- Split clusters for iteration"
```

---

## Task 6: Add LLM Prompt for Project Name Generation

**Files:**
- Modify: `workflows/08-project-detection/workflow.json`

### Step 1: Add Build Project Name Prompt node

Add this node to the `nodes` array in workflow.json (after Split Clusters):

```json
{
  "parameters": {
    "functionCode": "const cluster = $input.item.json;\n\nconsole.log('[Build Name Prompt] Processing concept:', cluster.concept);\n\n// Get task titles for context\nconst taskIds = cluster.task_ids.split(',');\n\nconst prompt = `You are a project naming assistant for an ADHD-optimized productivity system.\n\nGenerate a clear, human-readable project name for a group of related tasks.\n\n## INPUT\n\nConcept: ${cluster.concept}\nTask Count: ${cluster.task_count}\nTotal Estimated Time: ${cluster.total_minutes} minutes\n\n## REQUIREMENTS\n\n1. Name should be 2-5 words\n2. Use active, descriptive language\n3. Avoid generic terms like \"Project\" or \"Tasks\"\n4. Make it specific enough to distinguish from other projects\n5. Use title case\n\n## EXAMPLES\n\nConcept: website-redesign -> \"Website Redesign Sprint\"\nConcept: tax-prep -> \"Q4 Tax Preparation\"\nConcept: home-renovation -> \"Kitchen Renovation\"\nConcept: learning-python -> \"Python Fundamentals\"\n\n## OUTPUT FORMAT\n\nReturn ONLY valid JSON with no additional text:\n\n{\n  \"project_name\": \"Your Project Name Here\"\n}\n\nBEGIN:`;\n\nreturn {\n  json: {\n    ...cluster,\n    name_prompt: prompt\n  }\n};"
  },
  "id": "build-name-prompt",
  "name": "Build Project Name Prompt",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [1100, 300]
}
```

### Step 2: Add Ollama HTTP Request node

Add this node after Build Project Name Prompt:

```json
{
  "parameters": {
    "method": "POST",
    "url": "http://host.docker.internal:11434/api/generate",
    "options": {
      "timeout": 30000
    },
    "sendBody": true,
    "specifyBody": "json",
    "jsonBody": "={{ {\n  \"model\": \"mistral:7b\",\n  \"prompt\": $json.name_prompt,\n  \"stream\": false,\n  \"format\": \"json\",\n  \"options\": {\n    \"temperature\": 0.7,\n    \"num_predict\": 100\n  }\n} }}"
  },
  "id": "ollama-generate-name",
  "name": "Ollama Generate Name",
  "type": "n8n-nodes-base.httpRequest",
  "typeVersion": 3,
  "position": [1300, 300]
}
```

### Step 3: Add Parse Project Name node

Add this node after Ollama:

```json
{
  "parameters": {
    "functionCode": "const response = $input.item.json.response;\nconst clusterData = $('Build Project Name Prompt').first().json;\n\nconsole.log('[Parse Name] Raw response:', response);\n\nlet projectName = clusterData.concept.replace(/-/g, ' ').replace(/\\b\\w/g, l => l.toUpperCase());\n\ntry {\n  const parsed = JSON.parse(response);\n  if (parsed.project_name && parsed.project_name.trim()) {\n    projectName = parsed.project_name.trim();\n  }\n} catch (e) {\n  console.warn('[Parse Name] Failed to parse, using fallback:', e.message);\n}\n\nconsole.log('[Parse Name] Final name:', projectName);\n\nreturn {\n  json: {\n    concept: clusterData.concept,\n    project_name: projectName,\n    task_ids: clusterData.task_ids,\n    task_count: clusterData.task_count,\n    energy_values: clusterData.energy_values,\n    total_minutes: clusterData.total_minutes,\n    test_run: clusterData.test_run\n  }\n};"
  },
  "id": "parse-project-name",
  "name": "Parse Project Name",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [1500, 300]
}
```

### Step 4: Update connections

Add these connections:
```json
"Split Clusters": {
  "main": [[{ "node": "Build Project Name Prompt", "type": "main", "index": 0 }]]
},
"Build Project Name Prompt": {
  "main": [[{ "node": "Ollama Generate Name", "type": "main", "index": 0 }]]
},
"Ollama Generate Name": {
  "main": [[{ "node": "Parse Project Name", "type": "main", "index": 0 }]]
}
```

### Step 5: Verify JSON is valid

Run:
```bash
cat workflows/08-project-detection/workflow.json | jq . > /dev/null && echo "Valid JSON"
```

Expected: `Valid JSON`

### Step 6: Commit LLM integration

```bash
git add workflows/08-project-detection/workflow.json
git commit -m "feat(08): add LLM project name generation

- Build prompt with concept and task count
- Ollama generates human-readable project name
- Parse response with fallback to formatted concept"
```

---

## Task 7: Add Project Creation via AppleScript

**Files:**
- Modify: `workflows/08-project-detection/workflow.json`

### Step 1: Add Prepare Project JSON node

Add this node after Parse Project Name:

```json
{
  "parameters": {
    "functionCode": "const data = $input.item.json;\n\nconsole.log('[Prepare Project] Creating project:', data.project_name);\n\nconst timestamp = Date.now();\nconst random = Math.floor(Math.random() * 10000);\nconst filename = `project-${timestamp}-${random}.json`;\n\nconst projectJson = {\n  name: data.project_name,\n  notes: `Selene Project\\n\\nConcept: ${data.concept}\\nTasks: ${data.task_count}\\nTotal Time: ${data.total_minutes} minutes\\n\\nCreated automatically from task grouping.`\n};\n\nconst filePath = `/tmp/${filename}`;\n\n// Write JSON to temp file\nconst fs = require('fs');\nfs.writeFileSync(filePath, JSON.stringify(projectJson, null, 2));\n\nconsole.log('[Prepare Project] Wrote JSON to:', filePath);\n\nreturn {\n  json: {\n    ...data,\n    project_json_path: filePath,\n    project_json: projectJson\n  }\n};"
  },
  "id": "prepare-project-json",
  "name": "Prepare Project JSON",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [1700, 300]
}
```

### Step 2: Add Execute AppleScript node

Add this node to create the project:

```json
{
  "parameters": {
    "command": "=osascript /selene/scripts/things-bridge/create-project.scpt {{ $json.project_json_path }}"
  },
  "id": "create-things-project",
  "name": "Create Things Project",
  "type": "n8n-nodes-base.executeCommand",
  "typeVersion": 1,
  "position": [1900, 300]
}
```

### Step 3: Add Parse Project ID node

Add this node to handle the AppleScript output:

```json
{
  "parameters": {
    "functionCode": "const stdout = $input.item.json.stdout;\nconst prevData = $('Prepare Project JSON').first().json;\n\nconsole.log('[Parse Project ID] AppleScript output:', stdout);\n\nif (stdout.startsWith('ERROR:')) {\n  throw new Error(stdout);\n}\n\nconst thingsProjectId = stdout.trim();\n\nconsole.log('[Parse Project ID] Things project ID:', thingsProjectId);\n\n// Clean up temp file\ntry {\n  const fs = require('fs');\n  fs.unlinkSync(prevData.project_json_path);\n} catch (e) {\n  console.warn('[Parse Project ID] Could not delete temp file:', e.message);\n}\n\nreturn {\n  json: {\n    things_project_id: thingsProjectId,\n    project_name: prevData.project_name,\n    concept: prevData.concept,\n    task_ids: prevData.task_ids,\n    task_count: prevData.task_count,\n    energy_values: prevData.energy_values,\n    total_minutes: prevData.total_minutes,\n    test_run: prevData.test_run\n  }\n};"
  },
  "id": "parse-project-id",
  "name": "Parse Project ID",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [2100, 300]
}
```

### Step 4: Update connections

```json
"Parse Project Name": {
  "main": [[{ "node": "Prepare Project JSON", "type": "main", "index": 0 }]]
},
"Prepare Project JSON": {
  "main": [[{ "node": "Create Things Project", "type": "main", "index": 0 }]]
},
"Create Things Project": {
  "main": [[{ "node": "Parse Project ID", "type": "main", "index": 0 }]]
}
```

### Step 5: Verify JSON is valid

Run:
```bash
cat workflows/08-project-detection/workflow.json | jq . > /dev/null && echo "Valid JSON"
```

Expected: `Valid JSON`

### Step 6: Commit project creation

```bash
git add workflows/08-project-detection/workflow.json
git commit -m "feat(08): add Things project creation via AppleScript

- Prepare JSON with project name and notes
- Execute create-project.scpt
- Parse Things project ID from output"
```

---

## Task 8: Add Task Assignment Loop

**Files:**
- Modify: `workflows/08-project-detection/workflow.json`

### Step 1: Add Split Task IDs node

Add this node after Parse Project ID:

```json
{
  "parameters": {
    "functionCode": "const data = $input.item.json;\n\n// Split task IDs into array for iteration\nconst taskIds = data.task_ids.split(',').map(id => id.trim());\n\nconsole.log('[Split Task IDs] Preparing to assign', taskIds.length, 'tasks to project');\n\n// Create array of items, each with task_id and project context\nconst items = taskIds.map(taskId => ({\n  task_id: taskId,\n  things_project_id: data.things_project_id,\n  project_name: data.project_name,\n  concept: data.concept,\n  test_run: data.test_run\n}));\n\nreturn items.map(item => ({ json: item }));"
  },
  "id": "split-task-ids",
  "name": "Split Task IDs",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [2300, 300]
}
```

### Step 2: Add Assign Task to Project node

Add execute command node:

```json
{
  "parameters": {
    "command": "=osascript /selene/scripts/things-bridge/assign-to-project.scpt {{ $json.task_id }} {{ $json.things_project_id }}"
  },
  "id": "assign-task",
  "name": "Assign Task to Project",
  "type": "n8n-nodes-base.executeCommand",
  "typeVersion": 1,
  "position": [2500, 300]
}
```

### Step 3: Add Update Task Metadata node

```json
{
  "parameters": {
    "functionCode": "const db = require('better-sqlite3')('/selene/data/selene.db');\n\ntry {\n  const data = $input.item.json;\n  const stdout = data.stdout;\n  const taskId = $('Split Task IDs').first().json.task_id;\n  const projectId = $('Split Task IDs').first().json.things_project_id;\n\n  console.log('[Update Task] Assign result:', stdout);\n\n  if (stdout && stdout.includes('SUCCESS')) {\n    db.prepare(`\n      UPDATE task_metadata\n      SET things_project_id = ?\n      WHERE things_task_id = ?\n    `).run(projectId, taskId);\n\n    console.log('[Update Task] Updated task', taskId, 'with project', projectId);\n  }\n\n  return {\n    json: {\n      task_id: taskId,\n      project_id: projectId,\n      assignment_result: stdout,\n      success: stdout && stdout.includes('SUCCESS')\n    }\n  };\n} finally {\n  db.close();\n}"
  },
  "id": "update-task-metadata",
  "name": "Update Task Metadata",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [2700, 300]
}
```

### Step 4: Update connections

```json
"Parse Project ID": {
  "main": [[{ "node": "Split Task IDs", "type": "main", "index": 0 }]]
},
"Split Task IDs": {
  "main": [[{ "node": "Assign Task to Project", "type": "main", "index": 0 }]]
},
"Assign Task to Project": {
  "main": [[{ "node": "Update Task Metadata", "type": "main", "index": 0 }]]
}
```

### Step 5: Verify JSON is valid

Run:
```bash
cat workflows/08-project-detection/workflow.json | jq . > /dev/null && echo "Valid JSON"
```

Expected: `Valid JSON`

### Step 6: Commit task assignment

```bash
git add workflows/08-project-detection/workflow.json
git commit -m "feat(08): add task assignment loop

- Split task IDs for iteration
- Assign each task to project via AppleScript
- Update task_metadata with things_project_id"
```

---

## Task 9: Add Energy Profile Calculation and Storage

**Files:**
- Modify: `workflows/08-project-detection/workflow.json`

### Step 1: Add Aggregate Results node

Add this node to merge assignment results:

```json
{
  "parameters": {
    "aggregate": "aggregateAllItemData",
    "destinationFieldName": "assignment_results",
    "options": {}
  },
  "id": "aggregate-results",
  "name": "Aggregate Results",
  "type": "n8n-nodes-base.aggregate",
  "typeVersion": 1,
  "position": [2900, 300]
}
```

### Step 2: Add Store Project Metadata node

```json
{
  "parameters": {
    "functionCode": "const db = require('better-sqlite3')('/selene/data/selene.db');\n\ntry {\n  const results = $input.item.json.assignment_results;\n  \n  // Get project data from earlier node\n  const projectData = $('Parse Project ID').first().json;\n\n  console.log('[Store Project] Storing project:', projectData.project_name);\n\n  // Calculate energy profile from task energy values\n  const energyValues = projectData.energy_values.split(',');\n  const energyCounts = { high: 0, medium: 0, low: 0 };\n  \n  energyValues.forEach(e => {\n    const normalized = e.trim().toLowerCase();\n    if (energyCounts.hasOwnProperty(normalized)) {\n      energyCounts[normalized]++;\n    }\n  });\n\n  const total = energyValues.length;\n  let energyProfile = 'mixed';\n  \n  if (energyCounts.high / total > 0.6) {\n    energyProfile = 'high';\n  } else if (energyCounts.low / total > 0.6) {\n    energyProfile = 'low';\n  }\n\n  console.log('[Store Project] Energy profile:', energyProfile, 'from', energyCounts);\n\n  // Insert project metadata\n  db.prepare(`\n    INSERT INTO project_metadata (\n      things_project_id,\n      project_name,\n      primary_concept,\n      energy_profile,\n      total_estimated_minutes,\n      task_count,\n      test_run\n    ) VALUES (?, ?, ?, ?, ?, ?, ?)\n  `).run(\n    projectData.things_project_id,\n    projectData.project_name,\n    projectData.concept,\n    energyProfile,\n    projectData.total_minutes,\n    projectData.task_count,\n    projectData.test_run || null\n  );\n\n  // Log to integration_logs\n  db.prepare(`\n    INSERT INTO integration_logs (workflow, event, success, metadata)\n    VALUES ('08-project-detection', 'project_created', 1, ?)\n  `).run(JSON.stringify({\n    project_name: projectData.project_name,\n    concept: projectData.concept,\n    task_count: projectData.task_count,\n    energy_profile: energyProfile\n  }));\n\n  console.log('[Store Project] Stored project metadata successfully');\n\n  return {\n    json: {\n      success: true,\n      things_project_id: projectData.things_project_id,\n      project_name: projectData.project_name,\n      concept: projectData.concept,\n      energy_profile: energyProfile,\n      task_count: projectData.task_count,\n      tasks_assigned: results.filter(r => r.success).length,\n      test_run: projectData.test_run\n    }\n  };\n} finally {\n  db.close();\n}"
  },
  "id": "store-project-metadata",
  "name": "Store Project Metadata",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [3100, 300]
}
```

### Step 3: Update connections

```json
"Update Task Metadata": {
  "main": [[{ "node": "Aggregate Results", "type": "main", "index": 0 }]]
},
"Aggregate Results": {
  "main": [[{ "node": "Store Project Metadata", "type": "main", "index": 0 }]]
}
```

### Step 4: Verify JSON is valid

Run:
```bash
cat workflows/08-project-detection/workflow.json | jq . > /dev/null && echo "Valid JSON"
```

Expected: `Valid JSON`

### Step 5: Commit energy profile and storage

```bash
git add workflows/08-project-detection/workflow.json
git commit -m "feat(08): add energy profile calculation and storage

- Aggregate task assignment results
- Calculate energy profile (>60% = high/low, else mixed)
- Store project_metadata with all fields
- Log to integration_logs"
```

---

## Task 10: Import Workflow to n8n and Test

**Files:**
- None (n8n operations)

### Step 1: Ensure n8n is running

Run:
```bash
docker-compose ps
```

Expected: `selene` container is `Up`

### Step 2: Import workflow to n8n

Run:
```bash
./scripts/manage-workflow.sh import workflows/08-project-detection/workflow.json
```

Expected: Workflow imported message with ID

### Step 3: Note the workflow ID

Run:
```bash
./scripts/manage-workflow.sh list | grep "08-Project"
```

Expected: Shows workflow ID (e.g., `ID: 8`)

### Step 4: Run test script

Run:
```bash
./workflows/08-project-detection/scripts/test-with-markers.sh
```

Expected: All tests pass

### Step 5: Update STATUS.md with results

Update `workflows/08-project-detection/docs/STATUS.md` with actual test results.

### Step 6: Commit final status

```bash
git add workflows/08-project-detection/docs/STATUS.md
git commit -m "docs(08): update STATUS.md with test results

- All test cases passing
- Workflow ready for integration testing"
```

---

## Task 11: Update cleanup-tests.sh for New Tables

**Files:**
- Modify: `scripts/cleanup-tests.sh`

### Step 1: Add project_metadata cleanup

Edit `scripts/cleanup-tests.sh` to include:

```bash
# Add to cleanup_test_run function:
sqlite3 "$DB_PATH" "DELETE FROM project_metadata WHERE test_run = '$test_run';"
```

### Step 2: Test cleanup script

Run:
```bash
./scripts/cleanup-tests.sh --list
```

Expected: Shows any remaining test runs

### Step 3: Commit cleanup update

```bash
git add scripts/cleanup-tests.sh
git commit -m "chore(scripts): add project_metadata to cleanup-tests.sh"
```

---

## Task 12: Final Integration Test

### Step 1: End-to-end test

1. Create 3+ notes in Drafts with shared concept (e.g., "home-renovation")
2. Run ingestion workflow (Workflow 01)
3. Run LLM processing (Workflow 02)
4. Run task extraction (Workflow 07)
5. Run project detection (Workflow 08)
6. Verify in Things 3 that project exists with tasks

### Step 2: Verify database state

Run:
```bash
sqlite3 data/selene.db "SELECT project_name, primary_concept, energy_profile, task_count FROM project_metadata WHERE test_run IS NULL ORDER BY created_at DESC LIMIT 5;"
```

### Step 3: Update BRANCH-STATUS.md

Update the branch status file to mark phase 7.2f.1 as complete.

### Step 4: Final commit

```bash
git add .
git commit -m "feat: complete Phase 7.2f.1 Basic Project Creation

- Database migration for project_metadata table
- AppleScripts for create-project and assign-to-project
- Workflow 08 with concept clustering and LLM naming
- Energy profile calculation from task aggregation
- Full test coverage with test_run markers"
```

---

## Summary

This plan implements Phase 7.2f.1 with the following deliverables:

1. **Database:** `project_metadata` table with concept linkage and ADHD optimization fields
2. **AppleScripts:** `create-project.scpt` and `assign-to-project.scpt`
3. **Workflow 08:** Full detection and creation pipeline
4. **LLM Integration:** Project name generation with Ollama
5. **Testing:** Comprehensive test script with markers

**Total estimated time:** 60-90 minutes for implementation

**Next phase:** 7.2f.2 will add auto-assignment for new tasks (modify Workflow 07).
