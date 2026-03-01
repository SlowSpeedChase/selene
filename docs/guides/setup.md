# Selene n8n Setup Guide

Complete setup instructions for the Selene Knowledge Management System using n8n.

## Overview

This setup provides a complete note processing pipeline with:

- **Note Ingestion** from Drafts app (Workflow 01)
- **LLM Processing** with Ollama for concept/theme extraction (Workflow 02)
- **Pattern Detection** for theme trends (Workflow 03)
- **Obsidian Export** for knowledge vault integration (Workflow 04)
- **Sentiment Analysis** for emotional tone detection (Workflow 05)
- **Connection Network** for discovering note relationships (Workflow 06)

## Package Requirements

### Automatically Installed Packages

The Docker setup automatically installs all required packages:

| Package | Version | Used By | Purpose |
|---------|---------|---------|---------|
| `better-sqlite3` | 11.0.0 | Workflows 01, 02 | Native SQLite library for function nodes |
| `n8n-nodes-sqlite` | Latest | Workflows 03-06 | Community node for SQLite operations |

### System Dependencies

- **Docker** - Container runtime
- **Ollama** - Local LLM server (runs on host, not in container)
- **SQLite** - Database (included in Docker image)

## Prerequisites

### 1. Install Docker

**macOS (with Homebrew):**
```bash
brew install --cask docker
```

**Or download from:** https://www.docker.com/products/docker-desktop

### 2. Install Ollama

**macOS:**
```bash
brew install ollama
```

**Or download from:** https://ollama.ai

### 3. Pull Required LLM Model

```bash
# Start Ollama service
ollama serve

# In a new terminal, pull the model
ollama pull mistral:7b
```

Verify it's installed:
```bash
ollama list
# Should show mistral:7b
```

## Installation Steps

### Step 1: Clone or Navigate to Project

```bash
cd /Users/chaseeasterling/selene
```

### Step 2: Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit the .env file with your preferences
nano .env  # or use your preferred editor
```

**Key settings to customize:**

```bash
# Change the password!
N8N_BASIC_AUTH_PASSWORD=your_secure_password_here

# Set your timezone
TIMEZONE=America/Los_Angeles

# Set your Obsidian vault path (if you have one)
OBSIDIAN_VAULT_PATH=/Users/yourusername/Documents/ObsidianVault

# Or keep default to use ./vault
OBSIDIAN_VAULT_PATH=./vault
```

### Step 3: Create Required Directories

```bash
# Create data and vault directories
mkdir -p data vault

# Create Obsidian vault structure
mkdir -p vault/Selene/{Concepts,Themes,Patterns,Sources}
mkdir -p vault/Selene/{2024,2025}
```

### Step 4: Initialize Database

You need the database schema. If you have the old Selene project:

```bash
# Copy schema from old project (if available)
cp "/path/to/old/selene/data/schema.sql" ./database/schema.sql

# Create the database
sqlite3 data/selene.db < database/schema.sql
```

**If you don't have the schema file**, you'll need to create the database tables manually or request the schema.sql file.

### Step 5: Build and Start Containers

```bash
# Build the custom Docker image with all packages
docker-compose up -d --build

# View logs to ensure everything started correctly
docker-compose logs -f n8n
```

**Expected output:**
```
n8n ready on http://localhost:5678
Editor is now accessible via:
http://localhost:5678/
```

Press `Ctrl+C` to exit logs (container keeps running).

### Step 6: Access n8n Interface

1. Open browser: http://localhost:5678
2. Login with credentials from .env:
   - Username: `admin` (or your custom value)
   - Password: (your N8N_BASIC_AUTH_PASSWORD)

### Step 7: Import Workflows

**Method 1: Via n8n UI**

1. In n8n, click **"Add Workflow"** → **"Import from File"**
2. Import each workflow JSON file:
   - `01-ingestion-workflow.json`
   - `02-llm-processing-workflow.json`
   - `03-pattern-detection-workflow.json`
   - `04-obsidian-export-workflow.json`
   - `05-sentiment-analysis-workflow.json`
   - `06-connection-network-workflow.json`

3. **Important**: After importing, configure the SQLite credentials:
   - Click on any SQLite node
   - Create credential named "Selene SQLite"
   - Database path: `/selene/data/selene.db`

**Method 2: Via Volume Mount**

The workflows are already mounted in the container at `/workflows`. You can reference them from there.

### Step 8: Activate Workflows

For each imported workflow:

1. Open the workflow
2. Click **"Active"** toggle in top-right corner
3. Save the workflow

**Recommended activation order:**

1. Activate Workflow 01 (Ingestion) - enables webhook
2. Activate Workflow 02 (LLM Processing) - starts processing queue
3. Activate Workflows 03-06 as needed

## Workflow Descriptions

### 01: Note Ingestion Workflow

- **Trigger**: Webhook at `/api/drafts`
- **Function**: Receives notes from Drafts app, checks for duplicates, stores in database
- **Runs**: On-demand when webhook receives data
- **Packages Used**: better-sqlite3, crypto (built-in)

### 02: LLM Processing Workflow

- **Trigger**: Every 30 seconds (cron)
- **Function**: Processes pending notes with Ollama to extract concepts and themes
- **Runs**: Automatically every 30 seconds
- **Packages Used**: better-sqlite3, HTTP Request (built-in)

### 03: Pattern Detection Workflow

- **Trigger**: Daily at 6am (cron)
- **Function**: Analyzes theme trends and detects patterns over time
- **Runs**: Automatically daily
- **Packages Used**: n8n-nodes-sqlite

### 04: Obsidian Export Workflow

- **Trigger**: Daily at 7am (cron)
- **Function**: Exports processed notes as markdown files to Obsidian vault
- **Runs**: Automatically daily
- **Packages Used**: n8n-nodes-sqlite, File operations (built-in)
- **Note**: Update the vault path in the function nodes if needed

### 05: Sentiment Analysis Workflow (Advanced)

- **Trigger**: Every 45 seconds (cron)
- **Function**: Analyzes emotional tone and sentiment of notes using Ollama
- **Runs**: Automatically every 45 seconds
- **Packages Used**: n8n-nodes-sqlite, better-sqlite3

### 06: Connection Network Workflow (Advanced)

- **Trigger**: Every 6 hours (cron)
- **Function**: Discovers connections between notes based on shared concepts/themes
- **Runs**: Automatically every 6 hours
- **Packages Used**: n8n-nodes-sqlite

## Testing the Setup

### Test 1: Verify n8n is Running

```bash
curl http://localhost:5678/healthz
# Expected: HTTP 200 OK
```

### Test 2: Verify Ollama Access from Container

```bash
docker exec selene wget -qO- http://localhost:11434/api/tags
# Expected: JSON response with model list
```

### Test 3: Send Test Note

```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "title": "Test Note",
      "content": "This is a test note about Docker and n8n workflows.",
      "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
    }
  }'
```

**Expected response:**
```json
{
  "success": true,
  "action": "stored",
  "message": "Note successfully ingested",
  "noteId": 1
}
```

### Test 4: Verify Database Entry

```bash
sqlite3 data/selene.db "SELECT id, title, status FROM raw_notes ORDER BY id DESC LIMIT 1;"
```

**Expected:** Your test note should appear with `status='pending'`

### Test 5: Wait for LLM Processing

Wait ~30-60 seconds for Workflow 02 to process the note, then check:

```bash
sqlite3 data/selene.db "SELECT raw_note_id, concepts, primary_theme FROM processed_notes ORDER BY id DESC LIMIT 1;"
```

**Expected:** Your note should be processed with extracted concepts and theme

## Troubleshooting

### Problem: Container won't start

**Solution:**
```bash
# Check logs
docker-compose logs n8n

# Rebuild from scratch
docker-compose down -v
docker-compose up -d --build
```

### Problem: SQLite node not available

**Solution:**

The community package may need manual installation:

```bash
# Enter container
docker exec -it selene sh

# Install SQLite community node
npm install -g n8n-nodes-sqlite

# Exit and restart
exit
docker-compose restart n8n
```

### Problem: Ollama connection fails

**Solution:**

Verify Ollama is running on host:
```bash
# Check Ollama status
curl http://localhost:11434/api/tags

# If not running, start it
ollama serve
```

Verify network mode:
```bash
# Check docker-compose.yml has: network_mode: "host"
grep "network_mode" docker-compose.yml
```

### Problem: better-sqlite3 not found in function nodes

**Solution:**

The package should be installed globally in the Dockerfile. Verify:
```bash
docker exec selene npm list -g better-sqlite3
```

If not installed, rebuild:
```bash
docker-compose down
docker-compose up -d --build
```

### Problem: Workflows can't access database

**Solution:**

1. Verify database file exists:
```bash
ls -la data/selene.db
```

2. Check volume mount in container:
```bash
docker exec selene ls -la /selene/data/
```

3. Verify SQLite credential path is: `/selene/data/selene.db`

## Maintenance

### View Logs

```bash
# All logs
docker-compose logs -f

# Only n8n logs
docker-compose logs -f n8n

# Last 100 lines
docker-compose logs --tail=100 n8n
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart only n8n
docker-compose restart n8n
```

### Update n8n

```bash
# Pull latest base image
docker-compose pull

# Rebuild with latest
docker-compose up -d --build
```

### Backup Database

```bash
# Simple backup
cp data/selene.db data/selene.db.backup

# Timestamped backup
cp data/selene.db "data/selene.db.backup.$(date +%Y%m%d_%H%M%S)"
```

### Stop Services

```bash
# Stop but keep data
docker-compose down

# Stop and remove all data (careful!)
docker-compose down -v
```

## Package Management

### Installed Packages Overview

The Dockerfile installs:

1. **System packages** (via apk):
   - python3 (required for building better-sqlite3)
   - make, g++ (compilation tools)
   - sqlite, sqlite-dev (SQLite libraries)

2. **Node packages** (via npm):
   - better-sqlite3@11.0.0 (globally installed)

3. **n8n community packages** (via environment variable):
   - n8n-nodes-sqlite (auto-installed on startup)

### Adding Additional Packages

**For Node.js packages needed in function nodes:**

Edit `Dockerfile` and add:
```dockerfile
RUN npm install -g package-name
```

**For system packages:**

Edit `Dockerfile` and add to apk install:
```dockerfile
RUN apk add --no-cache \
    package-name
```

Then rebuild:
```bash
docker-compose up -d --build
```

## Next Steps

1. **Set up Drafts integration** - Create Drafts action to send notes to webhook
2. **Customize workflows** - Adjust prompts, schedules, and processing logic
3. **Configure Obsidian vault path** - Update workflow 04 with your vault location
4. **Monitor pattern detection** - Review insights generated by workflow 03
5. **Explore advanced features** - Enable workflows 05 and 06 for sentiment and network analysis

## Support Resources

- **n8n Documentation**: https://docs.n8n.io
- **Ollama Documentation**: https://ollama.ai/docs
- **SQLite Documentation**: https://www.sqlite.org/docs.html
- **better-sqlite3**: https://github.com/WiseLibs/better-sqlite3

## File Structure

```
selene/
├── .env                              # Your configuration (create from .env.example)
├── .env.example                      # Configuration template
├── docker-compose.yml                # Docker orchestration
├── Dockerfile                        # Custom n8n image with packages
├── SETUP.md                          # This file
├── ROADMAP.md                        # Migration roadmap and design docs
├── data/
│   └── selene.db                     # SQLite database
├── vault/                            # Obsidian vault
│   └── Selene/
│       ├── Concepts/                 # Concept index files
│       ├── Themes/                   # Theme files
│       ├── Patterns/                 # Pattern detection results
│       ├── Sources/                  # Original notes
│       ├── 2024/                     # Notes by year
│       └── 2025/
└── *.json                            # n8n workflow files (01-06)
```

---

**Questions or issues?** Check the troubleshooting section or review the logs with `docker-compose logs -f n8n`
