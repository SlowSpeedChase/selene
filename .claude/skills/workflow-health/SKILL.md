---
name: workflow-health
description: Data pipeline health check for Selene — DB row counts, last-processed timestamps, Ollama availability, and pending backlog. Complements launchd-check (which covers agent scheduling). Use for daily check-ins or when diagnosing stalled processing.
disable-model-invocation: true
---

# Workflow Health Check

Show the health of Selene's data pipeline: how much data has flowed through, what's pending, and whether LLM processing is available.

> For launchd agent status (is each agent running?), use `/launchd-check` instead.

## Procedure

Run all of these in sequence and report as a single dashboard:

### 1. Database Row Counts

```bash
sqlite3 ~/selene-data/selene.db "
SELECT
  (SELECT COUNT(*) FROM raw_notes) AS raw_total,
  (SELECT COUNT(*) FROM raw_notes WHERE processed = 0) AS raw_pending,
  (SELECT COUNT(*) FROM processed_notes) AS processed_total,
  (SELECT COUNT(*) FROM note_essences) AS essences_total,
  (SELECT COUNT(*) FROM note_essences WHERE essence IS NULL OR essence = '') AS essences_pending;
"
```

### 2. Last Activity Timestamps

```bash
sqlite3 ~/selene-data/selene.db "
SELECT
  'Last ingested'  AS event,
  MAX(created_at)  AS timestamp
FROM raw_notes
UNION ALL
SELECT
  'Last processed',
  MAX(processed_at)
FROM processed_notes
UNION ALL
SELECT
  'Last essence',
  MAX(distilled_at)
FROM note_essences
WHERE essence IS NOT NULL AND essence != '';
"
```

### 3. Ollama Availability

```bash
curl -s http://localhost:11434/api/tags 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    models = [m['name'] for m in d.get('models', [])]
    print('Ollama: ONLINE — models:', ', '.join(models) if models else 'none loaded')
except:
    print('Ollama: OFFLINE')
" 2>/dev/null || echo "Ollama: OFFLINE (connection refused)"
```

### 4. Recent Selene Log Activity (last 5 entries)

```bash
tail -5 ~/selene/logs/selene.log 2>/dev/null | npx --yes pino-pretty --singleLine 2>/dev/null || tail -5 ~/selene/logs/selene.log
```

## Output Format

Present results as a concise dashboard:

```
── Selene Pipeline Health ──────────────────────
  Raw notes:       [total] total, [pending] unprocessed
  Processed notes: [total] total
  Essences:        [total] total, [pending] pending distillation

  Last ingested:   [timestamp or "never"]
  Last processed:  [timestamp or "never"]
  Last essence:    [timestamp or "never"]

  Ollama:          ONLINE (mistral:7b, nomic-embed-text) | OFFLINE
────────────────────────────────────────────────
  ⚠ Flags: [any issues — pending backlog > 50, Ollama offline, no activity in 24h]
```

Flag if:
- `raw_pending > 50` → processing backlog
- `essences_pending > 50` → essence distillation backlog
- Ollama is OFFLINE → LLM workflows will fail silently
- Last processed timestamp is more than 1 hour old (during waking hours)
