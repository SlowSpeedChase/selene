# Current Environment

**Status:** PRODUCTION

---

## What This Means

- **PRODUCTION**: Claude should NOT make changes to workflows or test against production database
- **DEVELOPMENT**: Claude can freely modify workflows and test against dev database

## Environment Details

| Environment | Port | Database | Container |
|-------------|------|----------|-----------|
| Production | 5678 | selene.db | selene |
| Development | 5679 | selene-dev.db | selene-dev |

## Switching Environments

Use the dev scripts:
- `./scripts/dev-start.sh` - Start dev environment (updates this file)
- `./scripts/dev-stop.sh` - Stop dev environment (updates this file)

## Current Status

- Production: Running (always on)
- Development: Not running

---

*This file is automatically updated by dev-start.sh and dev-stop.sh*
