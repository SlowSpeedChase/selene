---
name: cleanup-test-run
description: Remove test data from the Selene database by test_run marker. Use after running any workflow test that inserted rows with a test_run marker, or when CLAUDE.md's PostToolUse warning hook reports leftover test rows.
---

# Cleanup Test Run Skill

Selene's critical testing rule (see `CLAUDE.md`) is that every test must tag rows with a `test_run` marker and clean them up afterward. This skill wraps `./scripts/cleanup-tests.sh` with a consistent, safe procedure.

## When to invoke

- **Automatically** after any workflow test Claude just ran that inserted rows with a `test_run` field
- **When prompted** by the `PostToolUse` hook that warns "TEST-RUN WARNING: N row(s) with test_run marker remain"
- **On user request**: `/cleanup-test-run [marker-id|--all|--list]`

## Procedure

1. **List current test runs** to see what's present:
   ```bash
   ./scripts/cleanup-tests.sh --list
   ```

2. **Decide scope**:
   - If the user named a specific marker, clean only that one.
   - If Claude created the test run in this session, clean the known marker.
   - If multiple unknown runs exist, ask the user which to clean — do NOT default to `--all`.

3. **Clean**:
   ```bash
   ./scripts/cleanup-tests.sh <marker-id>
   ```

4. **Verify**:
   ```bash
   sqlite3 "${SELENE_DB_PATH:-./data/selene.db}" \
     "SELECT COUNT(*) FROM raw_notes WHERE test_run = '<marker-id>';"
   ```
   Expect `0`. If non-zero, report the failure and stop — do not retry destructively.

## Critical Rules

- **Never run `--all` without explicit user confirmation**. This deletes every row with a test_run marker, which may include another developer's or another session's in-flight tests.
- **Never hand-write `DELETE FROM` SQL** against the production database. Always go through `cleanup-tests.sh` — it knows which tables need cleaning (raw_notes, processed_notes, sentiment_history, etc.) and keeps them consistent.
- **Never clean without listing first**. The list step is a cheap sanity check that surfaces surprising markers you didn't know about.
- Production database is at `data/selene.db` (symlink → `~/selene-data/selene.db`). The dev database at `~/selene-data-dev/selene.db` does not need this skill — wipe and reseed via `./scripts/reset-dev-data.sh` instead.
