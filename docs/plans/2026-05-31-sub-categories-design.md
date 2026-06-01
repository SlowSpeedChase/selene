# Design: Sub-categories within the 8 main categories

**Date:** 2026-05-31
**Status:** Vision → **Ready** (Phase 1)
**Depends on:** Content-based multi-topic clustering (`synthesize-topics.ts`, `category-clusters.ts`), Knowledge Constellation (`constellation.ts`)
**Related:** [[2026-05-29-content-based-multitopic-clustering-design]], [[2026-05-29-knowledge-constellation-design]], [[2026-05-31-fact-store-design]] (durability model), agent-layer v1 ([[2026-05-23-agent-layer-design]])

---

## What & why

The note taxonomy today is **one flat level**: 8 controlled categories (`Personal Growth`, `Relationships & Social`, `Health & Body`, `Projects & Tech`, `Career & Work`, `Creativity & Expression`, `Politics & Society`, `Daily Systems`). Notes attach to one or more of them (multi-membership via `cross_ref_categories`). The categories are deliberately fixed and content-free — that flatness was a *deliberate* choice in the May clustering pivot, which killed LLM-named clusters because emergent names drifted into messy "source buckets."

**The problem:** the 8 categories are **too coarse**. `Health & Body` lumps running, sleep, and diet together; `Projects & Tech` lumps every project into one bucket. The user wants finer-grained *meaning* — a second level of distinction — without re-opening the drift that the flat model was built to prevent.

**This design adds a second taxonomy level (sub-categories) under the existing 8.** It does so in a way that preserves the no-drift guarantee: the firm taxonomy is human-controlled, and any machine-proposed ("emergent") sub-categories are quarantined as *soft* until they earn promotion.

### Named assumptions (decisions, not omissions)
- **The 8 parent categories stay fixed.** Sub-categories refine; they do not re-parent. "Too coarse" is in scope; "wrong parents" is not.
- **Multi-membership is preserved at the sub-level.** A note can attach to several sub-categories, including ones under *different* parent categories (e.g. `Health & Body / Running` **and** `Projects & Tech / Side Projects`).

---

## Approach (the destination, and how we get there)

The committed destination is **Approach C: seeded per-note classification + an LLM emergent-tail pass owned by a curator agent.** It is built in two honestly-sized phases.

Two rejected alternatives, recorded so they are not re-litigated:
- **Per-note seeded only** — simple and deterministic, but never discovers distinctions you did not predefine. (This *is* Phase 1 — kept as the first cut, not the final shape.)
- **Embedding sub-clustering within each category** — **ruled out.** This is precisely the embedding-clustering that was spiked and *killed* on the eink mega-bucket: homogeneous notes re-collapse into one blob. C avoids this by running the LLM only over the residual *unmatched tail*, never re-partitioning a whole category.

### Why C survives where embedding-clustering dies
Embedding-clustering tries to *partition a homogeneous blob* and fails. C only ever runs the LLM over the **leftovers** a category's seed list did not catch — it looks for pockets in the residual, a different and tractable problem. C also keeps the ingest path deterministic and cheap (seeded classification is a closed-set choice) and quarantines all nondeterminism inside a scheduled, reviewable, rollback-able agent.

---

## Durability resolution (why this is safe on `feat/fact-store`)

This work lands while the **fact store** split is in flight, whose premise is *separate by durability*: `facts.db` is precious (human decisions, survives a `rebuild`); `selene.db` is disposable (LLM-derived, regenerated). A naïve design that stored a curated taxonomy in `selene.db` would have a future `rebuild` **silently wipe the sub-categories the user worked to firm up**.

Resolution:
- **Phase 1 needs zero `facts.db` schema.** The seed taxonomy is a **git-tracked config file** (`config/sub-taxonomy.ts` — a map of each of the 8 categories → its sub-category list). Git *is* the precious layer: a `rebuild` of `selene.db` cannot touch a file in the repo. The user curates it by asking Claude to edit one file.
- **Sub-cluster rows** (`topic_clusters`) and **per-note assignments** (`processed_notes`) live in `selene.db` (disposable) — correctly, because on `rebuild` they regenerate deterministically from (git seed config) + (re-derived classification). Nothing human is lost.
- **`facts.db` enters only in Phase 2**, when promotion/firmness becomes *runtime* human curation (not a code edit). A precious-side `category_taxonomy` table then holds the firmed taxonomy + approvals, re-applied after `rebuild` keyed on sub-slug — exactly as `category_overrides` is planned to.

---

## Phase 1 — Seeded sub-categories (shippable, deterministic, zero drift risk)

### Data model
No migration to `topic_clusters` — the needed columns already exist.

- **Sub-cluster** = a `topic_clusters` row with `parent_id` set to its category cluster's id, and a **namespaced slug**, e.g. `health-body/running`.
- **`processed_notes` gains a sub-category assignment** stored as a JSON map keyed by parent category, e.g. `{ "Health & Body": "Running", "Projects & Tech": "Side Projects" }`. The per-category map (vs. a single field) is what preserves cross-parent multi-membership.
- **`topic_note_links`** gains note→sub-cluster rows *in addition to* the existing note→category-cluster rows. Category clusters keep full membership (so "show me all of Health" is unchanged); sub-clusters hold the subset. No backward-compat break.

### Pipeline flow
1. **`process-llm.ts`** — after picking category + cross-refs, a follow-up **closed-set** choice: for each category the note is in, which sub-category from that category's seed list, or `none`? Closed-set = deterministic, no invented names in Phase 1.
2. **`category-clusters.ts`** — `groupNotesByCategory` extended to also yield (category → sub-category → noteIds), reusing the existing `validCategoriesFor` iteration.
3. **`synthesize-topics.ts`** — for each non-empty sub-group, upsert a sub-cluster row (`parent_id` = the category cluster) + note links.
   - **Highest-risk edit:** the orphan-cleanup guard (`synthesize-topics.ts:250-262`) currently deletes any cluster whose slug is not one of the 8 category slugs. It **must** be taught that a slug like `health-body/running` is legitimate when its parent slug is one of the 8 — otherwise it deletes every sub-cluster on each run.
4. **`constellation.ts` / `export-obsidian.ts`** — already future-proofed: the `LEFT JOIN topic_clusters p ON p.id = c.parent_id` emits `parent::` automatically once sub-clusters have `parent_id`. Mostly it just starts working.

### Out of scope for Phase 1
- The 8 parent categories stay fixed; no re-parenting of existing notes.
- No emergent/proposed sub-categories, no firmness, no curator agent.
- No PKM-dashboard sub-category UI.

---

## Phase 2 — Emergent tail + curator agent + firmness (sketch, not built)

Phase 1 deliberately produces Phase 2's raw material: notes assigned `none` *are* the "unmatched tail."

- **Emergent tail discovery.** A scheduled pass takes each category's `none`-assigned notes and asks the LLM "what recurring sub-themes here aren't covered by the seed list?", proposing **soft** sub-categories. It runs over the residual only — never re-partitioning a whole category.
- **Firmness gradient.** Each sub-category has a state: `soft` (emergent, few notes) → `firm` (≥ N notes + survived curation). Seeded sub-categories from the git config are `firm` by declaration.
- **What firmness gates** (the chosen behaviours):
  - *Constellation depth* — soft sub-clusters do **not** emit `parent::`/child edges; they stay out of the fly-through until firm. The visual map only deepens for proven distinctions.
  - *Agent's freedom to act* — the curator agent may merge/rename/prune **soft** sub-categories autonomously; **firm** ones are protected and changes require user approval.
- **Curator agent.** A new agent in the existing agent-layer v1 (`BaseAgent` + `ActionExecutor` + dashboard). Its editing loop: merge near-duplicates, promote soft→firm at threshold, prune dead soft ones, and surface protected-change proposals for approval.
- **`facts.db` storage.** A precious-side `category_taxonomy` table (parent slug, sub-slug, name, status) holds firmed taxonomy + approvals; soft proposals stay in disposable `selene.db`. On `rebuild`, firm taxonomy re-applies keyed on sub-slug.

---

## Testing

- **TDD throughout** (matches the repo's pattern; see the fact-store tests). Pure-function units first: seed-config lookup, extended `groupNotesByCategory` (note in 2 categories → a sub-cat under each), sub-slug namespacing.
- **Mandatory guard regression test:** prove orphan-cleanup *keeps* `health-body/running` (parent slug valid) but still deletes a true orphan. This protects against the silent-wipe landmine.
- **Constellation/export:** DB-backed test that a sub-cluster with `parent_id` emits a `parent::` edge (extends `constellation.db.test.ts`).
- **`rebuild` safety (when fact-store Phase 2 lands):** a test that the git seed config + re-derivation reconstructs Phase 1 sub-categories with no human data loss.

---

## User-facing surfaces & wrap-up

- **Obsidian constellation** gains a navigable level (cluster → sub-cluster → note).
- **Guides to update at wrap-up:** `docs/guides/features/knowledge-constellation.md` and `docs/guides/features/synthesis-layer.md` (verify claims against the real code, per the wrap-up rule).
- No new user surface in Phase 1.

---

## Acceptance criteria (Phase 1)

- [ ] A git-tracked seed sub-taxonomy config exists, mapping each of the 8 categories → its sub-categories.
- [ ] `process-llm.ts` assigns a closed-set sub-category (or `none`) per category a note belongs to, stored as a per-category JSON map on `processed_notes`.
- [ ] `synthesize-topics.ts` creates sub-cluster rows with `parent_id` set + note→sub-cluster links, preserving category-level membership.
- [ ] Orphan-cleanup keeps valid sub-slugs and still deletes true orphans (regression-tested).
- [ ] The Obsidian/constellation export emits `parent::` edges for sub-clusters with no new export code beyond what the existing join provides.
- [ ] A `rebuild` regenerates Phase 1 sub-categories deterministically from git config + re-derivation (no human data lost).
- [ ] ADHD check: reduces friction (finer browsing without manual filing), visual (deeper constellation), externalizes cognition (the structure is in the map, not the head).
- [ ] Scope check: Phase 1 is < 1 week of focused work.
