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
