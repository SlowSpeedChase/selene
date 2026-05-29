# Content-Based, Multi-Topic Clustering

**Date:** 2026-05-29
**Status:** Done — built + validated on a prod copy (branch `feat/content-multitopic-clustering`)
**Topic:** clustering, processing-pipeline, categories, ipad-browse, reprocessing

---

## Problem

In the SeleneMarkup iPad app, the Notes section shows **"E-Ink Empowerment: Personal
Growth & Relations"** as a giant category with **104 notes — all 104 are `eink`**. Every
other cluster is small (≤11) and almost entirely `drafts`. The owner does not care *how*
or *where* a note was captured (source is fine to keep as metadata); they care about the
**content**, and a single brain-dump page should appear under **every** topic it touches.

Two failures in the embedding clusterer produce the mega-bucket:

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

## What we learned (the pivot)

The original plan was to fix this by clustering at the **chunk** level (segment each note,
embed each chunk, cluster chunks, link a note to every topic its chunks hit). A Phase 0
spike was built to gate that approach. **The spike failed the gate** — see "Spike RESULTS"
below. The decisive finding: embedding clustering is simply the wrong tool for this
content, because the e-ink notes are **homogeneous daily journaling** with no clean latent
topic taxonomy to discover (the LLM produced 102 distinct `primary_theme` strings for 110
notes — near-unique paraphrases of the same few domains).

But a **controlled taxonomy already exists and is already applied**: every note is
classified by `process-llm.ts` into the 8-value `CATEGORIES` list (`processed_notes.category`
+ `cross_ref_categories`). Grouping by those categories satisfies all three of the owner's
goals **directly**: content-based (category = what the note is *about*), multi-membership
(`cross_ref_categories` is a many-to-many list), and theme-named (names come from a fixed
list, so a source-named bucket is impossible). The Obsidian export **already** organizes the
library this exact way (`export-obsidian.ts` + `MOC_PROMPT`); only the iPad cluster view was
out of step.

## Approved design — category-derived clusters

Rewrite the cluster-build so `topic_clusters` / `topic_note_links` are derived from the
controlled categories instead of from whole-note embeddings. **No schema migration** — the
tables and columns already exist; we change what populates them.

- **One `topic_clusters` row per category** (8 total). Stable per-category `slug`
  (slugified category name); `name` = the category itself. Because names come from a fixed
  list, **no LLM ever names a cluster** — "E-Ink Empowerment" cannot recur.
- **Membership = the union of `category` + `cross_ref_categories`.** A note links (via
  `topic_note_links`) to its primary category **and** every cross-referenced category →
  genuine multi-topic membership.
- **`note_count` = distinct member notes.** All non-empty categories stay visible — a fixed
  8-category taxonomy should not hide "Politics & Society" just because it has 2 notes, so
  the `is_proto` / `MIN_CLUSTER_SIZE` hiding is retired for this model.
- **`synthesis_text` per category** = the existing `generateSynthesis()` over the category's
  member essences. This is where "I care about the **concepts** I spoke about" is surfaced —
  concepts roll up into a per-category synthesis, the analysis surface the app already reads.
- **Date is a reference, not the axis.** Within a category, member notes carry `created_at`
  for ordering/reference; the **category** is the organizing principle, the date is "when I
  was discussing it."
- **`capture_type` stays as metadata**, never drives a cluster.

```
ingest ─▶ process-llm.ts (unchanged)          ─▶ synthesize-topics.ts (rewritten)
          • classify into category +              • buildCategoryClusters():
            cross_ref_categories (already)           for each of 8 CATEGORIES:
          • embed() stays (feeds LanceDB +           members = notes WHERE category=C
            note_connections, not just clusters)             OR cross_ref_categories ∋ C
                                                      • upsert topic_clusters (stable slug,
backfill ─▶ classify-categories (one-shot)              name=C, synthesis over members)
          • fills category on the ~148 older         • link each member → its category rows
            notes (mostly drafts) that predate       • note_count = DISTINCT members
            the category feature                     • all non-empty categories visible
```

### Decision: unify everything on categories (chosen)

E-ink is **97% classified** (107/110 have a category, 58 have cross-refs). Drafts are only
**22% classified** (40/185) — they predate the category feature. The owner chose to
**unify all notes on categories** rather than keep the (cleanly-clustering) draft embedding
clusters as a second mechanism. This requires a one-time **classification backfill** of the
~148 unclassified notes (mostly drafts) before the rebuild, so no draft vanishes from the
browse view. One mechanism for everything; the "full clean rebuild" the owner approved,
with categories — not chunks — as the unit.

## Components / changes

### New: one-shot classification backfill (`scripts/backfill-categories.ts`)
- Select `processed_notes` rows where `category IS NULL` (≈148: mostly older drafts).
- Re-run **`EXTRACT_PROMPT`** (reuse `src/lib/prompts.ts`) on each note's title+content;
  parse the JSON; update **only** `category` + `cross_ref_categories`. Leave concepts/
  essence/sentiment untouched (already populated).
- Idempotent (re-running skips rows that now have a category); local Ollama, background,
  not time-critical (~148 calls ≈ minutes).

### `src/workflows/synthesize-topics.ts` (rewrite the build, shrink the file)
- **Remove** `clusterNotes()` (embedding greedy), `loadAllEmbeddings()`,
  `backfillEmbeddings()`, and `generateClusterName()` — all now dead.
- **Add** `buildCategoryClusters()`: for each category in `CATEGORIES`, gather members
  (`category = C OR cross_ref_categories` contains `C`), upsert the `topic_clusters` row
  with a stable slug, link members in `topic_note_links`, set `note_count` = distinct
  members, `is_proto = 0`.
- **Keep** `generateSynthesis()` (called per category) and the delta-guard /
  evolution-detection / weekly-rollup machinery — they operate on the cluster regardless of
  how membership was derived.
- **Full clean rebuild**: wipe `topic_clusters` + `topic_note_links` before the first
  category build (clean transition from embedding clusters).

### `src/workflows/process-llm.ts` — **unchanged**
- Leave the per-note `embed(note.content)` block alone. Although the `note_embeddings`
  **table** becomes write-only after clustering is removed (nothing reads it anymore), the
  same `embed()` result also feeds **LanceDB** (`indexNote`) and **connection detection**
  (`searchSimilarNotes` → `note_connections`), both still live. Removing the embed would
  break those, so it stays. (`note_embeddings` is left as inert write-only state — no
  destructive migration; can be dropped later if desired.)

### Schema
- **No changes.** `topic_clusters`, `topic_note_links`, `category`, `cross_ref_categories`
  all already exist.

## Validation / reprocess procedure (never write to the live prod DB)

1. **Work on a writable COPY of prod**, never the live file:
   `cp ~/selene-data/selene.db /tmp/selene-rebuild-test.db`. (The dev DB now holds fictional
   `dev-seed` fixtures, so it cannot validate real-content grouping — a prod copy is the
   only realistic surface, and a copy in `/tmp` never touches prod.)
2. On the copy: run the **classification backfill**, then **wipe** `topic_clusters` +
   `topic_note_links`, then run the **category build**.
3. Eyeball the resulting `topic_clusters` exactly as the app's `/api/clusters` query would
   render them (`WHERE is_proto = 0 ORDER BY note_count DESC`): 8 content-themed categories,
   sane `note_count`s, at least one note appearing under multiple categories.
4. Merge → deploy to prod (compiled `dist/`) → run the backfill + one-shot rebuild on prod
   → verify on the iPad.

## Out of scope / deferred

- **Embedding sub-clusters within a category** — the spike showed embedding clustering
  re-collapses/​fragments on this homogeneous content; the per-category `synthesis_text`
  already captures the through-lines (YAGNI).
- **OCR-boilerplate cleanup** (`**Page Number Indicator…**`, `[unclear]`, `--- Page N ---`)
  — pollutes essences/search system-wide, but does **not** affect category grouping
  (categories are already assigned). Tracked as a separate task.
- **A bespoke "analysis dashboard"** — the category browse view *is* the analysis surface.

## Risks / mitigations

- **Backfill misclassifies old drafts** → validate on the prod copy before prod; backfill is
  re-runnable, and a later quality re-pass can refine categories if the iPad view shows drift.
- **Large-category synthesis prompt** (Personal Growth could exceed ~30 members) → cap/sample
  member essences in `generateSynthesis` if the prompt grows too large (implementation note).
- **A note with no category after backfill** (LLM fails to classify) → assign a fallback
  bucket or leave unlinked; decide in the plan (prefer: retry, then a "Daily Systems"/"General"
  fallback so nothing silently vanishes — and **log** any drops, no silent truncation).
- **Stale embedding artifacts** → embedding-clustering code removed; `note_embeddings` left
  inert (no reader), not relied upon.

## Testing

- TDD on pure functions: category-membership union/dedup (primary + cross-refs → distinct
  cluster set), stable slug derivation, backfill JSON parse → `{category, cross_ref_categories}`.
- `synthesis-reviewer` subagent reviews `synthesize-topics` changes (workflow + DB contract).
- Full backfill + rebuild validated on the prod **copy** (steps 1–3) before any prod run.
- New test files must be added to `jest.config.js` `testMatch` (explicit allowlist).

## Acceptance criteria

- [x] After backfill, every note has a `category` — **138 reclassified**; 4 genuine LLM
      failures remain `NULL` and are **logged by ID** (not silently dropped), 11 `test_run`
      notes correctly excluded.
- [x] `topic_clusters` contains one row per non-empty category, named from the fixed list —
      **8 rows, 0 source/format-named clusters** (no "E-Ink Empowerment").
- [x] On the prod copy, the 104-note e-ink bucket is gone; notes are spread across the
      content categories.
- [x] At least one brain-dump note appears under **multiple** categories — **104 notes** in
      ≥2 categories.
- [x] Drafts and e-ink are grouped by the **same** mechanism (unified).
- [ ] After prod deploy + backfill + one-shot rebuild, the iPad Notes section reflects the
      above. *(Pending — see "Production rollout" in the plan; runs post-merge.)*

## Validation results (2026-05-29, prod copy `/tmp/selene-rebuild-test.db`)

Run with `SELENE_ENV=production SELENE_DB_PATH=/tmp/...` (verified the resolved path was the
copy, never live prod). Backfill: 138 updated / 4 failed. Rebuild (`SELENE_REBUILD_CLUSTERS=1`):

| Category | note_count |
|----------|-----------:|
| Relationships & Social | 120 |
| Projects & Tech | 82 |
| Personal Growth | 81 |
| Health & Body | 57 |
| Career & Work | 54 |
| Daily Systems | 31 |
| Creativity & Expression | 23 |
| Politics & Society | 23 |

Coverage: **282 / 286 distinct notes clustered**; the 4 uncovered all have `NULL` category
(backfill failures, identifiable). `uncovered_with_nonnull_category = 0` — every classified
note is in a cluster. Synthesis narratives are concept-aware, second-person, source-word-free
(spot-checked Health & Body). A real-data fix surfaced during validation: `process-llm.ts`
stores `category` **unvalidated**, so the DB held comma-joined values
("Personal Growth, Relationships & Social") and parentheticals — `normalizeToValidCategories`
now splits/strips these, recovering ~9 multi-topic notes as proper multi-membership.

## Known follow-ups (not blocking)

- **4 `NULL`-category notes** after backfill — re-run `scripts/backfill-categories.ts` or
  classify manually; they currently appear in no category cluster (logged).
- **Dead `is_proto = 1` path** in `src/lib/synthesis-digest.ts` ("Pattern forming" digest
  section) — proto-clusters are retired, so that section is permanently empty. Harmless;
  remove in a follow-up.
- **`process-llm.ts` writes `category` unvalidated** — root cause of the messy values; a
  future hardening could validate on write (out of scope here; read-side normalization covers it).

## ADHD check

Makes the knowledge base **visual and trustworthy** — topics reflect what notes are *about*,
not where they came from, so the browse view externalizes meaning instead of mirroring
capture mechanics. Multi-category membership matches how brain dumps actually work (one page,
many threads), reducing the friction of "which single bucket does this belong in?". A small,
fixed, predictable taxonomy (8 categories) is easier to hold than an ever-shifting list of
emergent cluster names. Passes.

## Scope check

One rewritten workflow (smaller than before), one one-shot backfill script, no schema
migration, and a copy-based validation pass. Net code is **negative** (an entire embedding
clustering mechanism is removed). Under a week. Passes.

## User-facing change?

**Yes** — the iPad Notes browse experience changes (category names, multi-category
membership, date demoted to reference). Wrap-up: create/update the relevant entry under
`docs/guides/features/` (notes browse / clustering) and link it in `docs/USER-EXPERIENCE.md`.

---

## Spike RESULTS (2026-05-29) — evidence the embedding approach was abandoned

Run against a read-only prod snapshot (`/tmp/spike-snapshot.db`; the dev DB had been
re-seeded with fictional fixtures by the parallel prod/dev work, so it could not be used).
Script: `scripts/spike-chunk-separation.ts` (throwaway — removed after the gate; findings below are the record).

- **Whole-note e-ink cohesion = 0.714** > current threshold 0.65 → confirms why all 104
  collapse today.
- **Chunk-level** loosens cohesion (within-note 0.563 ≈ cross-note 0.546) but does **not**
  separate clean topics. Clustering raw chunk text produced **grab-bags + OCR-boilerplate
  clusters** (a 31–61-note *"What Went Well today?"* daily-journal blob; clusters of pure
  OCR scaffolding). Aggressive OCR de-biasing is needed but not sufficient.
- **The content is genuinely homogeneous daily journaling.** The LLM gave **102 distinct
  `primary_theme` strings for 110 notes** — near-unique paraphrases all orbiting the same few
  domains. No hidden clean taxonomy emerges from free-form theming.
- **Decisive:** a **controlled taxonomy already exists** (`CATEGORIES`, 8 values) and every
  e-ink note is **already classified** into it (Personal Growth 32, Relationships & Social 19,
  Projects & Tech 19, Daily Systems 10, Career & Work 8, Health & Body 7, Politics & Society 2,
  plus multi-category notes). Drafts, by contrast, DID embedding-cluster cleanly — but are only
  22% classified, which is why unification needs the backfill.
- **Conclusion:** embedding-based clustering is the wrong tool for this homogeneous content;
  the controlled categories meet the goals for free. → Category-derived clusters (above).
