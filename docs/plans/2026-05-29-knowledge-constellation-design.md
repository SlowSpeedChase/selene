# Design: Knowledge Constellation (ExcaliBrain visual surface)

**Date:** 2026-05-29
**Status:** Vision → **Ready** (pending acceptance-criteria + ADHD check below)
**Depends on:** Synthesis layer (`synthesize-topics.ts`, `synthesis-db.ts`), [[2026-05-29-excalidraw-excalibrain-research]]
**Related:** [[2026-05-26-synthesis-retrieval-agent-design]], [[2026-05-29-content-based-multitopic-clustering-design]], Lumen native port (someday-maybe escape hatch)

---

## What & why

A **navigable "knowledge constellation"** — a visual map of the user's notes that they can *fly through* by clicking from note to related note. Externalizes the shape of one's own thinking (ADHD principle #4: visual over mental), making latent connections between notes spatially obvious instead of buried in a list.

**Validated decision (2026-05-29):** built on **ExcaliBrain inside Obsidian**, not a native app. ExcaliBrain renders a live, read-only, auto-laid-out graph from each note's links/Dataview fields, recomputed on every navigation. The user feel-tested it on real data (dev vault, Topic hub → ~18–20 node crowd, click-to-recenter navigation) and accepted the recenter-hop motion as "flying." See the research doc for full rationale, including why this dissolves the regeneration-vs-annotation conflict and why true semantic zoom (the one thing that would force a native build) is not required.

**Selene's only job:** ExcaliBrain needs no code. Selene writes **structured relationship data into the notes it already exports**, so ExcaliBrain renders a rich graph. That structured data already largely exists in the synthesis layer.

---

## Surfaces (scope)

This design covers **one** of the two surfaces in the broader vision:

- ✅ **Constellation** (this doc) — the persistent, navigable map.
- ⛔ **Handwriting "dump zone"** (out of scope here) — existing SeleneMarkup/OCR territory; designed/shipped separately ([[project_note_annotation]]).

---

## Data foundation (verified 2026-05-29)

ExcaliBrain infers graph edges from a note's wikilinks, Dataview inline fields, tags, and YAML. The synthesis layer already produces most of the relationship structure:

| Synthesis table | Holds | Prod rows | Constellation role |
|---|---|---|---|
| `topic_clusters` (`parent_id` hierarchy) | LLM-named, hierarchical topic groups | **83** | Container nodes; hierarchy = navigable detail levels |
| `topic_note_links` | cluster→note membership | **286** | Cluster–note edges (parent/child) |
| `note_connections` | pairwise note similarity (`writeConnection`) | **0 (empty)** | Note↔note "friend" edges = direct note-to-note flight |

**Current gaps (the actual work):**
1. `note_connections` is **empty (0 rows prod / 1 dev) despite a wired write path** — `writeConnection()` *is* called in `process-llm.ts:164` with an `approxSimilarity`, and embeddings exist (`note_embeddings` table; `cosineSimilarity` in `cosine.ts`; `synthesize-topics.ts` already computes pairwise sims for clustering at line ~95). So the machinery is present but the edge-write path isn't producing rows. **Phase B requires a diagnostic first** (why does the call site yield ~0 rows — candidate gating? empty embeddings at call time?), not merely a threshold tune. Effort unverified until that spike.
2. `export-obsidian.ts` emits **no Dataview fields** — only body-text `[[wikilinks]]` (verified: it reads `processed_notes`, not the synthesis tables). It needs to read `topic_clusters`/`topic_note_links` and emit structured `parent::` / `friend::` fields for ExcaliBrain to read clean relationships.
3. **DB path RESOLVED (verified 2026-05-29):** `config.ts:getDbPath()` defaults to `~/selene-data/selene.db` — the prod DB that holds the 83 clusters / 286 links. `data/selene.db` is a **stale repo leftover** (real 454KB file, Apr 13, not a symlink, not read by any workflow). So the export opens the DB that has the synthesis data — Phase A is genuinely data-ready. (Memory [[feedback_db_path]] symlink claim is stale — correct it.)

---

## Approach — two honestly-sized phases

### Phase A — Cluster constellation (data-ready, low effort)
Emit the existing cluster hierarchy as Dataview fields so the user can fly **cluster → note → cluster**.

**What this adds over the baseline already demoed:** the feel-test on 2026-05-29 flew on *body-text `[[wikilinks]]`* (Topic notes linking to member notes) with zero new Selene code. Phase A's value over that baseline is **clean structured hierarchy**: `parent::` Dataview fields give ExcaliBrain unambiguous parent/child edges (vs. links buried in prose, mixed with theme/concept links), and the `topic_clusters.parent_id` chain exposes *multi-level* containers (cluster → sub-cluster → note) that the flat Topic→Note body links cannot. That hierarchy is the "containers AND detail levels by navigation" the user wants.

- In `export-obsidian.ts` (or a new export step), for each exported note read its `topic_note_links` and write inline Dataview fields, e.g. `parent:: [[<cluster note>]]`.
- Export each `topic_cluster` as its own note with `parent:: [[<parent cluster>]]` to expose the hierarchy.
- Result in ExcaliBrain: clusters are container nodes; notes hang off them; the `parent_id` hierarchy gives detail levels via click-to-descend. **No new computation — data exists in the prod DB the export already opens.**

### Phase B — Note-to-note flight (the chosen target)
Populate the missing pairwise edges so the user flies **note → directly to a related note**.

- **Diagnose first (spike):** the write path (`writeConnection` at `process-llm.ts:164`, embeddings in `note_embeddings`, `cosineSimilarity`) exists but yields ~0 rows. Find out why before sizing — candidate gating, empty embeddings at call time, or a threshold that rejects everything. **Until this spike, Phase B effort is unverified — do not assume "small."**
- Once understood, ensure pairwise similarity is computed and `note_connections` is populated above a tuned threshold + top-N cap per note (avoid hairball). Note `synthesize-topics.ts` *already* computes pairwise sims for clustering (~line 95) — the cheapest fix may be routing those into `note_connections` rather than relying on the process-llm call site.
- In the export step, emit top-N `friend:: [[<note>]]` fields per note from `note_connections`.
- Result: ExcaliBrain shows related notes as lateral "friends" — direct flight without routing through a cluster hub. This is the constellation the user picked.

**Why phase, not all-at-once:** Phase A delivers a real, flyable constellation from data that already exists, immediately. Phase B turns on the note↔note edges — but its size is unknown until the diagnostic spike, so it must not gate Phase A.

---

## Acceptance criteria

- [ ] **Phase A:** Opening any exported note in ExcaliBrain shows it connected to its topic cluster(s); clusters show their member notes; cluster hierarchy is navigable by click-to-recenter. Built from existing prod synthesis data.
- [ ] **Phase B:** Each note shows its top-N most-similar notes as friend edges; user can traverse note→note→note without passing through a cluster. `note_connections` is actually populated (diagnostic spike completed first).
- [ ] Selene's scheduled regeneration of notes never breaks or duplicates the graph (ExcaliBrain re-reads on each navigation — verify after a regen cycle).
- [ ] Dataview fields are additive — they don't disrupt the existing Obsidian note reading experience.
- [ ] A short user guide added: `docs/guides/features/knowledge-constellation.md` + hub link (per CLAUDE.md wrap-up rule).

## ADHD check

- **Externalizes working memory / visual-over-mental:** ✅ core purpose — makes the shape of one's thinking spatial.
- **Reduces friction:** ✅ zero new capture/interaction burden; the map is generated, not maintained by hand.
- **Realistic over idealistic:** ✅ Phase A ships something real from existing data rather than waiting on the full vision.

## Scope check

- No new always-on infrastructure (ExcaliBrain is a read-only view; Selene only adds fields to an existing export).
- Phase B reuses existing embedding/cosine utilities — no new model or service.
- Test bed already stood up: `~/selene-data-dev/vault` (live-vault replica + ExcaliBrain 0.2.17).

---

## Open questions (carry into the plan)

1. **Cluster-note file naming:** ExcaliBrain matches `[[wikilinks]]` to note filenames. Confirm exported cluster notes and note filenames resolve cleanly (the existing filenames carry dates/parens — e.g. `2025-11-01-... (2025-11-01).md`).
2. **Threshold/top-N for `note_connections`:** what similarity cutoff and per-note cap keeps the constellation legible (avoid a hairball) while still feeling connected? Needs empirical tuning in the dev vault.
3. **Performance ceiling:** ExcaliBrain recomputes from the metadata cache per navigation; confirm responsiveness at full note volume (research left this unquantified).
4. **Phase B sizing:** the diagnostic spike (why `note_connections` is ~0 despite a wired write path) must complete before Phase B can be estimated or scheduled.
5. **Annotation path:** if the user wants to draw on a constellation, ExcaliBrain's one-way "Take Snapshot" forks a static Excalidraw file — confirm that satisfies, or revisit.

---

## Escape hatch (explicit)

A **native build** (folds into the Lumen port, reading Selene output read-only) becomes justified **only if**: (a) true content-morphing semantic zoom becomes a hard requirement, or (b) the user needs a single artifact that mixes persistent hand-annotation with scheduled regeneration. Neither is required as of this design.
