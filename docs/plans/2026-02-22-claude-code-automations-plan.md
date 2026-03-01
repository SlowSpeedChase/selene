# Claude Code Automations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add MCP servers, Claude Code hooks, and custom skills to improve Selene development velocity and safety.

**Architecture:** Configuration-only changes. MCP servers via `claude mcp add`. Hooks in `.claude/settings.json`. Skills as SKILL.md files in `.claude/skills/`. No application code changes.

**Tech Stack:** Claude Code CLI, context7 MCP, @anthropic/mcp-sqlite, TypeScript compiler (tsc)

**Design Doc:** `docs/plans/2026-02-22-claude-code-automations-design.md`

---

### Task 1: Install context7 MCP Server

**Files:**
- Create: `.mcp.json` (auto-created by CLI)

**Step 1: Install the MCP server**

Run:
```bash
claude mcp add context7 --scope project -- npx -y @upstash/context7-mcp@latest
```

Expected: Success message, `.mcp.json` created or updated in project root.

**Step 2: Verify `.mcp.json` was created**

Run:
```bash
cat .mcp.json
```

Expected: JSON containing `context7` entry with `npx -y @upstash/context7-mcp@latest` command.

**Step 3: Commit**

```bash
git add .mcp.json
git commit -m "chore: add context7 MCP server for live documentation"
```

---

### Task 2: Install sqlite-dev MCP Server

**Files:**
- Modify: `.mcp.json`

**Step 1: Install the MCP server**

Run:
```bash
claude mcp add sqlite-dev --scope project -- npx -y @anthropic/mcp-sqlite --db-path /Users/chaseeasterling/selene-data-dev/selene.db
```

Expected: Success message, `.mcp.json` updated with `sqlite-dev` entry.

**Step 2: Verify the config**

Run:
```bash
cat .mcp.json
```

Expected: JSON containing both `context7` and `sqlite-dev` entries. The `sqlite-dev` entry should reference `/Users/chaseeasterling/selene-data-dev/selene.db`.

**Step 3: Commit**

```bash
git add .mcp.json
git commit -m "chore: add sqlite-dev MCP server for dev database queries"
```

---

### Task 3: Create Claude Code Hooks

**Files:**
- Create: `.claude/settings.json`

**Step 1: Write the hooks configuration**

Create `.claude/settings.json` with this exact content:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$CLAUDE_FILE_PATHS\" | grep -qE '(\\.env$|\\.env\\.|selene\\.db)'; then echo 'BLOCKED: Cannot edit .env files or production database' >&2; exit 2; fi"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$CLAUDE_FILE_PATHS\" | grep -q '\\.ts$'; then cd /Users/chaseeasterling/selene && npx tsc --noEmit --pretty 2>&1 | head -20; fi"
          }
        ]
      }
    ]
  }
}
```

**Step 2: Verify JSON is valid**

Run:
```bash
python3 -c "import json; json.load(open('.claude/settings.json')); print('Valid JSON')"
```

Expected: `Valid JSON`

**Step 3: Verify the hooks don't conflict with settings.local.json**

Read `.claude/settings.local.json` and confirm it only has `permissions` — no `hooks` key. The shared `settings.json` handles hooks, the local file handles permissions. These merge at runtime; they don't conflict.

**Step 4: Test the type-check hook manually**

Run:
```bash
cd /Users/chaseeasterling/selene && npx tsc --noEmit --pretty 2>&1 | head -20
```

Expected: Either clean output (no errors) or a list of type errors. This verifies `tsc` runs correctly in the project. The hook will run this same command automatically after Claude edits `.ts` files.

**Step 5: Commit**

```bash
git add .claude/settings.json
git commit -m "chore: add Claude Code hooks for type-check and sensitive file blocking"
```

---

### Task 4: Create run-workflow Skill

**Files:**
- Create: `.claude/skills/run-workflow/SKILL.md`

**Step 1: Create the skill directory**

Run:
```bash
mkdir -p .claude/skills/run-workflow
```

**Step 2: Write the skill file**

Create `.claude/skills/run-workflow/SKILL.md`:

````markdown
---
name: run-workflow
description: Run a Selene workflow with test markers and log tailing. Use when executing any workflow from src/workflows/.
disable-model-invocation: true
---

# Run Workflow

Execute a Selene TypeScript workflow with proper test isolation.

## Arguments

- `$ARGUMENTS` = workflow name (e.g., `process-llm`, `extract-tasks`, `detect-threads`)

## Available Workflows

- `process-llm` - LLM concept extraction
- `extract-tasks` - Task classification and routing
- `index-vectors` - LanceDB vector indexing
- `compute-associations` - Pairwise note similarity
- `compute-relationships` - Typed note relationships
- `detect-threads` - Thread detection
- `reconsolidate-threads` - Thread summary + momentum
- `thread-lifecycle` - Archive/split/merge threads
- `export-obsidian` - Obsidian vault sync
- `daily-summary` - Daily summary generation
- `send-digest` - Apple Notes digest delivery
- `transcribe-voice-memos` - whisper.cpp voice transcription

## Procedure

1. **Validate argument**: If no workflow name provided, list available workflows and ask which one to run.

2. **Verify workflow file exists**:
   ```bash
   ls src/workflows/$ARGUMENTS.ts
   ```
   If not found, list available workflows and suggest the closest match.

3. **Generate test marker**:
   ```bash
   TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
   echo "Test marker: $TEST_RUN"
   ```

4. **Run the workflow**:
   ```bash
   cd /Users/chaseeasterling/selene && TEST_RUN="$TEST_RUN" npx ts-node src/workflows/$ARGUMENTS.ts
   ```

5. **Check logs** (last 30 lines):
   ```bash
   tail -30 logs/selene.log | npx pino-pretty
   ```

6. **Report results**: State whether the workflow succeeded or failed. Include any errors from the output.

7. **Remind about cleanup**: Tell the user:
   > Test data created with marker `$TEST_RUN`. When done reviewing, clean up with:
   > ```bash
   > ./scripts/cleanup-tests.sh "$TEST_RUN"
   > ```
````

**Step 3: Commit**

```bash
git add .claude/skills/run-workflow/SKILL.md
git commit -m "feat: add run-workflow skill for streamlined workflow execution"
```

---

### Task 5: Create launchd-check Skill

**Files:**
- Create: `.claude/skills/launchd-check/SKILL.md`

**Step 1: Create the skill directory**

Run:
```bash
mkdir -p .claude/skills/launchd-check
```

**Step 2: Write the skill file**

Create `.claude/skills/launchd-check/SKILL.md`:

````markdown
---
name: launchd-check
description: Check health and status of Selene launchd agents. Use when diagnosing workflow scheduling issues or checking if agents are running.
disable-model-invocation: true
---

# Launchd Health Check

Diagnose Selene launchd agent status and recent activity.

## Arguments

- `$ARGUMENTS` = optional agent short name (e.g., `process-llm`, `server`)
- If empty, check ALL Selene agents

## Selene Agents

| Short Name | Label | Schedule |
|-----------|-------|----------|
| server | com.selene.server | Always running |
| process-llm | com.selene.process-llm | Every 5 min |
| extract-tasks | com.selene.extract-tasks | Every 5 min |
| index-vectors | com.selene.index-vectors | Every 10 min |
| compute-relationships | com.selene.compute-relationships | Every 10 min |
| detect-threads | com.selene.detect-threads | Every 30 min |
| reconsolidate-threads | com.selene.reconsolidate-threads | Hourly |
| export-obsidian | com.selene.export-obsidian | Hourly |
| daily-summary | com.selene.daily-summary | Daily midnight |
| thread-lifecycle | com.selene.thread-lifecycle | Daily 2am |
| send-digest | com.selene.send-digest | Daily 6am |
| transcribe-voice-memos | com.selene.transcribe-voice-memos | WatchPaths |
| dev-process-batch | com.selene.dev-process-batch | Hourly (dev) |

## Procedure

### If specific agent requested (`$ARGUMENTS` provided):

1. **Check agent status**:
   ```bash
   launchctl list | grep "com.selene.$ARGUMENTS"
   ```
   Parse the output: column 1 = PID (or `-` if not running), column 2 = last exit code, column 3 = label.

2. **Check recent stdout log** (last 15 lines):
   ```bash
   tail -15 /Users/chaseeasterling/selene/logs/$ARGUMENTS.log
   ```

3. **Check recent stderr log** (last 10 lines):
   ```bash
   tail -10 /Users/chaseeasterling/selene/logs/$ARGUMENTS.error.log
   ```

4. **Report**:
   - Status: Running (with PID) or Not Running
   - Last exit code: 0 = success, non-zero = error
   - Recent log activity summary
   - Flag any errors found in stderr

### If no argument (check all agents):

1. **List all Selene agents**:
   ```bash
   launchctl list | grep com.selene
   ```

2. **Summarize in a table**:
   | Agent | Status | Exit Code | Notes |
   |-------|--------|-----------|-------|

3. **Flag any issues**:
   - Agents with non-zero exit codes
   - Agents not in the list (not loaded)
   - The server agent should have a PID (it's always-running)

4. **For any flagged agents**, show recent stderr:
   ```bash
   tail -5 /Users/chaseeasterling/selene/logs/<agent>.error.log
   ```
````

**Step 3: Commit**

```bash
git add .claude/skills/launchd-check/SKILL.md
git commit -m "feat: add launchd-check skill for agent health diagnosis"
```

---

### Task 6: Final Verification

**Step 1: Verify all files exist**

Run:
```bash
ls -la .mcp.json .claude/settings.json .claude/skills/run-workflow/SKILL.md .claude/skills/launchd-check/SKILL.md
```

Expected: All 4 files exist.

**Step 2: Verify git is clean**

Run:
```bash
git status
```

Expected: Clean working tree, all changes committed.

**Step 3: Review commit history**

Run:
```bash
git log --oneline -6
```

Expected: 5 new commits (context7, sqlite-dev, hooks, run-workflow, launchd-check) on top of the design doc commit.

**Step 4: Test MCP servers are registered**

Run:
```bash
cat .mcp.json | python3 -c "import json,sys; d=json.load(sys.stdin); print('context7:', 'context7' in d.get('mcpServers',{})); print('sqlite-dev:', 'sqlite-dev' in d.get('mcpServers',{}))"
```

Expected:
```
context7: True
sqlite-dev: True
```

**Step 5: Note for user**

MCP servers require restarting Claude Code to take effect. After the session ends, the next `claude` invocation will have both MCP servers available. The hooks and skills take effect immediately in new sessions.

---
