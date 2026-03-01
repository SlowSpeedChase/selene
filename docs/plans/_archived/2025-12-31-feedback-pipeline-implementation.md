# Feedback Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a feedback pipeline that captures `#selene-feedback` tagged notes, converts them to user stories, and auto-generates a backlog file.

**Architecture:** Ingestion workflow detects feedback tag, routes to separate table, processing workflow converts to user stories via Ollama, backlog generator writes markdown file.

**Tech Stack:** n8n workflows, SQLite, Ollama (mistral:7b), better-sqlite3, shell scripts

---

## Task 1: Database Migration - Add feedback_notes Table

**Files:**
- Create: `database/migrations/009_add_feedback_notes.sql`
- Modify: `database/schema.sql` (append new table)

**Step 1: Create migration file**

```sql
-- database/migrations/009_add_feedback_notes.sql
-- Migration: Add feedback_notes table for product feedback capture

CREATE TABLE IF NOT EXISTS feedback_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    processed_at TEXT,
    user_story TEXT,
    theme TEXT,
    cluster_id INTEGER,
    priority INTEGER DEFAULT 1,
    mention_count INTEGER DEFAULT 1,
    status TEXT DEFAULT 'open',
    implemented_pr TEXT,
    implemented_at TEXT,
    test_run TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_feedback_theme ON feedback_notes(theme);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedback_notes(status);
CREATE INDEX IF NOT EXISTS idx_feedback_cluster ON feedback_notes(cluster_id);
CREATE INDEX IF NOT EXISTS idx_feedback_test_run ON feedback_notes(test_run);
```

**Step 2: Apply migration**

Run: `sqlite3 data/selene.db < database/migrations/009_add_feedback_notes.sql`
Expected: No output (success)

**Step 3: Verify table exists**

Run: `sqlite3 data/selene.db ".schema feedback_notes"`
Expected: Shows CREATE TABLE statement

**Step 4: Update schema.sql**

Append the feedback_notes table definition to `database/schema.sql` for documentation.

**Step 5: Commit**

```bash
git add database/migrations/009_add_feedback_notes.sql database/schema.sql
git commit -m "feat(db): add feedback_notes table for product feedback

- Stores #selene-feedback tagged notes
- Supports user story conversion and clustering
- Includes test_run column for test isolation"
```

---

## Task 2: Modify Ingestion Workflow - Add Feedback Detection

**Files:**
- Modify: `workflows/01-ingestion/workflow.json`
- Modify: `workflows/01-ingestion/docs/STATUS.md`

**Step 1: Export current workflow**

Run: `./scripts/manage-workflow.sh export $(./scripts/manage-workflow.sh list | grep "01-Note-Ingestion" | awk '{print $1}')`
Expected: Backup created

**Step 2: Read current workflow.json**

Read `workflows/01-ingestion/workflow.json` to understand current structure.

**Step 3: Add feedback detection node**

After "Parse Note Data" node, add a new node to check for feedback tag:

```json
{
  "parameters": {
    "functionCode": "// Check if this is feedback for Selene itself\nconst noteData = $json;\nconst tags = noteData.tags || [];\nconst isFeedback = tags.includes('selene-feedback');\n\nreturn {\n  json: {\n    ...noteData,\n    isFeedback: isFeedback\n  }\n};"
  },
  "id": "check-feedback-tag",
  "name": "Check Feedback Tag",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [550, 300]
}
```

**Step 4: Add IF node to route feedback**

```json
{
  "parameters": {
    "conditions": {
      "boolean": [
        {
          "value1": "={{ $json.isFeedback }}",
          "value2": true
        }
      ]
    }
  },
  "id": "route-feedback",
  "name": "Is Feedback?",
  "type": "n8n-nodes-base.if",
  "typeVersion": 1,
  "position": [750, 300]
}
```

**Step 5: Add feedback insert node**

```json
{
  "parameters": {
    "functionCode": "const Database = require('better-sqlite3');\n\nconst noteData = $json;\n\ntry {\n  const db = new Database('/selene/data/selene.db');\n\n  // Check for duplicate feedback\n  const existing = db.prepare('SELECT id FROM feedback_notes WHERE content_hash = ?').get(noteData.contentHash);\n  \n  if (existing) {\n    // Increment mention count instead of inserting duplicate\n    db.prepare('UPDATE feedback_notes SET mention_count = mention_count + 1 WHERE id = ?').run(existing.id);\n    db.close();\n    return {\n      json: {\n        feedback_id: existing.id,\n        action: 'incremented_mention',\n        testRun: noteData.testRun\n      }\n    };\n  }\n\n  // Insert new feedback\n  const result = db.prepare(`\n    INSERT INTO feedback_notes (content, content_hash, created_at, test_run)\n    VALUES (?, ?, ?, ?)\n  `).run(\n    noteData.content,\n    noteData.contentHash,\n    noteData.timestamp,\n    noteData.testRun\n  );\n\n  db.close();\n\n  return {\n    json: {\n      feedback_id: result.lastInsertRowid,\n      action: 'inserted',\n      testRun: noteData.testRun\n    }\n  };\n\n} catch (error) {\n  console.error('Feedback insert error:', error);\n  throw new Error('Failed to insert feedback: ' + error.message);\n}"
  },
  "id": "insert-feedback",
  "name": "Insert Feedback Note",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [950, 200]
}
```

**Step 6: Update connections**

Modify the `connections` object to route:
- "Parse Note Data" → "Check Feedback Tag"
- "Check Feedback Tag" → "Is Feedback?"
- "Is Feedback?" (true) → "Insert Feedback Note"
- "Is Feedback?" (false) → "Check for Duplicate" (existing flow)

**Step 7: Update workflow in n8n**

Run: `./scripts/manage-workflow.sh update <workflow-id> workflows/01-ingestion/workflow.json`
Expected: "Workflow updated successfully"

**Step 8: Test feedback routing**

Run: `curl -X POST http://localhost:5678/webhook/api/drafts -H "Content-Type: application/json" -d '{"content": "The task suggestion felt wrong #selene-feedback", "test_run": "test-feedback-001"}'`
Expected: 200 OK

**Step 9: Verify feedback in database**

Run: `sqlite3 data/selene.db "SELECT * FROM feedback_notes WHERE test_run = 'test-feedback-001'"`
Expected: One row with the feedback content

**Step 10: Clean up test data**

Run: `sqlite3 data/selene.db "DELETE FROM feedback_notes WHERE test_run = 'test-feedback-001'"`

**Step 11: Update STATUS.md**

Record the new feedback routing feature and test results.

**Step 12: Commit**

```bash
git add workflows/01-ingestion/workflow.json workflows/01-ingestion/docs/STATUS.md
git commit -m "feat(01): add feedback tag detection and routing

- Detects #selene-feedback tag in incoming notes
- Routes feedback to separate feedback_notes table
- Increments mention_count for duplicate feedback
- Preserves test_run isolation"
```

---

## Task 3: Create Feedback Processing Workflow

**Files:**
- Create: `workflows/09-feedback-processing/workflow.json`
- Create: `workflows/09-feedback-processing/README.md`
- Create: `workflows/09-feedback-processing/docs/STATUS.md`
- Create: `workflows/09-feedback-processing/scripts/test-with-markers.sh`
- Create: `prompts/feedback/user-story-conversion.md`

**Step 1: Create directory structure**

```bash
mkdir -p workflows/09-feedback-processing/docs
mkdir -p workflows/09-feedback-processing/scripts
mkdir -p prompts/feedback
```

**Step 2: Create user story conversion prompt**

Create `prompts/feedback/user-story-conversion.md`:

```markdown
You are converting user feedback about the Selene app into user stories.

Input: Raw feedback text from the user.

Output: A JSON object with:
- user_story: "As a user, I want [X] so that [Y]" format
- theme: One of: "task-routing", "dashboard", "planning", "ui", "performance", "other"
- priority_hint: 1-3 based on severity/importance mentioned

Example input: "The task suggestion felt wrong - gave me a coding task when I said low energy"

Example output:
{
  "user_story": "As a user, I want energy levels to filter out high-cognitive tasks so I get appropriate suggestions when tired",
  "theme": "task-routing",
  "priority_hint": 2
}

Now convert this feedback:
{{feedback}}
```

**Step 3: Create workflow.json**

Create `workflows/09-feedback-processing/workflow.json`:

```json
{
  "name": "09-Feedback-Processing | Selene",
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "minutes",
              "minutesInterval": 5
            }
          ]
        }
      },
      "id": "schedule-trigger",
      "name": "Every 5 Minutes",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "functionCode": "const Database = require('better-sqlite3');\n\ntry {\n  const db = new Database('/selene/data/selene.db', { readonly: true });\n  \n  const unprocessed = db.prepare(`\n    SELECT id, content, created_at, test_run\n    FROM feedback_notes\n    WHERE processed_at IS NULL\n    ORDER BY created_at ASC\n    LIMIT 10\n  `).all();\n  \n  db.close();\n  \n  if (unprocessed.length === 0) {\n    return [];\n  }\n  \n  return unprocessed.map(row => ({ json: row }));\n  \n} catch (error) {\n  console.error('Query error:', error);\n  return [];\n}"
      },
      "id": "query-unprocessed",
      "name": "Query Unprocessed Feedback",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [450, 300]
    },
    {
      "parameters": {
        "functionCode": "const fs = require('fs');\n\nconst feedback = $json;\n\n// Read prompt template\nlet promptTemplate;\ntry {\n  promptTemplate = fs.readFileSync('/workflows/prompts/feedback/user-story-conversion.md', 'utf8');\n} catch (e) {\n  promptTemplate = `Convert this feedback to a user story in JSON format with user_story, theme, and priority_hint fields:\\n\\n{{feedback}}`;\n}\n\nconst prompt = promptTemplate.replace('{{feedback}}', feedback.content);\n\nreturn {\n  json: {\n    ...feedback,\n    prompt: prompt\n  }\n};"
      },
      "id": "build-prompt",
      "name": "Build LLM Prompt",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [650, 300]
    },
    {
      "parameters": {
        "url": "http://host.docker.internal:11434/api/generate",
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ model: 'mistral:7b', prompt: $json.prompt, stream: false, format: 'json' }) }}",
        "options": {
          "timeout": 60000
        }
      },
      "id": "call-ollama",
      "name": "Send to Ollama",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [850, 300]
    },
    {
      "parameters": {
        "functionCode": "const feedback = $('Build LLM Prompt').item.json;\nconst ollamaResponse = $json;\n\ntry {\n  const parsed = JSON.parse(ollamaResponse.response);\n  \n  return {\n    json: {\n      id: feedback.id,\n      content: feedback.content,\n      test_run: feedback.test_run,\n      user_story: parsed.user_story || 'Failed to generate user story',\n      theme: parsed.theme || 'other',\n      priority: parsed.priority_hint || 1\n    }\n  };\n} catch (error) {\n  console.error('Parse error:', error);\n  return {\n    json: {\n      id: feedback.id,\n      content: feedback.content,\n      test_run: feedback.test_run,\n      user_story: 'As a user, I want ' + feedback.content.substring(0, 100),\n      theme: 'other',\n      priority: 1\n    }\n  };\n}"
      },
      "id": "parse-response",
      "name": "Parse LLM Response",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [1050, 300]
    },
    {
      "parameters": {
        "functionCode": "const Database = require('better-sqlite3');\n\nconst data = $json;\n\ntry {\n  const db = new Database('/selene/data/selene.db');\n  \n  db.prepare(`\n    UPDATE feedback_notes\n    SET user_story = ?,\n        theme = ?,\n        priority = ?,\n        processed_at = datetime('now')\n    WHERE id = ?\n  `).run(\n    data.user_story,\n    data.theme,\n    data.priority,\n    data.id\n  );\n  \n  db.close();\n  \n  return {\n    json: {\n      id: data.id,\n      success: true,\n      user_story: data.user_story,\n      theme: data.theme\n    }\n  };\n  \n} catch (error) {\n  console.error('Update error:', error);\n  throw error;\n}"
      },
      "id": "update-feedback",
      "name": "Update Feedback Record",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [1250, 300]
    }
  ],
  "connections": {
    "Every 5 Minutes": {
      "main": [
        [
          {
            "node": "Query Unprocessed Feedback",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Query Unprocessed Feedback": {
      "main": [
        [
          {
            "node": "Build LLM Prompt",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Build LLM Prompt": {
      "main": [
        [
          {
            "node": "Send to Ollama",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Send to Ollama": {
      "main": [
        [
          {
            "node": "Parse LLM Response",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Parse LLM Response": {
      "main": [
        [
          {
            "node": "Update Feedback Record",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "settings": {
    "executionOrder": "v1"
  },
  "staticData": null,
  "tags": []
}
```

**Step 4: Create README.md**

Create `workflows/09-feedback-processing/README.md`:

```markdown
# 09-Feedback-Processing Workflow

Processes feedback notes tagged with `#selene-feedback`, converting them to user stories via Ollama.

## Trigger

Runs every 5 minutes, processing up to 10 unprocessed feedback notes per run.

## Flow

1. Query `feedback_notes` where `processed_at IS NULL`
2. Build prompt from template
3. Send to Ollama for user story conversion
4. Parse JSON response
5. Update `feedback_notes` with user_story, theme, priority

## Testing

```bash
./scripts/test-with-markers.sh
```

## Configuration

- Ollama model: mistral:7b
- Prompt template: `prompts/feedback/user-story-conversion.md`
```

**Step 5: Create STATUS.md**

Create `workflows/09-feedback-processing/docs/STATUS.md`:

```markdown
# 09-Feedback-Processing Status

**Last Updated:** 2025-12-31
**Status:** In Development

## Test Results

| Test | Status | Notes |
|------|--------|-------|
| Basic feedback processing | Not tested | |
| Theme detection | Not tested | |
| Priority assignment | Not tested | |
| Duplicate handling | Not tested | |

## Change Log

- 2025-12-31: Initial creation
```

**Step 6: Create test script**

Create `workflows/09-feedback-processing/scripts/test-with-markers.sh`:

```bash
#!/bin/bash

set -e

TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
echo "Test run ID: $TEST_RUN"

# Insert test feedback
echo "Inserting test feedback..."
sqlite3 data/selene.db "INSERT INTO feedback_notes (content, content_hash, test_run) VALUES ('The task suggestion felt wrong when I was tired #selene-feedback', 'test-hash-$TEST_RUN', '$TEST_RUN')"

echo "Waiting for processing (manual trigger required or wait 5 min)..."
echo ""
echo "To manually trigger, run the workflow in n8n UI or wait for schedule"
echo ""
echo "To verify results:"
echo "sqlite3 data/selene.db \"SELECT * FROM feedback_notes WHERE test_run = '$TEST_RUN'\""
echo ""
echo "To cleanup:"
echo "sqlite3 data/selene.db \"DELETE FROM feedback_notes WHERE test_run = '$TEST_RUN'\""
```

**Step 7: Make test script executable**

Run: `chmod +x workflows/09-feedback-processing/scripts/test-with-markers.sh`

**Step 8: Import workflow to n8n**

Run: `./scripts/manage-workflow.sh import workflows/09-feedback-processing/workflow.json`
Expected: Workflow imported with new ID

**Step 9: Commit**

```bash
git add workflows/09-feedback-processing/ prompts/feedback/
git commit -m "feat(09): add feedback processing workflow

- Processes #selene-feedback notes every 5 minutes
- Converts raw feedback to user stories via Ollama
- Detects theme and assigns priority
- Updates feedback_notes table with results"
```

---

## Task 4: Create Backlog Generator Script

**Files:**
- Create: `scripts/generate-backlog.sh`
- Modify: `docs/backlog/user-stories.md` (auto-generated output)

**Step 1: Create generator script**

Create `scripts/generate-backlog.sh`:

```bash
#!/bin/bash

# Generate user-stories.md from feedback_notes table
# Run manually or via cron/launchd

set -e

DB_PATH="${SELENE_DB_PATH:-data/selene.db}"
OUTPUT_PATH="docs/backlog/user-stories.md"

# Query all open feedback grouped by theme
generate_backlog() {
    cat << 'HEADER'
# Selene Backlog

Last updated: $(date -u +"%Y-%m-%d %H:%M UTC")

*This file is auto-generated from #selene-feedback notes. Do not edit manually.*

---

HEADER

    # Get themes
    themes=$(sqlite3 "$DB_PATH" "SELECT DISTINCT theme FROM feedback_notes WHERE status = 'open' AND test_run IS NULL ORDER BY theme")

    if [ -z "$themes" ]; then
        echo "## Open Stories"
        echo ""
        echo "*No feedback captured yet. Start using Selene and log your thoughts!*"
        echo ""
    else
        for theme in $themes; do
            # Count stories in theme
            count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM feedback_notes WHERE theme = '$theme' AND status = 'open' AND test_run IS NULL")

            echo "## ${theme^} ($count stories)"
            echo ""

            # Get stories for theme
            sqlite3 -separator '|' "$DB_PATH" "
                SELECT id, user_story, priority, mention_count, date(created_at)
                FROM feedback_notes
                WHERE theme = '$theme' AND status = 'open' AND test_run IS NULL
                ORDER BY priority DESC, mention_count DESC
            " | while IFS='|' read -r id story priority mentions created; do
                stars=$(printf '★%.0s' $(seq 1 $priority))
                echo "### $stars $(echo "$story" | head -c 50)..."
                echo "$story"
                echo ""
                echo "- Priority: $priority"
                echo "- Mentions: $mentions"
                echo "- Created: $created"
                echo "- ID: feedback-$id"
                echo ""
            done
        done
    fi

    echo "---"
    echo ""
    echo "## Completed"
    echo ""

    # Get completed stories
    completed=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM feedback_notes WHERE status = 'implemented' AND test_run IS NULL")

    if [ "$completed" -eq 0 ]; then
        echo "*Stories move here after implementation.*"
    else
        sqlite3 -separator '|' "$DB_PATH" "
            SELECT user_story, implemented_pr, date(implemented_at)
            FROM feedback_notes
            WHERE status = 'implemented' AND test_run IS NULL
            ORDER BY implemented_at DESC
            LIMIT 10
        " | while IFS='|' read -r story pr date; do
            echo "### [$date] $(echo "$story" | head -c 50)..."
            echo "$story"
            echo ""
            echo "- Implemented in: $pr"
            echo ""
        done
    fi
}

# Generate and write
echo "Generating backlog..."
generate_backlog > "$OUTPUT_PATH"
echo "Backlog written to $OUTPUT_PATH"
```

**Step 2: Make script executable**

Run: `chmod +x scripts/generate-backlog.sh`

**Step 3: Test generator**

Run: `./scripts/generate-backlog.sh`
Expected: Updates docs/backlog/user-stories.md

**Step 4: Verify output**

Run: `cat docs/backlog/user-stories.md`
Expected: Shows formatted backlog (empty if no feedback yet)

**Step 5: Commit**

```bash
git add scripts/generate-backlog.sh docs/backlog/user-stories.md
git commit -m "feat(scripts): add backlog generator

- Reads feedback_notes table
- Groups by theme
- Sorts by priority and mention count
- Generates markdown backlog file
- Run manually: ./scripts/generate-backlog.sh"
```

---

## Task 5: Add Backlog Generation to Feedback Workflow

**Files:**
- Modify: `workflows/09-feedback-processing/workflow.json`

**Step 1: Export current workflow**

Run: `./scripts/manage-workflow.sh export <workflow-09-id>`

**Step 2: Add backlog generation node**

Add a final node that triggers the backlog generator after processing:

```json
{
  "parameters": {
    "functionCode": "const { execSync } = require('child_process');\n\ntry {\n  // Generate backlog file\n  execSync('/workflows/scripts/generate-backlog.sh', {\n    cwd: '/workflows',\n    encoding: 'utf8'\n  });\n  \n  return {\n    json: {\n      backlog_updated: true,\n      timestamp: new Date().toISOString()\n    }\n  };\n} catch (error) {\n  console.error('Backlog generation failed:', error);\n  return {\n    json: {\n      backlog_updated: false,\n      error: error.message\n    }\n  };\n}"
  },
  "id": "generate-backlog",
  "name": "Generate Backlog File",
  "type": "n8n-nodes-base.function",
  "typeVersion": 1,
  "position": [1450, 300]
}
```

**Step 3: Update connections**

Add connection from "Update Feedback Record" to "Generate Backlog File".

**Step 4: Update workflow in n8n**

Run: `./scripts/manage-workflow.sh update <workflow-09-id> workflows/09-feedback-processing/workflow.json`

**Step 5: Commit**

```bash
git add workflows/09-feedback-processing/workflow.json
git commit -m "feat(09): add automatic backlog generation

- Generates docs/backlog/user-stories.md after processing
- Triggers after each feedback batch"
```

---

## Task 6: End-to-End Test

**Step 1: Ensure Docker is running**

Run: `docker-compose ps`
Expected: selene container running

**Step 2: Ensure Ollama is running**

Run: `curl http://localhost:11434/api/tags`
Expected: JSON response with model list

**Step 3: Send test feedback**

Run:
```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"content": "The dashboard should show weekly themes not just daily #selene-feedback", "test_run": "e2e-test-001"}'
```
Expected: 200 OK

**Step 4: Verify feedback routed correctly**

Run: `sqlite3 data/selene.db "SELECT id, content FROM feedback_notes WHERE test_run = 'e2e-test-001'"`
Expected: One row with the feedback

**Step 5: Manually trigger processing**

In n8n UI, manually execute workflow 09-Feedback-Processing, or wait 5 minutes.

**Step 6: Verify user story generated**

Run: `sqlite3 data/selene.db "SELECT user_story, theme, priority FROM feedback_notes WHERE test_run = 'e2e-test-001'"`
Expected: user_story populated, theme assigned

**Step 7: Verify backlog updated**

Run: `cat docs/backlog/user-stories.md`
Expected: Shows the new story (if test_run filter removed for testing)

**Step 8: Clean up test data**

Run: `sqlite3 data/selene.db "DELETE FROM feedback_notes WHERE test_run = 'e2e-test-001'"`

**Step 9: Regenerate clean backlog**

Run: `./scripts/generate-backlog.sh`

**Step 10: Final commit**

```bash
git add -A
git commit -m "test(feedback): verify end-to-end feedback pipeline

- Feedback capture working
- LLM processing working
- Backlog generation working"
```

---

## Summary

After completing all tasks:

1. `#selene-feedback` notes route to `feedback_notes` table
2. Processing workflow converts to user stories every 5 minutes
3. Backlog file auto-generates after processing
4. Ready for review sessions: "let's look at the backlog"

**Next phases:**
- Phase B: Dashboard View (DashboardView.swift)
- Phase C: Direct Me Feature (ThingsQueryService.swift)
- Phase D: Enhanced Task Tagging
