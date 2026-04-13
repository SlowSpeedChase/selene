---
name: new-workflow
description: Scaffold a new Selene background workflow with matching test file, launchd plist, and architecture doc updates. Use when adding a new ts-node workflow to src/workflows/ that needs to run on a schedule.
disable-model-invocation: true
---

# New Workflow Skill

Scaffolds a new Selene background workflow. A Selene workflow is a coordinated set of files:

1. `src/workflows/<name>.ts` — the workflow script (exports an async function + CLI entry point)
2. `src/workflows/<name>.test.ts` — assertion-based test using `node:assert`
3. `launchd/com.selene.<name>.plist` — macOS LaunchAgent plist
4. Entry added to `scripts/install-launchd.sh` in the `AGENTS` array
5. Reference in `CLAUDE.md` architecture section

Missing any one of these leaves the workflow partially wired and silently broken.

## Arguments

The user invokes with: `/new-workflow <name> <interval-seconds> "<one-line description>"`

- `name`: kebab-case workflow name (e.g. `daily-reflection`)
- `interval-seconds`: integer for `StartInterval` in the plist (e.g. `3600` for hourly)
- `description`: shown in CLAUDE.md architecture section

## Procedure

1. **Validate name**: must match `^[a-z][a-z0-9-]*$` and must not already exist as `src/workflows/<name>.ts`.

2. **Create workflow file** from `templates/workflow.ts.template`, substituting:
   - `{{NAME}}` → kebab-case name
   - `{{FUNCTION_NAME}}` → camelCase version of name (e.g. `dailyReflection`)

3. **Create test file** from `templates/workflow.test.ts.template`, substituting:
   - `{{NAME}}` → kebab-case name
   - `{{FUNCTION_NAME}}` → camelCase

4. **Create plist** from `templates/workflow.plist.template`, substituting:
   - `{{NAME}}` → kebab-case name
   - `{{INTERVAL}}` → the integer from arguments

5. **Update `scripts/install-launchd.sh`**: add `"com.selene.<name>"` to the `AGENTS` array (alphabetical placement preferred).

6. **Update `CLAUDE.md`**: in the "Key Components" tree under `src/workflows/`, add a line for the new file with the description. Also add the new plist under `launchd/`.

7. **Run type check**: `cd /Users/chaseeasterling/selene && npx tsc --noEmit` — must pass before reporting success.

8. **Report**: summarize files created, remind the user to run `./scripts/install-launchd.sh` to activate the new launchd agent, and to run `npx ts-node src/workflows/<name>.ts` once manually to verify it executes.

## Critical Rules

- **Do NOT install launchd agents automatically** — that requires user approval.
- **Do NOT use `any` types** — the workflow must match `WorkflowResult` from `src/types`.
- **Do NOT add the workflow to launchd agents list without also adding the plist file** — `install-launchd.sh` will error on missing plists.
- The workflow function **must** check Ollama availability via `isAvailable()` if it calls `generate()`, and return early with `{ processed: 0, errors: 0, details: [] }` if unavailable. This matches the pattern in `process-llm.ts`.
- The CLI entry point (`if require.main === module`) is mandatory so the plist can invoke the file directly.

## Templates

Templates live in `templates/` next to this SKILL.md:
- `workflow.ts.template`
- `workflow.test.ts.template`
- `workflow.plist.template`

Read them with the Read tool when scaffolding.
