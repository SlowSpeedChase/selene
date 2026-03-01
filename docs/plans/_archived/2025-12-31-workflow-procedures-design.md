# Workflow Procedures Design

**Created:** 2025-12-31
**Status:** Approved
**Purpose:** Define mandatory procedures for Claude to follow when creating, modifying, or deleting n8n workflows.

---

## Problem Statement

1. Claude doesn't reliably follow existing workflow procedures
2. Missing procedures for workflow creation and deletion
3. Existing documentation mixes procedures with reference material, causing procedures to get buried

## Solution

1. Add hard trigger in root `CLAUDE.md` that forces procedure check before any workflow action
2. Restructure `workflows/CLAUDE.md` with procedures first, reference material second
3. Add CREATE and DELETE procedures (MODIFY already exists but needs consolidation)
4. Create `workflows/_template/` for consistent new workflow creation
5. Create `workflows/_archived/` for deleted workflow preservation

---

## Part 1: Trigger Mechanism (Root CLAUDE.md Addition)

Add to the "Critical Rules" section of root `CLAUDE.md`:

```markdown
## MANDATORY: Workflow Procedure Check

**BEFORE taking ANY action involving n8n workflows, you MUST:**

1. Read `@workflows/CLAUDE.md` (the full procedures section)
2. Identify which procedure applies (Create, Modify, or Delete)
3. Follow that procedure step-by-step without skipping

**Trigger conditions (if ANY apply, read procedures first):**
- User mentions: workflow, n8n, webhook, node, trigger
- User asks to: add, modify, fix, debug, delete, remove, create
- Files involved: `workflow.json`, `workflows/` directory
- Actions on: ingestion, processing, export, or any numbered workflow (01-, 02-, etc.)

**Examples that trigger this:**
- "Add a new node to the ingestion workflow" -> Read procedures, use MODIFY
- "Create a workflow for daily summaries" -> Read procedures, use CREATE
- "Remove the old sentiment workflow" -> Read procedures, use DELETE
- "Fix the webhook in 02-llm-processing" -> Read procedures, use MODIFY

**Claude: This is not optional. Skipping procedures causes git sync issues and broken workflows.**
```

---

## Part 2: CREATE Workflow Procedure

```markdown
## PROCEDURE: Create New Workflow

**When to use:** User asks to create, add, or build a new workflow.

### Pre-flight Checks
1. Confirm the workflow doesn't already exist: `ls workflows/`
2. Determine the next workflow number (e.g., if 08 exists, use 09)
3. Confirm the workflow name with user if ambiguous

### Step-by-Step Process

**Step 1: Copy Template**
```bash
cp -r workflows/_template workflows/XX-new-name
```
Replace `XX` with the number and `new-name` with descriptive kebab-case name.

**Step 2: Rename Template Files**
```bash
mv workflows/XX-new-name/workflow.template.json workflows/XX-new-name/workflow.json
```

**Step 3: Edit workflow.json**
- Update the `"name"` field to match workflow purpose
- Add/modify nodes for the workflow's functionality
- Set up connections between nodes
- Configure webhook path if needed (use `api/descriptive-name`)

**Step 4: Update Documentation**
- Edit `README.md` - describe what the workflow does
- Edit `docs/STATUS.md` - set initial status to "In Development"

**Step 5: Import to n8n**
```bash
./scripts/manage-workflow.sh import /workflows/XX-new-name/workflow.json
```

**Step 6: Get the Workflow ID**
```bash
./scripts/manage-workflow.sh list
```
Note the ID assigned to your new workflow.

**Step 7: Test the Workflow**
```bash
./workflows/XX-new-name/scripts/test-with-markers.sh
```

**Step 8: Update STATUS.md**
Record test results and mark as "Ready" or note issues.

**Step 9: Commit**
```bash
git add workflows/XX-new-name/
git commit -m "feat(XX): add new-name workflow

- Brief description of what it does
- Key features"
```

### Verification Checklist
- [ ] Workflow appears in `./scripts/manage-workflow.sh list`
- [ ] Test script runs without errors
- [ ] STATUS.md reflects current state
- [ ] All files committed to git
```

---

## Part 3: MODIFY Workflow Procedure

```markdown
## PROCEDURE: Modify Existing Workflow

**When to use:** User asks to edit, fix, debug, update, add nodes to, or change an existing workflow.

### Pre-flight Checks
1. Identify the workflow by name or number
2. Get the workflow ID: `./scripts/manage-workflow.sh list`
3. Confirm n8n container is running: `docker-compose ps`

### Step-by-Step Process

**Step 1: Export Current Version (Creates Backup)**
```bash
./scripts/manage-workflow.sh export <workflow-id>
```
This creates a timestamped backup automatically.

**Step 2: Read the Current workflow.json**
Use the Read tool to examine:
```
workflows/XX-name/workflow.json
```
Understand the current structure before making changes.

**Step 3: Edit the JSON File**
Use the Edit tool to make changes to `workflows/XX-name/workflow.json`.

Common modifications:
- Add new node (add to `nodes` array, update `connections`)
- Change node parameters (find node by name, edit `parameters`)
- Fix bug (locate problematic node, correct the logic)
- Update connections (modify `connections` object)

**Step 4: Update Workflow in n8n**
```bash
./scripts/manage-workflow.sh update <workflow-id> /workflows/XX-name/workflow.json
```

**Step 5: Test the Workflow**
```bash
./workflows/XX-name/scripts/test-with-markers.sh
```

**Step 6: Update Documentation**
Edit `workflows/XX-name/docs/STATUS.md`:
- Record test results
- Note what changed and why
- Update date

**Step 7: Commit Changes**
```bash
git add workflows/XX-name/workflow.json workflows/XX-name/docs/STATUS.md
git commit -m "fix(XX): description of change

- What was changed
- Why it was changed"
```

### If Tests Fail
1. Do NOT commit
2. Read error output carefully
3. Return to Step 3 and fix
4. Repeat Steps 4-6

### Verification Checklist
- [ ] Backup exists (check for timestamped file)
- [ ] Tests pass
- [ ] STATUS.md updated with today's date
- [ ] Changes committed to git
```

---

## Part 4: DELETE Workflow Procedure

```markdown
## PROCEDURE: Delete Workflow

**When to use:** User asks to remove, delete, retire, or decommission a workflow.

### Pre-flight Checks
1. Confirm which workflow to delete (get explicit confirmation from user)
2. Get the workflow ID: `./scripts/manage-workflow.sh list`
3. Check if workflow is currently active: `./scripts/manage-workflow.sh show <id>`

### Step-by-Step Process

**Step 1: Confirm with User**
Ask: "You want to delete workflow XX-name (ID: N). This will:
- Deactivate it in n8n
- Archive the files to `workflows/_archived/`
- Remove it from active workflows

Proceed? (yes/no)"

**Do NOT proceed without explicit confirmation.**

**Step 2: Export Final Version**
```bash
./scripts/manage-workflow.sh export <workflow-id>
```
Ensures we have the latest state before archiving.

**Step 3: Deactivate in n8n**
```bash
docker exec selene n8n update:workflow --id=<workflow-id> --active=false
```

**Step 4: Create Archive Directory (if needed)**
```bash
mkdir -p workflows/_archived
```

**Step 5: Move to Archive**
```bash
mv workflows/XX-name workflows/_archived/XX-name
```

**Step 6: Add Archive Note**
Create `workflows/_archived/XX-name/ARCHIVED.md`:
```markdown
# Archived: XX-name

**Archived Date:** YYYY-MM-DD
**Reason:** [User's reason or "User requested deletion"]
**Last Workflow ID:** N

## Notes
- Any relevant context about why this was archived
- What replaced it (if applicable)
```

**Step 7: Delete from n8n (Optional)**
Only if user explicitly wants it removed from n8n entirely:
```bash
docker exec selene n8n delete:workflow --id=<workflow-id>
```
Skip this step if user might want to restore later.

**Step 8: Commit**
```bash
git add workflows/_archived/XX-name/
git rm -r workflows/XX-name/  # Stages the removal
git commit -m "chore(XX): archive XX-name workflow

- Reason: [reason]
- Archived to workflows/_archived/"
```

### Verification Checklist
- [ ] User explicitly confirmed deletion
- [ ] Final export completed
- [ ] Workflow deactivated in n8n
- [ ] Files moved to `_archived/` (not deleted)
- [ ] ARCHIVED.md created with context
- [ ] Changes committed to git
```

---

## Part 5: Template Structure

Create `workflows/_template/` with:

```
workflows/_template/
├── workflow.template.json
├── README.md
├── docs/
│   └── STATUS.md
└── scripts/
    └── test-with-markers.sh
```

### workflow.template.json

```json
{
  "name": "XX-WORKFLOW-NAME",
  "nodes": [
    {
      "parameters": {
        "path": "api/ENDPOINT-NAME",
        "responseMode": "onReceived",
        "options": {}
      },
      "id": "webhook-trigger",
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.Webhook",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "jsCode": "// TODO: Implement workflow logic\nreturn items;"
      },
      "id": "process-data",
      "name": "Process Data",
      "type": "n8n-nodes-base.Code",
      "typeVersion": 2,
      "position": [450, 300]
    }
  ],
  "connections": {
    "Webhook Trigger": {
      "main": [[{"node": "Process Data", "type": "main", "index": 0}]]
    }
  },
  "settings": {
    "executionOrder": "v1"
  }
}
```

### README.md

```markdown
# XX-Workflow-Name

**Status:** In Development
**Workflow ID:** (assigned after import)

## Purpose

Brief description of what this workflow does.

## Trigger

- Webhook: `http://localhost:5678/webhook/api/ENDPOINT-NAME`

## Testing

```bash
./scripts/test-with-markers.sh
```

## Related

- Upstream: (workflow that feeds into this)
- Downstream: (workflow this feeds into)
```

### docs/STATUS.md

```markdown
# XX-Workflow-Name Status

**Last Updated:** YYYY-MM-DD
**Status:** In Development

---

## Current State

- [ ] Workflow created
- [ ] Basic logic implemented
- [ ] Test script working
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Ready for production

---

## Test Results

### Latest Run

| Test Case | Status | Notes |
|-----------|--------|-------|
| (none yet) | - | - |

---

## Change Log

### YYYY-MM-DD
- Initial creation from template
```

### scripts/test-with-markers.sh

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# ============================================================================
# CUSTOMIZE FOR YOUR WORKFLOW:
# 1. Update WEBHOOK_PATH to your endpoint
# 2. Update TABLE_NAME to the table this workflow writes to
# 3. Add test cases specific to your workflow
# ============================================================================

TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
WEBHOOK_URL="http://localhost:5678/webhook/api/ENDPOINT-NAME"
DB_PATH="../../data/selene.db"
TABLE_NAME="raw_notes"  # Change to your table

echo "================================================"
echo "Testing XX-workflow-name"
echo "Test marker: $TEST_RUN"
echo "================================================"

# Test 1: Basic success case
echo ""
echo "Test 1: Normal operation"
curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"test_field\": \"test value\",
    \"test_run\": \"$TEST_RUN\"
  }"

sleep 2

# Verify
COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $TABLE_NAME WHERE test_run = '$TEST_RUN';")
echo "Records created: $COUNT"

# Results
echo ""
echo "================================================"
echo "Test complete. Marker: $TEST_RUN"
echo "Cleanup: ../../scripts/cleanup-tests.sh $TEST_RUN"
echo "================================================"
```

---

## Part 6: Final Document Structure

The restructured `workflows/CLAUDE.md` will be organized:

```markdown
# Workflow Development Context

**Claude: Before ANY workflow action, read the relevant PROCEDURE below.**

---

## Table of Contents

1. [PROCEDURES (MANDATORY)](#procedures-mandatory)
   - [Create New Workflow](#procedure-create-new-workflow)
   - [Modify Existing Workflow](#procedure-modify-existing-workflow)
   - [Delete Workflow](#procedure-delete-workflow)
2. [Quick Reference](#quick-reference)
3. [Reference Material](#reference-material)
   - [Workflow JSON Structure](#workflow-json-structure)
   - [Node Naming Conventions](#node-naming-conventions)
   - [Error Handling Patterns](#error-handling-patterns)
   - [Database Integration Patterns](#database-integration-patterns)
   - [Common Workflow Patterns](#common-workflow-patterns)

---

# PROCEDURES (MANDATORY)

**These procedures are not optional. Follow step-by-step.**

## PROCEDURE: Create New Workflow
[Content from Part 2]

## PROCEDURE: Modify Existing Workflow
[Content from Part 3]

## PROCEDURE: Delete Workflow
[Content from Part 4]

---

# Quick Reference

| Action | Command |
|--------|---------|
| List workflows | `./scripts/manage-workflow.sh list` |
| Export workflow | `./scripts/manage-workflow.sh export <id>` |
| Update workflow | `./scripts/manage-workflow.sh update <id> <file>` |
| Import new | `./scripts/manage-workflow.sh import <file>` |
| Test workflow | `./workflows/XX-name/scripts/test-with-markers.sh` |
| Cleanup tests | `./scripts/cleanup-tests.sh <test-run-id>` |

---

# Reference Material

[Existing patterns and reference content from current file, moved to bottom]
```

---

## Implementation Checklist

1. [ ] Add trigger block to root `CLAUDE.md`
2. [ ] Create `workflows/_template/` directory with all files
3. [ ] Create `workflows/_archived/` directory
4. [ ] Restructure `workflows/CLAUDE.md` with procedures first
5. [ ] Test the procedures manually
6. [ ] Commit all changes
