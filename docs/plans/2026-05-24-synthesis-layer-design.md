# Synthesis Layer Design

**Date:** 2026-05-24
**Status:** Vision
**Topic:** pkm, synthesis, obsidian, ollama

---

## Vision

Selene captures everything but currently only surfaces individual notes and category-sorted lists. The synthesis layer adds a third knowledge tier: **topic clusters** — automatically detected groupings of related notes, with an LLM-generated synthesis that describes what you know about a topic, the recurring tensions, and the open questions. Synthesis notes link back to all source notes and form a navigable hierarchy that splits as topics grow.

The goal: you can open Obsidian and answer "what do I actually *know* about standing desks?" without searching, without reading 12 individual notes.

---

## Design Principles

- **Zero input required**: synthesis emerges automatically from concepts already extracted by `process-llm.ts`. No tagging, no categorizing.
- **Local-first**: Ollama only. No cloud API calls.
- **DB is source of truth**: Obsidian files are a rendered view. The `topic_clusters` table is what the future PKM browse layer will read from directly.
- **Propose structure, don't impose it**: the split detection asks Ollama "do you see sub-themes?" and only splits when the answer is unambiguous. Conservative threshold (8 notes before split check).
- **Delta updates**: clusters with no new notes since last synthesis run are skipped entirely.

---

## Architecture

```
processed_notes (existing)
  concepts: ["ergonomics", "standing desk", "back pain"]
        ↓ synthesize-topics.ts (daily at 2am)
topic_clusters (new DB table)
  "Ergonomics & Workspace" → member notes
  ↓ when split_threshold reached + sub-themes detected
  "Standing Desks" (child, parent_id = ergonomics)
  "Back Pain"      (child, parent_id = ergonomics)
        ↓ write to Obsidian
vault/synthesis/
  _INDEX.md
  ergonomics-workspace.md       ← hub after split
  ergonomics-workspace/
    standing-desks.md
    back-pain.md
```

### Future: Approach C (PKM Browse Layer)

The `topic_clusters` and `topic_note_links` tables are designed to be read directly by the PKM dashboard at `/pkm/synthesis`. When that layer is built, no DB migration is needed — the same rows power both the Obsidian files and the web dashboard. The Obsidian export becomes optional.

---

## Data Model

Two new SQLite tables added to `data/selene.db`:

### `topic_clusters`

```sql
CREATE TABLE topic_clusters (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  parent_id TEXT,
  synthesis_text TEXT,
  synthesis_updated_at TEXT,
  split_threshold INTEGER NOT NULL DEFAULT 8,
  created_at TEXT NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES topic_clusters(id)
);
```

### `topic_note_links`

```sql
CREATE TABLE topic_note_links (
  topic_id TEXT NOT NULL,
  note_id TEXT NOT NULL,
  added_at TEXT NOT NULL,
  PRIMARY KEY (topic_id, note_id),
  FOREIGN KEY (topic_id) REFERENCES topic_clusters(id)
);
```

Notes can belong to multiple topics (many-to-many). A note about "standing desks and focus" legitimately belongs to both an Ergonomics cluster and a Focus/Productivity cluster.

---

## Topic Discovery Algorithm

Runs at the start of each `synthesize-topics.ts` execution.

**Step 1 — Concept frequency scan**
Query all `processed_notes.concepts` (JSON arrays). Count concept frequency across all notes. Concepts appearing in **3+ notes** become candidate cluster seeds.

**Step 2 — Group notes by seed concept**
For each seed concept, collect all notes containing it → preliminary cluster.

**Step 3 — Merge overlapping clusters**
If two seed concepts share ≥60% of the same member notes (Jaccard similarity on note ID sets), they describe the same topic and are merged into one cluster.

**Step 4 — Name the cluster**
One Ollama call per new/merged cluster:
```
Given these concept keywords: [ergonomics, standing desk, monitor height]
Return a 2-4 word topic name. Return only the name, nothing else.
```
Stored as `name`. Slugified as `slug` for Obsidian filenames.

**Existing clusters:** On subsequent runs, the algorithm checks for new notes that belong to existing clusters (via concept overlap) and adds them to `topic_note_links`. It does not re-run the full discovery pass for clusters that already exist unless their note count changes enough to trigger a merge or split check.

---

## Synthesis Generation

For each cluster where `topic_note_links.added_at > topic_clusters.synthesis_updated_at` (delta check — only regenerate when new notes arrived):

```
You are synthesizing a personal knowledge base.
Topic: "{cluster_name}"
Notes ({n} total):

{for each note:}
Title: {title}
Essence: {essence}
Top concepts: {top 3 concepts}

Write a synthesis in second person ("You've been exploring..."):
1. A 3-5 sentence synthesis capturing the recurring questions,
   tensions, and through-line across these notes.
2. Any open questions that keep resurfacing.
3. List each note as "- [[{slug}]] — one sentence on why it belongs here."

Do not invent information not present in the notes.
Use [[filename]] links exactly as provided.
```

Output stored in `topic_clusters.synthesis_text`.

---

## Split Detection

Triggers when `COUNT(topic_note_links WHERE topic_id = ?) >= split_threshold` (default: 8).

One Ollama call with all member note essences:

```
These {n} notes are all about "{cluster_name}".
Do you see 2 or more clearly distinct sub-themes?

Respond with JSON only — no explanation:
{ "split": false }
OR
{ "split": true, "children": [
    { "name": "Standing Desks", "note_ids": ["id1", "id3", "id7"] },
    { "name": "Back Pain",      "note_ids": ["id2", "id4", "id5", "id6"] }
  ]
}
```

If `split: true`:
1. Create child `topic_clusters` with `parent_id` = current cluster id
2. Reassign `topic_note_links` rows to appropriate child cluster IDs
3. Parent synthesis becomes a **hub note**: short intro paragraph + wikilinks to each child synthesis note. Parent `synthesis_text` is regenerated with this hub structure.

Split check only runs once per threshold crossing. After a split, the threshold resets relative to the child clusters.

---

## Obsidian Output

New folder structure alongside existing `notes/` and `mocs/`:

```
vault/
  synthesis/
    _INDEX.md                         ← full topic tree, always regenerated
    ergonomics-workspace.md           ← root synthesis or hub
    ergonomics-workspace/
      standing-desks.md
      back-pain.md
  notes/                              ← unchanged
  mocs/                               ← unchanged
  Dashboard.md                        ← gains a ## Synthesis section
```

### Synthesis note format

```markdown
---
topic: Ergonomics & Workspace
note_count: 9
parent: null
children: [ergonomics-workspace/standing-desks, ergonomics-workspace/back-pain]
last_updated: 2026-05-24
---

You've been returning to workspace ergonomics for three months.
The tension that keeps resurfacing: you know standing more would
help your back, but you haven't committed to the setup change.
The open question is cost vs. benefit — your notes circle this
without resolving it.

## Sub-topics
- [[synthesis/ergonomics-workspace/standing-desks]]
- [[synthesis/ergonomics-workspace/back-pain]]

## Source notes
- [[notes/2026-03-10-standing-desk-thoughts]] — initial research pass
- [[notes/2026-04-02-back-pain-patterns]] — recurring symptom log
```

### `_INDEX.md` format

```markdown
# Synthesis Index
*{n} topics across {m} notes. Last updated: {date}.*

## Topics
- [[ergonomics-workspace]] (9 notes)
  - [[ergonomics-workspace/standing-desks]] (5 notes)
  - [[ergonomics-workspace/back-pain]] (4 notes)
- [[morning-routine]] (6 notes)
- [[typescript-patterns]] (3 notes)
```

### Dashboard.md addition

A `## Synthesis` section is added (or updated) listing `_INDEX.md` and the 3 most recently updated synthesis topics.

---

## Schedule + Integration

New launchd plist: `com.selene.synthesize-topics.plist` — daily at **2am**.

```
midnight  → daily-summary.ts        (unchanged)
2am       → synthesize-topics.ts    ← new
6am       → send-digest.ts          (unchanged)
every 5m  → process-llm.ts, distill-essences.ts  (unchanged)
hourly    → export-obsidian.ts      (unchanged — preserves synthesis/ on disk)
```

`export-obsidian.ts` receives a guard: do not overwrite files under `vault/synthesis/`. Synthesis files are owned by `synthesize-topics.ts`.

---

## Acceptance Criteria

- [ ] `topic_clusters` and `topic_note_links` tables migrated to `data/selene.db`
- [ ] Concept frequency scan correctly clusters existing notes (manual verification pass: inspect output, adjust thresholds if needed)
- [ ] Synthesis notes generated in `/vault/synthesis/` with working `[[wikilinks]]` to source notes
- [ ] `_INDEX.md` reflects full topic tree after each run
- [ ] Dashboard.md updated with `## Synthesis` section linking to `_INDEX.md`
- [ ] Split detection: cluster at/above threshold gets a split-check call; children created and parent becomes hub when sub-themes are detected
- [ ] Delta updates: clusters with no new notes since `synthesis_updated_at` are skipped
- [ ] `com.selene.synthesize-topics.plist` running via launchd, visible in `launchctl list | grep selene`
- [ ] `export-obsidian.ts` preserves `synthesis/` folder on each export run

## ADHD Check

- **Reduces friction**: zero input — synthesis emerges from captures you've already made
- **Visible**: appears in Obsidian Dashboard.md, the place you already look
- **Externalizes cognition**: you can see *what you know* about a topic, not just *what you captured*
- **Realistic scope**: v1 is read-only synthesis generation, no UI, no approval flows

## Scope Check

~1 week of focused work.

| Component | Effort |
|-----------|--------|
| DB migration (2 tables) | Small |
| Concept clustering algorithm | Medium — threshold tuning needed |
| Ollama prompts (naming, synthesis, split detection) | Medium — iteration expected |
| Obsidian file writer | Small — follows export-obsidian patterns |
| launchd plist + install-launchd.sh | Small |
| Dashboard.md + export-obsidian guard | Small |

Uncertain part: concept clustering thresholds (minimum frequency = 3, Jaccard merge threshold = 60%, split threshold = 8). These are starting values and will need a manual calibration pass against real note data before shipping.

---

## Vision: Approach C (PKM Browse Layer)

When the PKM browse layer ships, `/pkm/synthesis` reads from `topic_clusters` and `topic_note_links` directly. The topic hierarchy becomes a browsable tree in the web dashboard — no Obsidian required. The Obsidian files become an optional second rendering, not the primary interface. No schema migration needed; the tables are designed for this from day one.
