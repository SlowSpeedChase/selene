# Content-Based, Multi-Topic Clustering

**Date:** 2026-05-29
**Status:** Ready
**Topic:** clustering, processing-pipeline, embeddings, ipad-browse, reprocessing

---

## Problem

In the SeleneMarkup iPad app, the Notes section shows **"E-Ink Empowerment: Personal
Growth & Relations"** as a giant category with **104 notes — all 104 are `eink`**. Every
other cluster is small (≤11) and almost entirely `drafts`. The owner does not care *how*
or *where* a note was captured (source is fine to keep as metadata); they care about the
**content**. Two distinct failures produce this:

1. **Clustering by muddiness, which correlates with source.** `synthesize-topics.ts`
   embeds the **whole note** (`embed(note.content)`). E-ink notes are long, multi-topic
   brain-dump pages (avg 790 chars, max 4291). Averaging a whole page into one 768-dim
   vector yields a blurred "generic personal-growth" vector; all 104 such vectors look
   mutually similar, so the greedy clusterer swept them into one blob — and the naming LLM
   christened it after the source ("E-Ink Empowerment").

2. **Hard single-assignment.** `clusterNotes()` calls `assigned.add(noteId)` the moment a
   note joins a cluster, so every note lands in **exactly one** cluster (confirmed: 286
   `topic_note_links` across 286 distinct notes — 1:1). A brain-dump page touching five
   topics can never appear under more than one; its other topics vanish.

A third, fixable contributor: e-ink `content` contains **source boilerplate**
(`# E-Ink: <date> kindle journal`, `--- Page 1 ---`, `E-Ink:` title prefix) that is
embedded along with the real content, injecting an "e-ink-ness" signal into all 110
vectors.

## Goal / success criterion

The real deliverable is the **iPad Notes browse view**. Success =

- the 104-note e-ink bucket is gone, replaced by **content-themed topics**;
- a single brain-dump page appears under **every** topic it actually touches;
- the list is **not** shattered into ~150 one-note clusters;
- `capture_type` remains as metadata but never drives a cluster.

## Constraints / decisions made

- **Scope:** Full — segment each note into topical chunks, embed each chunk, cluster at
  the **chunk** level, and link a note to **every** topic its chunks land in.
- **Segmentation:** Hybrid — split on natural boundaries (`--- Page N ---`, Markdown
  headings, blank-line paragraphs), then the local LLM merges/splits into clean topical
  segments and labels each (`note_chunks.topic`).
- **Transition:** Full clean rebuild — wipe and regenerate clusters from chunks (no mixing
  old whole-note clusters with new chunk clusters).
- **De-bias:** strip source boilerplate from content before embedding/segmenting; the
  cluster-naming prompt must name by **theme**, never by source/format.
- **Build gate:** a Phase 0 spike must prove chunks separate topics before the pipeline is
  built (see below).
- **Project rule:** never test on the prod DB — validate on a prod→dev snapshot first.

## Key facts verified (2026-05-29)

- Largest non-proto cluster: "E-Ink Empowerment: Personal Growth & Relations", `note_count`
  104, **all 104 notes are `eink`**. Next largest is 11 (`drafts`).
- `capture_type` counts: `drafts` 182, `eink` 110, `annotation` 1.
- The app's `/api/clusters` reads real `topic_clusters` (`WHERE is_proto = 0 ORDER BY
  note_count DESC`) — there is **no** grouping by source in the route code. The "eink"
  category is a genuine content cluster, not a source filter.
- Clustering embeds **whole-note content** (`process-llm.ts:127`, `synthesize-topics.ts`
  backfill). `clusterNotes()` is greedy single-pass with **hard exclusive assignment**.
- **Unused infrastructure already exists:** `note_chunks` (per-chunk `topic` + `embedding`
  BLOB) and `topic_note_links` (many-to-many, PK = topic+note) and `topic_clusters.is_proto`.
  The clustering workflow ignores chunks and uses whole-note vectors.
- `note_chunks` currently holds **176 stale rows** from the archived chunker (chunk_index 0,
  10-char content, garbage repeated topics; only referenced under `archive/`). Must be
  wiped, not reused.
- `synthesize-topics` **is** scheduled — `com.selene.synthesize-topics.plist`, and
  `com.selene.prod.synthesize-topics` is loaded in prod (compiled `dist/`). A one-time full
  rebuild is therefore a **manual one-shot run** (dev first, then prod after deploy).
- A sample e-ink note confirms genuine multi-topic content (Vision Board, core drivers,
  life areas, finances, health) split by `--- Page N ---` and `**Title:**`/heading markers
  — highly segmentable.

## Architecture

```
ingest ─▶ process-llm.ts                                 ─▶ synthesize-topics.ts
          • debiasContent(): strip E-Ink/Page boilerplate    • clusterChunks(): greedy over chunk
          • segmentNote(): structure split → LLM merge/        vectors, re-tuned threshold θ
            split/label → note_chunks(content, topic)         • note → link to EVERY topic its
          • embed EACH chunk → note_chunks.embedding            chunks hit (union, dedup)
          • keep whole-note embedding (for search)            • note_count = DISTINCT parent notes
                                                              • min-size guard → small = is_proto
                                                              • name by THEME, never source
```

The clustering unit moves from **note → chunk**. That single change unlocks multi-topic
membership: a note's chunks scatter into different clusters and the parent note links to
each. Chunks are embedded *in addition to* the whole-note embedding — vector **search**
wants one vector per note; **clustering** wants chunks.

## Phase 0 — SPIKE (gates the build)

Before building anything, validate the core hypothesis on real data: **do chunks from
different topics actually pull apart?** Take ~8 notes from the current "E-Ink Empowerment"
cluster, hand-segment, embed the chunks, and inspect pairwise cosine similarity.

- **Risk being tested:** if the owner genuinely brain-dumps about *personal growth* on the
  e-ink device, those chunks may stay mutually similar and **re-collapse** into a "Personal
  Growth" cluster that is *still* ~all e-ink — same outcome, new name.
- **Question answered:** is there a threshold θ that separates distinct topics without
  shattering everything?
- **Gate:** if the spike fails, **stop and rethink** (hierarchical topics, or accept broad
  themes) rather than build a pipeline that reproduces the bucket.

### Spike RESULTS (2026-05-29) — GATE: the embedding-clustering approach FAILED; pivot required

Run against a read-only prod snapshot (`/tmp/spike-snapshot.db`; the dev DB had been
re-seeded with fictional fixtures by the parallel prod/dev work, so it could not be used).
Script: `scripts/spike-chunk-separation.ts`.

- **Whole-note e-ink cohesion = 0.714** > current threshold 0.65 → confirms why all 104
  collapse today.
- **Chunk-level** loosens cohesion (within-note 0.563 ≈ cross-note 0.546) but does **not**
  separate clean topics. Clustering raw chunk text produced **grab-bags + OCR-boilerplate
  clusters**: the dominant cluster is a 31–61-note *"What Went Well today?"* daily-journal
  blob; clusters [2]/[3] were pure OCR scaffolding (`**Page Numbering and Footer** 3 of 3`).
  Aggressive OCR de-biasing is needed but is not sufficient.
- **The content is genuinely homogeneous daily journaling.** The LLM gave **102 distinct
  `primary_theme` strings for 110 notes** — near-unique paraphrases ("Work and Personal
  Relations" / "…Development" / "…Life Balance") all orbiting the same few domains. No hidden
  clean taxonomy emerges from free-form theming; distilled-theme clustering would re-collapse
  or fragment just like raw text.
- **Decisive:** a **controlled taxonomy already exists** (`CATEGORIES` in `prompts.ts`, 8
  values) and every e-ink note is **already classified** into it via
  `processed_notes.category` (+ `cross_ref_categories` for multi-membership):
  Personal Growth 32, Relationships & Social 19, Projects & Tech 19, Daily Systems 10,
  Career & Work 8, Health & Body 7, Politics & Society 2 — plus several multi-category notes.
- **Conclusion:** embedding-based `topic_clusters` clustering is the wrong tool for this
  homogeneous content. The user's goals (content-based groups, theme names, multi-membership)
  are met *for free* by the controlled categories. Drafts, by contrast, DID embedding-cluster
  cleanly. → Pivot to a **category-based grouping** (hybrid: categories top-level, embedding
  sub-clusters optional/for drafts). Pending user decision before re-planning Phases 1–5.

## Components / changes

### `src/workflows/process-llm.ts`
- `debiasContent(content, title)`: strip `# E-Ink: …` header, `--- Page N ---` separators,
  and the `E-Ink:` title prefix (extensible to other source markers).
- `segmentNote(content)`: structural pre-split (page markers, headings, blank lines), then
  an LLM pass to merge/split into coherent topical segments and label each.
- Write segments to `note_chunks` (content, chunk_index, topic, token_count, embedding).
- Embed each chunk; keep the existing whole-note embedding for search.

### `src/workflows/synthesize-topics.ts`
- Replace `clusterNotes()` (whole-note) with `clusterChunks()` over chunk vectors.
- Derive note membership as the **union** of the clusters its chunks fall into; dedup so a
  note links once per topic; `note_count` = **distinct** parent notes.
- **Re-tune `CLUSTER_SIMILARITY_THRESHOLD`** on the chunk-similarity distribution (the old
  whole-note value will not transfer). Keep the greedy algorithm — no k-means/HDBSCAN
  dependency (YAGNI).
- Enforce a **min-cluster-size**: clusters below it become `is_proto = 1` (hidden from the
  app) rather than littering the browse view.
- Cluster-naming prompt forbids source/format words (no "e-ink", "kindle", "page", etc.).

### Schema
- **No changes** — `note_chunks`, `topic_note_links`, and `is_proto` already exist.

## Reprocess procedure (dev-first; never test on prod DB)

1. Snapshot prod → dev DB (the **same snapshot the remote-iPad design already needs** —
   sequence the two together).
2. On dev: **wipe** `note_chunks` (176 stale rows), `topic_clusters`, `topic_note_links`;
   run the new pipeline end-to-end; eyeball the resulting topic list as the app would show it.
3. Iterate θ and min-size until the browse view looks right.
4. Merge → deploy to prod (compiled `dist/`) → run the one-shot rebuild on prod → verify on
   the iPad.

## Risks / mitigations

- **Re-collapse into a broad theme** → Phase 0 spike gates the build.
- **Singleton explosion** (many one-note clusters) → min-size + `is_proto` guard; judge by
  the browse view, not cluster count.
- **Threshold drift** (old θ tuned on whole-note sims) → re-derive empirically from chunk sims.
- **LLM segmentation cost** → 293 notes × local Ollama in a background workflow; not
  time-critical.
- **Stale chunk reuse** → full wipe of `note_chunks` is mandatory, not optional.

## Testing

- TDD on pure functions: `debiasContent`, `segmentNote` boundary logic, membership
  union/dedup, min-size → proto.
- `synthesis-reviewer` subagent reviews `synthesize-topics` changes (workflow + schema
  contract).
- Full pipeline validated against the dev snapshot (step 2–3) before any prod run.

## Acceptance criteria

- [ ] Phase 0 spike shows distinct in-note topics separate at a usable θ (else: stop/rethink).
- [ ] On the dev snapshot, the 104-note e-ink bucket is replaced by content-themed topics.
- [ ] At least one brain-dump note appears under **multiple** topics (multi-membership works).
- [ ] No source/format words appear in cluster names.
- [ ] The app browse view is neither one mega-bucket nor a wall of singletons.
- [ ] After prod deploy + one-shot rebuild, the iPad Notes section reflects the above.

## ADHD check

Makes the knowledge base **visual and trustworthy** — topics reflect what notes are *about*,
not where they came from, so the browse view externalizes meaning instead of mirroring
capture mechanics. Multi-topic membership matches how brain dumps actually work (one page,
many threads), reducing the friction of "which single bucket does this belong in?". Passes.

## Scope check

Two workflow files changed (no schema migration), a gated spike, and a one-shot reprocess.
The spike de-risks the largest unknown up front. Under a week. Passes.

## User-facing change?

**Yes** — the iPad Notes browse experience changes (topic names, multi-topic membership).
Wrap-up: update/create the relevant entry under `docs/guides/features/` (clustering / notes
browse) and link it in `docs/USER-EXPERIENCE.md`.
