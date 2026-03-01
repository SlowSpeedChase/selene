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
