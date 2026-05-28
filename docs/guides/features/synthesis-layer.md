# Synthesis Layer

**What this does for you:** Every morning Selene tells you what topics you keep circling, when your understanding of something shifted, and what last night's notes unexpectedly connect to from months ago — without you having to tag, search, or remember anything.

## Using it

There's nothing to do. The synthesis layer runs automatically every night and adds four new sections to your 6am Apple Notes digest:

```
## Topics circling
DevOps Incident Management (29 notes) — You've been exploring
various aspects of incident management, with a recurring theme
revolving around production incidents and their impact on your team.

## Understanding shifted
Procrastination: The angle shifted toward identity, not just habit.

## Unexpected connections
"Friction in the morning" → "The cost of starting" (Feb 2026, 88% match)

## Pattern forming
3 recent notes circling "Dopamine and Digital Habits" — not a full cluster yet.
```

On Sundays, "Pattern forming" is replaced by a **weekly evolution rollup** summarising how your understanding across all topics shifted during the week.

## How it works

**Three signals, two workflows:**

| Signal | When | Workflow |
|--------|------|----------|
| **C — Connection detection** | Every 5 min (at process time) | `src/workflows/process-llm.ts` |
| **A — Evolution detection** | Nightly at 2am | `src/workflows/synthesize-topics.ts` |
| **B — Proto-cluster detection** | Nightly at 2am | `src/workflows/synthesize-topics.ts` |

**process-llm.ts (extended):** After extracting concepts from a new note, it generates an embedding and searches LanceDB for older notes (>7 days) with ≥ 75% similarity. Surprising matches are written to the `note_connections` table.

**synthesize-topics.ts (new, 2am):**
1. Backfills embeddings for any notes that missed process-llm (limit 200/run)
2. Loads all embeddings from SQLite, clusters by cosine similarity (threshold 0.65)
3. Clusters ≥ 4 notes get an Ollama synthesis narrative (mistral:7b); smaller groups become proto-clusters
4. If a cluster's synthesis changed since yesterday, an evolution check fires
5. On Sundays, a weekly rollup summarises all evolution events from the past 7 days

**send-digest.ts (extended):** Reads the new tables and appends the 4 synthesis sections to the digest before posting to Apple Notes.

**New tables:** `topic_clusters`, `topic_note_links`, `note_connections`, `synthesis_meta`

**Launchd agent:** `com.selene.synthesize-topics` — runs at 2:00am daily.

## Configure & customize

| Setting | Where | Default |
|---------|-------|---------|
| Cluster similarity threshold | `src/workflows/synthesize-topics.ts` `CLUSTER_SIMILARITY_THRESHOLD` | `0.65` |
| Minimum cluster size | `src/workflows/synthesize-topics.ts` `MIN_CLUSTER_SIZE` | `4` |
| Connection similarity threshold | `src/workflows/process-llm.ts` `CONNECTION_THRESHOLD` | `0.75` |
| Embedding backfill batch size | `src/workflows/synthesize-topics.ts` (LIMIT 200 in SQL) | `200` |

**Tuning guide:**
- Clusters too broad / incoherent → raise `CLUSTER_SIMILARITY_THRESHOLD` to `0.70`
- Too many tiny clusters → lower to `0.60`
- Connections too obvious → raise `CONNECTION_THRESHOLD` to `0.80`
- Too many proto-clusters never graduating → lower `MIN_CLUSTER_SIZE` to `3`

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No "Topics circling" in digest | Run `npx ts-node src/workflows/synthesize-topics.ts` manually; check `sqlite3 data/selene.db "SELECT COUNT(*) FROM topic_clusters WHERE is_proto=0;"` |
| `note_connections` always empty | Normal until notes have been processed through the new `process-llm.ts` for 7+ days |
| "Understanding shifted" never appears | Needs two nights where a cluster's synthesis changes; add notes to an existing topic and wait |
| First run is slow (5-10 min) | Embedding backfill: 200 notes/run × ~5s each. Runs 3× to cover 536 notes; stabilises after that |
| Delta guard not firing | Check that `synthesis_updated_at` is set in `topic_clusters`; if null for a cluster, it re-synthesises every run |
| `synthesize-topics.ts` crashes on first run with "no such column" | Stale schema from an earlier version — `sqlite3 data/selene.db "DROP TABLE IF EXISTS topic_note_links; DROP TABLE IF EXISTS topic_clusters;"` and rerun |
| launchd agent not in list | Run `./scripts/install-launchd.sh` and check `launchctl list \| grep synthesize` |

## Related

- Design doc: `docs/plans/2026-05-26-synthesis-retrieval-agent-design.md`
- Implementation plan: `docs/plans/2026-05-27-synthesis-layer-plan.md`
- Connected guides: `docs/guides/features/daily-digest.md`

---
*Last updated: 2026-05-28*
