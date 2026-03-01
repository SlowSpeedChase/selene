# Development Environment Isolation Design

**Date:** 2025-11-30
**Status:** Approved
**Purpose:** Separate development and production environments to enable safe workflow development without contaminating production data.

---

## Problem Statement

Current development challenges:
1. **Data contamination** - Test data mixes with real notes
2. **Development risk** - Modifying workflows risks breaking production
3. **Context switching** - Mental overhead switching between dev and production modes
4. **AI development safety** - Claude needs to work with non-production data
5. **Sustainability** - Project must remain manageable as it grows

---

## Solution: Dual Docker Stack

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         GIT REPOSITORY                          │
│                    (Single Source of Truth)                     │
│                                                                 │
│   workflows/01-ingestion/workflow.json                         │
│   workflows/02-llm-processing/workflow.json                    │
│   ...                                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
┌───────────────────────────┐ ┌───────────────────────────────────┐
│   PRODUCTION STACK        │ │   DEVELOPMENT STACK               │
│                           │ │                                   │
│   Port: 5678              │ │   Port: 5679                      │
│   DB: data/selene.db      │ │   DB: data/selene-dev.db          │
│   Status: Always running  │ │   Status: On-demand               │
│                           │ │                                   │
│   Your real notes         │ │   Test/dummy data                 │
│   Don't touch during dev  │ │   Claude works here freely        │
└───────────────────────────┘ └───────────────────────────────────┘
```

### Key Principles

1. **Git is the single source of truth** - Both environments import workflows from the same JSON files
2. **Environments differ only in data** - Same workflows, different databases
3. **Production stays untouched** - Claude never modifies production during development
4. **Explicit promotion** - Changes reach production only through checklist-gated process

---

## File Organization

```
selene/
├── docker-compose.yml              # Production stack (existing, minor changes)
├── docker-compose.dev.yml          # Development stack (new)
├── .claude/
│   ├── CURRENT-ENV.md              # Environment indicator for Claude
│   └── ...existing files...
├── data/
│   ├── selene.db                   # Production database (hands off)
│   └── selene-dev.db               # Development database (Claude's playground)
├── scripts/
│   ├── dev-start.sh                # Start dev stack
│   ├── dev-stop.sh                 # Stop dev stack
│   ├── dev-reset-db.sh             # Reset dev DB to clean state
│   ├── dev-seed-data.sh            # Load sample test data
│   └── promote-workflow.sh         # Checklist-driven promotion
└── workflows/
    └── ...unchanged...
```

### Guardrails Against Context Overload

1. **`CURRENT-ENV.md`** - Single file Claude checks to know which environment is active
2. **Script encapsulation** - Complex operations hidden inside single-command scripts
3. **No file duplication** - Workflows exist once; environment differences only in docker-compose

---

## Environment Configuration

### Production Stack (`docker-compose.yml`)

Existing file with minor additions:

```yaml
services:
  n8n:
    container_name: selene
    ports:
      - "5678:5678"
    environment:
      - SELENE_DB_PATH=/selene/data/selene.db
      - SELENE_ENV=production
    volumes:
      - ./data:/selene/data:rw
      - n8n_data:/home/node/.n8n
```

### Development Stack (`docker-compose.dev.yml`)

New file:

```yaml
services:
  n8n-dev:
    container_name: selene-dev
    build: .
    ports:
      - "5679:5678"
    environment:
      - SELENE_DB_PATH=/selene/data/selene-dev.db
      - SELENE_ENV=development
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=selene_dev_2025
      - NODE_FUNCTION_ALLOW_EXTERNAL=better-sqlite3
      - NODE_PATH=/home/node/.n8n/node_modules
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
      - OLLAMA_MODEL=mistral:7b
    volumes:
      - ./data:/selene/data:rw
      - ./vault:/obsidian:rw
      - .:/workflows:ro
      - n8n_dev_data:/home/node/.n8n
    extra_hosts:
      - "host.docker.internal:host-gateway"

volumes:
  n8n_dev_data:
```

### What Stays the Same

- Workflow files (mounted read-only from same location)
- Ollama connection configuration
- better-sqlite3 setup
- All existing workflows

### What Differs

| Aspect | Production | Development |
|--------|------------|-------------|
| Container name | `selene` | `selene-dev` |
| Port | 5678 | 5679 |
| Database | `selene.db` | `selene-dev.db` |
| n8n data volume | `n8n_data` | `n8n_dev_data` |
| Auth password | `selene_n8n_2025` | `selene_dev_2025` |

---

## Workflow Promotion Checklist

The `scripts/promote-workflow.sh` script enforces this checklist:

```
┌─────────────────────────────────────────────────────────────────┐
│              WORKFLOW PROMOTION CHECKLIST                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  □ 1. VERIFY DEV TESTS PASS                                    │
│       Run: ./workflows/XX-name/scripts/test-with-markers.sh    │
│       Gate: All tests green? [y/n]                             │
│                                                                 │
│  □ 2. SHOW DIFF                                                │
│       Run: git diff workflows/XX-name/workflow.json            │
│       Gate: Changes look correct? [y/n]                        │
│                                                                 │
│  □ 3. DOCUMENT CHANGES                                         │
│       Verify: STATUS.md updated with what changed              │
│       Gate: Documentation current? [y/n]                       │
│                                                                 │
│  □ 4. USER APPROVAL                                            │
│       Summary shown to user                                    │
│       Gate: Approve promotion? [y/n]                           │
│                                                                 │
│  □ 5. IMPORT TO PRODUCTION                                     │
│       Run: ./scripts/manage-workflow.sh update <id> <file>     │
│       Target: Production n8n (port 5678)                       │
│                                                                 │
│  □ 6. VERIFY PRODUCTION                                        │
│       Run: Quick smoke test against production                 │
│       Gate: Production working? [y/n]                          │
│                                                                 │
│  □ 7. COMMIT                                                   │
│       Run: git commit with promotion message                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Process:**
- Claude creates TodoWrite items for each checklist step
- User sees progress and approves at each gate
- If any gate fails, promotion stops
- Nothing reaches production without explicit approval

---

## Claude's Development Workflow

### Starting a Development Session

```bash
# Claude runs:
./scripts/dev-start.sh

# Script:
# 1. Starts dev stack (docker-compose -f docker-compose.dev.yml up -d)
# 2. Updates .claude/CURRENT-ENV.md to "development"
# 3. Waits for n8n-dev to be healthy

# Claude confirms:
"Dev environment ready on port 5679"
```

### During Development

```bash
# 1. Claude checks environment
cat .claude/CURRENT-ENV.md  # Confirms: "development"

# 2. Claude edits workflow JSON files directly
#    (Never touches n8n UI)

# 3. Claude imports to dev stack
./scripts/manage-workflow.sh update <id> <file> --dev

# 4. Claude tests with dev database
#    - Uses selene-dev.db
#    - Uses test_run markers as backup safety

# 5. Claude iterates freely
#    - Breaking things is fine
#    - Production is untouched
```

### When Ready to Promote

```bash
# 1. User says: "This looks good, let's promote"

# 2. Claude runs promotion script
./scripts/promote-workflow.sh 01-ingestion

# 3. Claude creates TodoWrite items for each checklist step

# 4. User approves at each gate

# 5. Production updated only after all gates pass
```

### Ending a Session

```bash
# Optional - dev can stay running
./scripts/dev-stop.sh

# Clean up test data
./scripts/cleanup-tests.sh
```

### Key Constraint

All database queries during development target `selene-dev.db`. Claude never reads or writes `selene.db` unless:
- Explicitly promoting a workflow
- User requests production debugging

---

## Sustainability Guardrails

### Against Context Overload

- **One entry point:** `CURRENT-ENV.md` tells Claude everything about current state
- **Script wrappers:** Complex operations hidden behind single commands
- **No file duplication:** Workflows exist once, not per-environment
- **Existing structure preserved:** Adds ~5 new files, not a reorganization

### Against Drift

- **Git is truth:** Both environments import from same JSON files
- **No UI edits:** Existing rule, now enforced by workflow
- **Promotion is explicit:** Changes don't "leak" to production
- **Smoke test on promote:** Catches drift immediately

### Against Complexity Creep

- **Dev stack is optional:** Production works independently; dev is additive
- **Scripts are simple:** Each does one thing (start, stop, reset, promote)
- **Checklist is the process:** No hidden steps or tribal knowledge
- **Can delete dev anytime:** Remove `docker-compose.dev.yml` to return to current setup

### Project Growth Protection

- Workflows stay in existing structure
- New workflows follow same pattern automatically
- No per-workflow configuration needed

---

## Implementation Files

### New Files to Create

| File | Purpose |
|------|---------|
| `docker-compose.dev.yml` | Development stack configuration |
| `.claude/CURRENT-ENV.md` | Environment indicator for Claude |
| `scripts/dev-start.sh` | Start dev stack |
| `scripts/dev-stop.sh` | Stop dev stack |
| `scripts/dev-reset-db.sh` | Reset dev database to clean state |
| `scripts/dev-seed-data.sh` | Load sample test data |
| `scripts/promote-workflow.sh` | Checklist-driven promotion |

### Files to Modify

| File | Change |
|------|--------|
| `docker-compose.yml` | Add `SELENE_ENV=production` environment variable |
| `scripts/manage-workflow.sh` | Add `--dev` flag for targeting dev stack |
| `.claude/OPERATIONS.md` | Document dev workflow procedures |

### Files Unchanged

- All existing workflows
- Database schema
- Drafts integration
- Production behavior

---

## Success Criteria

1. Production n8n runs independently on port 5678
2. Development n8n runs on port 5679 with separate database
3. Claude can develop freely without touching production data
4. Workflow changes require explicit promotion through checklist
5. Project remains manageable as workflows grow

---

## Open Questions (Resolved)

- **Q: Where should source of truth live?**
  A: Git. Both environments import from same workflow JSON files.

- **Q: How to handle workflow promotion?**
  A: Checklist-driven script with user approval gates.

- **Q: How to prevent context overload for Claude?**
  A: Single `CURRENT-ENV.md` file, script encapsulation, no file duplication.
