# Selene Quick Start Guide

Get Selene up and running in 15 minutes!

---

## Prerequisites Checklist

Before you begin, make sure you have:

- [ ] **Docker** installed and running
- [ ] **Ollama** installed with `mistral:7b` model
- [ ] **Terminal** access (Terminal.app on Mac)
- [ ] **Web browser** for accessing n8n UI

### Quick Verification

```bash
# Check Docker
docker --version
# Expected: Docker version 24.x or higher

# Check Ollama
ollama list
# Expected: Should show mistral:7b in the list

# If mistral:7b is missing, pull it:
ollama pull mistral:7b
```

---

## Step 1: Start Ollama (2 minutes)

Ollama must be running before starting Selene.

```bash
# Start Ollama service
ollama serve
```

Leave this terminal window open. Ollama will show:
```
Ollama is running on http://localhost:11434
```

---

## Step 2: Start Selene (3 minutes)

Open a **new terminal window** and navigate to the project:

```bash
cd /Users/chaseeasterling/selene

# Start the Docker container
docker-compose up -d

# View logs to confirm it's running
docker-compose logs -f n8n
```

**Look for this in the logs:**
```
n8n ready on ::, port 5678

Editor is now accessible via:
http://localhost:5678
```

Press `Ctrl+C` to exit the logs (container keeps running).

---

## Step 3: Access n8n (1 minute)

Open your web browser and go to:

**http://localhost:5678**

**Login with:**
- Username: `admin`
- Password: `selene_n8n_2025`

> **Tip:** Change the password in your `.env` file for better security

---

## Step 4: Import Workflows (5 minutes)

### Import Method

For each workflow file:

1. Click **"Workflows"** in the left sidebar
2. Click **"Add workflow"** → **"Import from File"**
3. Select the workflow JSON file
4. Click **"Import"**
5. Save the workflow

**Import these workflows in order:**

1. ✅ `01-ingestion-workflow.json` - Note intake
2. ✅ `02-llm-processing-workflow.json` - AI processing
3. ⬜ `03-pattern-detection-workflow.json` - Optional: Pattern analysis
4. ⬜ `04-obsidian-export-workflow.json` - Optional: Obsidian export
5. ⬜ `05-sentiment-analysis-workflow.json` - Optional: Sentiment tracking
6. ⬜ `06-connection-network-workflow.json` - Optional: Note connections

> **Note:** Workflows 01 and 02 are required. Workflows 03-06 are optional extras.

### Configure SQLite Credentials

After importing any workflow with SQLite nodes (03-06):

1. Open the workflow
2. Click on any **SQLite** node
3. Click **"Create New Credential"**
4. **Name:** `Selene SQLite`
5. **Database Path:** `/selene/data/selene.db`
6. Click **"Save"**

Now all workflows can use this credential.

---

## Step 5: Activate Core Workflows (2 minutes)

### Activate Workflow 01 (Ingestion)

1. Open **"01: Selene: Note Ingestion"** workflow
2. Click the **"Active"** toggle in the top-right (should turn green)
3. **Important:** Copy the webhook URL
   - Click on the first node ("Webhook: Receive from Drafts")
   - Look for **"Test URL"** or **"Production URL"**
   - Should look like: `http://localhost:5678/webhook/api/drafts`
   - Keep this URL for later!
4. Click **"Save"** (top-right)

### Activate Workflow 02 (LLM Processing)

1. Open **"02: Selene: LLM Processing"** workflow
2. Click the **"Active"** toggle (should turn green)
3. Click **"Save"**

**Your core workflows are now running!**

---

## Step 6: Send Your First Note (2 minutes)

### Option A: Test with cURL (Recommended First)

```bash
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "title": "Test Note - First Selene Note",
      "content": "This is my first note in Selene! I am testing the workflow to see how it processes concepts like Docker, n8n, and Ollama. This is exciting!",
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
  "noteId": 1,
  "title": "Test Note - First Selene Note",
  "wordCount": 28
}
```

### Option B: Test via Drafts App

If you have Drafts on iOS/Mac:

1. Open Drafts app
2. Create a new draft with some content
3. Run the Selene action (you'll need to create this - see [Drafts Integration](../api/drafts.md))

---

## Step 7: Verify Processing (2 minutes)

### Check the Database

Wait ~30-60 seconds for LLM processing, then check:

```bash
# Check raw notes
sqlite3 data/selene.db "SELECT id, title, status FROM raw_notes;"

# Expected output:
# 1|Test Note - First Selene Note|processed
```

```bash
# Check processed results
sqlite3 data/selene.db "SELECT raw_note_id, concepts, primary_theme FROM processed_notes;"

# Expected output (concepts will vary):
# 1|["Docker","n8n","Ollama","Selene","workflow"]|technical
```

### Check in n8n UI

1. Go to **"Executions"** in the left sidebar
2. You should see:
   - ✅ Successful execution of **"01: Note Ingestion"**
   - ✅ Successful execution of **"02: LLM Processing"** (after 30 seconds)
3. Click on an execution to see the data flow through nodes

---

## 🎉 Success!

You've successfully:

- ✅ Started Selene with Docker
- ✅ Connected to Ollama for AI processing
- ✅ Imported and activated core workflows
- ✅ Sent and processed your first note
- ✅ Verified the pipeline is working

---

## Next Steps

### Customize Your Setup

1. **[Configure Drafts Integration](../api/drafts.md)** - Send notes from your phone
2. **[Set Up Obsidian Export](../workflows/04-obsidian-export.md)** - Export to your vault
3. **[Enable Pattern Detection](../workflows/03-pattern-detection.md)** - Track theme trends
4. **[Enable Sentiment Analysis](../workflows/05-sentiment-analysis.md)** - Track emotional patterns

### Learn More

- **[Understanding Workflows](../workflows/overview.md)** - How each workflow works
- **[Architecture Overview](../architecture/overview.md)** - System design
- **[API Documentation](../api/webhooks.md)** - Integrate with other apps

---

## Common First-Time Issues

### Issue: "n8n not accessible at localhost:5678"

**Solution:**
```bash
# Check container status
docker-compose ps

# If not running:
docker-compose up -d

# Check logs for errors:
docker-compose logs -f n8n
```

### Issue: "Ollama connection failed in workflow"

**Solution:**
```bash
# Make sure Ollama is running
curl http://localhost:11434/api/tags

# If not running:
ollama serve
```

### Issue: "SQLite node not found in n8n"

**Solution:**
```bash
# Install community node
docker exec selene sh -c "cd /home/node/.n8n && npm install n8n-nodes-sqlite"

# Restart n8n
docker-compose restart n8n

# Refresh browser
```

### Issue: "Workflow shows error but note was saved"

**Solution:**

This is normal! The ingestion workflow saves the note first, then LLM processing happens separately every 30 seconds. Check the "02: LLM Processing" execution logs.

---

## Quick Reference Commands

```bash
# Start Selene
docker-compose up -d

# Stop Selene
docker-compose down

# View logs
docker-compose logs -f n8n

# Restart Selene
docker-compose restart n8n

# Check database
sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes;"

# Send test note
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"query": {"title": "Test", "content": "Test note", "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}}'
```

---

## Getting Help

- **Troubleshooting:** [Common Issues](../troubleshooting/common-issues.md)
- **FAQ:** [Frequently Asked Questions](../troubleshooting/faq.md)
- **Full Setup Guide:** [Complete Installation](setup.md)

---

**Ready to capture and organize your thoughts?** Start sending notes to Selene! 🚀
