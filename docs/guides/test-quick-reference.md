# Test Environment - Quick Reference Card

## 🚀 Testing Commands

```bash
# Submit test note
./scripts/test-ingest.sh "test_name" "Title" "Content"

# Check results
./scripts/test-verify.sh "test_name"

# Reset test environment
./scripts/test-reset.sh

# Verify production is clean
./scripts/verify-production-clean.sh
```

## 📋 Test Workflows (Must be Active)

- Selene TEST: Note Ingestion
- Selene TEST: LLM Processing
- Selene TEST: Sentiment Analysis
- Selene TEST: Obsidian Export

Activate at: http://localhost:5678

## 🔐 Data Locations

| Environment | Database | Vault | Webhook |
|-------------|----------|-------|---------|
| **Production** | `./data/selene.db` | `./vault` | `/api/drafts` |
| **Test** | `./data-test/selene-test.db` | `./vault-test` | `/api/test/drafts` |

## ✅ Daily Checklist

- [ ] Production has 0 test notes: `./scripts/verify-production-clean.sh`
- [ ] Test workflows active in n8n UI
- [ ] Test note processes end-to-end (< 60 seconds)
- [ ] Production Drafts action still works normally

## 🎯 Feature Development Flow

1. Modify test workflow (e.g., `workflow-test.json`)
2. Import: `docker exec selene n8n import:workflow --input=/workflows/workflows/XX/workflow-test.json`
3. Restart: `docker-compose restart n8n`
4. Test: `./scripts/test-ingest.sh "feature_v1"`
5. Verify: `./scripts/test-verify.sh "feature_v1"`
6. Deploy to production when ready

## 📖 Full Documentation

- `TEST-ENVIRONMENT-READY.md` - Complete setup summary
- `TEST-ENVIRONMENT-STRATEGY.md` - Full strategy guide
- `ACTIVATION-INSTRUCTIONS.md` - How to activate workflows
- `PRODUCTION-CLEAN-SETUP.md` - Production safety

## 🆘 Troubleshooting

```bash
# n8n not responding
docker-compose restart n8n

# Test webhook not working
# → Activate test workflows in UI

# Test data in production
./scripts/clean-production-database.sh

# Reset test environment
./scripts/test-reset.sh
```

## 💡 Remember

- Production: Use Drafts app (as normal)
- Testing: Use `test-ingest.sh` script
- Both: Completely isolated!
