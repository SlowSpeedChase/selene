# US-041: Embedding Generation Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create n8n workflow that generates vector embeddings for notes via Ollama and stores them in SQLite.

**Architecture:** Webhook receives note ID(s), fetches content from database, calls Ollama embedding API, stores 768-dimensional vectors in note_embeddings table. Idempotent (skips existing embeddings).

**Tech Stack:** n8n workflows, better-sqlite3, Ollama nomic-embed-text model, SQLite

---

## Task 1: Create Directory Structure

**Files:**
- Create: `workflows/09-embedding-generation/`
- Create: `workflows/09-embedding-generation/docs/`
- Create: `workflows/09-embedding-generation/scripts/`

**Step 1: Create directories**

```bash
mkdir -p workflows/09-embedding-generation/docs
mkdir -p workflows/09-embedding-generation/scripts
```

**Step 2: Verify structure exists**

```bash
ls -la workflows/09-embedding-generation/
```

Expected: `docs/` and `scripts/` directories present

**Step 3: Commit**

```bash
git add workflows/09-embedding-generation/
git commit -m "chore(09): create embedding-generation workflow directory structure"
```

---

## Task 2: Create Workflow JSON

**Files:**
- Create: `workflows/09-embedding-generation/workflow.json`

**Step 1: Write workflow.json**

Create file with these nodes:

1. **Webhook Trigger** - `POST /webhook/api/embed`
2. **Normalize Input** - Convert `note_id` to `note_ids` array
3. **Split Into Batches** - One item per note ID
4. **Fetch Note Content** - Query raw_notes table
5. **Check Existing Embedding** - Query note_embeddings table
6. **Route: Has Embedding** - IF node to skip/continue
7. **Call Ollama API** - POST to embedding endpoint
8. **Store Embedding** - INSERT into note_embeddings
9. **Aggregate Results** - Count embedded/skipped/failed
10. **Return Response** - Respond with JSON summary

**Step 2: Verify JSON is valid**

```bash
cat workflows/09-embedding-generation/workflow.json | jq '.nodes | length'
```

Expected: Node count (approximately 10)

**Step 3: Commit**

```bash
git add workflows/09-embedding-generation/workflow.json
git commit -m "feat(09): add embedding generation workflow

- Webhook trigger: POST /webhook/api/embed
- Supports single note_id or batch note_ids
- Calls Ollama nomic-embed-text for 768-dim vectors
- Stores embeddings in note_embeddings table
- Idempotent: skips existing embeddings"
```

---

## Task 3: Create Test Script

**Files:**
- Create: `workflows/09-embedding-generation/scripts/test-with-markers.sh`

**Step 1: Write test script**

Test cases to implement:
1. Single note embedding (success)
2. Batch embedding (multiple notes)
3. Skip existing embedding (idempotent)
4. Note not found (graceful skip)
5. Verify embedding dimensions (768)

**Step 2: Make executable**

```bash
chmod +x workflows/09-embedding-generation/scripts/test-with-markers.sh
```

**Step 3: Commit**

```bash
git add workflows/09-embedding-generation/scripts/test-with-markers.sh
git commit -m "test(09): add embedding workflow test script

- Tests single and batch embedding
- Verifies idempotency (skip existing)
- Validates 768-dimension vectors
- Uses test_run markers for cleanup"
```

---

## Task 4: Create Documentation

**Files:**
- Create: `workflows/09-embedding-generation/README.md`
- Create: `workflows/09-embedding-generation/docs/STATUS.md`

**Step 1: Write README.md**

Include:
- Purpose
- Endpoint
- Input/output format
- Example curl commands
- Dependencies

**Step 2: Write STATUS.md**

Initial status: "In Development"

**Step 3: Commit**

```bash
git add workflows/09-embedding-generation/README.md workflows/09-embedding-generation/docs/STATUS.md
git commit -m "docs(09): add README and STATUS for embedding workflow"
```

---

## Task 5: Import Workflow to n8n

**Files:**
- Modify: n8n database (via CLI)

**Step 1: Import workflow**

```bash
./scripts/manage-workflow.sh import workflows/09-embedding-generation/workflow.json
```

**Step 2: Get workflow ID**

```bash
./scripts/manage-workflow.sh list | grep -i embed
```

Note the ID for testing.

**Step 3: Activate workflow**

```bash
docker exec selene n8n update:workflow --id=<ID> --active=true
```

---

## Task 6: Run Tests and Verify

**Files:**
- Modify: `workflows/09-embedding-generation/docs/STATUS.md`

**Step 1: Run test suite**

```bash
./workflows/09-embedding-generation/scripts/test-with-markers.sh
```

**Step 2: Verify embeddings in database**

```bash
sqlite3 data/selene.db "SELECT raw_note_id, model_version, length(embedding) as embed_size FROM note_embeddings WHERE test_run IS NOT NULL LIMIT 3;"
```

Expected: Records with model_version='nomic-embed-text' and embed_size > 0

**Step 3: Update STATUS.md with results**

Record:
- Date
- Test results (pass/fail counts)
- Any issues found

**Step 4: Cleanup test data**

```bash
./scripts/cleanup-tests.sh <test-run-id>
```

**Step 5: Commit final status**

```bash
git add workflows/09-embedding-generation/docs/STATUS.md
git commit -m "docs(09): update STATUS with test results"
```

---

## Task 7: Move Story to Active

**Files:**
- Move: `docs/stories/draft/US-041-embedding-generation-workflow.md` → `docs/stories/active/`

**Step 1: Move story file**

```bash
mv docs/stories/draft/US-041-embedding-generation-workflow.md docs/stories/active/
```

**Step 2: Update story with branch link**

Add to Links section:
- Branch: `US-041/embedding-workflow`

**Step 3: Update INDEX.md**

Move US-041 from Draft to Active section.

**Step 4: Commit**

```bash
git add docs/stories/
git commit -m "chore(US-041): move story to active status"
```

---

## Verification Checklist

After all tasks:

- [ ] Workflow appears in `./scripts/manage-workflow.sh list`
- [ ] Webhook responds: `curl -X POST http://localhost:5678/webhook/api/embed -d '{"note_id": 1}'`
- [ ] Embeddings stored in database with correct schema
- [ ] Test script passes all cases
- [ ] STATUS.md reflects test results
- [ ] Story in `active/` with branch link

---

## Rollback

If workflow breaks:

1. Deactivate: `docker exec selene n8n update:workflow --id=<ID> --active=false`
2. Delete test embeddings: `sqlite3 data/selene.db "DELETE FROM note_embeddings WHERE test_run IS NOT NULL;"`
3. Review error logs: `docker-compose logs -f n8n`
