# Modular Context Structure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize codebase documentation into modular, focused context files optimized for Claude Code AI development with clear separation between operational instructions, development decisions, and domain-specific patterns.

**Architecture:** Split monolithic CLAUDE.md files into focused, single-responsibility context documents. Create navigation hierarchy (.claude/ for principles, workflows/ for patterns, scripts/ for operations). Each context file serves one specific AI agent task (e.g., "modifying workflows" vs "understanding ADHD principles" vs "running tests").

**Tech Stack:** Markdown documentation, Claude Code context system, existing git repository structure

---

## Task 1: Create Context Navigation Guide

**Files:**
- Create: `.claude/README.md`

**Step 1: Write the context navigation guide**

Create `.claude/README.md` with complete structure:

```markdown
# Claude Code Context Guide

**Purpose:** Navigation map for AI agents working on Selene. Read this first to understand which context files to load for your task.

---

## Context Loading Strategy

**Claude Code automatically loads:**
- Root `CLAUDE.md` (always)
- Files in `.claude/` directory (project-wide)
- `CLAUDE.md` files in subdirectories (when working in that area)

**You should explicitly read:**
- Context files relevant to your specific task
- Referenced files using @filename syntax

---

## Quick Reference: What to Read for Common Tasks

### Modifying n8n Workflows
**Primary:** `@workflows/CLAUDE.md`
**Supporting:** `@.claude/OPERATIONS.md`, `@scripts/CLAUDE.md`
**Commands:** Use `./scripts/manage-workflow.sh`

### Understanding System Architecture
**Primary:** `@.claude/DEVELOPMENT.md`
**Supporting:** `@CLAUDE.md`, `@ROADMAP.md`

### Testing Workflows
**Primary:** `@workflows/CLAUDE.md` (Testing section)
**Supporting:** `@scripts/CLAUDE.md` (test-with-markers.sh)

### Database Operations
**Primary:** `@.claude/DEVELOPMENT.md` (Database section)
**Supporting:** `@database/schema.sql`

### ADHD Feature Design
**Primary:** `@.claude/ADHD_Principles.md`
**Supporting:** `@.claude/DEVELOPMENT.md` (Design Decisions)

### Daily Operations (Testing, Debugging, Commits)
**Primary:** `@.claude/OPERATIONS.md`
**Supporting:** `@scripts/CLAUDE.md`

### Project Status Check
**Primary:** `@.claude/PROJECT-STATUS.md`
**Supporting:** `@ROADMAP.md`

---

## Context File Descriptions

### Root Level

#### `CLAUDE.md` (Project Overview)
**Load for:** Initial orientation, system overview
**Contains:**
- Project purpose and goals
- High-level architecture diagram
- Key components list
- Critical "Do NOT" rules
- Quick reference to detailed context files

#### `ROADMAP.md` (Project Planning)
**Load for:** Understanding project phases, what's next
**Contains:**
- Phase-by-phase implementation plan
- Current status and completed work
- Links to detailed phase documents in `docs/roadmap/`

---

### `.claude/` (Project-Wide Principles)

#### `.claude/ADHD_Principles.md`
**Load for:** Designing ADHD-friendly features
**Contains:**
- Neurological characteristics of ADHD
- 3-step framework (Capture, Organize, Plan)
- Design principles (Visual Over Mental, Reduce Friction)
- Emotional regulation integration
- Success metrics for ADHD systems

#### `.claude/DEVELOPMENT.md`
**Load for:** Making architectural decisions
**Contains:**
- System architecture deep dive
- Database schema and patterns
- Technology choices and rationale
- Development patterns (testing, error handling)
- Performance considerations
- Integration points (Ollama, Obsidian, Drafts)

#### `.claude/OPERATIONS.md`
**Load for:** Daily development tasks
**Contains:**
- Common commands (Docker, testing, database)
- Testing procedures and patterns
- Debugging workflows
- Git commit conventions
- CI/CD patterns
- Troubleshooting quick reference

#### `.claude/PROJECT-STATUS.md`
**Load for:** Understanding current state
**Contains:**
- Completed workflows and features
- In-progress work
- Known issues
- Recent achievements
- Next session priorities

---

### `workflows/` (Workflow Development)

#### `workflows/CLAUDE.md`
**Load for:** Working with n8n workflows
**Contains:**
- Workflow modification procedures (CLI-only)
- Node naming conventions
- Error handling patterns
- JSON structure patterns
- Testing requirements
- Documentation requirements (STATUS.md updates)
- Integration testing patterns

#### `workflows/XX-name/README.md`
**Load for:** Understanding specific workflow
**Contains:**
- Workflow-specific quick start
- What the workflow does
- Configuration requirements
- Testing instructions

#### `workflows/XX-name/docs/STATUS.md`
**Load for:** Current test results for specific workflow
**Contains:**
- Test pass/fail status
- Known issues
- Recent changes
- Performance metrics

---

### `scripts/` (Utility Operations)

#### `scripts/CLAUDE.md`
**Load for:** Using or modifying utility scripts
**Contains:**
- Script purposes and usage
- Common patterns (test markers, cleanup)
- Integration with workflows
- Error handling examples

---

### `database/` (Data Schema)

#### `database/schema.sql`
**Load for:** Understanding data structures
**Contains:**
- Table definitions
- Column types and constraints
- Indexes and relationships
- Migration patterns

---

### `docs/` (Comprehensive Documentation)

#### `docs/README.md`
**Load for:** User-facing documentation
**Contains:**
- Setup guides
- API documentation
- Troubleshooting
- Integration guides

#### `docs/roadmap/` (Phase Documents)
**Load for:** Detailed phase implementation
**Contains:**
- Phase-specific technical details
- Implementation specifications
- Testing procedures
- Migration guides

---

## Loading Patterns for AI Agents

### Pattern 1: New to Project
```
Read:
1. @CLAUDE.md (overview)
2. @.claude/README.md (this file)
3. @.claude/PROJECT-STATUS.md (current state)
4. Task-specific context (see Quick Reference above)
```

### Pattern 2: Continuing Existing Work
```
Read:
1. @.claude/PROJECT-STATUS.md (what's in progress)
2. Task-specific context files
3. Relevant workflow/script CLAUDE.md files
```

### Pattern 3: Making Architectural Decisions
```
Read:
1. @.claude/DEVELOPMENT.md (patterns and decisions)
2. @.claude/ADHD_Principles.md (if user-facing)
3. @ROADMAP.md (future plans)
4. Relevant implementation files
```

### Pattern 4: Bug Fixing
```
Read:
1. @.claude/OPERATIONS.md (debugging procedures)
2. @workflows/CLAUDE.md (if workflow issue)
3. @scripts/CLAUDE.md (if script issue)
4. Relevant STATUS.md files
```

---

## Context File Maintenance Rules

### When to Update Each File

**`CLAUDE.md` (Root):**
- New major components added
- Architecture changes
- Critical "Do NOT" rules added

**`.claude/DEVELOPMENT.md`:**
- New architectural patterns established
- Technology choices made
- Database schema changes
- Integration points added

**`.claude/OPERATIONS.md`:**
- New common commands added
- Testing procedures change
- New debugging patterns discovered

**`.claude/PROJECT-STATUS.md`:**
- After completing any task/workflow
- Daily during active development
- When starting new work

**`workflows/CLAUDE.md`:**
- Workflow modification patterns change
- New testing requirements
- New documentation standards

**`workflows/XX-name/docs/STATUS.md`:**
- After every test run
- When bugs are discovered/fixed
- When workflow is modified

---

## Principles for Context Organization

1. **Single Responsibility:** Each file serves one specific AI task
2. **DRY:** Information lives in one canonical location
3. **Clear References:** Use @filename syntax to point to related context
4. **Minimal Loading:** Agent reads only what's needed for current task
5. **Progressive Disclosure:** Overview → Specific → Details
6. **Always Current:** Update context immediately when reality changes

---

## Questions?

If unsure which context to load, start with this file's Quick Reference section at the top.
```

**Step 2: Commit the navigation guide**

```bash
git add .claude/README.md
git commit -m "docs: add Claude Code context navigation guide"
```

---

## Task 2: Create Development Context (Architecture & Decisions)

**Files:**
- Create: `.claude/DEVELOPMENT.md`
- Reference: Current `CLAUDE.md` (extract architecture sections)

**Step 1: Extract and expand architecture content**

Create `.claude/DEVELOPMENT.md`:

```markdown
# Development Context: Architecture & Decisions

**Purpose:** Architectural patterns, technology choices, and development standards for Selene. Read this when making design decisions or understanding system internals.

**Related Context:**
- `@.claude/ADHD_Principles.md` - Why we make ADHD-focused design choices
- `@.claude/OPERATIONS.md` - How to execute common operations
- `@workflows/CLAUDE.md` - Workflow-specific implementation patterns

---

## System Architecture

### Three-Tier Design

```
┌─────────────────────────────────────────────────────────────┐
│ TIER 1: CAPTURE (Reduce Friction)                          │
│ ┌──────────────┐                                            │
│ │  Drafts App  │ → Webhook → 01-Ingestion → SQLite         │
│ └──────────────┘                                            │
│ Design Goal: One-click note capture, zero organization      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ TIER 2: PROCESS (Externalize Working Memory)               │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ n8n Workflows:                                        │   │
│ │ 02-LLM Processing → Concepts/Themes                   │   │
│ │ 03-Pattern Detection → Trends                         │   │
│ │ 05-Sentiment Analysis → Emotional Tone                │   │
│ │ 06-Connection Network → Relationships                 │   │
│ └──────────────────────────────────────────────────────┘   │
│ Design Goal: Automatic organization, visual patterns       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ TIER 3: RETRIEVE (Make Information Visible)                │
│ ┌─────────────────┐   ┌──────────────────┐                 │
│ │  SeleneChat App │   │ Obsidian Vault   │                 │
│ │  (Swift/macOS)  │   │ (04-Export)      │                 │
│ └─────────────────┘   └──────────────────┘                 │
│ Design Goal: Query and explore without mental overhead     │
└─────────────────────────────────────────────────────────────┘
```

### Why This Architecture?

**ADHD-Driven Decisions:**

1. **Single Capture Point** - Drafts app is the ONLY input
   - Reduces decision paralysis: "Where should this note go?"
   - Prevents information fragmentation across multiple apps
   - See: `@.claude/ADHD_Principles.md` (Capture section)

2. **Automatic Processing** - No manual tagging/filing
   - ADHD brains struggle with consistent categorization
   - LLM does the "thinking work" of extracting concepts
   - Visual patterns emerge without mental effort

3. **Multiple Retrieval Options** - SeleneChat + Obsidian
   - SeleneChat: Quick AI-powered search
   - Obsidian: Visual graph exploration
   - Different modes for different ADHD states (hyperfocus vs scattered)

---

## Technology Choices

### n8n vs Python

**Original System:** 10,000+ lines of Python
**Current System:** ~1,600 lines of n8n JSON

**Why We Switched:**

| Aspect | Python | n8n | ADHD Impact |
|--------|--------|-----|-------------|
| **Visibility** | Code in files | Visual canvas | ✅ Reduces "out of sight, out of mind" |
| **Debugging** | Stack traces | Execution logs | ✅ Visual flow easier to follow |
| **Maintenance** | Requires Python knowledge | Drag & drop | ✅ Lower cognitive load |
| **Setup** | venv, dependencies | Import JSON | ✅ Reduces friction |

**Decision:** Visual beats text for ADHD brains. n8n makes the entire system visible on one screen.

### SQLite vs PostgreSQL

**Choice:** SQLite (better-sqlite3)

**Rationale:**
- **Local-first:** All data on user's machine (privacy)
- **No server management:** Zero setup friction
- **Fast enough:** Tested with 10,000+ notes
- **Portable:** Single file database
- **ADHD-friendly:** No configuration paralysis

**Trade-offs Accepted:**
- ❌ No concurrent writes (not needed for personal system)
- ❌ No advanced features (not needed yet)
- ✅ Simplicity wins for solo ADHD user

### Ollama vs Cloud LLMs

**Choice:** Ollama (mistral:7b) local LLM

**Rationale:**
- **Privacy:** Notes never leave user's machine
- **No API costs:** Free to run unlimited processing
- **Offline capable:** Works without internet
- **Fast enough:** 10-30 seconds per note acceptable

**Trade-offs Accepted:**
- ❌ Less accurate than GPT-4 (good enough for concept extraction)
- ❌ Requires decent hardware (M1 Mac minimum)
- ✅ Privacy and cost win for personal notes

### Docker vs Native

**Choice:** Docker containerization

**Rationale:**
- **Reproducible:** Same environment everywhere
- **Isolated:** No conflicts with system packages
- **Easy reset:** `docker-compose down && docker-compose up -d`
- **ADHD-friendly:** "It just works" without troubleshooting

**Trade-offs Accepted:**
- ❌ Requires Docker installation
- ❌ Slightly more resource usage
- ✅ Simplicity wins over optimization

---

## Database Schema Design

### Core Tables

#### `raw_notes` (Ingestion Layer)
```sql
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,  -- SHA256 for deduplication
    source_type TEXT DEFAULT 'drafts',
    source_uuid TEXT,                    -- Draft UUID for edit tracking
    word_count INTEGER DEFAULT 0,
    character_count INTEGER DEFAULT 0,
    tags TEXT,                           -- JSON array
    created_at DATETIME NOT NULL,
    imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME,
    exported_at DATETIME,
    status TEXT DEFAULT 'pending',       -- pending, processing, completed, failed
    exported_to_obsidian INTEGER DEFAULT 0,
    test_run TEXT DEFAULT NULL           -- Test data marker
);
```

**Design Decisions:**

- **content_hash:** Prevents exact duplicates (ADHD = repeat captures of same thought)
- **source_uuid:** Track individual drafts for edit detection (Phase 1.5)
- **status column:** Explicit workflow state tracking
- **test_run:** Programmatic test data isolation (never pollute production)
- **Timestamps:** created_at (user time) vs imported_at (system time)

#### `processed_notes` (LLM Layer)
```sql
CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,                       -- JSON array of key concepts
    primary_theme TEXT,
    secondary_themes TEXT,               -- JSON array
    confidence_score REAL,
    processing_model TEXT DEFAULT 'mistral:7b',
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    test_run TEXT DEFAULT NULL,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
```

**Design Decisions:**

- **JSON storage:** Flexible arrays without separate tables (YAGNI)
- **confidence_score:** Track LLM certainty for future filtering
- **processing_model:** Track which LLM version for debugging
- **Foreign key:** Maintain relationship to source note

### Testing Pattern: test_run Column

**Problem:** How to test workflows without polluting production data?

**Solution:** Every table has nullable `test_run` column

**Pattern:**
```bash
# Test data marked with unique ID
TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"

# In test payload
{"content": "Test note", "test_run": "$TEST_RUN"}

# Cleanup
sqlite3 data/selene.db "DELETE FROM raw_notes WHERE test_run = '$TEST_RUN';"
```

**Why This Works:**
- Production data: `test_run IS NULL`
- Test data: `test_run = 'test-run-...'`
- Programmatic cleanup without manual sorting
- Zero risk of deleting production data

**See:** `@scripts/CLAUDE.md` (cleanup-tests.sh)

---

## Common Development Patterns

### Pattern 1: Duplicate Detection

**Problem:** ADHD users capture the same thought multiple times

**Solution:** SHA256 hash of content

**Implementation:**
```javascript
// In n8n Function node
const crypto = require('crypto');
const content = $json.content.trim();
const hash = crypto.createHash('sha256').update(content).digest('hex');

return {
  ...item.json,
  content_hash: hash
};
```

**Database Constraint:**
```sql
content_hash TEXT UNIQUE NOT NULL
```

**Behavior:** Second identical note is rejected (duplicate key error)

### Pattern 2: Status Tracking

**Problem:** Need to know what's been processed

**Solution:** Explicit status column with state transitions

**States:**
- `pending` → Note captured, waiting for processing
- `processing` → LLM currently analyzing
- `completed` → Processing finished
- `failed` → Error occurred (with error details)

**Transitions:**
```
pending → processing → completed
        ↓
       failed
```

**Query Pattern:**
```sql
-- Get unprocessed notes
SELECT * FROM raw_notes WHERE status = 'pending' LIMIT 10;

-- Mark as processing
UPDATE raw_notes SET status = 'processing' WHERE id = ?;

-- Mark as complete
UPDATE raw_notes SET
  status = 'completed',
  processed_at = CURRENT_TIMESTAMP
WHERE id = ?;
```

### Pattern 3: Node Naming Convention

**Format:** `[Verb] + [Object]`

**Examples:**
- ✅ "Parse Note Data"
- ✅ "Check for Duplicate"
- ✅ "Insert Raw Note"
- ✅ "Send to Ollama"
- ❌ "Function" (what does it do?)
- ❌ "Main Logic" (too vague)
- ❌ "Process" (verb needs object)

**Why:** ADHD brains scan visually. Clear names reduce cognitive load when debugging.

### Pattern 4: Error Handling

**Rule:** Every n8n node connects to error handler

**Pattern:**
```
[Node] → [Success Path]
   ↓
[On Error] → [Log Error] → [Update Status to Failed]
```

**Implementation:**
- Error node captures full context
- Logs to database or file
- Updates status column
- Optionally sends notification

**Why:** Failures must be visible. ADHD = "out of sight, out of mind" applies to errors too.

### Pattern 5: JSON Storage for Complex Data

**When to Use:**
- Arrays of strings (tags, concepts, themes)
- Small nested objects (metadata)
- Data structure evolving (early development)

**When NOT to Use:**
- Need to query/filter by nested values
- Large datasets (use proper columns + indexes)
- Relational data (use foreign keys)

**Example:**
```javascript
// Store concepts as JSON
{
  "concepts": ["time management", "focus", "productivity"],
  "primary_theme": "ADHD strategies",
  "secondary_themes": ["executive function", "motivation"]
}
```

**Query Pattern:**
```sql
-- SQLite JSON functions
SELECT * FROM processed_notes
WHERE json_extract(concepts, '$[0]') = 'time management';
```

---

## Integration Points

### Ollama Integration

**Container Access:**
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

**URL from n8n:**
```
http://host.docker.internal:11434
```

**Why:** n8n runs in Docker, Ollama runs on host machine

**Model Configuration:**
```bash
# Environment variable
OLLAMA_MODEL=mistral:7b

# In workflow
POST http://host.docker.internal:11434/api/generate
{
  "model": "{{ $env.OLLAMA_MODEL }}",
  "prompt": "...",
  "stream": false
}
```

**See:** `@docs/roadmap/11-OLLAMA-INTEGRATION.md`

### Drafts App Integration

**Webhook URL:**
```
http://localhost:5678/webhook/api/drafts        # Same device
http://192.168.1.26:5678/webhook/api/drafts     # Same WiFi
http://100.111.6.10:5678/webhook/api/drafts     # Tailscale
```

**Payload Format:**
```json
{
  "title": "Note Title",
  "content": "Note content...",
  "uuid": "draft-uuid-123",
  "test_run": null
}
```

**Drafts Action Script:**
```javascript
let endpoint = "http://localhost:5678/webhook/api/drafts";
let data = {
  "title": draft.title,
  "content": draft.content,
  "uuid": draft.uuid
};

let http = HTTP.create();
let response = http.request({
  "url": endpoint,
  "method": "POST",
  "data": data,
  "headers": {"Content-Type": "application/json"}
});
```

**See:** `@workflows/01-ingestion/docs/DRAFTS-QUICKSTART.md`

### Obsidian Export Integration

**Vault Path:**
```yaml
volumes:
  - ${OBSIDIAN_VAULT_PATH:-./vault}:/obsidian:rw
```

**Export Format:**
```markdown
---
created: 2025-11-27T10:30:00
concepts: [[time management]], [[focus]], [[productivity]]
theme: ADHD strategies
---

# Note Title

Note content...

## Extracted Concepts
- time management
- focus
- productivity

## Related Notes
- [[Note about focus]]
- [[Note about productivity]]
```

**See:** `@workflows/04-obsidian-export/`

---

## Performance Considerations

### Tested Limits

| Metric | Tested | Performance |
|--------|--------|-------------|
| **Database Size** | 10,000+ notes | No slowdown |
| **Note Processing** | mistral:7b | 10-30 seconds per note |
| **Export Speed** | Obsidian | ~50 notes/minute |
| **Concurrent Processing** | Sequential | 1 note at a time (by design) |

### Optimization Decisions

**Sequential Processing (Not Parallel):**
- **Why:** Ollama on consumer hardware (M1 Mac) handles 1 request well, struggles with parallel
- **Trade-off:** Slower bulk processing, but reliable results
- **ADHD Impact:** User captures notes throughout day, not in batches

**Polling vs Event-Driven:**
- **Original:** Cron schedules (every 30 seconds)
- **Phase 6:** Event-driven triggers
- **Result:** 3x faster processing, 100% resource efficiency
- **See:** `@docs/roadmap/08-PHASE-6-EVENT-DRIVEN.md`

---

## Development Standards

### Testing Requirements

**Every workflow must have:**
1. `scripts/test-with-markers.sh` - Automated test suite
2. `docs/STATUS.md` - Test results and pass/fail tracking
3. Test cases for success path
4. Test cases for error conditions
5. Cleanup procedure

**See:** `@workflows/CLAUDE.md` (Testing section)

### Documentation Requirements

**When modifying workflows:**
1. Update `workflows/XX-name/docs/STATUS.md` with changes
2. Update `workflows/XX-name/README.md` if interface changed
3. Update `.claude/PROJECT-STATUS.md` when complete
4. Commit workflow.json to git

**See:** `@workflows/CLAUDE.md` (Documentation section)

### Git Commit Conventions

**Format:** `type: description`

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `refactor:` Code restructure, no behavior change
- `test:` Add or modify tests
- `workflow:` n8n workflow changes

**Examples:**
```bash
git commit -m "feat: add task extraction workflow"
git commit -m "fix: duplicate detection in ingestion workflow"
git commit -m "docs: update STATUS.md with test results"
git commit -m "workflow: add error handling to LLM processing"
```

---

## Questions to Ask When Designing Features

### ADHD Impact Check

Before implementing any feature, ask:

1. **Does this reduce friction?**
   - How many clicks/decisions required?
   - Can it be automated?

2. **Is this visible?**
   - Will user remember it exists?
   - Can they see progress/state?

3. **Does this reduce cognitive load?**
   - How much mental tracking required?
   - Can information be externalized?

4. **Is this realistic (not idealistic)?**
   - Does it assume perfect user behavior?
   - Does it account for forgetfulness?

**See:** `@.claude/ADHD_Principles.md` for full framework

### Technical Decision Checklist

1. **YAGNI:** Do we actually need this now?
2. **DRY:** Are we duplicating existing functionality?
3. **Testability:** Can we write automated tests?
4. **Simplicity:** Is this the simplest solution?
5. **Visibility:** Can we see when it breaks?

---

## Related Context Files

- **`@.claude/ADHD_Principles.md`** - Why ADHD drives our architecture
- **`@.claude/OPERATIONS.md`** - Daily commands and operations
- **`@workflows/CLAUDE.md`** - Workflow implementation patterns
- **`@.claude/PROJECT-STATUS.md`** - Current state of development
- **`@ROADMAP.md`** - Planned phases and features
```

**Step 2: Commit development context**

```bash
git add .claude/DEVELOPMENT.md
git commit -m "docs: add development context with architecture and decisions"
```

---

## Task 3: Create Operations Context (Daily Commands)

**Files:**
- Create: `.claude/OPERATIONS.md`
- Reference: Current `CLAUDE.md` (extract commands/operations)

**Step 1: Create operations guide**

Create `.claude/OPERATIONS.md`:

```markdown
# Operations Context: Daily Development Tasks

**Purpose:** Common commands, testing procedures, and troubleshooting for daily Selene development. Read this when you need to DO something (test, debug, commit, deploy).

**Related Context:**
- `@workflows/CLAUDE.md` - Workflow-specific operations
- `@scripts/CLAUDE.md` - Script usage details
- `@.claude/DEVELOPMENT.md` - Why we do things this way

---

## Quick Command Reference

### Docker Operations

```bash
# Start n8n
docker-compose up -d

# Stop n8n
docker-compose down

# View logs (follow mode)
docker-compose logs -f n8n

# Restart n8n
docker-compose restart n8n

# Check container status
docker-compose ps

# Shell into container
docker exec -it selene /bin/sh
```

### n8n Workflow Management

**CRITICAL: Always use CLI commands. Never manual UI edits.**

```bash
# List all workflows with IDs
./scripts/manage-workflow.sh list

# Export workflow to JSON (auto-backup)
./scripts/manage-workflow.sh export <workflow-id>

# Export to specific file
./scripts/manage-workflow.sh export <workflow-id> /workflows/XX-name/workflow.json

# Import new workflow
./scripts/manage-workflow.sh import /workflows/XX-name/workflow.json

# Update existing workflow (backup + import)
./scripts/manage-workflow.sh update <workflow-id> /workflows/XX-name/workflow.json

# Show workflow details
./scripts/manage-workflow.sh show <workflow-id>

# Backup credentials
./scripts/manage-workflow.sh backup-creds
```

**See:** `@workflows/CLAUDE.md` for workflow modification procedures

### Database Operations

```bash
# Open SQLite CLI
sqlite3 data/selene.db

# Common queries
sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes;"
sqlite3 data/selene.db "SELECT * FROM raw_notes WHERE status='pending' LIMIT 5;"
sqlite3 data/selene.db ".schema raw_notes"
sqlite3 data/selene.db ".tables"

# Export database
sqlite3 data/selene.db ".backup data/selene-backup-$(date +%Y%m%d).db"

# Check database integrity
sqlite3 data/selene.db "PRAGMA integrity_check;"
```

### Testing Operations

```bash
# Test specific workflow
cd workflows/01-ingestion
./scripts/test-with-markers.sh

# List all test runs
./scripts/cleanup-tests.sh --list

# Cleanup specific test run
./scripts/cleanup-tests.sh test-run-20251127-120000

# Cleanup all test data
./scripts/cleanup-tests.sh --all

# Test ingestion endpoint directly
./scripts/test-ingest.sh
```

### Git Operations

```bash
# Check status
git status

# Stage workflow changes
git add workflows/XX-name/workflow.json workflows/XX-name/docs/STATUS.md

# Commit with convention
git commit -m "workflow: add error handling to ingestion"

# View recent commits
git log --oneline -10

# Check for uncommitted test data
git status | grep test-run
```

---

## Workflow Modification Procedure

**MANDATORY STEPS - Do not skip any step**

### Step 1: List Workflows

```bash
./scripts/manage-workflow.sh list
```

Output shows workflow IDs and names.

### Step 2: Export Current Version (Backup)

```bash
./scripts/manage-workflow.sh export <workflow-id>
```

Creates timestamped backup in `/workflows/backup-<id>-<timestamp>.json`

### Step 3: Edit Workflow JSON

Use Read/Edit tools on `workflows/XX-name/workflow.json`

**Common edits:**
- Add new node
- Modify node parameters
- Change connections
- Update credentials

**Do NOT:**
- Edit in n8n UI (changes won't persist in git)
- Skip backup step
- Modify without testing

### Step 4: Import Updated Workflow

```bash
./scripts/manage-workflow.sh update <workflow-id> /workflows/XX-name/workflow.json
```

This automatically:
1. Creates backup
2. Imports new version
3. Replaces existing workflow

### Step 5: Test Workflow

```bash
cd workflows/XX-name
./scripts/test-with-markers.sh
```

**Verify:**
- All test cases pass
- No errors in n8n execution logs
- Database updated correctly
- Cleanup works

### Step 6: Update Documentation

```bash
# Edit STATUS.md with test results
# Edit README.md if interface changed
# Update PROJECT-STATUS.md if workflow complete
```

### Step 7: Commit to Git

```bash
git add workflows/XX-name/workflow.json
git add workflows/XX-name/docs/STATUS.md
git commit -m "workflow: description of changes"
```

**See:** `@workflows/CLAUDE.md` for detailed workflow patterns

---

## Testing Procedures

### Test Data Pattern

**ALWAYS use test_run markers for test data**

```bash
# Generate unique test run ID
TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"

# Use in test payload
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Test Note\",
    \"content\": \"Test content\",
    \"test_run\": \"$TEST_RUN\"
  }"

# Verify data created
sqlite3 data/selene.db "SELECT * FROM raw_notes WHERE test_run = '$TEST_RUN';"

# Cleanup
./scripts/cleanup-tests.sh "$TEST_RUN"
```

**Why:**
- Production data: `test_run IS NULL`
- Test data: `test_run = 'test-run-...'`
- Zero risk of deleting production data
- Programmatic cleanup

### Workflow Testing Pattern

**Every workflow should have:**

1. **Test script:** `workflows/XX-name/scripts/test-with-markers.sh`
2. **Test cases:**
   - Success path (normal operation)
   - Error conditions (missing data, invalid input)
   - Edge cases (duplicates, large data, etc.)
3. **Cleanup:** Automatic cleanup prompt
4. **Documentation:** Results in `docs/STATUS.md`

**Example Test Script:**

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
WEBHOOK_URL="http://localhost:5678/webhook/api/drafts"

echo "Testing with marker: $TEST_RUN"

# Test 1: Normal note
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"title\": \"Test\", \"content\": \"Test\", \"test_run\": \"$TEST_RUN\"}"

# Verify
COUNT=$(sqlite3 ../../data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE test_run = '$TEST_RUN';")
echo "Created $COUNT notes (expected: 1)"

# Cleanup prompt
read -p "Cleanup test data? (y/n) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ../../scripts/cleanup-tests.sh "$TEST_RUN"
fi
```

### Integration Testing

**Test full pipeline:**

```bash
# 1. Ingest note
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Integration Test", "content": "Test full pipeline", "test_run": "integration-test"}'

# 2. Wait for processing (if event-driven) or trigger manually

# 3. Verify each stage
sqlite3 data/selene.db "SELECT status FROM raw_notes WHERE test_run = 'integration-test';"
sqlite3 data/selene.db "SELECT COUNT(*) FROM processed_notes WHERE test_run = 'integration-test';"
sqlite3 data/selene.db "SELECT COUNT(*) FROM sentiment_history WHERE test_run = 'integration-test';"

# 4. Cleanup
./scripts/cleanup-tests.sh integration-test
```

---

## Debugging Workflows

### Step 1: Check Execution Logs

**In n8n UI:**
1. Open workflow
2. Click "Executions" tab
3. Find failed execution
4. Click to view details
5. Check each node's input/output

**Common issues:**
- Node received empty data
- JSON parsing error
- Database connection failed
- Ollama timeout

### Step 2: Check Docker Logs

```bash
# Real-time logs
docker-compose logs -f n8n

# Last 100 lines
docker-compose logs --tail=100 n8n

# Search for errors
docker-compose logs n8n | grep -i error
```

### Step 3: Check Database State

```bash
# Check if data exists
sqlite3 data/selene.db "SELECT * FROM raw_notes WHERE id = <id>;"

# Check status
sqlite3 data/selene.db "SELECT id, status, created_at FROM raw_notes ORDER BY id DESC LIMIT 10;"

# Check for locks
sqlite3 data/selene.db "PRAGMA wal_checkpoint;"
```

### Step 4: Manual Node Testing

**Test individual nodes:**

1. In n8n UI, click "Execute Node"
2. Provide sample input data
3. Verify output
4. Check for errors

**Test database queries:**

```javascript
// In n8n Function node
const Database = require('better-sqlite3');
const db = new Database('/selene/data/selene.db');

try {
  const result = db.prepare('SELECT * FROM raw_notes LIMIT 1').get();
  console.log('Result:', result);
  return {json: result};
} catch (error) {
  console.error('Error:', error);
  throw error;
} finally {
  db.close();
}
```

### Step 5: Ollama Connection Testing

```bash
# From host machine
curl http://localhost:11434/api/generate \
  -d '{"model": "mistral:7b", "prompt": "test", "stream": false}'

# From n8n container
docker exec selene curl http://host.docker.internal:11434/api/generate \
  -d '{"model": "mistral:7b", "prompt": "test", "stream": false}'
```

**Common Ollama issues:**
- Ollama not running: `ollama serve`
- Model not pulled: `ollama pull mistral:7b`
- host.docker.internal not mapped (check docker-compose.yml)

---

## Git Commit Procedures

### Before Committing

**Checklist:**
- [ ] All tests pass
- [ ] Documentation updated (STATUS.md, README.md)
- [ ] No test data in commit
- [ ] Workflow JSON validated

**Check for test data:**

```bash
# Should return nothing
git diff | grep test-run
git status | grep test-run

# If found, unstage
git reset HEAD <file-with-test-data>
```

### Commit Message Format

**Format:** `type: description`

**Types:**
- `feat:` New feature (e.g., new workflow)
- `fix:` Bug fix
- `docs:` Documentation only
- `refactor:` Code restructure, no behavior change
- `test:` Add or modify tests
- `workflow:` n8n workflow changes
- `chore:` Maintenance (dependencies, config)

**Examples:**

```bash
# Good
git commit -m "feat: add task extraction workflow (07)"
git commit -m "fix: duplicate detection in ingestion workflow"
git commit -m "docs: update STATUS.md with Phase 1.5 results"
git commit -m "workflow: add error handling to LLM processing"

# Bad (too vague)
git commit -m "updates"
git commit -m "fix stuff"
git commit -m "changes to workflow"
```

### Commit Workflow Changes

**Always commit these together:**

```bash
# 1. Workflow JSON
git add workflows/XX-name/workflow.json

# 2. Updated documentation
git add workflows/XX-name/docs/STATUS.md
git add workflows/XX-name/README.md  # if changed

# 3. Project status (if workflow complete)
git add .claude/PROJECT-STATUS.md

# 4. Commit with descriptive message
git commit -m "workflow: add sentiment analysis to ingestion pipeline

- Added sentiment node after LLM processing
- Extracts emotional tone and ADHD markers
- Updates processed_notes with sentiment data
- All 7/7 tests passing"
```

---

## Troubleshooting Quick Reference

### "Container won't start"

```bash
# Check if port 5678 in use
lsof -i :5678

# Kill process using port
kill -9 <PID>

# Remove old containers
docker-compose down -v
docker-compose up -d
```

### "Workflow fails immediately"

**Checklist:**
- [ ] Check credentials in n8n UI
- [ ] Verify database file exists (`data/selene.db`)
- [ ] Check Ollama running (`ollama serve`)
- [ ] Check Docker logs for errors

### "Database locked"

```bash
# Close all connections
docker-compose restart n8n

# Check for WAL files
ls -la data/selene.db*

# Checkpoint WAL
sqlite3 data/selene.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

### "Ollama timeout"

**Causes:**
- Model not loaded (first request is slow)
- System under load
- Ollama crashed

**Solutions:**

```bash
# Restart Ollama
pkill ollama
ollama serve

# Check Ollama logs
tail -f ~/.ollama/logs/server.log

# Test Ollama directly
ollama run mistral:7b "test prompt"
```

### "better-sqlite3 not found"

```bash
# Check if installed in container
docker exec selene ls /home/node/.n8n/node_modules/better-sqlite3

# Reinstall if missing
docker exec selene npm install -g better-sqlite3

# Restart container
docker-compose restart n8n
```

---

## Environment Variables

**Location:** `.env` file (not committed to git)

**Key variables:**

```bash
# Authentication
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=your_secure_password

# Paths
SELENE_DB_PATH=/selene/data/selene.db
OBSIDIAN_VAULT_PATH=./vault

# Ollama
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=mistral:7b

# Node modules
NODE_FUNCTION_ALLOW_EXTERNAL=better-sqlite3
NODE_PATH=/home/node/.n8n/node_modules

# Timezone
TIMEZONE=America/Chicago
```

**To change:**

```bash
# 1. Edit .env file
nano .env

# 2. Restart container
docker-compose down
docker-compose up -d
```

---

## Daily Development Checklist

### Starting Work

- [ ] Check project status: `@.claude/PROJECT-STATUS.md`
- [ ] Start Docker: `docker-compose up -d`
- [ ] Check container: `docker-compose ps`
- [ ] Pull latest: `git pull`
- [ ] Review what's next in `@ROADMAP.md`

### During Work

- [ ] Test frequently with `test-run` markers
- [ ] Update STATUS.md after changes
- [ ] Commit logical chunks (not giant diffs)
- [ ] Keep documentation current

### Before Ending Session

- [ ] Run full test suite
- [ ] Update PROJECT-STATUS.md
- [ ] Commit all changes
- [ ] Note next steps in PROJECT-STATUS.md
- [ ] Cleanup test data: `./scripts/cleanup-tests.sh --list`

---

## Related Context Files

- **`@workflows/CLAUDE.md`** - Workflow-specific operations
- **`@scripts/CLAUDE.md`** - Script usage details
- **`@.claude/DEVELOPMENT.md`** - Why we do things this way
- **`@.claude/PROJECT-STATUS.md`** - Current state
```

**Step 2: Commit operations context**

```bash
git add .claude/OPERATIONS.md
git commit -m "docs: add operations context for daily development tasks"
```

---

## Task 4: Create Workflow-Specific Context

**Files:**
- Create: `workflows/CLAUDE.md`
- Reference: Current root `CLAUDE.md` (extract workflow sections)

**Step 1: Create workflow development guide**

Create `workflows/CLAUDE.md`:

```markdown
# Workflow Development Context

**Purpose:** n8n workflow implementation patterns, testing requirements, and modification procedures. Read this when working with any workflow.

**Related Context:**
- `@.claude/OPERATIONS.md` - Commands to manage workflows
- `@.claude/DEVELOPMENT.md` - Architecture and design decisions
- `@scripts/CLAUDE.md` - Script utilities (manage-workflow.sh)

---

## CRITICAL RULE: CLI-Only Workflow Modifications

**ALWAYS use command line tools to modify workflows. NEVER edit in n8n UI without exporting to JSON.**

**Why:**
- UI changes don't persist in git
- JSON files are source of truth
- CLI workflow ensures testing and documentation
- Version control requires committed JSON files

**See:** `@.claude/OPERATIONS.md` (Workflow Modification Procedure)

---

## Workflow Modification Workflow

### Standard Process (6 Steps)

**Step 1: Export Current Version**

```bash
./scripts/manage-workflow.sh export <workflow-id>
```

Creates timestamped backup automatically.

**Step 2: Edit JSON File**

```bash
# Use Read/Edit tools on:
workflows/XX-name/workflow.json
```

**Common modifications:**
- Add new node
- Change node parameters
- Modify connections
- Update error handling

**Step 3: Import Updated Version**

```bash
./scripts/manage-workflow.sh update <workflow-id> /workflows/XX-name/workflow.json
```

**Step 4: Test Workflow**

```bash
cd workflows/XX-name
./scripts/test-with-markers.sh
```

**Step 5: Update Documentation**

```bash
# REQUIRED updates:
workflows/XX-name/docs/STATUS.md    # Test results
workflows/XX-name/README.md         # If interface changed
.claude/PROJECT-STATUS.md           # If workflow complete
```

**Step 6: Commit Changes**

```bash
git add workflows/XX-name/workflow.json
git add workflows/XX-name/docs/STATUS.md
git commit -m "workflow: description of changes"
```

---

## Workflow JSON Structure

### Top-Level Properties

```json
{
  "name": "01-Ingestion Workflow",
  "nodes": [...],
  "connections": {...},
  "settings": {...},
  "staticData": null,
  "tags": [],
  "triggerCount": 1,
  "updatedAt": "2025-11-27T10:00:00.000Z"
}
```

### Node Structure

```json
{
  "parameters": {
    // Node-specific configuration
  },
  "id": "unique-uuid",
  "name": "Verb + Object Format",
  "type": "n8n-nodes-base.Function",
  "typeVersion": 1,
  "position": [x, y],
  "onError": "continueErrorOutput"  // Error handling
}
```

### Connection Structure

```json
{
  "Node Name": {
    "main": [
      [
        {
          "node": "Next Node",
          "type": "main",
          "index": 0
        }
      ]
    ]
  }
}
```

---

## Node Naming Conventions

### Format: [Verb] + [Object]

**Good Examples:**
- ✅ "Parse Note Data"
- ✅ "Check for Duplicate"
- ✅ "Insert Raw Note"
- ✅ "Extract Concepts"
- ✅ "Send to Ollama"
- ✅ "Update Note Status"
- ✅ "Log Error Details"

**Bad Examples:**
- ❌ "Function" (what does it do?)
- ❌ "Main Logic" (too vague)
- ❌ "Process" (verb needs object)
- ❌ "Node 1" (meaningless)
- ❌ "TODO" (not descriptive)

**Why:** ADHD brains scan visually. Clear names reduce cognitive load when debugging flow.

### Verb Categories

**Data Operations:**
- Parse, Extract, Transform, Format, Validate

**Database Operations:**
- Insert, Update, Delete, Query, Check

**External Services:**
- Send, Receive, Fetch, Upload, Download

**Control Flow:**
- Route, Filter, Merge, Split, Aggregate

**Error Handling:**
- Log, Catch, Handle, Retry, Notify

---

## Error Handling Patterns

### Pattern 1: Error Output on Every Node

**Configuration:**

```json
{
  "parameters": {...},
  "onError": "continueErrorOutput"
}
```

**Benefit:** Error path can handle failures without stopping workflow.

### Pattern 2: Dedicated Error Handler

**Structure:**

```
[Any Node] → [Success Path] → ...
     ↓
[Error Output] → [Log Error] → [Update Status to Failed] → [Stop]
```

**Log Error Node (Function):**

```javascript
const error = $input.item.json.error || 'Unknown error';
const context = $input.item.json;

console.error('Workflow Error:', {
  error: error,
  node: context.node,
  timestamp: new Date().toISOString(),
  data: context
});

return {
  json: {
    error: error,
    logged_at: new Date().toISOString()
  }
};
```

**Update Status Node (SQLite):**

```javascript
const Database = require('better-sqlite3');
const db = new Database('/selene/data/selene.db');

const noteId = $json.raw_note_id || $json.id;

db.prepare(`
  UPDATE raw_notes
  SET status = 'failed',
      error_message = ?
  WHERE id = ?
`).run($json.error, noteId);

db.close();

return {json: $json};
```

### Pattern 3: Retry Logic

**For transient failures (network, timeouts):**

```javascript
// In Function node
const maxRetries = 3;
const retryCount = $json.retry_count || 0;

if (retryCount < maxRetries) {
  // Increment retry counter
  return {
    json: {
      ...$json,
      retry_count: retryCount + 1
    }
  };
} else {
  // Max retries reached, fail
  throw new Error('Max retries exceeded');
}
```

**Connect back to original operation for retry.**

---

## Database Integration Patterns

### Pattern 1: better-sqlite3 in Function Nodes

**Always follow this structure:**

```javascript
const Database = require('better-sqlite3');
const db = new Database('/selene/data/selene.db');

try {
  // Your database operations here
  const result = db.prepare('SELECT * FROM raw_notes WHERE id = ?').get($json.id);

  return {json: result};

} catch (error) {
  console.error('Database error:', error);
  throw error;
} finally {
  db.close();  // CRITICAL: Always close connection
}
```

**Why try/finally:**
- Ensures connection closes even on error
- Prevents database locks
- Clean resource management

### Pattern 2: Parameterized Queries (Prevent SQL Injection)

**Good (Parameterized):**

```javascript
db.prepare('SELECT * FROM raw_notes WHERE id = ?').get($json.id);
db.prepare('INSERT INTO raw_notes (title, content) VALUES (?, ?)').run($json.title, $json.content);
```

**Bad (String Concatenation - SQL Injection Risk):**

```javascript
// NEVER DO THIS
db.prepare(`SELECT * FROM raw_notes WHERE id = ${$json.id}`).get();
db.prepare(`INSERT INTO raw_notes (title) VALUES ('${$json.title}')`).run();
```

### Pattern 3: Transaction for Multi-Step Operations

**Use transactions when:**
- Multiple related inserts/updates
- Need atomicity (all or nothing)
- Rollback on error

**Example:**

```javascript
const Database = require('better-sqlite3');
const db = new Database('/selene/data/selene.db');

const transaction = db.transaction(() => {
  // Step 1: Insert raw note
  const rawNoteResult = db.prepare(`
    INSERT INTO raw_notes (title, content, status)
    VALUES (?, ?, 'pending')
  `).run($json.title, $json.content);

  const rawNoteId = rawNoteResult.lastInsertRowid;

  // Step 2: Insert processed note
  db.prepare(`
    INSERT INTO processed_notes (raw_note_id, concepts)
    VALUES (?, ?)
  `).run(rawNoteId, JSON.stringify($json.concepts));

  return rawNoteId;
});

try {
  const noteId = transaction();
  db.close();
  return {json: {id: noteId, success: true}};
} catch (error) {
  db.close();
  throw error;
}
```

**Benefits:**
- Atomic: Both inserts succeed or both fail
- Rollback: Error in step 2 undoes step 1
- Performance: Single write to disk

### Pattern 4: Handling NULL vs Undefined

**Problem:** SQLite NULL vs JavaScript undefined/null

**Solution: Explicit null checks**

```javascript
// Check for existence
const row = db.prepare('SELECT id FROM raw_notes WHERE content_hash = ?').get($json.hash);

if (row === undefined) {
  // No match found
  return {json: {exists: false}};
} else {
  // Match found
  return {json: {exists: true, id: row.id}};
}
```

**Common mistake:**

```javascript
// BAD: undefined != null in JavaScript
if (row == null) {
  // This catches both null and undefined, but confusing
}

// GOOD: Explicit
if (row === undefined) {
  // No row returned
}
```

---

## Testing Requirements

### Every Workflow Must Have

**1. Test Script:** `workflows/XX-name/scripts/test-with-markers.sh`

**Template:**

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
WEBHOOK_URL="http://localhost:5678/webhook/api/WORKFLOW_ENDPOINT"

echo "Testing XX-name workflow with marker: $TEST_RUN"

# Test Case 1: Success path
echo "Test 1: Normal operation"
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"test_data\": \"value\", \"test_run\": \"$TEST_RUN\"}"

sleep 2  # Wait for processing

# Test Case 2: Error condition
echo "Test 2: Invalid input"
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"invalid\": true, \"test_run\": \"$TEST_RUN\"}"

# Verify results
PASS_COUNT=$(sqlite3 ../../data/selene.db "SELECT COUNT(*) FROM table WHERE test_run = '$TEST_RUN' AND status = 'completed';")
FAIL_COUNT=$(sqlite3 ../../data/selene.db "SELECT COUNT(*) FROM table WHERE test_run = '$TEST_RUN' AND status = 'failed';")

echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

# Cleanup prompt
read -p "Cleanup test data? (y/n) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ../../scripts/cleanup-tests.sh "$TEST_RUN"
fi
```

**2. Test Cases Coverage:**

**Minimum required:**
- ✅ Success path (normal operation)
- ✅ Missing required fields
- ✅ Invalid data format
- ✅ Duplicate detection (if applicable)
- ✅ Database constraints (unique, foreign key)

**Nice to have:**
- Large data (stress test)
- Edge cases (empty strings, special characters)
- Concurrent requests
- Recovery from errors

**3. STATUS.md:** `workflows/XX-name/docs/STATUS.md`

**Template:**

```markdown
# XX-Name Workflow Status

**Last Updated:** YYYY-MM-DD
**Test Results:** X/Y passing

---

## Current Status

**Production Ready:** ✅ Yes / ❌ No

**Test Coverage:**
- ✅ Success path
- ✅ Error handling
- ✅ Database integration
- ❌ Edge cases (TODO)

---

## Test Results

### Latest Run (YYYY-MM-DD)

**Test Suite:** `./scripts/test-with-markers.sh`

| Test Case | Status | Notes |
|-----------|--------|-------|
| Normal operation | ✅ PASS | |
| Missing fields | ✅ PASS | Proper error message |
| Invalid format | ✅ PASS | |
| Duplicate | ✅ PASS | Rejected correctly |
| Large data | ⚠️ SKIP | Not critical |

**Overall:** 4/4 critical tests passing

---

## Known Issues

1. **Issue:** Description
   **Impact:** High/Medium/Low
   **Workaround:** Temporary solution
   **Status:** Open/In Progress/Fixed

---

## Recent Changes

### YYYY-MM-DD
- Added error handling for X
- Fixed duplicate detection
- Updated documentation

### YYYY-MM-DD
- Initial implementation
- Basic test coverage
```

---

## Documentation Requirements

### When You Modify a Workflow

**MUST update:**
1. ✅ `workflows/XX-name/docs/STATUS.md` - Test results and changes
2. ✅ `workflows/XX-name/README.md` - If interface/usage changed
3. ✅ `.claude/PROJECT-STATUS.md` - If workflow complete or status changed

**SHOULD update:**
4. `workflows/XX-name/docs/*-REFERENCE.md` - If technical details changed
5. `ROADMAP.md` - If phase complete

**Example workflow:**

```bash
# 1. Modify workflow
./scripts/manage-workflow.sh update 1 /workflows/01-ingestion/workflow.json

# 2. Test
cd workflows/01-ingestion
./scripts/test-with-markers.sh

# 3. Update STATUS.md
# (Document test results, changes made)

# 4. Update README.md (if needed)
# (Update usage examples if API changed)

# 5. Update PROJECT-STATUS.md
# (Mark workflow complete, note achievements)

# 6. Commit all together
git add workflows/01-ingestion/workflow.json
git add workflows/01-ingestion/docs/STATUS.md
git add .claude/PROJECT-STATUS.md
git commit -m "workflow: add sentiment extraction to ingestion

- Added sentiment analysis node
- Extracts emotional tone
- All 5/5 tests passing
- Updated documentation"
```

---

## Common Workflow Patterns

### Pattern 1: Webhook Trigger

**Configuration:**

```json
{
  "parameters": {
    "path": "api/drafts",
    "responseMode": "onReceived",
    "options": {}
  },
  "name": "Webhook Trigger",
  "type": "n8n-nodes-base.Webhook"
}
```

**Options:**
- `responseMode: "onReceived"` - Return immediately, process async
- `responseMode: "lastNode"` - Wait for workflow completion

**ADHD Impact:** Use "onReceived" to reduce perceived latency (user doesn't wait).

### Pattern 2: Schedule Trigger

**Configuration:**

```json
{
  "parameters": {
    "rule": {
      "interval": [
        {
          "field": "seconds",
          "secondsInterval": 30
        }
      ]
    }
  },
  "name": "Schedule Trigger",
  "type": "n8n-nodes-base.Schedule"
}
```

**Common intervals:**
- Every 30 seconds: Processing loop
- Every 5 minutes: Periodic checks
- Daily at 6am: Batch operations

**Phase 6 Note:** Event-driven triggers preferred over schedules (3x faster, 100% efficient).

### Pattern 3: Conditional Routing (IF Node)

**Configuration:**

```json
{
  "parameters": {
    "conditions": {
      "string": [
        {
          "value1": "={{$json.status}}",
          "operation": "equals",
          "value2": "pending"
        }
      ]
    }
  },
  "name": "Check Status",
  "type": "n8n-nodes-base.If"
}
```

**Outputs:**
- `true` branch - Condition met
- `false` branch - Condition not met

**Common mistake:** Using Switch node with `notExists` for null checks (doesn't work). Use IF node with explicit null check.

### Pattern 4: Function Node (JavaScript)

**Always include error handling:**

```javascript
try {
  // Your logic here
  const result = processData($json);
  return {json: result};

} catch (error) {
  console.error('Function error:', error);

  return {
    json: {
      error: error.message,
      input: $json
    }
  };
}
```

**Available globals:**
- `$json` - Current item data
- `$input` - All input items
- `$env` - Environment variables
- `require()` - Node.js modules (whitelisted)

**Whitelisted modules:**
- `better-sqlite3` - Database
- `crypto` - Hashing
- Standard library (fs, path, etc.)

### Pattern 5: Merge Node (Combine Data)

**Use when:**
- Joining data from multiple sources
- Adding enrichment data
- Combining parallel branches

**Configuration:**

```json
{
  "parameters": {
    "mode": "mergeByIndex",  // or "mergeByKey"
    "options": {}
  },
  "name": "Merge Data",
  "type": "n8n-nodes-base.Merge"
}
```

**Modes:**
- `mergeByIndex` - Combine items at same position
- `mergeByKey` - Join on matching field (like SQL JOIN)

---

## Integration Testing

### Test Full Pipeline

**Example: Ingestion → Processing → Export**

```bash
#!/bin/bash
set -e

TEST_RUN="integration-$(date +%Y%m%d-%H%M%S)"

echo "=== Integration Test: Full Pipeline ==="

# 1. Ingest note
echo "Step 1: Ingesting note..."
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Integration Test Note\",
    \"content\": \"This is a test of the full pipeline from ingestion through export.\",
    \"test_run\": \"$TEST_RUN\"
  }"

echo "Waiting for processing..."
sleep 15

# 2. Verify ingestion
echo "Step 2: Checking ingestion..."
INGESTED=$(sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE test_run = '$TEST_RUN';")
echo "Ingested: $INGESTED (expected: 1)"

# 3. Verify processing
echo "Step 3: Checking LLM processing..."
PROCESSED=$(sqlite3 data/selene.db "SELECT COUNT(*) FROM processed_notes WHERE test_run = '$TEST_RUN';")
echo "Processed: $PROCESSED (expected: 1)"

# 4. Verify sentiment
echo "Step 4: Checking sentiment analysis..."
SENTIMENT=$(sqlite3 data/selene.db "SELECT COUNT(*) FROM sentiment_history WHERE test_run = '$TEST_RUN';")
echo "Sentiment: $SENTIMENT (expected: 1)"

# 5. Verify export
echo "Step 5: Checking Obsidian export..."
if [ -f "vault/Selene/Integration Test Note.md" ]; then
  echo "Exported: Yes"
else
  echo "Exported: No (check export workflow)"
fi

# Summary
echo ""
echo "=== Integration Test Summary ==="
echo "Ingested: $INGESTED"
echo "Processed: $PROCESSED"
echo "Sentiment: $SENTIMENT"

# Cleanup prompt
read -p "Cleanup test data? (y/n) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./scripts/cleanup-tests.sh "$TEST_RUN"
    rm -f "vault/Selene/Integration Test Note.md"
fi
```

---

## Performance Optimization

### Sequential vs Parallel Processing

**Current (Sequential):**
- Process 1 note at a time
- Wait for completion before next
- Prevents Ollama overload

**Why not parallel:**
- Ollama on M1 Mac handles 1 request well
- Parallel requests cause slowdowns
- ADHD users capture notes throughout day (not batches)

**When to consider parallel:**
- Bulk import of existing notes
- More powerful hardware
- Cloud-hosted Ollama

### Event-Driven vs Scheduled

**Phase 6 Migration:**

**Before (Scheduled):**
```json
{
  "type": "n8n-nodes-base.Schedule",
  "parameters": {
    "rule": {"interval": [{"field": "seconds", "secondsInterval": 30}]}
  }
}
```
- Runs every 30 seconds
- Wastes resources if no data
- 20-25 second processing time

**After (Event-Driven):**
```json
{
  "type": "n8n-nodes-base.Trigger",
  "parameters": {
    "events": ["workflow:completed"]
  }
}
```
- Triggers only when previous workflow completes
- Zero wasted executions
- ~14 second processing time
- 3x faster, 100% efficient

**See:** `@docs/roadmap/08-PHASE-6-EVENT-DRIVEN.md`

---

## Workflow Directory Structure

**Standard structure for each workflow:**

```
workflows/XX-name/
├── workflow.json          # Main n8n workflow (source of truth)
├── README.md             # Quick start guide
├── docs/
│   ├── STATUS.md         # Test results and current state
│   ├── SETUP.md          # Configuration instructions
│   └── REFERENCE.md      # Technical details
├── scripts/
│   ├── test-with-markers.sh   # Automated test suite
│   └── cleanup-tests.sh       # Test data cleanup (optional)
└── tests/                # Test data/fixtures (optional)
```

**Why this structure:**
- `workflow.json` - Version controlled, single source of truth
- `README.md` - Quick orientation (ADHD = needs fast context)
- `STATUS.md` - Current state visible (ADHD = needs status visible)
- `test-with-markers.sh` - Automated testing (prevents regressions)

---

## Related Context Files

- **`@.claude/OPERATIONS.md`** - Commands to execute workflows
- **`@.claude/DEVELOPMENT.md`** - Architecture and design patterns
- **`@scripts/CLAUDE.md`** - Script utilities (manage-workflow.sh)
- **`@.claude/PROJECT-STATUS.md`** - Current workflow status
```

**Step 2: Commit workflow context**

```bash
git add workflows/CLAUDE.md
git commit -m "docs: add workflow development context with patterns and testing"
```

---

## Task 5: Update Root CLAUDE.md (Lightweight with References)

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Replace root CLAUDE.md with lightweight overview**

Replace entire content of `CLAUDE.md`:

```markdown
# Selene-n8n Project Context

> **For Claude:** This is a high-level overview. For detailed context, see the Context Guide below and load specific files as needed.

---

## Purpose

ADHD-focused knowledge management system using n8n workflows, SQLite, and local LLM processing for note capture, organization, and retrieval. Designed to externalize working memory and make information visual and accessible.

---

## Tech Stack

- **n8n** - Workflow automation engine (Docker-based)
- **SQLite** + better-sqlite3 - Database for note storage
- **Ollama** + mistral:7b - Local LLM for concept extraction
- **Swift** + SwiftUI - SeleneChat macOS app
- **Docker** - Container orchestration
- **Drafts** - iOS/Mac note capture app

---

## Context Navigation

**New to this project? Start here:** `@.claude/README.md`

**Quick reference for common tasks:**

| Task | Primary Context | Supporting Context |
|------|-----------------|-------------------|
| **Modify workflows** | `@workflows/CLAUDE.md` | `@.claude/OPERATIONS.md` |
| **Understand architecture** | `@.claude/DEVELOPMENT.md` | `@ROADMAP.md` |
| **Run tests** | `@.claude/OPERATIONS.md` | `@workflows/CLAUDE.md` |
| **Design ADHD features** | `@.claude/ADHD_Principles.md` | `@.claude/DEVELOPMENT.md` |
| **Daily operations** | `@.claude/OPERATIONS.md` | `@scripts/CLAUDE.md` |
| **Check status** | `@.claude/PROJECT-STATUS.md` | `@ROADMAP.md` |

---

## Architecture Overview

### Three-Tier System

```
┌─────────────────────────────────────────────────────────────┐
│ TIER 1: CAPTURE                                             │
│ Drafts App → Webhook → 01-Ingestion → SQLite               │
│ Design: One-click capture, zero friction                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ TIER 2: PROCESS                                             │
│ n8n Workflows → Ollama LLM → Extract patterns              │
│ Design: Automatic organization, visual patterns            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ TIER 3: RETRIEVE                                            │
│ SeleneChat (macOS) + Obsidian → Query & Explore            │
│ Design: Information visible without mental overhead        │
└─────────────────────────────────────────────────────────────┘
```

**Why this architecture?** See `@.claude/DEVELOPMENT.md` (System Architecture section)

---

## ADHD Design Principles

1. **Externalize Working Memory** - Visual systems, not mental tracking
2. **Make Time Visible** - Structured vs. unstructured time
3. **Reduce Friction** - One-click capture, minimal steps
4. **Visual Over Mental** - "Out of sight, out of mind"
5. **Realistic Over Idealistic** - Under-schedule, not over-schedule

**Full framework:** `@.claude/ADHD_Principles.md`

---

## Critical Rules (Do NOT)

**Workflow Modifications:**
- ❌ **NEVER edit workflows in n8n UI without exporting to JSON** - Changes won't persist in git
- ❌ **NEVER modify workflows without using docker exec commands** - Use CLI for all changes
- ✅ **ALWAYS use** `./scripts/manage-workflow.sh` for workflow operations

**Testing:**
- ❌ **NEVER use production database for testing** - Always use test_run markers
- ❌ **NEVER skip `test_run` marker** when testing workflows
- ❌ **NEVER commit test data** to production tables
- ✅ **ALWAYS cleanup test data** with `./scripts/cleanup-tests.sh`

**Documentation:**
- ❌ **NEVER modify workflow.json without updating STATUS.md**
- ✅ **ALWAYS update documentation** after changes

**Security:**
- ❌ **NEVER commit .env files** - Use .env.example only
- ❌ **NEVER skip duplicate detection** in ingestion workflow

**Code Quality:**
- ❌ **NEVER use ANY type** in TypeScript/Swift - Always specify types
- ✅ **ALWAYS use parameterized SQL queries** (prevent injection)

**See:** `@workflows/CLAUDE.md` and `@.claude/OPERATIONS.md` for detailed procedures

---

## Quick Command Reference

### Workflow Management
```bash
./scripts/manage-workflow.sh list              # List workflows
./scripts/manage-workflow.sh export <id>       # Export workflow
./scripts/manage-workflow.sh update <id> <file> # Update workflow
```

### Testing
```bash
./workflows/XX-name/scripts/test-with-markers.sh  # Test workflow
./scripts/cleanup-tests.sh --list                  # List test runs
./scripts/cleanup-tests.sh <test-run-id>           # Cleanup
```

### Docker
```bash
docker-compose up -d       # Start
docker-compose logs -f n8n # View logs
docker-compose restart n8n # Restart
```

### Database
```bash
sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes;"
sqlite3 data/selene.db ".schema raw_notes"
```

**Full command reference:** `@.claude/OPERATIONS.md`

---

## Project Status

**Completed:**
- ✅ Workflow 01 (Ingestion) - Production ready, 6/7 tests passing
- ✅ Workflow 02 (LLM Processing) - Concept extraction working
- ✅ SeleneChat - Database integration, Ollama AI, clickable citations

**In Progress:**
- 🔨 Phase 1.5 - UUID Tracking Foundation
- 🔨 Phase 7 - Things Integration (planning complete)

**Next Up:**
- ⬜ Workflow 03 (Pattern Detection) - Theme trend analysis
- ⬜ Phase 2 - Obsidian Export - ADHD-optimized export

**Details:** `@.claude/PROJECT-STATUS.md`

---

## File Organization

### Key Directories

```
selene/
├── .claude/                 # Context files for AI development
│   ├── README.md           # Context navigation guide (START HERE)
│   ├── DEVELOPMENT.md      # Architecture and decisions
│   ├── OPERATIONS.md       # Daily commands and procedures
│   ├── ADHD_Principles.md  # ADHD design framework
│   └── PROJECT-STATUS.md   # Current state
├── workflows/              # n8n workflows
│   ├── CLAUDE.md          # Workflow development patterns
│   └── XX-name/           # Individual workflows
│       ├── workflow.json  # Source of truth
│       ├── README.md      # Quick start
│       ├── docs/STATUS.md # Test results
│       └── scripts/       # Test utilities
├── scripts/                # Project-wide utilities
│   ├── CLAUDE.md          # Script documentation
│   └── manage-workflow.sh # Workflow CLI tool
├── database/              # Database schema
│   └── schema.sql
├── docs/                  # User documentation
│   ├── README.md          # Documentation index
│   └── roadmap/           # Phase documents
├── SeleneChat/            # macOS app
└── data/                  # SQLite database
    └── selene.db
```

---

## Common Workflows

### Modifying a Workflow

1. Export: `./scripts/manage-workflow.sh export <id>`
2. Edit: Use Read/Edit tools on `workflows/XX-name/workflow.json`
3. Update: `./scripts/manage-workflow.sh update <id> <file>`
4. Test: `./workflows/XX-name/scripts/test-with-markers.sh`
5. Document: Update `workflows/XX-name/docs/STATUS.md`
6. Commit: `git add workflows/XX-name/workflow.json workflows/XX-name/docs/STATUS.md`

**See:** `@workflows/CLAUDE.md` (Workflow Modification Workflow)

### Testing Changes

1. Generate test ID: `TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"`
2. Send test data with `test_run` marker
3. Verify results in database
4. Cleanup: `./scripts/cleanup-tests.sh "$TEST_RUN"`

**See:** `@.claude/OPERATIONS.md` (Testing Procedures)

### Daily Development

**Starting:**
- Check `@.claude/PROJECT-STATUS.md`
- Start Docker: `docker-compose up -d`
- Review `@ROADMAP.md` for next tasks

**During:**
- Test frequently with `test_run` markers
- Update STATUS.md after changes
- Commit logical chunks

**Ending:**
- Run full test suite
- Update PROJECT-STATUS.md
- Cleanup test data
- Commit all changes

**See:** `@.claude/OPERATIONS.md` (Daily Development Checklist)

---

## Learning Resources

**Getting oriented:**
1. Read `@.claude/README.md` (context navigation)
2. Read `@.claude/DEVELOPMENT.md` (architecture)
3. Read `@.claude/ADHD_Principles.md` (design philosophy)
4. Read `@.claude/PROJECT-STATUS.md` (current state)

**Working on specific tasks:**
- Workflows: `@workflows/CLAUDE.md`
- Scripts: `@scripts/CLAUDE.md`
- Operations: `@.claude/OPERATIONS.md`

**Deep dives:**
- Database schema: `@database/schema.sql`
- Phase details: `@docs/roadmap/`
- Project roadmap: `@ROADMAP.md`

---

## Support

**Documentation Questions:**
- Start with `@.claude/README.md` (context guide)
- Check relevant context file for your task
- Review `@docs/README.md` (user documentation)

**Technical Issues:**
- Check `@.claude/OPERATIONS.md` (Troubleshooting section)
- Review workflow STATUS.md files
- Check Docker logs: `docker-compose logs -f n8n`

---

## Version History

- **2025-11-27**: Reorganized into modular context structure
- **2025-11-13**: Added SeleneChat enhancements phase
- **2025-11-01**: Added Phase 1.5 (UUID Tracking Foundation)
- **2025-10-30**: Phase 1 completed (10 notes processed)
- **2025-10-18**: Initial roadmap created

---

**This is a living document. Update after major changes or architectural decisions.**

**For detailed context on any topic, see the navigation guide:** `@.claude/README.md`
```

**Step 2: Commit updated root CLAUDE.md**

```bash
git add CLAUDE.md
git commit -m "docs: reorganize root CLAUDE.md as lightweight overview with context references"
```

---

## Task 6: Test Context Loading and Update PROJECT-STATUS.md

**Files:**
- Modify: `.claude/PROJECT-STATUS.md`

**Step 1: Test context file readability**

Read each new context file to verify:

```bash
# 1. Context navigation guide
cat .claude/README.md

# 2. Development context
cat .claude/DEVELOPMENT.md

# 3. Operations context
cat .claude/OPERATIONS.md

# 4. Workflow context
cat workflows/CLAUDE.md

# 5. Updated root context
cat CLAUDE.md
```

Expected: All files readable, no syntax errors, cross-references work.

**Step 2: Update PROJECT-STATUS.md with new structure**

Add section to `.claude/PROJECT-STATUS.md`:

```markdown
---

## Context Structure (2025-11-27)

### Modular Documentation

The codebase now uses modular context files optimized for Claude Code AI development:

**Root Level:**
- `CLAUDE.md` - High-level overview with navigation
- `ROADMAP.md` - Project phases and planning

**`.claude/` Directory:**
- `README.md` - Context navigation guide (START HERE)
- `DEVELOPMENT.md` - Architecture, patterns, decisions
- `OPERATIONS.md` - Daily commands and procedures
- `ADHD_Principles.md` - ADHD design framework
- `PROJECT-STATUS.md` - Current state (this file)

**`workflows/` Directory:**
- `CLAUDE.md` - Workflow development patterns
- `XX-name/workflow.json` - Source of truth for workflows
- `XX-name/docs/STATUS.md` - Per-workflow test results

**`scripts/` Directory:**
- `CLAUDE.md` - Script utilities documentation
- `manage-workflow.sh` - Workflow CLI tool (new)

### Why This Structure?

**Single Responsibility:**
- Each file serves one specific AI task
- Development decisions separate from operations
- Workflow patterns separate from architecture

**Minimal Context Loading:**
- Agents read only what's needed for current task
- Faster context loading
- Reduced token usage

**DRY Principle:**
- Information lives in one canonical location
- Cross-references using @filename syntax
- No duplication across files

### Loading Patterns

**For workflow modifications:**
```
@workflows/CLAUDE.md → @.claude/OPERATIONS.md → @scripts/CLAUDE.md
```

**For architectural decisions:**
```
@.claude/DEVELOPMENT.md → @.claude/ADHD_Principles.md → @ROADMAP.md
```

**For daily operations:**
```
@.claude/OPERATIONS.md → @.claude/PROJECT-STATUS.md
```

---
```

**Step 3: Commit PROJECT-STATUS update**

```bash
git add .claude/PROJECT-STATUS.md
git commit -m "docs: document new modular context structure in PROJECT-STATUS"
```

---

## Verification Steps

### Step 1: Verify all files created

```bash
ls -la .claude/
ls -la workflows/CLAUDE.md
ls -la scripts/manage-workflow.sh
```

Expected:
- `.claude/README.md` exists
- `.claude/DEVELOPMENT.md` exists
- `.claude/OPERATIONS.md` exists
- `workflows/CLAUDE.md` exists
- `scripts/manage-workflow.sh` exists and is executable

### Step 2: Verify cross-references

```bash
grep -r "@.claude/" .claude/
grep -r "@workflows/" .claude/
grep -r "@scripts/" workflows/
```

Expected: All @references point to existing files

### Step 3: Test manage-workflow.sh script

```bash
# Should show usage
./scripts/manage-workflow.sh --help

# Should check container
./scripts/manage-workflow.sh list
```

Expected: Script runs without errors

### Step 4: Verify git status

```bash
git status
```

Expected: All new files committed, working tree clean

---

## Complete!

**Summary of changes:**

1. ✅ Created `.claude/README.md` - Context navigation guide
2. ✅ Created `.claude/DEVELOPMENT.md` - Architecture and decisions
3. ✅ Created `.claude/OPERATIONS.md` - Daily operations
4. ✅ Created `workflows/CLAUDE.md` - Workflow patterns
5. ✅ Updated `CLAUDE.md` - Lightweight overview with references
6. ✅ Updated `.claude/PROJECT-STATUS.md` - Documented new structure
7. ✅ Created `scripts/manage-workflow.sh` - Workflow CLI tool

**Benefits:**

- **Modular:** Each file serves one specific AI task
- **DRY:** Information lives in one canonical location
- **Minimal Loading:** Agents read only what's needed
- **Clear Navigation:** Quick reference for common tasks
- **Maintainable:** Updates go to specific, focused files

**Next steps:**

Use the new structure:
1. Start with `@.claude/README.md` for navigation
2. Load task-specific context files as needed
3. Update context files as reality changes
4. Keep documentation current with code
```

**Step 2: Save implementation plan**

```bash
git add docs/plans/2025-11-27-modular-context-structure.md
git commit -m "docs: add implementation plan for modular context structure"
```

---

## Execution Options

Plan complete and saved to `docs/plans/2025-11-27-modular-context-structure.md`.

**Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration with quality gates

**2. Parallel Session (separate)** - Open new session with executing-plans skill, batch execution with checkpoints

**Which approach would you like?**