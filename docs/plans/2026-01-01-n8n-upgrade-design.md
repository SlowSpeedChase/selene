# n8n 2.x Upgrade Design

**Created:** 2026-01-01
**Status:** Design Complete
**Target Version:** 2.1.4 (from 1.110.1)

---

## Overview

Upgrade n8n from version 1.110.1 to 2.1.4 to gain security hardening, performance improvements, and access to new features (MCP integration, improved Code node, SQLite pooling).

### Motivation

- **Security hardening** - Task runners enabled by default, isolated Code execution
- **Staying current** - Avoid accumulating technical debt (13+ versions behind)
- **New features** - MCP nodes for SeleneChat integration, Data Tables, Publish/Save workflow

### Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| `executeCommand` disabled by default | High | Add `N8N_ALLOW_EXECUTE_COMMAND=true` |
| `update:workflow` CLI removed | High | Update `manage-workflow.sh` script |
| File access restrictions | High | Configure `N8N_RESTRICT_FILE_ACCESS_TO` |
| Community package compatibility | Medium | Test `n8n-nodes-sqlite` after upgrade |
| better-sqlite3 in Function nodes | Medium | Verify in test environment first |

---

## Current State

### Version Info

- **Current:** n8n 1.110.1
- **Target:** n8n 2.1.4
- **Docker image:** `n8nio/n8n:latest` (unpinned)

### Affected Components

| Component | Impact |
|-----------|--------|
| `Dockerfile` | Change base image to pinned version |
| `docker-compose.yml` | Add new environment variables |
| `scripts/manage-workflow.sh` | Update CLI commands |
| `workflows/04-obsidian-export` | Uses `executeCommand` - needs env var |
| `workflows/08-project-detection` | Uses `executeCommand` - migrate to native node |

### Node Usage Audit

```
68x n8n-nodes-base.function    - OK (may migrate to Code node)
13x n8n-nodes-base.httpRequest - OK
 9x n8n-nodes-base.webhook     - OK
 7x n8n-nodes-base.respondToWebhook - OK
 5x n8n-nodes-base.if          - OK
 4x n8n-nodes-base.scheduleTrigger - OK
 2x n8n-nodes-base.executeCommand - BREAKING (disabled by default)
 2x n8n-nodes-base.writeBinaryFile - OK (check file access)
 1x n8n-nodes-base.code        - OK (task runner changes)
```

---

## Implementation Plan

### Phase 1: Preparation (Before Upgrade)

**1.1 Update manage-workflow.sh**

Add version detection and command mapping:

```bash
# Detect n8n version
N8N_VERSION=$(docker exec "$CONTAINER_NAME" n8n --version 2>/dev/null)

# Use appropriate command based on version
if [[ "$N8N_VERSION" =~ ^2\. ]]; then
    # n8n 2.x uses publish:workflow
    n8n_exec publish:workflow --id="$WORKFLOW_ID"
else
    # n8n 1.x uses update:workflow
    n8n_exec update:workflow --id="$WORKFLOW_ID"
fi
```

**1.2 Migrate workflow 08-project-detection**

Replace `executeCommand` node (mkdir + echo) with `writeBinaryFile` node:

Current:
```json
{
  "type": "n8n-nodes-base.executeCommand",
  "parameters": {
    "command": "mkdir -p /obsidian/projects-pending && echo '{{ $json.project_json }}' > ..."
  }
}
```

Replace with:
```json
{
  "type": "n8n-nodes-base.writeBinaryFile",
  "parameters": {
    "fileName": "={{ $json.filename }}",
    "filePath": "/obsidian/projects-pending/"
  }
}
```

**1.3 Create Backups**

```bash
# Backup all workflows
./scripts/manage-workflow.sh export-all

# Backup database
cp data/selene.db data/selene-pre-upgrade-$(date +%Y%m%d).db

# Backup n8n data volume
docker run --rm \
  -v selene_n8n_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/n8n-data-$(date +%Y%m%d).tar.gz /data
```

**1.4 Test Environment (Optional)**

Create `docker-compose.test.yml`:
```yaml
services:
  n8n-test:
    build:
      context: .
      dockerfile: Dockerfile.test  # Uses n8n:2.1.4
    ports:
      - "5679:5678"
    volumes:
      - n8n_test_data:/home/node/.n8n
      - ./data-test:/selene/data:rw
```

---

### Phase 2: Configuration Updates

**2.1 Update Dockerfile**

```dockerfile
# Pin to specific version instead of latest
FROM n8nio/n8n:2.1.4

# Rest of Dockerfile unchanged
```

**2.2 Update docker-compose.yml**

Add new environment variables:

```yaml
environment:
  # Existing variables...

  # n8n 2.0 compatibility
  - N8N_ALLOW_EXECUTE_COMMAND=true  # Required for workflow 04
  - N8N_RESTRICT_FILE_ACCESS_TO=/selene/data,/obsidian,/home/node/.n8n,/obsidian-test,/selene/data-test

  # Already set (good):
  # - N8N_RUNNERS_ENABLED=true
  # - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
```

**2.3 Verify CLI Changes**

| Old Command (1.x) | New Command (2.x) |
|-------------------|-------------------|
| `update:workflow --id=X` | `publish:workflow --id=X` |
| `n/a` | `unpublish:workflow --id=X` |
| `export:workflow` | `export:workflow` (unchanged) |
| `import:workflow` | `import:workflow` (unchanged) |

---

### Phase 3: Upgrade & Test

**3.1 Upgrade Sequence**

```bash
# 1. Stop current n8n
docker-compose down

# 2. Pull new base image
docker pull n8nio/n8n:2.1.4

# 3. Rebuild custom image (no cache to ensure fresh build)
docker-compose build --no-cache

# 4. Start upgraded n8n
docker-compose up -d

# 5. Verify version
docker exec selene n8n --version
# Expected output: 2.1.4

# 6. Check logs for errors
docker-compose logs -f n8n | head -100
```

**3.2 Test Matrix**

| Workflow | Test Command | Pass Criteria |
|----------|--------------|---------------|
| 01-ingestion | `./workflows/01-ingestion/scripts/test-with-markers.sh` | All 6 tests pass |
| 04-obsidian-export | Manual webhook test | Files written to /obsidian |
| 06-connection-network | `./workflows/06-connection-network/scripts/test-with-markers.sh` | Network analysis completes |
| 07-task-extraction | `./workflows/07-task-extraction/scripts/test-with-markers.sh` | Classification + Things file output |
| 08-project-detection | `./workflows/08-project-detection/scripts/test-with-markers.sh` | Project files created |

**3.3 Performance Comparison**

Baseline before upgrade:
```bash
# Record current performance
time curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -d '{"content": "Performance baseline test", "test_run": "perf-baseline"}'
```

Compare after upgrade for SQLite performance improvement (up to 10x claimed).

**3.4 Rollback Procedure**

If critical failures occur:

```bash
# 1. Stop failed container
docker-compose down

# 2. Restore Dockerfile to previous version
# Change: FROM n8nio/n8n:2.1.4
# To:     FROM n8nio/n8n:1.110.1

# 3. Remove new volume data
docker volume rm selene_n8n_data

# 4. Restore backup
tar -xzf backups/n8n-data-YYYYMMDD.tar.gz -C /var/lib/docker/volumes/

# 5. Restore database
cp data/selene-pre-upgrade-YYYYMMDD.db data/selene.db

# 6. Rebuild and start
docker-compose build
docker-compose up -d
```

---

### Phase 4: New Features (Post-Upgrade)

**4.1 MCP Integration**

n8n 2.x includes native MCP nodes:
- **MCP Server Trigger** - Expose workflows as tools for AI agents
- **MCP Client Tool** - Call external MCP servers from workflows

**Potential SeleneChat integration:**
```
SeleneChat → MCP → n8n workflow → Task extraction → Things
```

This could replace HTTP webhook calls with native MCP protocol.

**4.2 Publish/Save Workflow Pattern**

New paradigm for safer workflow iteration:
- **Save** - Preserve edits without affecting live workflow
- **Publish** - Deploy changes to production

Update `manage-workflow.sh` to support this pattern.

**4.3 Data Tables Evaluation**

Built-in structured storage (50MB limit). Evaluate for:
- Processing queues (instead of SQLite staging tables)
- LLM response caching
- Session state for multi-step workflows

**Not recommended for:** Primary note storage (SQLite better for this).

---

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `Dockerfile` | Modify | Pin to `n8n:2.1.4` |
| `docker-compose.yml` | Modify | Add `N8N_ALLOW_EXECUTE_COMMAND`, `N8N_RESTRICT_FILE_ACCESS_TO` |
| `scripts/manage-workflow.sh` | Modify | Add version detection, use `publish:workflow` for 2.x |
| `workflows/08-project-detection/workflow.json` | Modify | Replace `executeCommand` with `writeBinaryFile` |

---

## Success Criteria

- [ ] n8n reports version 2.1.4
- [ ] All existing workflow tests pass
- [ ] Webhook ingestion works (workflow 01)
- [ ] SQLite database reads/writes work
- [ ] Obsidian file exports work (workflow 04)
- [ ] Things bridge file creation works (workflows 07, 08)
- [ ] `manage-workflow.sh` commands work with new CLI
- [ ] No errors in container logs after 24 hours

---

## Timeline Estimate

| Phase | Tasks |
|-------|-------|
| **Phase 1** | Script updates, workflow migration, backups |
| **Phase 2** | Configuration file updates |
| **Phase 3** | Upgrade execution, full test suite |
| **Phase 4** | MCP exploration (optional, ongoing) |

---

## References

- [n8n 2.0 Breaking Changes](https://docs.n8n.io/2-0-breaking-changes/)
- [n8n 2.0 Blog Announcement](https://blog.n8n.io/introducing-n8n-2-0/)
- [n8n MCP Integration Docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.toolmcp/)
- [n8n GitHub Releases](https://github.com/n8n-io/n8n/releases)

---

## Version History

- **2026-01-01**: Initial design document created
