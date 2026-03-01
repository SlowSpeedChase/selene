# Selene n8n Recovery Guide

**Created:** 2025-11-13
**Last Updated:** 2025-11-13

This document describes how to recover from n8n database corruption and provides preventive measures to avoid future issues.

---

## Problem Summary

### What Happened
- n8n v1.110.1 database became corrupted after manual user/role manipulation
- Attempted to disable authentication by modifying database directly
- Database relationships between users, roles, projects, and workflows became broken

### Root Cause
**IMPORTANT:** n8n v1.x+ requires user authentication - it CANNOT be disabled.
- `N8N_BASIC_AUTH_ACTIVE=false` does not work in v1.x+
- `N8N_USER_MANAGEMENT_DISABLED=true` is deprecated and non-functional
- Manual database manipulation breaks referential integrity

---

## Recovery Process (What We Did)

### Phase 1: Backup Everything
```bash
# Create timestamped backup directory
mkdir -p backup-$(date +%Y%m%d-%H%M%S)

# Backup the corrupted database (just in case)
docker cp selene:/home/node/.n8n/database.sqlite backup-TIMESTAMP/database-backup.sqlite

# Verify workflow JSON backups exist
find workflows/ -name "workflow.json" -o -name "workflow-test.json"
```

**Result:** All workflows have JSON backups in `/workflows` directory ✓

### Phase 2: Clean Reset
```bash
# Stop the container
docker-compose down

# Remove the corrupted volume
docker volume rm selene_n8n_data
```

### Phase 3: Configuration Cleanup
Updated `docker-compose.yml`:

**REMOVED (non-functional):**
```yaml
- N8N_BASIC_AUTH_ACTIVE=false
- N8N_USER_MANAGEMENT_DISABLED=true
```

**ADDED (recommended settings):**
```yaml
- DB_SQLITE_POOL_SIZE=5          # Prevents SQLite deprecation warnings
- N8N_RUNNERS_ENABLED=true        # Future-proof task runners
```

**REMOVED (obsolete):**
```yaml
version: '3.8'  # No longer needed in modern Docker Compose
```

### Phase 4: Fresh Start
```bash
# Build and start with clean database
docker-compose up -d --build

# Wait for migrations to complete (watch logs)
docker logs -f selene
```

### Phase 5: Create Owner Account
1. Open browser to `http://localhost:5678`
2. Fill out "Set up owner account" form
3. Use credentials you'll remember (authentication is MANDATORY)

### Phase 6: Import Workflows
```bash
# Import all production workflows
docker exec selene n8n import:workflow --input=/workflows/workflows/01-ingestion/workflow.json
docker exec selene n8n import:workflow --input=/workflows/workflows/02-llm-processing/workflow.json
docker exec selene n8n import:workflow --input=/workflows/workflows/03-pattern-detection/workflow.json
docker exec selene n8n import:workflow --input=/workflows/workflows/04-obsidian-export/workflow.json
docker exec selene n8n import:workflow --input=/workflows/workflows/05-sentiment-analysis/workflow.json
docker exec selene n8n import:workflow --input=/workflows/workflows/06-connection-network/workflow.json

# Import test workflows
docker exec selene n8n import:workflow --input=/workflows/workflows/01-ingestion/workflow-test.json
docker exec selene n8n import:workflow --input=/workflows/workflows/02-llm-processing/workflow-test.json
docker exec selene n8n import:workflow --input=/workflows/workflows/04-obsidian-export/workflow-test.json
docker exec selene n8n import:workflow --input=/workflows/workflows/05-sentiment-analysis/workflow-test.json

# Import Apple variant
docker exec selene n8n import:workflow --input=/workflows/workflows/02-llm-processing_apple/workflow.json
```

### Phase 7: Activate Production Workflows
```bash
# Activate the 4 main production workflows
docker exec selene sqlite3 /home/node/.n8n/database.sqlite \
  "UPDATE workflow_entity SET active = 1 WHERE name IN (
    '01-Note-Ingestion | Selene',
    '02-LLM-Processing | Selene',
    '04-Obsidian-Export | Selene',
    '05-Sentiment-Analysis | Selene'
  );"

# Restart to apply activation
docker-compose restart n8n
```

---

## Final State

### Active Workflows (4)
- ✅ 01-Note-Ingestion | Selene
- ✅ 02-LLM-Processing | Selene
- ✅ 04-Obsidian-Export | Selene
- ✅ 05-Sentiment-Analysis | Selene

### Inactive Workflows (Available)
- 03-Pattern-Detection | Selene
- 06-Connection-Network | Selene
- TEST-02-LLM-Processing-Apple | Selene
- All test workflows (workflow-test.json variants)

### Backups Created
- `/backup-20251113-165806/database-backup.sqlite` (corrupted database backup)
- All workflow JSONs in `/workflows/` directory (version controlled)

---

## Preventive Measures

### DO NOT Do These Things
❌ **NEVER** manually delete users from the database
❌ **NEVER** try to disable authentication in n8n v1.x+
❌ **NEVER** manually manipulate user/role/project tables
❌ **NEVER** use deprecated environment variables

### Best Practices
✅ **ALWAYS** keep workflow JSON files in version control
✅ **ALWAYS** export workflows regularly using n8n CLI or UI
✅ **ALWAYS** use simple, memorable credentials (authentication is mandatory)
✅ **ALWAYS** backup the database before major changes
✅ **ALWAYS** use n8n's built-in tools (CLI, API, UI) instead of direct database access

---

## Future Recovery (If This Happens Again)

### Quick Recovery Checklist
1. ✅ Verify workflow JSON backups exist in `/workflows/`
2. ✅ Backup current database (if not already done)
3. ✅ Stop container: `docker-compose down`
4. ✅ Remove volume: `docker volume rm selene_n8n_data`
5. ✅ Start fresh: `docker-compose up -d --build`
6. ✅ Create owner account via browser at `http://localhost:5678`
7. ✅ Import workflows using commands from Phase 6 above
8. ✅ Activate workflows using commands from Phase 7 above
9. ✅ Verify all workflows are running

### Automated Recovery Script
See `scripts/recover-n8n.sh` (to be created) for one-command recovery.

---

## Additional Resources

### n8n CLI Commands
```bash
# Export a workflow
docker exec selene n8n export:workflow --id=WORKFLOW_ID --output=/workflows/backup.json

# Export all workflows
docker exec selene n8n export:workflow --all --output=/workflows/

# List workflows
docker exec selene n8n list:workflow

# Update workflow (activate/deactivate)
docker exec selene n8n update:workflow --id=WORKFLOW_ID --active=true
```

### Database Inspection (Safe Read-Only)
```bash
# View workflows
docker exec selene sqlite3 /home/node/.n8n/database.sqlite \
  "SELECT id, name, active FROM workflow_entity;"

# View users
docker exec selene sqlite3 /home/node/.n8n/database.sqlite \
  "SELECT email, firstName, lastName FROM user;"

# Database backup
docker exec selene sqlite3 /home/node/.n8n/database.sqlite \
  ".backup /home/node/.n8n/backup-$(date +%Y%m%d).sqlite"
```

### Important Files
- `docker-compose.yml` - Container configuration
- `.env` - Environment variables (TIMEZONE, paths, etc.)
- `workflows/*/workflow.json` - Production workflow definitions
- `workflows/*/workflow-test.json` - Test workflow definitions
- `data/selene.db` - Selene database (mounted, persists across resets)
- `vault/` - Obsidian vault (mounted, persists across resets)

---

## Contact & Support
- n8n Documentation: https://docs.n8n.io
- n8n Community Forum: https://community.n8n.io
- This recovery guide created: 2025-11-13

**Remember:** Authentication is mandatory in n8n v1.x+. Use a password manager if you need quick access.
