# Synthesis + Retrieval Agent Design

**Date:** 2026-05-26
**Status:** Vision
**Supersedes:** `2026-05-24-synthesis-layer-design.md`
**Topic:** pkm, synthesis, retrieval-agent, ollama, lancedb

---

## Vision

Selene captures everything but has no way to answer "what do I actually *know* about X?" without searching through individual notes. This design adds three connected pieces:

1. **Background clustering** — nightly workflow that groups semantically similar notes into topic clusters and generates an LLM synthesis per cluster ("You've been circling procrastination since March…")
2. **Retrieval agent** — a local Ollama-powered agent that classifies incoming questions and routes to the right retrieval strategy before answering
3. **Browse + chat interface** — a LAN web UI on iPad that shows your topic clusters and accepts typed questions; synthesis also surfaces in the daily 6am digest

The result: you can open a browser on iPad, see what topics your notes have been forming, tap a cluster to read the synthesis, and ask questions that get answered from your actual notes — not from the internet, not from general knowledge.

---

## What You Get

| Surface | What appears |
|---------|-------------|
| **Daily Apple Notes digest (6am)** | "Topics circling" section: top 3 active clusters with one-line synthesis preview |
| **iPad web browser (`/pkm/synthesis`)** | Full topic list with note counts and last-updated dates |
| **Topic detail page (`/pkm/synthesis/:slug`)** | Full synthesis text + source notes list + chat input |
| **Chat input on any topic page** | Type a question; agent decides how to retrieve, Ollama answers |

---

## Architecture

```
processed_notes (existing, 288 rows)
note_embeddings (existing, 117 rows — needs backfill to 288)
        ↓
synthesize-topics.ts  (nightly 2am, new workflow)
        ↓
topic_clusters + topic_note_links (new SQLite tables)
        ↓
        ├── send-digest.ts  → "Topics circling" section in Apple Notes
        │
        └── Fastify /pkm/synthesis/*  (new routes on existing server)
                ↓
            RetrieverAgent  (new, lives in src/agents/)
                ↓ classifies question
                ↓ selects retrieval tool(s)
                ↓ assembles context
                ↓ Ollama generates answer
```

---

## Data Model

Two new SQLite tables in `data/selene.db`:

```sql
CREATE TABLE topic_clusters (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE,
  parent_id   TEXT REFERENCES topic_clusters(id),
  synthesis_text        TEXT,
  synthesis_updated_at  TEXT,
  note_count            INTEGER NOT NULL DEFAULT 0,
  split_threshold       INTEGER NOT NULL DEFAULT 8,
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
```

Notes belong to multiple topics (many-to-many). A note about procrastination and focus legitimately belongs to both clusters.

---

## Component 1 — Embedding Backfill (prerequisite)

117 of 288 notes have embeddings. The clustering algorithm requires all notes to have them.

**Step 0** before synthesize-topics.ts can run: iterate `raw_notes` where no corresponding row in `note_embeddings`, call `ollama.embeddings('nomic-embed-text', note.content)`, write to `note_embeddings`. This is already the pattern used by the (now-archived) `index-vectors.ts` workflow.

Two options for where this lives:
- **Inline in synthesize-topics.ts** at startup — simple, self-contained
- **Added to process-llm.ts** — embeddings generated at ingest time going forward, no backfill needed after first run

Recommendation: add to `process-llm.ts` so new notes always get embeddings at processing time, and run a one-time backfill on first synthesize-topics.ts execution.

---

## Component 2 — synthesize-topics.ts

New workflow at `src/workflows/synthesize-topics.ts`, scheduled via launchd at 2am daily.

### Clustering Algorithm (embedding-based, not string-frequency)

**Why embeddings over concept strings:** The real note data shows "Personal Growth" and "personal growth" as separate concept strings, and "procrastination" vs "Procrastination" as different values. String-frequency clustering would create duplicate clusters for the same topic. Embedding-based clustering groups semantically similar notes regardless of exact wording.

**Algorithm:**

1. Load all note embeddings (768-dimensional vectors from nomic-embed-text)
2. Compute cosine similarity between every pair of unassigned notes
3. Group notes where similarity ≥ 0.65 (tunable constant `CLUSTER_SIMILARITY_THRESHOLD`)
4. Discard clusters with fewer than 4 notes (`MIN_CLUSTER_SIZE`)
5. For each new cluster: one Ollama call with the top 5 most frequent concept strings across member notes → returns a 2–4 word topic name

**On subsequent runs:** Check for new notes (added since `synthesis_updated_at`) and add them to the closest existing cluster if similarity ≥ threshold. Only trigger full re-cluster if note count has grown by more than 20%.

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

Result stored in `topic_clusters.synthesis_text`. `synthesis_updated_at` stamped.

### Split Detection

Triggers when `note_count >= split_threshold` (default 8). One Ollama call:

```
These {n} notes are all about "{cluster_name}".
Do you see 2 or more clearly distinct sub-themes?

JSON only:
{ "split": false }
OR
{ "split": true, "children": [
    { "name": "Sub-theme A", "note_ids": ["id1", "id3"] },
    { "name": "Sub-theme B", "note_ids": ["id2", "id4"] }
  ]
}
```

If split: create child clusters, reassign `topic_note_links`, parent becomes a hub entry with one-paragraph intro + links to children.

### Delta Guard

Clusters where `topic_note_links.added_at` has no rows newer than `synthesis_updated_at` are skipped entirely — no Ollama calls, no writes.

---

## Component 3 — RetrieverAgent

New agent at `src/agents/retriever-agent.ts`. Extends `BaseAgent` but operates in request-response mode rather than scheduled batch mode — instantiated per web request, not run via launchd.

### Retrieval Tools

| Tool | Fetches | Best for |
|------|---------|----------|
| `getSynthesisForTopic(slug)` | `synthesis_text` + source note titles for one cluster | "What do I know about X broadly?" |
| `searchBySimilarity(question, limit)` | Top N notes by LanceDB cosine similarity to the question embedding | "What did I capture about X specifically?" |
| `getRecentNotes(days, limit)` | Notes from last N days with their essences | "What have I been thinking about lately?" |
| `getConceptNotes(concept, limit)` | Notes containing a specific concept string | "Everything I've tagged with X" |

### Routing Step

One Ollama call to classify the incoming question before retrieval:

```
Classify this question into exactly one category:
- "pattern": asks about recurring themes, what the user knows broadly, tensions
- "specific": asks about a particular detail, memory, or capture
- "recent": asks about what's been happening lately
- "cross-topic": asks about connections between topics

Question: "{question}"

JSON only: { "type": "pattern" | "specific" | "recent" | "cross-topic" }
```

Routing decisions:
- `pattern` → `getSynthesisForTopic` (if a topic is identified) + top 3 by similarity
- `specific` → `searchBySimilarity` (top 8 notes)
- `recent` → `getRecentNotes` (last 14 days) + `searchBySimilarity` (top 3)
- `cross-topic` → `searchBySimilarity` (top 5) + `getSynthesisForTopic` for each matched cluster

### Answer Generation

After retrieval, assemble context (capped at ~2,000 tokens to stay well within mistral:7b's window) and call Ollama:

```
You are answering a question about someone's personal notes.
Use only the information provided — do not invent or generalise beyond it.

Context:
{assembled retrieval results}

Question: {question}

Answer directly and personally ("Your notes show…", "You've been returning to…").
```

---

## Component 4 — Web Interface

New Fastify plugin at `src/routes/pkm-synthesis.ts`, registered under `/pkm/synthesis`. No new server process — extends the existing Fastify instance on port 5678.

### Routes

| Route | Purpose |
|-------|---------|
| `GET /pkm/synthesis` | Topic list: cluster names, note counts, synthesis preview (first sentence), last updated |
| `GET /pkm/synthesis/:slug` | Topic detail: full synthesis text + source note links + chat input |
| `POST /pkm/synthesis/chat` | JSON `{ question, topic_slug? }` → agent runs → returns `{ answer, sources[] }` |
| `GET /pkm/synthesis/chat` | General chat (no topic context): same agent, no topic pre-filter |

### UI (plain TS template literals, no build step)

Same pattern as the PKM Browse Layer design: `layout(title, body)` wrapper, inline `<style>`, system font, `max-width: 760px`, dark mode via `prefers-color-scheme`, tap targets ≥ 44px.

Topic list page shows clusters as cards: cluster name, note count badge, one-line synthesis preview, last updated date.

Topic detail page: synthesis text in a readable block, source notes as a collapsible list, chat textarea at bottom with a Submit button. Response appears below the form without page reload (one `<script>` block with a fetch call — minimal JS, no framework).

---

## Component 5 — Daily Digest Integration

`send-digest.ts` gains a "Topics circling" section inserted after the daily summary and before the end of the Apple Note:

```
## Topics circling

**Procrastination** (12 notes) — You've been returning to the tension between
knowing what to start and not starting it. The open question: is this energy
or structure?

**Personal Growth** (9 notes) — A thread connecting therapy reflections and
self-observation. Recently more active.

**E-Ink journaling** (7 notes) — Consistent practice notes; split into
hardware and habit sub-themes last week.

Browse all topics: http://macbook.local:5678/pkm/synthesis
```

Query: top 3 clusters by `note_count DESC` where `synthesis_updated_at > datetime('now', '-7 days')`. Falls back to top 3 by note_count if nothing updated this week.

---

## Schedule & Integration

```
midnight  → daily-summary.ts         (unchanged)
2am       → synthesize-topics.ts     ← new
6am       → send-digest.ts           ← gains "Topics circling" section
every 5m  → process-llm.ts          ← gains embedding generation for new notes
hourly    → export-obsidian.ts       (unchanged — synthesis/ folder not touched)
```

New file: `launchd/com.selene.synthesize-topics.plist`

`export-obsidian.ts` gets a guard: do not write to or delete files under `vault/synthesis/`. That folder is no longer managed by the exporter — it can be dropped from the exporter entirely, as the web UI is now the primary synthesis surface.

---

## Acceptance Criteria

- [ ] All 288 processed notes have embeddings in `note_embeddings` after first synthesize-topics.ts run
- [ ] `topic_clusters` contains ≥ 3 meaningful clusters from real note data (manual review pass)
- [ ] No junk clusters (single-note, proper-name-only, or incoherent concept groups) in first run output
- [ ] `GET /pkm/synthesis` returns an HTML topic list on iPad Safari
- [ ] Topic detail page renders synthesis text and source notes
- [ ] Chat on a topic page returns a relevant answer within 30 seconds (mistral:7b speed)
- [ ] General chat (`/pkm/synthesis/chat`) answers "what have I been thinking about lately?" with a plausible, note-grounded response
- [ ] Daily digest Apple Note includes "Topics circling" section with ≥ 1 cluster entry
- [ ] `com.selene.synthesize-topics` appears in `launchctl list | grep selene`
- [ ] Delta guard: second synthesize-topics.ts run with no new notes makes zero Ollama calls
- [ ] `GET /health` and `POST /webhook/api/drafts` pass smoke tests after refactor

---

## ADHD Check

- **Reduces friction**: synthesis runs while you sleep; no tagging, no categorizing, no manual grouping
- **Externalizes cognition**: the browse UI answers "what do I know about X?" without you having to hold it in your head
- **Makes information visible**: digest surfaces active topics at 6am; you don't have to go looking
- **Realistic scope**: read-only v1; no editing; no write-back; agent answers questions, doesn't make decisions

---

## Scope Check

~1 week of focused work.

| Component | Effort |
|-----------|--------|
| Embedding backfill + process-llm.ts integration | Small (1 day) |
| synthesize-topics.ts (clustering + synthesis + split) | Medium (2 days) — threshold tuning against real data needed |
| RetrieverAgent (routing + tools + answer) | Medium (1.5 days) |
| Web UI (/pkm/synthesis routes + HTML) | Small-medium (1 day) |
| Digest integration + launchd plist | Small (0.5 days) |

Uncertain part: cosine similarity threshold (0.65) and minimum cluster size (4) are starting values. A manual calibration pass — read 10 cluster outputs, adjust one constant, re-run — is expected before marking this done.

---

## Open Questions (for implementation)

1. **LanceDB vs SQLite for similarity search** — `note_embeddings` is in SQLite (117 rows); `vectors.lance` (LanceDB) also exists. For `searchBySimilarity`, LanceDB is faster at scale. Implementation should write new embeddings to both and use LanceDB for retrieval queries.
2. **Model for routing** — mistral:7b handles 4-option classification reliably. If routing quality is poor in testing, swap routing step only to a stronger pulled model (qwen2.5:7b) without changing synthesis or answer generation.
3. **Obsidian synthesis/ folder** — original design wrote synthesis to vault. With the web UI as primary surface, Obsidian output is optional. Defer to implementation — if it's cheap to keep, keep it; if it adds complexity, drop it.

---

## Related

- Supersedes: `docs/plans/2026-05-24-synthesis-layer-design.md`
- Complements: `docs/plans/2026-04-12-pkm-browse-layer-design.md` (shares `/pkm/*` route namespace; could be built in the same branch)
- Existing infrastructure used: `src/lib/lancedb.ts`, `src/lib/ollama.ts`, `src/agents/base-agent.ts`, `src/workflows/send-digest.ts`, `launchd/com.selene.server.plist`
