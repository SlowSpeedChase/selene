# Development Context: Architecture & Decisions

**Purpose:** Architectural patterns, technology choices, and development standards for Selene. Read this when making design decisions or understanding system internals.

**Related Context:**
- `@.claude/ADHD_Principles.md` - Why we make ADHD-focused design choices
- `@.claude/OPERATIONS.md` - How to execute common operations
- `@src/workflows/` - TypeScript workflow implementations

---

## System Architecture

### Three-Tier Design

```
+-------------------------------------------------------------+
| TIER 1: CAPTURE (Reduce Friction)                           |
| +-------------+                                              |
| | Drafts App  | -> Webhook -> src/workflows/ingest.ts       |
| +-------------+                                              |
|                                       |                      |
|                                       v                      |
|                                    SQLite                    |
| Design Goal: One-click note capture, zero organization      |
+-------------------------------------------------------------+

+-------------------------------------------------------------+
| TIER 2: PROCESS (Externalize Working Memory)                |
| +-------------------------------------------------------+   |
| | launchd Scheduled Jobs:                               |   |
| |   - process-llm.ts        -> Concepts/Themes          |   |
| |   - distill-essences.ts   -> 1-2 sentence essences    |   |
| +-------------------------------------------------------+   |
| Design Goal: Automatic organization, no manual effort       |
+-------------------------------------------------------------+

+-------------------------------------------------------------+
| TIER 3: RETRIEVE (Make Information Visible)                 |
| +------------------+   +---------------------------+         |
| | Obsidian Vault   |   | Apple Notes Daily Digest  |        |
| | (export-obsidian)|   | (send-digest @ 6am)       |        |
| +------------------+   +---------------------------+         |
| Design Goal: Push delivery — insights surface without       |
| the user needing to remember to check anything              |
+-------------------------------------------------------------+
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

### TypeScript vs n8n

**Original System:** n8n workflow engine
**Current System:** TypeScript + Fastify + launchd

**Why We Switched:**

| Aspect | n8n | TypeScript | Impact |
|--------|-----|------------|--------|
| **Debugging** | UI execution logs | Stack traces, IDE breakpoints | Faster debugging |
| **Version Control** | JSON exports, UI state sync | All code in git | No sync issues |
| **Dependencies** | Docker + n8n runtime | Node.js only | Simpler setup |
| **Type Safety** | None | TypeScript compiler | Fewer runtime errors |
| **Scheduling** | n8n triggers | macOS launchd | Native, reliable |

**Decision:** Simpler is better. TypeScript gives us full control with fewer moving parts.

### SQLite vs PostgreSQL

**Choice:** SQLite (better-sqlite3)

**Rationale:**
- **Local-first:** All data on user's machine (privacy)
- **No server management:** Zero setup friction
- **Fast enough:** Tested with 10,000+ notes
- **Portable:** Single file database
- **ADHD-friendly:** No configuration paralysis

**Trade-offs Accepted:**
- No concurrent writes (not needed for personal system)
- No advanced features (not needed yet)
- Simplicity wins for solo ADHD user

### Ollama vs Cloud LLMs

**Choice:** Ollama (mistral:7b + nomic-embed-text) local LLM

**Rationale:**
- **Privacy:** Notes never leave user's machine
- **No API costs:** Free to run unlimited processing
- **Offline capable:** Works without internet
- **Fast enough:** 10-30 seconds per note acceptable

**Trade-offs Accepted:**
- Less capable than cloud models (GPT-4, Claude) for nuanced reasoning
- Apple Silicon (M1+) required — unified memory architecture is why local inference is viable at all; discrete GPU memory bandwidth is ~30–50x slower than data center GPUs for LLM decode
- Privacy and cost win for personal notes

**What mistral:7b handles well (within Selene's current tasks):**
- Short note concept extraction and theme detection
- 1-2 sentence essence distillation
- Daily summary aggregation
- 128K context window — context exhaustion is not a concern

**Where the ceiling is:**
- Long-horizon pattern detection across months of notes (cross-note synthesis at scale)
- Non-obvious conceptual connections requiring deep reasoning
- These are out-of-scope for the current pipeline — push delivery of daily summaries is the design, not queryable intelligence

### launchd vs Cron vs Always-On Server

**Choice:** macOS launchd agents

**Rationale:**
- **Native:** Built into macOS, no extra dependencies
- **Reliable:** Proper process management, restart on failure
- **Efficient:** Only runs when scheduled, no idle resource usage
- **User-space:** No root permissions needed

**Trade-offs Accepted:**
- macOS-only (acceptable for personal system)
- Slightly more complex than cron

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
- **source_uuid:** Track individual drafts for edit detection
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

**See:** `@.claude/OPERATIONS.md` (Testing Procedures)

---

## Common Development Patterns

### Pattern 1: Duplicate Detection

**Problem:** ADHD users capture the same thought multiple times

**Solution:** SHA256 hash of content

**Implementation (TypeScript):**
```typescript
import { createHash } from 'crypto';

const contentHash = createHash('sha256')
  .update(content.trim())
  .digest('hex');
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
- `pending` -> Note captured, waiting for processing
- `processing` -> LLM currently analyzing
- `completed` -> Processing finished
- `failed` -> Error occurred (with error details)

**Transitions:**
```
pending -> processing -> completed
        |
        v
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

### Pattern 3: Structured Logging

**Tool:** Pino (fast JSON logging)

**Implementation:**
```typescript
import { logger } from './lib/logger';

logger.info({ noteId: 123 }, 'Processing note');
logger.error({ err, noteId: 123 }, 'Failed to process note');
```

**Output:** JSON lines to `logs/selene.log`

**Viewing:**
```bash
tail -f logs/selene.log | npx pino-pretty
```

### Pattern 4: Error Handling

**Rule:** All errors are logged with context

**Pattern:**
```typescript
try {
  const result = await processNote(note);
  logger.info({ noteId: note.id }, 'Note processed');
} catch (err) {
  logger.error({ err, noteId: note.id }, 'Failed to process note');
  await updateNoteStatus(note.id, 'failed');
}
```

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
```typescript
const processedNote = {
  concepts: ['time management', 'focus', 'productivity'],
  primary_theme: 'ADHD strategies',
  secondary_themes: ['executive function', 'motivation']
};

// Store as JSON string
db.run('INSERT INTO processed_notes (concepts) VALUES (?)',
  JSON.stringify(processedNote.concepts));
```

---

## Integration Points

### Ollama Integration

**URL:** `http://localhost:11434`

**Models:**
- `mistral:7b` - Text generation, concept extraction
- `nomic-embed-text` - Embeddings for semantic similarity

**API Usage (via src/lib/ollama.ts):**
```typescript
import { ollama } from './lib/ollama';

// Generate text
const response = await ollama.generate({
  model: 'mistral:7b',
  prompt: 'Extract concepts from: ...',
});

// Generate embeddings
const embedding = await ollama.embed({
  model: 'nomic-embed-text',
  input: 'Note content here',
});
```

**Common Issues:**
- Ollama not running: `ollama serve`
- Model not pulled: `ollama pull mistral:7b`
- First request slow (model loading)

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
  "created_at": "2026-01-09T12:00:00Z"
}
```

**Drafts Action Script:**
```javascript
let endpoint = "http://localhost:5678/webhook/api/drafts";
let data = {
  "title": draft.title,
  "content": draft.content,
  "created_at": draft.createdAt.toISOString()
};

let http = HTTP.create();
let response = http.request({
  "url": endpoint,
  "method": "POST",
  "data": data,
  "headers": {"Content-Type": "application/json"}
});
```

### Obsidian Export Integration

**Vault Path:** `./vault/` (or `$OBSIDIAN_VAULT_PATH`)

**Daily Summary Output:**
```
vault/Selene/Daily/YYYY-MM-DD-summary.md
```

---

## Performance Considerations

### Tested Limits

| Metric | Tested | Performance |
|--------|--------|-------------|
| **Database Size** | 10,000+ notes | No slowdown |
| **Note Processing** | mistral:7b | 10-30 seconds per note |
| **Embedding Generation** | nomic-embed-text | 1-2 seconds per note |
| **Concurrent Processing** | Sequential | 1 note at a time (by design) |

### Optimization Decisions

**Sequential Processing (Not Parallel):**
- **Why:** Ollama on consumer hardware handles 1 request well, struggles with parallel
- **Trade-off:** Slower bulk processing, but reliable results
- **ADHD Impact:** User captures notes throughout day, not in batches

**launchd Intervals:**
- Process LLM: Every 5 minutes (balance between responsiveness and resource usage)
- Distill Essences: Every 5 minutes (backfill, runs after process-llm)
- Export Obsidian: Hourly
- Daily summary: Once at midnight (natural boundary)
- Send digest: Daily at 6am (Apple Notes delivery)

---

## Development Standards

### Testing Requirements

**Every workflow must have:**
1. Test with `test_run` marker
2. Verification queries
3. Cleanup procedure

**See:** `@.claude/OPERATIONS.md` (Testing Procedures)

### Documentation Requirements

**When modifying code:**
1. Update relevant CLAUDE.md files
2. Update PROJECT-STATUS.md when complete
3. Commit with descriptive message

### Git Commit Conventions

**Format:** `type: description`

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `refactor:` Code restructure, no behavior change
- `test:` Add or modify tests
- `chore:` Maintenance

**Examples:**
```bash
git commit -m "feat: add task extraction workflow"
git commit -m "fix: handle Ollama timeout in LLM processing"
git commit -m "docs: update OPERATIONS.md with new commands"
git commit -m "refactor: extract Ollama client to shared lib"
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
- **`@src/workflows/`** - TypeScript workflow implementations
- **`@.claude/PROJECT-STATUS.md`** - Current state of development
- **`@docs/plans/INDEX.md`** - Design documents and roadmap
