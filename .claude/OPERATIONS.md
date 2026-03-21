# Operations Context: Daily Development Tasks

**Purpose:** Common commands, testing procedures, and troubleshooting for daily Selene development. Read this when you need to DO something (test, debug, commit, deploy).

**Related Context:**
- `@src/workflows/` - TypeScript workflow scripts
- `@scripts/CLAUDE.md` - Script usage details
- `@.claude/DEVELOPMENT.md` - Why we do things this way

---

## Quick Command Reference

### Server Operations

**The Fastify webhook server runs on port 5678 with health check, ingestion, and export-obsidian trigger.**

```bash
# Check if server is running
curl -s http://localhost:5678/health

# View server logs
tail -f logs/server.out.log

# View workflow logs (structured JSON via Pino)
tail -f logs/selene.log | npx pino-pretty

# Restart server via launchd
launchctl kickstart -k gui/$(id -u)/com.selene.server

# Start server manually (for debugging)
npx ts-node src/server.ts
```

**Environment when running:**
- Selene DB: `data/selene.db`
- Obsidian vault: `vault/`
- Ollama: `http://localhost:11434`
- Webhook: `http://localhost:5678`

### Launchd Operations

**All background workflows run via macOS launchd agents (6 active).**

```bash
# List all Selene agents
launchctl list | grep selene

# Check specific agent status
launchctl list com.selene.server
launchctl list com.selene.process-llm

# Start/stop agents
launchctl start com.selene.process-llm
launchctl stop com.selene.process-llm

# Restart agent (force kill and restart)
launchctl kickstart -k gui/$(id -u)/com.selene.server

# Install all agents (run after changes to plist files)
./scripts/install-launchd.sh

# Unload an agent
launchctl unload ~/Library/LaunchAgents/com.selene.server.plist
```

**Agent Schedule:**
| Agent | Schedule |
|-------|----------|
| com.selene.server | Always running (KeepAlive) |
| com.selene.process-llm | Every 5 minutes |
| com.selene.distill-essences | Every 5 minutes |
| com.selene.export-obsidian | Hourly |
| com.selene.daily-summary | Daily at midnight |
| com.selene.send-digest | Daily at 6am |

### Workflow Operations

**Run workflows manually for testing:**

```bash
# Run individual workflows
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/distill-essences.ts
npx ts-node src/workflows/export-obsidian.ts
npx ts-node src/workflows/daily-summary.ts
npx ts-node src/workflows/send-digest.ts

# Run with debug logging
DEBUG=selene:* npx ts-node src/workflows/process-llm.ts
```

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
# Test ingestion endpoint
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Note", "content": "Test content", "test_run": "test-123"}'

# Test with full payload
TEST_RUN="test-run-$(date +%Y%m%d-%H%M%S)"
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Test Note\",
    \"content\": \"Test content with #tags\",
    \"created_at\": \"2026-01-09T12:00:00Z\",
    \"test_run\": \"$TEST_RUN\"
  }"

# List all test runs
./scripts/cleanup-tests.sh --list

# Cleanup specific test run
./scripts/cleanup-tests.sh test-123

# Cleanup all test data
./scripts/cleanup-tests.sh --all
```

### Git Operations

```bash
# Check status
git status

# Stage changes
git add src/workflows/process-llm.ts

# Commit with convention
git commit -m "feat: add concept extraction to LLM workflow"

# View recent commits
git log --oneline -10
```

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

**Test individual workflows:**

```bash
# 1. Insert test note into database
sqlite3 data/selene.db "
INSERT INTO raw_notes (title, content, content_hash, status, created_at, test_run)
VALUES ('Test Note', 'Test content', 'test-hash-123', 'pending', datetime('now'), 'test-123');
"

# 2. Run workflow
npx ts-node src/workflows/process-llm.ts

# 3. Verify results
sqlite3 data/selene.db "SELECT * FROM processed_notes WHERE test_run = 'test-123';"

# 4. Cleanup
./scripts/cleanup-tests.sh test-123
```

### Integration Testing

**Test full pipeline:**

```bash
# 1. Ingest note
TEST_RUN="integration-$(date +%Y%m%d-%H%M%S)"
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d "{\"title\": \"Integration Test\", \"content\": \"Test full pipeline\", \"test_run\": \"$TEST_RUN\"}"

# 2. Run processing workflows
npx ts-node src/workflows/process-llm.ts
npx ts-node src/workflows/distill-essences.ts

# 3. Verify each stage
sqlite3 data/selene.db "SELECT status FROM raw_notes WHERE test_run = '$TEST_RUN';"
sqlite3 data/selene.db "SELECT COUNT(*) FROM processed_notes WHERE test_run = '$TEST_RUN';"

# 4. Cleanup
./scripts/cleanup-tests.sh "$TEST_RUN"
```

---

## Debugging Workflows

### Step 1: Check Logs

```bash
# Workflow logs (Pino JSON format)
tail -f logs/selene.log | npx pino-pretty

# Server logs
tail -f logs/server.out.log

# All logs
tail -f logs/*.log
```

### Step 2: Check Database State

```bash
# Check if data exists
sqlite3 data/selene.db "SELECT * FROM raw_notes WHERE id = <id>;"

# Check status
sqlite3 data/selene.db "SELECT id, status, created_at FROM raw_notes ORDER BY id DESC LIMIT 10;"

# Check for locks
sqlite3 data/selene.db "PRAGMA wal_checkpoint;"
```

### Step 3: Run Workflow Manually

```bash
# Run with verbose output
npx ts-node src/workflows/process-llm.ts

# Check exit code
echo $?
```

### Step 4: Check Ollama

```bash
# Test Ollama directly
curl http://localhost:11434/api/generate \
  -d '{"model": "mistral:7b", "prompt": "test", "stream": false}'

# Check if Ollama is running
curl http://localhost:11434/api/tags

# Check embeddings model
curl http://localhost:11434/api/generate \
  -d '{"model": "nomic-embed-text", "prompt": "test", "stream": false}'
```

---

## Troubleshooting Quick Reference

### "Server won't start"

```bash
# Check if port 5678 in use
lsof -i :5678

# Kill process using port
kill -9 <PID>

# Check launchd status
launchctl list com.selene.server

# View error logs
tail -50 logs/server.err.log
```

### "Workflow fails"

**Checklist:**
- [ ] Check logs: `tail -f logs/selene.log | npx pino-pretty`
- [ ] Verify database file exists (`data/selene.db`)
- [ ] Check Ollama running (`curl http://localhost:11434/api/tags`)
- [ ] Run workflow manually to see full error

### "Database locked"

```bash
# Find processes using database
lsof data/selene.db

# Checkpoint WAL
sqlite3 data/selene.db "PRAGMA wal_checkpoint(TRUNCATE);"

# Check for WAL files
ls -la data/selene.db*
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

### "Launchd agent not running"

```bash
# Check if agent is loaded
launchctl list com.selene.server

# If PID is "-", agent failed to start
# Check error log
tail -50 logs/server.err.log

# Reload agent
launchctl unload ~/Library/LaunchAgents/com.selene.server.plist
launchctl load ~/Library/LaunchAgents/com.selene.server.plist
```

---

## Git Commit Procedures

### Before Committing

**Checklist:**
- [ ] All tests pass
- [ ] Documentation updated
- [ ] No test data in commit
- [ ] TypeScript compiles without errors

**Check for test data:**

```bash
# Should return nothing
git diff | grep test-run
git status | grep test-run
```

### Commit Message Format

**Format:** `type: description`

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `refactor:` Code restructure, no behavior change
- `test:` Add or modify tests
- `chore:` Maintenance (dependencies, config)

**Examples:**

```bash
# Good
git commit -m "feat: add task extraction workflow"
git commit -m "fix: handle Ollama timeout in LLM processing"
git commit -m "docs: update OPERATIONS.md with new commands"
git commit -m "refactor: extract Ollama client to shared lib"

# Bad (too vague)
git commit -m "updates"
git commit -m "fix stuff"
git commit -m "changes"
```

---

## Environment Variables

**Location:** `.env` (gitignored) or set in launchd plist files

**Key variables:**

```bash
# Server
PORT=5678
HOST=0.0.0.0

# Database
SELENE_DB_PATH=./data/selene.db

# Obsidian
OBSIDIAN_VAULT_PATH=./vault

# Ollama
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=mistral:7b
OLLAMA_EMBED_MODEL=nomic-embed-text

# Logging
LOG_LEVEL=info
LOG_FILE=./logs/selene.log
```

---

## Daily Development Checklist

### Starting Work

- [ ] Check project status: `@.claude/PROJECT-STATUS.md`
- [ ] Verify server running: `curl http://localhost:5678/health`
- [ ] Check launchd agents: `launchctl list | grep selene`
- [ ] Pull latest: `git pull`

### During Work

- [ ] Test frequently with `test_run` markers
- [ ] Check logs for errors
- [ ] Commit logical chunks (not giant diffs)
- [ ] Keep documentation current

### Before Ending Session

- [ ] Run tests
- [ ] Update PROJECT-STATUS.md
- [ ] Commit all changes
- [ ] Note next steps in PROJECT-STATUS.md
- [ ] Cleanup test data: `./scripts/cleanup-tests.sh --list`

---

## Development Environment

### Overview

A full parallel dev environment exists at `~/selene-data-dev/` with 536 fictional notes. Use `SELENE_ENV=development` to target it. **Never test against the production database.**

### Directory Layout

```
~/selene-data-dev/
  selene.db           # Dev SQLite database (environment='development')
  vault/              # Dev Obsidian vault
  vectors.lance/      # Dev LanceDB vector store
  digests/            # Dev digest output
  logs/               # Dev processing logs
```

### Quick Start

```bash
# Set up dev environment from scratch
./scripts/create-dev-db.sh                    # Create empty dev database

# Check dev processing status
./scripts/dev-process-batch.sh --status

# Run one batch manually
SELENE_ENV=development ./scripts/dev-process-batch.sh
```

### Dev Database Queries

```bash
DEV_DB=~/selene-data-dev/selene.db

# Check processing progress
sqlite3 "$DEV_DB" "SELECT COUNT(*) FROM raw_notes;"
sqlite3 "$DEV_DB" "SELECT COUNT(*) FROM processed_notes;"

# Verify it's a dev database
sqlite3 "$DEV_DB" "SELECT value FROM _selene_metadata WHERE key='environment';"
```

---

## Related Context Files

- **`@src/workflows/`** - TypeScript workflow implementations
- **`@scripts/CLAUDE.md`** - Script usage details
- **`@.claude/DEVELOPMENT.md`** - Why we do things this way
- **`@.claude/PROJECT-STATUS.md`** - Current state
