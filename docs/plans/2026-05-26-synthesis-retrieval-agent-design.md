# Synthesis Layer Design

**Date:** 2026-05-26
**Updated:** 2026-05-27
**Status:** Ready
**Supersedes:** `2026-05-24-synthesis-layer-design.md`
**Topic:** pkm, synthesis, digest, ollama, lancedb

---

## Vision

Selene captures everything but has no way to answer "what do I actually *know* about X?" without searching through individual notes. This design adds three connected signals surfaced every morning in the digest:

1. **Background clustering** — nightly workflow groups semantically similar notes into topic clusters and generates an LLM synthesis per cluster ("You've been circling procrastination since March…")
2. **Evolution detection** — when a cluster's synthesis meaningfully changes overnight, the digest flags it. On Sundays, a weekly rollup summarises all evolutions across the week.
3. **Connection detection** — when a new note is processed, it immediately searches the full corpus for unexpectedly similar older notes and records the link. Surfaces in the next morning's digest.
4. **Proto-cluster detection** — when 3–4 recent notes are circling the same idea but haven't reached full cluster size, the digest flags the forming pattern.

The result: every morning at 6am, Selene tells you what topics are forming, when your understanding shifted, what last night's notes connect to from months ago, and what new theme might be emerging — without you tagging, categorising, or remembering to check anything.

---

## What You Get (6am digest)

```
## Topics circling
Procrastination (12 notes) — You've been returning to the tension
between knowing what to start and not starting it. The open
question: is this energy or structure?

Personal Growth (9 notes) — A thread connecting therapy reflections
and self-observation. Recently more active.

## Understanding shifted
Your thinking on Procrastination deepened overnight — a new note
added the angle of identity, not just habit.

## Unexpected connections
Last night's note "friction in the morning" connects to something
you wrote in February: "the cost of starting."

## Pattern forming           ← Sundays: weekly evolution rollup
3 recent notes are circling something around sleep and recovery —
not a full cluster yet, but gaining momentum.
```

---

## Architecture (Layered)

```
Every 5 min — process-llm.ts (existing, extended)
  + generate embedding for new note
  + search LanceDB for top similar notes across full corpus
  + write surprising connections → note_connections table

2am nightly — synthesize-topics.ts (new)
  + embedding backfill (one-time on first run)
  + cosine-similarity clustering → topic_clusters + topic_note_links
  + re-synthesize clusters with new notes
  + compare new vs prev synthesis → flag evolution (A)
  + detect proto-clusters below MIN_CLUSTER_SIZE (B)
  + Sunday only: weekly evolution rollup across all clusters

6am — send-digest.ts (existing, extended)
  + "Topics circling" section (top 3 active clusters)
  + "Understanding shifted" section (evolution flags from last run)
  + "Unexpected connections" section (note_connections from last 24h)
  + "Pattern forming" section (proto-clusters or Sunday weekly rollup)
```

---

## Data Model

### New tables

```sql
CREATE TABLE topic_clusters (
  id                    TEXT PRIMARY KEY,
  name                  TEXT NOT NULL,
  slug                  TEXT NOT NULL UNIQUE,
  parent_id             TEXT REFERENCES topic_clusters(id),
  synthesis_text        TEXT,
  prev_synthesis_text   TEXT,           -- for evolution detection
  synthesis_updated_at  TEXT,
  evolution_detected_at TEXT,           -- set when synthesis meaningfully changed
  note_count            INTEGER NOT NULL DEFAULT 0,
  split_threshold       INTEGER NOT NULL DEFAULT 8,
  is_proto              INTEGER NOT NULL DEFAULT 0, -- 1 = below MIN_CLUSTER_SIZE
  created_at            TEXT NOT NULL
);

CREATE TABLE topic_note_links (
  topic_id  TEXT NOT NULL REFERENCES topic_clusters(id),
  note_id   TEXT NOT NULL,
  added_at  TEXT NOT NULL,
  PRIMARY KEY (topic_id, note_id)
);
CREATE INDEX idx_tnl_topic ON topic_note_links(topic_id);
CREATE INDEX idx_tnl_note  ON topic_note_links(note_id);

CREATE TABLE note_connections (
  id               TEXT PRIMARY KEY,
  source_note_id   TEXT NOT NULL,   -- the new note
  target_note_id   TEXT NOT NULL,   -- the older note it connects to
  similarity_score REAL NOT NULL,
  found_at         TEXT NOT NULL
);
CREATE INDEX idx_nc_source ON note_connections(source_note_id);
CREATE INDEX idx_nc_found  ON note_connections(found_at);
```

Notes belong to multiple topics (many-to-many). A note about procrastination and focus legitimately belongs to both clusters.

---

## Component 1 — Embedding Backfill (prerequisite)

Notes added before this feature shipped have no embeddings. The clustering algorithm requires all notes to have them.

**Strategy:** one-time backfill runs at the top of `synthesize-topics.ts` on first execution. Iterates `raw_notes` where no corresponding row in `note_embeddings`, calls `ollama.embeddings('nomic-embed-text', note.content)`, writes to `note_embeddings`. Going forward, `process-llm.ts` generates embeddings for every new note at processing time.

---

## Component 2 — Connection Detection in process-llm.ts

**When:** immediately after a note's embedding is generated (every 5-minute cycle).

**What it does:**
1. Query LanceDB for top 5 most similar notes across the full corpus
2. Filter to notes with similarity ≥ `CONNECTION_SIMILARITY_THRESHOLD` (0.75 — higher than cluster threshold, requiring a strong match)
3. Filter out notes processed within the last 7 days (connections to very recent notes are expected, not surprising)
4. Write remaining matches to `note_connections`

**Why in process-llm.ts:** connections are most valuable when fresh. "Last night you captured X, which connects to something from February" lands harder the next morning than 3 days later. The 5-minute processing cycle means connections are always ready for the 6am digest.

---

## Component 3 — synthesize-topics.ts

New workflow at `src/workflows/synthesize-topics.ts`, scheduled via launchd at 2am daily.

### Clustering Algorithm

1. Load all note embeddings (768-dimensional vectors from nomic-embed-text)
2. Compute cosine similarity between every pair of unassigned notes
3. Group notes where similarity ≥ `CLUSTER_SIMILARITY_THRESHOLD` (0.65, tunable)
4. Discard clusters with fewer than `MIN_CLUSTER_SIZE` (4 notes) — track as proto-clusters instead
5. For each new cluster: one Ollama call with the top 5 most frequent concept strings → returns a 2–4 word topic name

**On subsequent runs:** check for new notes (added since `synthesis_updated_at`) and add to the closest existing cluster if similarity ≥ threshold. Only trigger full re-cluster if note count has grown by more than 20%.

### Synthesis Generation

For each cluster where new notes have been added since `synthesis_updated_at`:

```
You are synthesizing a personal knowledge base.
Topic: "{cluster_name}"
Notes ({n} total):

{for each member note:}
Title: {title}
Essence: {essence}

Write in second person ("You've been exploring..."):
1. 3–5 sentences capturing the recurring questions, tensions, and through-line.
2. The open question that keeps resurfacing (one sentence).
3. Each note as: "- {title} — one sentence on why it belongs here."

Do not invent information not present in the notes.
```

### Evolution Detection (Signal A)

After generating new `synthesis_text`:
1. Copy current `synthesis_text` to `prev_synthesis_text`
2. One Ollama call comparing old vs new: "Did the understanding meaningfully change, or just grow? JSON: { changed: boolean, summary: string }"
3. If `changed: true`, set `evolution_detected_at = now()` and store `summary` for digest use

**Daily:** digest surfaces clusters where `evolution_detected_at > datetime('now', '-1 day')`.

**Sunday weekly rollup:** synthesize-topics.ts checks if `strftime('%w', 'now') = '0'` (Sunday) and generates a single paragraph across all evolutions from the past 7 days. Written to a `weekly_evolution_summary` field in a new `synthesis_meta` key-value table.

### Proto-Cluster Detection (Signal B)

After clustering, any group of 3–`MIN_CLUSTER_SIZE-1` notes that exceed `CLUSTER_SIMILARITY_THRESHOLD` are written to `topic_clusters` with `is_proto = 1`. If a proto-cluster gains enough notes to cross `MIN_CLUSTER_SIZE`, it graduates to a full cluster on the next run.

Digest surfaces proto-clusters where `created_at > datetime('now', '-3 days')` — only flag newly forming patterns, not ones that have been sitting for a week.

### Split Detection

Triggers when `note_count >= split_threshold` (default 8). One Ollama call:

```
JSON only:
{ "split": false }
OR
{ "split": true, "children": [
    { "name": "Sub-theme A", "note_ids": ["id1", "id3"] },
    { "name": "Sub-theme B", "note_ids": ["id2", "id4"] }
  ]
}
```

If split: create child clusters, reassign `topic_note_links`, parent becomes a hub with one-paragraph intro.

### Delta Guard

Clusters where `topic_note_links.added_at` has no rows newer than `synthesis_updated_at` are skipped entirely — no Ollama calls, no writes.

---

## Component 4 — Daily Digest Integration

`send-digest.ts` gains four new sections:

### Topics circling
Query: top 3 clusters by `note_count DESC` where `synthesis_updated_at > datetime('now', '-7 days')`. Fallback to top 3 by note_count if nothing updated this week.

```
## Topics circling

**Procrastination** (12 notes) — You've been returning to the tension between
knowing what to start and not starting it. The open question: is this energy
or structure?
```

### Understanding shifted (Signal A)
Query: `topic_clusters WHERE evolution_detected_at > datetime('now', '-1 day')`.

```
## Understanding shifted
Your thinking on Procrastination deepened overnight — a new note
added the angle of identity, not just habit.
```

### Unexpected connections (Signal C)
Query: `note_connections WHERE found_at > datetime('now', '-1 day')` joined to both note titles.

```
## Unexpected connections
"friction in the morning" (last night) → "the cost of starting" (Feb 2026, 94% match)
```

### Pattern forming (Signal B) / Sunday rollup
Weekdays: proto-clusters where `created_at > datetime('now', '-3 days')`.
Sundays: weekly evolution rollup from `synthesis_meta`.

```
## Pattern forming
3 recent notes circling sleep and recovery — not a full cluster yet.

[Sunday only]
## This week in your thinking
Procrastination shifted toward identity. Personal Growth added 4 notes
on self-observation. A new thread around recovery is forming.
```

---

## Schedule & Integration

```
midnight  → daily-summary.ts         (unchanged)
2am       → synthesize-topics.ts     ← new
every 5m  → process-llm.ts          ← gains embedding generation + connection detection
6am       → send-digest.ts           ← gains 4 new digest sections
hourly    → export-obsidian.ts       (unchanged)
```

New file: `launchd/com.selene.synthesize-topics.plist`

---

## Phase 2 (not in scope for v1)

- **Conversational app** — dedicated privacy-first app for going deep on topic clusters, developing ideas through dialogue, grounded in your actual notes. Uses Ollama locally; `src/lib/anonymize.ts` already exists for any future external API routing.
- **Task loop** — synthesis surfaces actionable patterns → generates projects/tasks in Things; task notes and completions feed back into Selene as new captures.
- **Web browse UI** — `/pkm/synthesis` routes showing topic list and detail pages (already designed in prior iteration, intentionally deferred).

---

## Acceptance Criteria

- [ ] All processed notes have embeddings in `note_embeddings` after first synthesize-topics.ts run
- [ ] `topic_clusters` contains ≥ 3 meaningful clusters from real note data (manual review pass)
- [ ] No junk clusters (single-note, proper-name-only, or incoherent) in first run output
- [ ] `note_connections` table is populated after process-llm.ts runs on a new note
- [ ] Digest "Topics circling" section appears in Apple Notes with ≥ 1 cluster entry
- [ ] Digest "Understanding shifted" section appears when a cluster's synthesis changes
- [ ] Digest "Unexpected connections" section appears when note_connections has rows from last 24h
- [ ] Digest "Pattern forming" section appears when a proto-cluster is detected
- [ ] Sunday digest includes weekly evolution rollup
- [ ] Delta guard: second synthesize-topics.ts run with no new notes makes zero Ollama calls
- [ ] `com.selene.synthesize-topics` appears in `launchctl list | grep selene`
- [ ] `GET /health` and `POST /webhook/api/drafts` pass smoke tests after changes

---

## ADHD Check

- **Reduces friction**: synthesis runs while you sleep; no tagging, no categorising, no manual grouping
- **Externalizes cognition**: digest answers "what do I know and what is shifting?" without holding it in your head
- **Makes information visible**: 4 digest sections surface active topics, evolution, connections, and forming patterns at 6am — you don't have to go looking
- **Realistic scope**: read-only v1; no editing; no write-back; conversational layer and task loop are Phase 2

---

## Scope Check

~1 week of focused work.

| Component | Effort |
|-----------|--------|
| Embedding backfill + process-llm.ts connection detection | 1 day |
| synthesize-topics.ts (clustering + synthesis + evolution + proto-clusters) | 2 days |
| Sunday weekly rollup | 0.5 days |
| Digest integration (4 sections) + launchd plist | 1 day |
| Threshold tuning against real data | 0.5 days |

Uncertain part: cosine similarity threshold (0.65 cluster, 0.75 connection) and minimum cluster size (4) are starting values. A manual calibration pass after first run is expected.

---

## Open Questions (for implementation)

1. **LanceDB vs SQLite for similarity search** — use LanceDB for `searchBySimilarity` in connection detection; write new embeddings to both.
2. **Model for evolution detection** — mistral:7b handles binary changed/unchanged classification reliably. If quality is poor, swap that step only to qwen2.5:7b.
3. **`synthesis_meta` table** — simple key-value store for weekly rollup and any future synthesis-level metadata. One table, not cluttering `topic_clusters`.

---

## Related

- Supersedes: `docs/plans/2026-05-24-synthesis-layer-design.md`
- Phase 2 complements: `docs/plans/2026-04-12-pkm-browse-layer-design.md`
- Existing infrastructure: `src/lib/lancedb.ts`, `src/lib/ollama.ts`, `src/lib/anonymize.ts`, `src/workflows/send-digest.ts`
