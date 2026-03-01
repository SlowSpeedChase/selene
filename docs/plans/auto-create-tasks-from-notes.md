# Implementation Spec: Auto-Create Tasks from Notes

**Phase:** 7.1 - Task Extraction Foundation
**Status:** Ready for Implementation
**Created:** 2025-11-24
**Estimated Time:** 2 weeks
**Related:** [Things Integration Architecture](../architecture/things-integration.md), [Phase 7 Roadmap](../roadmap/16-PHASE-7-THINGS.md)

---

## Executive Summary

This document provides step-by-step implementation instructions for automatically extracting actionable tasks from Selene notes and creating them in Things 3 via MCP. This is the foundation of the Things integration and enables all future ADHD-optimized task management features.

**What we're building:**
- n8n workflow that extracts tasks from processed notes using Ollama LLM
- Database schema to store task metadata and enrichment
- Things MCP integration to create tasks in Things inbox
- ADHD-optimized task enrichment (energy, time estimates, overwhelm factor)

**Success criteria:**
- 80%+ of notes with action items → tasks created correctly
- Energy level assignments validated by user
- Zero duplicate tasks created
- Workflow completes in <30 seconds per note

---

## Prerequisites

### Required Components

**Already Installed:**
- ✅ n8n (running on Docker)
- ✅ Ollama (with mistral:7b model)
- ✅ SQLite database (`/Users/chaseeasterling/selene/data/selene.db`)
- ✅ Existing workflows 01-06

**Need to Install:**
- [ ] Things 3 app for macOS (from App Store)
- [ ] Things MCP server (via npx)
- [ ] Node.js (for npx, likely already installed)

**Permissions Needed:**
- [ ] Things 3 must grant accessibility permissions to AppleScript
- [ ] Claude Desktop config must include things-mcp server

---

## Step 1: Install Things MCP Server

### 1.1 Install Things 3

```bash
# If not already installed:
# 1. Open Mac App Store
# 2. Search for "Things 3"
# 3. Purchase and install ($49.99)
# 4. Launch Things to complete setup
```

### 1.2 Configure Claude Desktop for MCP

**File:** `~/Library/Application Support/Claude/claude_desktop_config.json`

```bash
# Create backup
cp ~/Library/Application\ Support/Claude/claude_desktop_config.json \
   ~/Library/Application\ Support/Claude/claude_desktop_config.json.backup

# Edit configuration
nano ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

**Add things-mcp server:**

```json
{
  "mcpServers": {
    "MCP_DOCKER": {
      "command": "docker",
      "args": ["mcp", "gateway", "run"]
    },
    "things-mcp": {
      "command": "npx",
      "args": ["-y", "github:hildersantos/things-mcp"]
    }
  }
}
```

**Restart Claude Desktop:**
```bash
# Quit Claude Desktop
# Relaunch from Applications
```

### 1.3 Test MCP Connection

**In Claude Desktop, test:**
```
Can you create a test task in Things called "MCP Test Task"?
```

Expected: Task appears in Things inbox

**Then test read:**
```
Can you read the task you just created?
```

Expected: Returns task details including ID

**Clean up:**
```
Can you delete the "MCP Test Task"?
```

---

## Step 2: Database Schema Changes

### 2.1 Create Migration Script

**File:** `/Users/chaseeasterling/selene/database/migrations/007_task_metadata.sql`

```sql
-- Migration 007: Task Metadata for Things Integration
-- Created: 2025-11-24
-- Phase: 7.1 - Task Extraction Foundation

BEGIN TRANSACTION;

-- Table: task_metadata
-- Stores relationship between Selene notes and Things tasks
-- Plus ADHD-optimized enrichment data
CREATE TABLE IF NOT EXISTS task_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Link to source note
    raw_note_id INTEGER NOT NULL,

    -- Things integration
    things_task_id TEXT NOT NULL UNIQUE, -- Things UUID from MCP
    things_project_id TEXT, -- NULL = inbox, otherwise project UUID

    -- ADHD-optimized enrichment (from Selene LLM analysis)
    energy_required TEXT CHECK(energy_required IN ('high', 'medium', 'low')),
    estimated_minutes INTEGER CHECK(estimated_minutes IN (5, 15, 30, 60, 120, 240)),
    related_concepts TEXT, -- JSON array of concept names
    related_themes TEXT, -- JSON array of theme names
    overwhelm_factor INTEGER CHECK(overwhelm_factor BETWEEN 1 AND 10),

    -- Task metadata extracted by LLM
    task_type TEXT CHECK(task_type IN ('action', 'decision', 'research', 'communication', 'learning', 'planning')),
    context_tags TEXT, -- JSON array: ["work", "personal", "urgent", "creative"]

    -- Timestamps
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    synced_at TEXT, -- Last time we read status from Things
    completed_at TEXT, -- When task was completed (from Things)

    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_metadata_note ON task_metadata(raw_note_id);
CREATE INDEX IF NOT EXISTS idx_task_metadata_things_id ON task_metadata(things_task_id);
CREATE INDEX IF NOT EXISTS idx_task_metadata_energy ON task_metadata(energy_required);
CREATE INDEX IF NOT EXISTS idx_task_metadata_completed ON task_metadata(completed_at);

-- Extend existing tables
ALTER TABLE raw_notes ADD COLUMN tasks_extracted BOOLEAN DEFAULT 0;
ALTER TABLE raw_notes ADD COLUMN tasks_extracted_at TEXT;

ALTER TABLE processed_notes ADD COLUMN things_integration_status TEXT
    CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))
    DEFAULT 'pending';

-- Migration tracking
INSERT INTO schema_version (version, description, applied_at)
VALUES (7, 'Task metadata for Things integration', CURRENT_TIMESTAMP);

COMMIT;
```

### 2.2 Apply Migration

```bash
# Navigate to database directory
cd /Users/chaseeasterling/selene/database

# Apply migration
sqlite3 ../data/selene.db < migrations/007_task_metadata.sql

# Verify
sqlite3 ../data/selene.db "SELECT name FROM sqlite_master WHERE type='table' AND name='task_metadata';"
# Should output: task_metadata

# Check columns
sqlite3 ../data/selene.db "PRAGMA table_info(task_metadata);"
# Should show all columns defined above
```

---

## Step 3: Create Ollama Prompt for Task Extraction

### 3.1 Prompt Design

**File:** `/Users/chaseeasterling/selene/workflows/07-task-extraction/task-extraction-prompt.txt`

```
You are a task extraction assistant for an ADHD-optimized productivity system.

Analyze the following note and extract actionable tasks. Be thorough but realistic.

INPUT:
Note Content: {content}
Energy Level: {energy_level}
Concepts: {concepts}
Themes: {themes}
Emotional Tone: {emotional_tone}
ADHD Markers: {adhd_markers}

INSTRUCTIONS:
1. Extract ONLY actionable tasks (things the person can DO)
2. Each task should be specific and start with a verb
3. Do NOT extract vague intentions ("I should..." → skip unless it becomes "Do X")
4. Do NOT extract questions unless they require research action
5. If note has no actionable tasks, return empty array

For each task, provide:
- task_text: Clear, actionable description (start with verb, <80 characters)
- energy_required: high/medium/low
  * high = creative work, learning, complex decisions, writing
  * medium = routine work, communication, light planning
  * low = organizing, simple responses, filing, sorting
- estimated_minutes: 5, 15, 30, 60, 120, or 240
  * Be realistic, ADHD users often underestimate
  * Add 25% buffer to initial estimates
- task_type: action/decision/research/communication/learning/planning
- context_tags: Array of relevant contexts (max 3)
  * Common: work, personal, home, creative, technical, social, urgent, deadline
- overwhelm_factor: 1-10 (how overwhelming this might feel)
  * 1-3 = Simple, clear, quick
  * 4-6 = Moderate complexity or time
  * 7-8 = Complex, vague, or emotionally difficult
  * 9-10 = Overwhelming, needs breakdown

ENERGY MATCHING:
- If note's energy_level is "high", bias tasks to "high" energy
- If note's energy_level is "low", bias tasks to "medium" or "low" energy
- If ADHD marker is "overwhelm", increase overwhelm_factor by 2

OUTPUT FORMAT (JSON only, no explanation):
[
  {
    "task_text": "Write project proposal draft",
    "energy_required": "high",
    "estimated_minutes": 60,
    "task_type": "action",
    "context_tags": ["work", "writing"],
    "overwhelm_factor": 6
  }
]

If no tasks: []

BEGIN ANALYSIS:
```

### 3.2 Test Prompt with Ollama

```bash
# Test the prompt manually
curl http://localhost:11434/api/generate -d '{
  "model": "mistral:7b",
  "prompt": "You are a task extraction assistant...[full prompt above with test data]",
  "stream": false,
  "format": "json"
}'
```

**Test Cases:**

**Test 1: Single clear task**
```json
{
  "content": "I need to email the client about the proposal deadline.",
  "energy_level": "medium",
  "concepts": ["communication", "work"],
  "themes": ["professional"],
  "emotional_tone": "neutral",
  "adhd_markers": ""
}
```
Expected output:
```json
[
  {
    "task_text": "Email client about proposal deadline",
    "energy_required": "medium",
    "estimated_minutes": 15,
    "task_type": "communication",
    "context_tags": ["work", "email"],
    "overwhelm_factor": 3
  }
]
```

**Test 2: Multiple tasks**
```json
{
  "content": "Excited to start the website redesign! Need to research competitors, create mockups, and set up the dev environment.",
  "energy_level": "high",
  "concepts": ["web-design", "creative"],
  "themes": ["project-start"],
  "emotional_tone": "excited",
  "adhd_markers": "hyperfocus"
}
```
Expected: 3 tasks extracted

**Test 3: No actionable tasks**
```json
{
  "content": "Feeling really overwhelmed today. Not sure what to do.",
  "energy_level": "low",
  "concepts": ["emotions"],
  "themes": ["stress"],
  "emotional_tone": "anxious",
  "adhd_markers": "overwhelm"
}
```
Expected: `[]` (empty array)

---

## Step 4: Create n8n Workflow

### 4.1 Workflow Overview

**Name:** `07-task-extraction`
**Trigger:** Webhook (called by workflow 05 after sentiment analysis)
**Nodes:** 8 total

**Flow:**
```
Webhook → Get Note Data → Ollama Extract → Parse JSON →
→ Split Out → Loop Tasks → Things Create → Store Metadata →
→ Update Status → Respond
```

### 4.2 Node Configuration

**Node 1: Webhook Trigger**
- **Type:** Webhook
- **Name:** Task Extraction Trigger
- **Path:** `task-extraction`
- **Method:** POST
- **Authentication:** None (internal workflow)
- **Response:** Immediately (don't wait)

**Expected Input:**
```json
{
  "raw_note_id": 123,
  "processed_note_id": 456
}
```

**Node 2: Get Note Data**
- **Type:** SQLite
- **Name:** Fetch Note for Task Extraction
- **Operation:** executeQuery
- **Query:**
```sql
SELECT
  rn.id as raw_note_id,
  rn.content,
  rn.tags,
  pn.energy_level,
  pn.concepts,
  pn.themes,
  pn.emotional_tone,
  sh.adhd_markers
FROM raw_notes rn
JOIN processed_notes pn ON rn.id = pn.raw_note_id
LEFT JOIN sentiment_history sh ON rn.id = sh.raw_note_id
WHERE rn.id = {{ $json.raw_note_id }}
LIMIT 1
```

**Node 3: Ollama Task Extraction**
- **Type:** HTTP Request
- **Name:** Ollama Extract Tasks
- **Method:** POST
- **URL:** `http://ollama:11434/api/generate`
- **Headers:**
  - `Content-Type`: `application/json`
- **Body:**
```json
{
  "model": "mistral:7b",
  "prompt": "{{$node["Fetch Note for Task Extraction"].json["prompt_text"]}}",
  "stream": false,
  "format": "json"
}
```
- **Timeout:** 60000 (60 seconds)

**Node 3.1: Build Prompt (Function node before Ollama)**
- **Type:** Function
- **Name:** Build Task Extraction Prompt
- **Code:**
```javascript
const note = $input.item.json;

// Load prompt template
const promptTemplate = `[Insert full prompt from 3.1 above]`;

// Replace placeholders
const prompt = promptTemplate
  .replace('{content}', note.content || '')
  .replace('{energy_level}', note.energy_level || 'unknown')
  .replace('{concepts}', note.concepts || '[]')
  .replace('{themes}', note.themes || '[]')
  .replace('{emotional_tone}', note.emotional_tone || 'neutral')
  .replace('{adhd_markers}', note.adhd_markers || 'none');

return {
  json: {
    ...note,
    prompt_text: prompt
  }
};
```

**Node 4: Parse Ollama Response**
- **Type:** Function
- **Name:** Parse Task JSON
- **Code:**
```javascript
const response = $input.item.json.response;
const noteData = $input.item.json;

let tasks = [];
try {
  tasks = JSON.parse(response);
} catch (e) {
  console.error('Failed to parse Ollama response:', e);
  return {
    json: {
      error: 'Invalid JSON from Ollama',
      raw_response: response,
      tasks: []
    }
  };
}

// Validate tasks
const validatedTasks = tasks.filter(task => {
  return task.task_text &&
         task.energy_required &&
         task.estimated_minutes &&
         task.task_type &&
         task.overwhelm_factor >= 1 && task.overwhelm_factor <= 10;
});

return {
  json: {
    raw_note_id: noteData.raw_note_id,
    tasks: validatedTasks,
    task_count: validatedTasks.length,
    original_note: noteData.content,
    concepts: noteData.concepts,
    themes: noteData.themes
  }
};
```

**Node 5: Split Out Tasks**
- **Type:** Split Out
- **Name:** Loop Each Task
- **Field:** `tasks`
- **Include:** `raw_note_id, concepts, themes, original_note`

**Node 6: Create Task in Things (HTTP Request to MCP)**
- **Type:** HTTP Request
- **Name:** Things MCP Create Task
- **Method:** POST
- **URL:** `http://localhost:3000/mcp/things/create-todo`
  *(Assumes MCP server exposed via local endpoint - may need to adjust)*
- **Alternative:** Use n8n Code node to call MCP directly
- **Body:**
```json
{
  "title": "{{ $json.task_text }}",
  "notes": "Extracted from Selene note #{{ $json.raw_note_id }}\n\nEnergy: {{ $json.energy_required }}\nEstimated: {{ $json.estimated_minutes }}min\nOverwhelm: {{ $json.overwhelm_factor }}/10\n\nOriginal note:\n{{ $json.original_note }}",
  "tags": {{ $json.context_tags }},
  "when": "anytime"
}
```

**IMPORTANT:** MCP Integration Method

Since MCP servers run as standalone processes, we need to wrap MCP calls. Two options:

**Option A: n8n Code Node (Recommended)**
```javascript
// Node 6: Things MCP Create (Code Node)
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

const task = $input.item.json;

// Create task via npx things-mcp
const thingsCommand = `npx -y github:hildersantos/things-mcp create-todo --title "${task.task_text}" --notes "Selene task" --when "anytime"`;

try {
  const { stdout, stderr } = await execPromise(thingsCommand);
  const taskId = stdout.trim(); // Assuming MCP returns task ID

  return {
    json: {
      ...task,
      things_task_id: taskId,
      created_successfully: true
    }
  };
} catch (error) {
  return {
    json: {
      ...task,
      things_task_id: null,
      created_successfully: false,
      error: error.message
    }
  };
}
```

**Option B: Create MCP HTTP Wrapper**
- Create small Express server that wraps MCP calls
- n8n calls HTTP endpoint
- Server calls MCP and returns result

For now, we'll use **Option A** (Code Node with exec).

**Node 7: Store Task Metadata**
- **Type:** SQLite
- **Name:** Insert Task Metadata
- **Operation:** executeQuery
- **Query:**
```sql
INSERT INTO task_metadata (
  raw_note_id,
  things_task_id,
  energy_required,
  estimated_minutes,
  related_concepts,
  related_themes,
  overwhelm_factor,
  task_type,
  context_tags
) VALUES (
  {{ $json.raw_note_id }},
  '{{ $json.things_task_id }}',
  '{{ $json.energy_required }}',
  {{ $json.estimated_minutes }},
  '{{ JSON.stringify($json.related_concepts) }}',
  '{{ JSON.stringify($json.related_themes) }}',
  {{ $json.overwhelm_factor }},
  '{{ $json.task_type }}',
  '{{ JSON.stringify($json.context_tags) }}'
);
```

**Node 8: Update Note Status**
- **Type:** SQLite
- **Name:** Mark Tasks Extracted
- **Operation:** executeQuery
- **Query:**
```sql
UPDATE raw_notes
SET tasks_extracted = 1,
    tasks_extracted_at = CURRENT_TIMESTAMP
WHERE id = {{ $json.raw_note_id }};

UPDATE processed_notes
SET things_integration_status = CASE
    WHEN {{ $json.task_count }} > 0 THEN 'tasks_created'
    ELSE 'no_tasks'
  END
WHERE raw_note_id = {{ $json.raw_note_id }};
```

**Node 9: Respond Success**
- **Type:** Respond to Webhook
- **Name:** Return Success
- **Response:**
```json
{
  "success": true,
  "raw_note_id": "{{ $json.raw_note_id }}",
  "tasks_created": "{{ $json.task_count }}",
  "message": "Task extraction completed"
}
```

### 4.3 Error Handling

Add **Error Trigger** node:
- Catches any workflow errors
- Logs to database:
```sql
INSERT INTO integration_logs (workflow, event, raw_note_id, success, error_message)
VALUES (
  '07-task-extraction',
  'task_creation_failed',
  {{ $json.raw_note_id }},
  0,
  '{{ $json.error }}'
);
```

---

## Step 5: Connect to Existing Workflows

### 5.1 Modify Workflow 05 (Sentiment Analysis)

**Add final node to workflow 05:**

**Node:** HTTP Request (Webhook Call)
- **Name:** Trigger Task Extraction
- **Method:** POST
- **URL:** `http://n8n:5678/webhook/task-extraction`
- **Body:**
```json
{
  "raw_note_id": "{{ $node["Query Note"].json.id }}",
  "processed_note_id": "{{ $json.id }}"
}
```
- **Place after:** "Store Sentiment History" node
- **Run:** Always (even if sentiment analysis shows no ADHD markers)

### 5.2 Test End-to-End Flow

**Test sequence:**
1. Send note from Drafts with clear action item
2. Verify workflow 01 (ingestion) stores note
3. Verify workflow 02 (LLM processing) extracts concepts
4. Verify workflow 05 (sentiment) analyzes emotions
5. Verify workflow 07 (NEW) creates task in Things
6. Check Things inbox for new task
7. Query database: `SELECT * FROM task_metadata ORDER BY created_at DESC LIMIT 1;`

---

## Step 6: Testing & Validation

### 6.1 Unit Tests

**Test 1: Empty array for non-actionable note**
```bash
# Send note with no tasks
# Expected: workflow completes, things_integration_status = 'no_tasks'
```

**Test 2: Single task extraction**
```bash
# Send: "I need to call the dentist tomorrow"
# Expected: 1 task in Things: "Call dentist"
# Expected: 1 row in task_metadata
```

**Test 3: Multiple tasks**
```bash
# Send: "Today I need to: email client, update presentation, and review code"
# Expected: 3 tasks in Things
# Expected: 3 rows in task_metadata with same raw_note_id
```

**Test 4: Duplicate prevention**
```bash
# Manually create task in Things: "Email client"
# Send note: "I should email the client"
# Expected: No duplicate created (requires fuzzy matching - Phase 7.2)
# For Phase 7.1: May create duplicate (acceptable for now)
```

**Test 5: Energy level accuracy**
```bash
# Send high-energy note with creative task
# Expected: task.energy_required = 'high'

# Send low-energy note with simple task
# Expected: task.energy_required = 'low' or 'medium'
```

**Test 6: Time estimates**
```bash
# Send: "Write comprehensive project documentation"
# Expected: estimated_minutes >= 120 (complex writing)

# Send: "Reply to John's email"
# Expected: estimated_minutes <= 15 (quick communication)
```

### 6.2 Integration Tests

**Test Full Pipeline:**
1. Drafts → n8n ingestion → processing → sentiment → task extraction → Things
2. Measure total time (should be <2 minutes)
3. Verify all data accurate

**Test Error Scenarios:**
- Things app not running → workflow should log error, not crash
- Ollama timeout → workflow should retry once, then fail gracefully
- Invalid JSON from Ollama → workflow should log and mark as 'error'
- Database constraint violation → workflow should handle gracefully

### 6.3 User Acceptance Testing

**Scenario 1: Daily Capture Flow**
- User records 5 voice notes throughout day
- Each contains 0-3 action items
- Expected: All tasks appear in Things within 2 minutes
- User validates: "Tasks make sense" (>80% accuracy)

**Scenario 2: Energy Matching**
- User records excited, high-energy note
- Task created with energy: 'high'
- User later (when tired) filters for low-energy tasks
- Verifies high-energy task not suggested

**Scenario 3: Time Estimation**
- User completes tasks over 1 week
- Compare estimated_minutes to actual duration
- Calculate accuracy (within 50% for Phase 7.1 is acceptable)
- Will improve in Phase 7.4 with pattern learning

---

## Step 7: Deployment Checklist

### Pre-Deployment

- [ ] Database migration applied successfully
- [ ] Things MCP server configured and tested
- [ ] Ollama prompt validated with test cases
- [ ] n8n workflow created and tested in isolation
- [ ] Workflow 05 modified to trigger task extraction
- [ ] All unit tests passing
- [ ] Integration tests passing

### Deployment

- [ ] Activate workflow 07 in n8n
- [ ] Monitor first 10 notes for issues
- [ ] Check error logs: `SELECT * FROM integration_logs WHERE success = 0;`
- [ ] Validate task quality with user

### Post-Deployment

- [ ] Monitor for 3 days
- [ ] Collect user feedback on task extraction accuracy
- [ ] Measure success metrics:
  - Task extraction rate: X% of notes create tasks
  - Energy accuracy: User validation >80%
  - Time to completion: <30 seconds per note
  - Error rate: <5%

### Rollback Plan

If critical issues occur:

1. **Pause workflow:**
```bash
# In n8n UI: Deactivate workflow 07
# Or via CLI:
docker exec n8n-container n8n workflow:deactivate --id=<workflow-id>
```

2. **Revert workflow 05:**
- Remove "Trigger Task Extraction" node
- Workflow 05 ends at "Store Sentiment History"

3. **Database rollback (if needed):**
```sql
-- Only if corrupted data
DELETE FROM task_metadata;
UPDATE raw_notes SET tasks_extracted = 0, tasks_extracted_at = NULL;
UPDATE processed_notes SET things_integration_status = 'pending';
```

4. **Things cleanup:**
- Tasks already created remain in Things
- Can manually delete or leave (no harm)

---

## Monitoring & Metrics

### Key Metrics to Track

**Daily:**
- Notes processed: `SELECT COUNT(*) FROM raw_notes WHERE created_at > date('now', '-1 day');`
- Tasks created: `SELECT COUNT(*) FROM task_metadata WHERE created_at > datetime('now', '-1 day');`
- Error rate: `SELECT COUNT(*) FROM integration_logs WHERE success = 0 AND timestamp > datetime('now', '-1 day');`

**Weekly:**
- Average tasks per note: `SELECT AVG(task_count) FROM (SELECT COUNT(*) as task_count FROM task_metadata GROUP BY raw_note_id);`
- Energy distribution: `SELECT energy_required, COUNT(*) FROM task_metadata GROUP BY energy_required;`
- Overwhelm distribution: `SELECT overwhelm_factor, COUNT(*) FROM task_metadata GROUP BY overwhelm_factor;`

**User Feedback:**
- Survey after 1 week: "Are extracted tasks accurate? (Yes/No/Sometimes)"
- Survey after 2 weeks: "Are energy levels helpful? (1-5 scale)"

### Alerts

Set up alerts for:
- Error rate >10% in any hour
- Task creation fails 3 times consecutively
- Ollama timeout rate >25%
- Average workflow completion time >60 seconds

---

## Future Enhancements (Phase 7.2+)

### Duplicate Detection
- Before creating task, search Things via MCP
- Fuzzy string matching (Levenshtein distance)
- If >80% match, link to existing instead of creating new

### Smart Energy Learning
- Track which energy assignments were accurate
- Adjust future estimates based on user patterns
- "User completes 'email' tasks quickly → reduce energy to 'low'"

### Context-Aware Tags
- Learn which tags user uses most
- Auto-suggest based on concepts/themes
- "Concept 'web-design' → suggest tag 'creative'"

### Batch Processing
- Process multiple notes at once (efficiency)
- Deduplicate tasks across notes
- Create projects for related task clusters

---

## Appendix

### A. Example Task Extraction Results

**Input Note:**
```
Feeling motivated today! Need to finish the blog post about ADHD strategies,
update the project roadmap, and send the newsletter. Also should research
that new productivity app everyone's talking about.
```

**Expected Output:**
```json
[
  {
    "task_text": "Finish blog post about ADHD strategies",
    "energy_required": "high",
    "estimated_minutes": 120,
    "task_type": "action",
    "context_tags": ["writing", "creative", "work"],
    "overwhelm_factor": 6
  },
  {
    "task_text": "Update project roadmap",
    "energy_required": "medium",
    "estimated_minutes": 30,
    "task_type": "planning",
    "context_tags": ["work", "planning"],
    "overwhelm_factor": 4
  },
  {
    "task_text": "Send newsletter",
    "energy_required": "medium",
    "estimated_minutes": 15,
    "task_type": "communication",
    "context_tags": ["work", "email"],
    "overwhelm_factor": 3
  },
  {
    "task_text": "Research new productivity app",
    "energy_required": "medium",
    "estimated_minutes": 30,
    "task_type": "research",
    "context_tags": ["learning", "productivity"],
    "overwhelm_factor": 4
  }
]
```

### B. Troubleshooting Guide

**Issue: Tasks not appearing in Things**
- Check: Is Things app running?
- Check: MCP server configured correctly?
- Check: Run test MCP command manually
- Check: n8n workflow logs for errors

**Issue: Ollama returns invalid JSON**
- Check: Model is mistral:7b (or adjust prompt)
- Check: Prompt includes `"format": "json"`
- Check: Timeout is sufficient (60s)
- Test: Run Ollama command manually with same prompt

**Issue: Duplicate tasks created**
- Expected in Phase 7.1 (no duplicate detection yet)
- Workaround: Manually merge duplicates in Things
- Planned: Phase 7.2 will add fuzzy matching

**Issue: Energy levels seem wrong**
- Validate: Is note's energy_level being passed correctly?
- Check: LLM prompt includes energy matching logic
- Adjust: Modify prompt to be more conservative/aggressive
- Track: User feedback to calibrate over time

---

## Related Documentation

- [Things Integration Architecture](../architecture/things-integration.md)
- [Phase 7 Roadmap](../roadmap/16-PHASE-7-THINGS.md)
- [User Stories](../user-stories/things-integration-stories.md)
- [Database Schema](../../database/schema.sql)

---

**Document Status:** ✅ Ready for Implementation
**Implementation Time:** 2 weeks (10-15 hours development + testing)
**Next Action:** Begin Step 1 (Install Things MCP Server)
**Owner:** Chase Easterling
**Last Updated:** 2025-11-24