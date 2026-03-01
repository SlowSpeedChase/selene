# Workflow Lifecycle Management Design

> **Status:** Approved
> **Created:** 2025-12-31
> **Purpose:** Git-first workflow management to prevent n8n database clutter

---

## Problem Statement

The current `manage-workflow.sh update` command uses the `--separate` flag, which creates new workflows instead of updating existing ones. This has resulted in:
- 5 versions of 07-Task-Extraction in n8n
- 8 versions of 08-Daily-Summary in n8n
- Confusion navigating the n8n UI
- No clear "canonical" version

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Source of truth | Git (`workflow.json` files) | Already version-controlled; enables code review |
| Identity tracking | `.workflow-ids.json` mapping file | Keeps workflow.json portable; single mapping location |
| Orphan handling | List only; separate `cleanup` command | Safe by default; explicit deletion |
| Update mechanism | n8n CLI import with ID injection | Uses supported tooling; preserves execution history |

---

## File Structure

```
selene/
├── .workflow-ids.json          # Maps logical names → n8n IDs (gitignored)
├── .workflow-ids.example.json  # Template showing expected format
├── workflows/
│   ├── 01-ingestion/
│   │   └── workflow.json       # Source of truth
│   ├── 07-task-extraction/
│   │   └── workflow.json
│   └── ...
└── scripts/
    └── manage-workflow.sh      # Enhanced with new commands
```

### The Mapping File (`.workflow-ids.json`)

```json
{
  "01-ingestion": "nsc1eqvBs7V2ofnv",
  "02-llm-processing": "Zj85TfAsIrfyowxG",
  "07-task-extraction": "OGrqsbTzuo83vzaR",
  "08-daily-summary": "2F4d6XmX9dTs3pGB"
}
```

- Auto-generated/updated by sync commands
- Gitignored (each environment may have different IDs)
- Created on first sync if missing

---

## Commands

| Command | Purpose |
|---------|---------|
| `sync` | Push all git workflows to n8n, update mapping file |
| `sync <name>` | Push single workflow (e.g., `sync 07-task-extraction`) |
| `status` | Show sync state: which are synced, orphaned, or missing |
| `cleanup` | Interactive deletion of orphaned n8n workflows |
| `cleanup --force` | Delete all orphans without prompting |
| `init` | First-time setup: import all workflows, create mapping file |

### Command Examples

```bash
# Sync all workflows from git → n8n
./scripts/manage-workflow.sh sync
# Output:
# [SYNC] 01-ingestion → nsc1eqvBs7V2ofnv ✓
# [SYNC] 07-task-extraction → OGrqsbTzuo83vzaR ✓
# [SKIP] 08-daily-summary (unchanged)
# [WARN] 3 orphaned workflows in n8n (run 'status' for details)

# Check current state
./scripts/manage-workflow.sh status
# Output:
# === Synced Workflows ===
# 01-ingestion        → nsc1eqvBs7V2ofnv (active)
# 07-task-extraction  → OGrqsbTzuo83vzaR (active)
#
# === Orphaned in n8n (not in git) ===
# BFaYfc5Lc3N4i18F    07-Task-Extraction (inactive)
# esuEBL3M3g4S1ZA0    07-Task-Extraction (inactive)
#
# === Missing from n8n (in git, not deployed) ===
# (none)

# Clean up orphans
./scripts/manage-workflow.sh cleanup
# Output:
# Found 5 orphaned workflows:
#   BFaYfc5Lc3N4i18F  07-Task-Extraction
#   esuEBL3M3g4S1ZA0  07-Task-Extraction
#   ...
# Delete all? [y/N]:
```

---

## Sync Logic

```
┌─────────────────────────────────────────────────────────────┐
│ For each workflow.json in workflows/*/                      │
├─────────────────────────────────────────────────────────────┤
│ 1. Extract logical name from directory (e.g., "07-task...")│
│ 2. Check .workflow-ids.json for existing n8n ID            │
│                                                             │
│ If ID exists:                                               │
│   → Inject ID into workflow JSON                           │
│   → n8n import:workflow (overwrites existing)              │
│                                                             │
│ If ID missing (new workflow):                              │
│   → n8n import:workflow (creates new)                      │
│   → Capture new ID from n8n                                │
│   → Update .workflow-ids.json                              │
└─────────────────────────────────────────────────────────────┘
```

### ID Injection Detail

n8n uses the `id` field inside the JSON to determine whether to update or create. Before importing, the sync command:

1. Reads workflow.json from git
2. Looks up the n8n ID from mapping file
3. Injects/overwrites the `id` field in memory
4. Writes to a temp file
5. Imports the temp file
6. Cleans up temp file

This keeps git workflow.json files clean (no n8n-specific IDs) while enabling in-place updates.

---

## Orphan Detection & Cleanup

### How Orphan Detection Works

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Get all workflow IDs from n8n database                   │
│ 2. Get all tracked IDs from .workflow-ids.json              │
│ 3. Orphans = n8n IDs - tracked IDs                         │
└─────────────────────────────────────────────────────────────┘
```

### Cleanup Output

```
Found 7 orphaned workflows:

ID                  Name                      Active  Created
─────────────────────────────────────────────────────────────
BFaYfc5Lc3N4i18F    07-Task-Extraction        no      2025-12-31
esuEBL3M3g4S1ZA0    07-Task-Extraction        no      2025-12-31
WMFuQNSB4LVHOVUZ    08-Daily-Summary          no      2025-12-31
...

Delete all 7 orphaned workflows? [y/N]:
```

### Safety Guards

- Never delete active workflows without explicit `--include-active` flag
- Show workflow names, not just IDs (easier to verify)
- Require confirmation unless `--force` is passed
- Log all deletions to stdout for audit trail

---

## Typical Development Flow

```bash
# 1. Make changes to workflow JSON in git
vim workflows/07-task-extraction/workflow.json
# (or use Claude to edit)

# 2. Push changes to n8n
./scripts/manage-workflow.sh sync 07-task-extraction

# 3. Test the workflow
./workflows/07-task-extraction/scripts/test-with-markers.sh

# 4. If good, commit
git add workflows/07-task-extraction/workflow.json
git commit -m "feat(07): add classification node"
```

---

## Migration (First-Time Setup)

For the current cluttered state, run once:

```bash
# 1. Initialize mapping with current "canonical" workflows
./scripts/manage-workflow.sh init

# This will:
# - Scan workflows/*/ directories
# - For each, find the ACTIVE workflow in n8n with matching name
# - Create .workflow-ids.json mapping to those IDs
# - Report any ambiguity (multiple active workflows with same name)

# 2. Review orphans
./scripts/manage-workflow.sh status

# 3. Clean up old versions
./scripts/manage-workflow.sh cleanup
```

### Handling Conflicts

If multiple active workflows have the same name (like 08-Daily-Summary), the `init` command will:
- Detect the conflict
- Prompt to choose which ID to keep
- Or allow manual edit of `.workflow-ids.json`

---

## Out of Scope (YAGNI)

| Feature | Why Not |
|---------|---------|
| Bidirectional sync (n8n → git) | Git-first means this isn't needed |
| Workflow versioning/history | Git already handles this |
| Automatic sync on file save | Explicit `sync` is clearer |
| Per-environment configs | Single environment for now |
| Rollback command | Use git checkout + sync |
| Dry-run mode | `status` command serves this purpose |

---

## Future Enhancements (If Needed)

- Hash-based change detection to skip unchanged workflows
- `export` command to pull from n8n → git (for prototyping)
- CI integration to auto-sync on merge to main

---

## Implementation Notes

### n8n CLI Commands Used

```bash
# List workflows
n8n list:workflow

# Import (update if ID matches, create if not)
n8n import:workflow --input=/path/to/workflow.json

# Delete workflow
n8n delete:workflow --id=<workflow-id>

# Export workflow
n8n export:workflow --id=<workflow-id> --output=/path/to/output.json
```

### Getting New Workflow ID After Creation

After `n8n import:workflow` creates a new workflow, query the database or use `n8n list:workflow` to find the newly created ID by matching on name.
