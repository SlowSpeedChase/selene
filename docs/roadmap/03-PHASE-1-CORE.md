# Phase 1: Core Workflow

**Status:** ✅ COMPLETE
**Completed:** October 30, 2025
**Goal:** Get ONE note flowing through the entire pipeline

## Overview

Phase 1 establishes the foundational pipeline: Drafts → n8n → Ollama → SQLite. This is the minimum viable system that proves the concept works.

## Architecture

```
┌─────────────────┐
│  Drafts Action  │
│  (sends note)   │
└────────┬────────┘
         │ HTTP POST
         ▼
┌─────────────────┐
│  n8n Webhook    │
│  Trigger Node   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Extract Data   │
│  (Set Node)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  SQLite Insert  │
│  raw_notes      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Response Node  │
│  (Success JSON) │
└─────────────────┘

         [Later: Cron triggers processing]

┌─────────────────┐
│  Cron Trigger   │
│  (every 30s)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Query Pending  │
│  raw_notes      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Ollama HTTP    │
│  Request Node   │
│  (Concepts)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Ollama HTTP    │
│  Request Node   │
│  (Themes)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Ollama HTTP    │
│  Request Node   │
│  (Sentiment)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  SQLite Insert  │
│  processed_notes│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Update Status  │
│  raw_notes      │
└─────────────────┘
```

## Completed Tasks

### ✅ 1. Project Directory Structure

```bash
/Users/chaseeasterling/selene/
├── database/
│   ├── schema.sql
│   └── selene.db
├── workflows/
│   ├── 01-ingestion/
│   │   ├── workflow.json
│   │   └── README.md
│   └── 02-llm-processing/
│       ├── workflow.json
│       └── README.md
├── drafts-actions/
│   └── send-to-selene.js
└── docs/
    └── roadmap/
```

### ✅ 2. Database Schema

Copied from Python project and initialized:

```bash
sqlite3 /selene/data/selene.db < database/schema.sql
```

Key tables used in Phase 1:
- `raw_notes` - Incoming notes from Drafts
- `processed_notes` - LLM analysis results

See [10-DATABASE-SCHEMA.md](./10-DATABASE-SCHEMA.md) for full schema.

### ✅ 3. Workflow: 01-ingestion

**Location:** `/workflows/01-ingestion/workflow.json`

**Trigger:** Webhook at `/webhook/selene/ingest`

**Nodes:**
1. **Webhook Trigger**
   - Method: POST
   - Path: `/selene/ingest`
   - Response: Wait for workflow

2. **Extract Note Data** (Set Node)
   - Extracts: `uuid`, `title`, `content`, `tags`, `created`
   - Validates required fields

3. **Insert into raw_notes** (SQLite Node)
   ```sql
   INSERT INTO raw_notes (uuid, title, content, tags, created_at, status)
   VALUES (?, ?, ?, ?, ?, 'pending')
   ```

4. **Build Success Response** (Set Node)
   ```json
   {
     "success": true,
     "message": "Note received",
     "note_id": "{{ $json.id }}"
   }
   ```

5. **Respond to Webhook**
   - Returns JSON response to Drafts

### ✅ 4. Workflow: 02-llm-processing (v2.0)

**Location:** `/workflows/02-llm-processing/workflow.json`

**Trigger:** Cron (every 30 seconds)

**Nodes:**
1. **Cron Trigger**
   - Interval: 30 seconds

2. **Query Pending Notes** (SQLite Node)
   ```sql
   SELECT * FROM raw_notes
   WHERE status = 'pending'
   ORDER BY created_at ASC
   LIMIT 1
   ```

3. **Check If Note Exists** (IF Node)
   - If no pending notes, stop execution

4. **Extract Concepts** (HTTP Request Node)
   - URL: `http://localhost:11434/api/generate`
   - Method: POST
   - Body:
     ```json
     {
       "model": "mistral:7b",
       "prompt": "Extract 5-10 key concepts from this note. Return ONLY a JSON array of strings.\n\nNote: {{ $json.content }}",
       "stream": false,
       "options": {"temperature": 0.3}
     }
     ```

5. **Parse Concepts** (Function Node)
   - Extracts JSON array from Ollama response
   - Calculates confidence score

6. **Extract Themes** (HTTP Request Node)
   - Similar to concepts, but for themes
   - Prompt: "Identify primary and secondary themes as JSON"

7. **Parse Themes** (Function Node)
   - Extracts themes
   - Calculates confidence score

8. **Analyze Sentiment** (HTTP Request Node) **NEW v2.0**
   - Prompt: "Analyze sentiment and emotional tone"
   - Extracts: overall_sentiment, sentiment_score, emotional_tone, energy_level

9. **Parse Sentiment** (Function Node) **NEW v2.0**
   - Extracts sentiment fields
   - Validates scores (0.0-1.0 range)

10. **Calculate Overall Confidence** (Function Node)
    ```javascript
    const avgConfidence = (conceptScore + themeScore) / 2;
    ```

11. **Insert Processed Note** (SQLite Node)
    ```sql
    INSERT INTO processed_notes (
      raw_note_id, concepts, themes,
      overall_sentiment, sentiment_score,
      emotional_tone, energy_level,
      confidence_score, processed_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ```

12. **Update Raw Note Status** (SQLite Node)
    ```sql
    UPDATE raw_notes
    SET status = 'processed'
    WHERE id = ?
    ```

### ✅ 5. Drafts Action Script

**Location:** `/drafts-actions/send-to-selene.js`

```javascript
const WEBHOOK_URL = "http://localhost:5678/webhook/selene/ingest";

const payload = {
  uuid: draft.uuid,
  title: draft.title || "Untitled",
  content: draft.content,
  tags: draft.tags,
  created: draft.createdAt.toISOString()
};

const http = HTTP.create();
const response = http.request({
  url: WEBHOOK_URL,
  method: "POST",
  headers: { "Content-Type": "application/json" },
  data: payload
});

if (response.success) {
  app.displayInfoMessage("✅ Sent to Selene!");
} else {
  app.displayErrorMessage(`❌ Failed: ${response.statusCode}`);
}
```

See [12-DRAFTS-INTEGRATION.md](./12-DRAFTS-INTEGRATION.md) for setup instructions.

### ✅ 6. End-to-End Testing

**Test Commands:**
```bash
# 1. Test webhook directly
curl -X POST http://localhost:5678/webhook/selene/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "uuid": "test-123",
    "title": "Test Note",
    "content": "Testing the pipeline with project planning concepts.",
    "tags": ["test"],
    "created": "2025-10-18T10:00:00Z"
  }'

# 2. Check database
sqlite3 /selene/data/selene.db "SELECT COUNT(*) FROM raw_notes;"
sqlite3 /selene/data/selene.db "SELECT COUNT(*) FROM processed_notes;"

# 3. View latest processed note
sqlite3 /selene/data/selene.db "SELECT title, concepts, themes FROM processed_notes ORDER BY id DESC LIMIT 1;"
```

**Test Results:**
- ✅ 10 notes sent from Drafts
- ✅ All 10 stored in `raw_notes`
- ✅ All 10 processed by Ollama
- ✅ All 10 stored in `processed_notes` with concepts, themes, and sentiment
- ✅ Average confidence score: 0.82
- ✅ Processing time: < 30 seconds per note

### ✅ 7. Verification

**Database Queries:**
```sql
-- Count processed notes
SELECT COUNT(*) FROM processed_notes;
-- Result: 10

-- Average confidence
SELECT AVG(confidence_score) FROM processed_notes;
-- Result: 0.82

-- Sample note data
SELECT
  id,
  title,
  json_array_length(concepts) as concept_count,
  json_array_length(themes) as theme_count,
  overall_sentiment,
  confidence_score
FROM processed_notes
LIMIT 5;

-- Check for stuck notes
SELECT COUNT(*) FROM raw_notes WHERE status = 'pending';
-- Result: 0 (all processed)
```

## Success Criteria (All Met ✅)

- ✅ Send note from Drafts
- ✅ Note appears in `raw_notes` table
- ✅ Ollama processes note (concepts + themes + sentiment)
- ✅ Results stored in `processed_notes`
- ✅ Confidence scores calculated and stored
- ✅ Sentiment analysis working
- ✅ Drafts shows success message
- ✅ Process takes < 30 seconds

## Known Issues

**None currently** - Phase 1 is stable and working as designed.

## Lessons Learned

1. **Cron-based processing works** but is inefficient (polling every 30s)
   - Consider event-driven architecture in Phase 6

2. **Ollama responses need parsing** - JSON extraction requires regex
   - Function nodes handle this well

3. **Confidence scoring is valuable** - Helps identify low-quality analysis
   - Average 0.82 is good quality

4. **Sentiment analysis adds context** - Emotional tone useful for later features
   - Integrates well with existing pipeline

5. **Simple beats complex** - Two workflows, clear flow, easy to debug
   - Visual n8n canvas much easier than Python codebase

## Next Steps

Phase 1 is complete! Move to:

1. **Phase 2: Obsidian Export** - [04-PHASE-2-OBSIDIAN.md](./04-PHASE-2-OBSIDIAN.md)
   - Export processed notes to markdown
   - Create Obsidian vault structure
   - Test concept/theme linking

OR

2. **Phase 6: Event-Driven Architecture** - [08-PHASE-6-EVENT-DRIVEN.md](./08-PHASE-6-EVENT-DRIVEN.md)
   - Refactor to workflow-triggered execution
   - Remove polling/cron inefficiency
   - Better foundation for future phases

## Maintenance

**To modify this phase:**

1. **Change ingestion logic:**
   - Edit workflow 01 in n8n UI
   - Test with curl before using Drafts
   - Verify database inserts

2. **Adjust LLM prompts:**
   - Edit workflow 02 HTTP Request nodes
   - See [11-OLLAMA-INTEGRATION.md](./11-OLLAMA-INTEGRATION.md) for prompt guidelines
   - Test with sample notes

3. **Tune processing frequency:**
   - Edit workflow 02 cron schedule
   - Balance between latency and resource usage
   - Monitor for stuck notes

**Monitoring:**
```bash
# Check for stuck notes (pending > 5 minutes)
sqlite3 /selene/data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE status = 'pending' AND created_at < datetime('now', '-5 minutes');"

# Check processing quality
sqlite3 /selene/data/selene.db "SELECT AVG(confidence_score) FROM processed_notes WHERE processed_at > datetime('now', '-24 hours');"

# View n8n execution log
# Open: http://localhost:5678 → Executions tab
```

## Technical Details

For detailed node configurations, see:
- [13-N8N-WORKFLOW-SPECS.md](./13-N8N-WORKFLOW-SPECS.md)

For Ollama prompt engineering:
- [11-OLLAMA-INTEGRATION.md](./11-OLLAMA-INTEGRATION.md)

For database queries:
- [10-DATABASE-SCHEMA.md](./10-DATABASE-SCHEMA.md)
