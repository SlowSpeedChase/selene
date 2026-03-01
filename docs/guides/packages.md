# Selene n8n Package Requirements

This document details all packages required for the Selene n8n workflows.

## Package Summary

| Package | Version | Install Method | Used By | Purpose |
|---------|---------|----------------|---------|---------|
| `better-sqlite3` | 11.0.0 | npm (global) | Workflows 01, 02 | Native SQLite database operations in function nodes |
| `n8n-nodes-sqlite` | latest | n8n community | Workflows 03, 04, 05, 06 | SQLite query node for n8n |
| `python3` | - | apk (system) | Build dependency | Required to compile better-sqlite3 |
| `make` | - | apk (system) | Build dependency | Required to compile better-sqlite3 |
| `g++` | - | apk (system) | Build dependency | Required to compile better-sqlite3 |
| `sqlite` | - | apk (system) | Runtime | SQLite command-line tools |
| `sqlite-dev` | - | apk (system) | Build dependency | SQLite development headers |

## Workflow Package Dependencies

### Workflow 01: Note Ingestion
```javascript
// File: 01-ingestion-workflow.json
// Packages used:
- better-sqlite3          // For duplicate detection queries
- crypto (built-in)       // For content hashing
```

**Function node example:**
```javascript
const Database = require('/usr/local/lib/node_modules/better-sqlite3');
const db = new Database('/selene/data/selene.db');
```

### Workflow 02: LLM Processing
```javascript
// File: 02-llm-processing-workflow.json
// Packages used:
- better-sqlite3          // For reading/writing processed notes
- HTTP Request (built-in) // For Ollama API calls
```

**Ollama endpoint:** `http://host.docker.internal:11434/api/generate`

### Workflow 03: Pattern Detection
```json
// File: 03-pattern-detection-workflow.json
// Packages used:
- n8n-nodes-sqlite        // For theme trend queries
```

**SQLite node configuration:**
- Operation: `executeQuery`
- Database path: `/selene/data/selene.db`

### Workflow 04: Obsidian Export
```json
// File: 04-obsidian-export-workflow.json
// Packages used:
- n8n-nodes-sqlite        // For export queries
- writeFile (built-in)    // For markdown file creation
- executeCommand (built-in) // For directory creation
```

### Workflow 05: Sentiment Analysis
```json
// File: 05-sentiment-analysis-workflow.json
// Packages used:
- n8n-nodes-sqlite        // For sentiment data storage
- better-sqlite3          // For sentiment queries (if needed)
- HTTP Request (built-in) // For Ollama sentiment analysis
```

### Workflow 06: Connection Network Analysis
```json
// File: 06-connection-network-workflow.json
// Packages used:
- n8n-nodes-sqlite        // For connection queries and storage
```

## Installation Methods

### Method 1: Automatic (Recommended)

All packages are automatically installed when you build the Docker container:

```bash
docker-compose up -d --build
```

This runs the `Dockerfile` which:
1. Installs system dependencies via `apk`
2. Installs `better-sqlite3` via `npm install -g`
3. Triggers auto-install of `n8n-nodes-sqlite` via environment variable

### Method 2: Manual Installation

If you need to manually install packages inside a running container:

**Enter the container:**
```bash
docker exec -it selene sh
```

**Install better-sqlite3:**
```bash
npm install -g better-sqlite3@11.0.0
```

**Install n8n-nodes-sqlite:**
```bash
# From n8n UI: Settings → Community Nodes → Install
# Or via CLI (requires restart):
npm install -g n8n-nodes-sqlite
```

**Exit and restart:**
```bash
exit
docker-compose restart n8n
```

## Package Verification

### Verify better-sqlite3

```bash
docker exec selene npm list -g better-sqlite3
```

**Expected output:**
```
/usr/local/lib
└── better-sqlite3@11.0.0
```

### Verify n8n-nodes-sqlite

```bash
docker exec selene npm list -g n8n-nodes-sqlite
```

Or check in n8n UI:
1. Open n8n at http://localhost:5678
2. Create new workflow
3. Click "Add node"
4. Search for "SQLite"
5. Should see "SQLite" node available

### Verify SQLite Database Access

```bash
# Check from host
sqlite3 data/selene.db "SELECT sqlite_version();"

# Check from container
docker exec selene sqlite3 /selene/data/selene.db "SELECT sqlite_version();"
```

## Package Configuration

### better-sqlite3 Configuration

**Location in container:** `/usr/local/lib/node_modules/better-sqlite3`

**Usage in function nodes:**
```javascript
const Database = require('/usr/local/lib/node_modules/better-sqlite3');

// Open database
const db = new Database('/selene/data/selene.db');

// Execute query
const stmt = db.prepare('SELECT * FROM raw_notes LIMIT 1');
const result = stmt.all();

// Close database
db.close();

return { json: result[0] };
```

**Important notes:**
- Always use absolute path: `/selene/data/selene.db`
- Always close database connection: `db.close()`
- Handle errors with try/catch blocks

### n8n-nodes-sqlite Configuration

**Credential setup:**
1. In n8n, click on SQLite node
2. Click "Create New Credential"
3. Name: "Selene SQLite"
4. Database Path: `/selene/data/selene.db`
5. Save

**Usage in workflows:**
- Select the SQLite node from node palette
- Choose operation (executeQuery, insert, update, etc.)
- Write SQL query
- Reference credential: "Selene SQLite"

## Environment Variables

The following environment variables are set in `docker-compose.yml` to support package operations:

```yaml
# Enable community packages
N8N_COMMUNITY_PACKAGES_ENABLED: true

# Auto-install SQLite node
N8N_COMMUNITY_PACKAGES_INSTALL: n8n-nodes-sqlite

# Database path for workflows
SELENE_DB_PATH: /selene/data/selene.db

# Allow workflows to access environment
N8N_BLOCK_ENV_ACCESS_IN_NODE: false
```

## Troubleshooting Package Issues

### Issue: better-sqlite3 not found

**Symptoms:**
```
Error: Cannot find module 'better-sqlite3'
```

**Solution:**
```bash
# Rebuild container
docker-compose down
docker-compose up -d --build

# Or install manually
docker exec -it selene npm install -g better-sqlite3
docker-compose restart n8n
```

### Issue: SQLite node not in palette

**Symptoms:**
- Can't find "SQLite" when adding nodes
- Workflows fail on SQLite nodes

**Solution:**
```bash
# Check if package is installed
docker exec selene npm list -g n8n-nodes-sqlite

# If not installed
docker exec -it selene sh
npm install -g n8n-nodes-sqlite
exit
docker-compose restart n8n
```

Or install via UI:
1. Settings → Community Nodes
2. Enter: `n8n-nodes-sqlite`
3. Click "Install"
4. Wait for installation
5. Refresh page

### Issue: Database locked errors

**Symptoms:**
```
Error: database is locked
```

**Solution:**
- Close database connections in function nodes: `db.close()`
- Use WAL mode for better concurrency
- Increase timeout in database operations

### Issue: Permission errors on database

**Symptoms:**
```
Error: unable to open database file
```

**Solution:**
```bash
# Fix permissions
chmod 666 data/selene.db
chmod 777 data/

# Verify volume mount
docker exec selene ls -la /selene/data/
```

## Package Update Strategy

### Updating better-sqlite3

Edit `Dockerfile`:
```dockerfile
RUN npm install -g better-sqlite3@12.0.0  # New version
```

Rebuild:
```bash
docker-compose up -d --build
```

### Updating n8n-nodes-sqlite

From n8n UI:
1. Settings → Community Nodes
2. Find n8n-nodes-sqlite
3. Click "Update" if available

Or manually:
```bash
docker exec selene npm update -g n8n-nodes-sqlite
docker-compose restart n8n
```

### Updating n8n Base Image

```bash
# Pull latest n8n image
docker pull n8nio/n8n:latest

# Rebuild with new base
docker-compose up -d --build
```

## Alternative Packages (Not Used)

These packages were considered but not used:

| Package | Why Not Used |
|---------|--------------|
| `sqlite3` | better-sqlite3 is faster, synchronous, better API |
| `node-sqlite3-wasm` | Overkill for this use case |
| Direct SQL execution | n8n SQLite node provides better UI integration |

## Package Licenses

- `better-sqlite3`: MIT License
- `n8n-nodes-sqlite`: MIT License
- `n8n`: Sustainable Use License (free for self-hosted)
- `SQLite`: Public Domain

## Additional Resources

- **better-sqlite3 Docs**: https://github.com/WiseLibs/better-sqlite3/wiki
- **n8n-nodes-sqlite**: https://www.npmjs.com/package/n8n-nodes-sqlite
- **n8n Community Nodes**: https://docs.n8n.io/integrations/community-nodes/
- **SQLite Documentation**: https://www.sqlite.org/docs.html

## Summary

All package requirements are automatically handled by the Dockerfile and docker-compose.yml configuration. Simply run:

```bash
docker-compose up -d --build
```

And all dependencies will be installed correctly.
