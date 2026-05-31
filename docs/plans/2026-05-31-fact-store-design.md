# Fact Store + Regenerable Derived DB Design

**Status:** Ready (Phase 1)
**Created:** 2026-05-31
**Updated:** 2026-05-31

---

## Problem

Selene's `raw_notes` table is *supposed* to be the source of truth, but it is contaminated: its genuinely-immutable capture columns (`title`, `content`, `content_hash`, `created_at`, `source_uuid`, …) sit in the same row as **mutable pipeline bookkeeping** (`status`, `processed_at`, `exported_at`, `exported_to_obsidian`, `obsidian_export_hash`, `inbox_status`, `status_folio`, `tasks_extracted*`, …). Two workflows even write derived bookkeeping back onto the fact row (`export-obsidian` → export hash; `folio-feedback` → `status_folio`).

Consequences:
- A bad pipeline run or LLM change can scribble on the source of truth.
- There is no clean way to **throw away everything derived and rebuild from facts** — to reprocess after a prompt/model upgrade, recover from corruption, or experiment safely.
- "What was captured" and "where this note is in the pipeline" are entangled.

The user wants an **ingest-only fact store** plus a **derived database that is a pure function of it**, so that if anything goes wrong the derived layer can be regenerated from the facts. Confirmed drivers (all four selected): reprocess-on-upgrade, corruption/disaster recovery, safe experimentation, and bad-pipeline-run recovery.

---

## Solution

Split the single `selene.db` into **two files, three logical layers**:

```
facts.db   ← PRECIOUS. Backed up. Never auto-overwritten.
  captured_notes      append-only; the fact columns of today's raw_notes
  category_overrides  human category/type corrections   [Phase 3 — net-new]
  review_state        migrated from pkm_review_state (human review flags)

selene.db  ← DISPOSABLE. Rebuildable from facts.db at any time.
  processed_notes, note_embeddings, note_connections,
  topic_clusters, topic_note_links, synthesis_meta, agent_reports,
  + pipeline bookkeeping (processing state, export hashes, status_folio)
```

`selene.db` **ATTACHes** `facts.db` and reads facts through it — not a physical copy (no duplication, no drift). The derived DB is *built from* the facts; the facts live in exactly one place.

**Organizing principle:** the fact/derived line == the **ingest chokepoint**. Everything `ingest.ts` and its funnels (eink / voice / worksheet / annotation) produce is a *fact*; everything downstream is *derived*.

**Separate by durability, not by source.** Captured notes and human edits share one fate — precious, backed up, never auto-overwritten — so they live together in `facts.db`. LLM output is disposable, so it lives in `selene.db`. The file boundary *is* the provenance flag (it can't be set wrong the way a `source=` column can).

---

## Design

### Fact boundary (what goes in `captured_notes`)

Written at capture time by `db.ts:114-129`, therefore facts:
`title`, `content`, `content_hash`, `tags`, `word_count`, `character_count`, `created_at`, `imported_at`, `capture_type`, `source_uuid`, `source_note_id`, `calendar_event` (snapshotted from the user's calendar), `test_run`. The integer `id` is the join key.

**Not facts** (pipeline bookkeeping, move to `selene.db`): `status`, `processed_at`, `exported_at`, `exported_to_obsidian`, `obsidian_export_hash`, `inbox_status`, `suggested_type`, `suggested_project_id`, `tasks_extracted`, `tasks_extracted_at`, `status_apple`, `processed_at_apple`, `status_folio` (added by `folio-feedback`).

### Data flow

- **Capture** — `ingest.ts` (+ eink/voice/worksheet/annotation funnels, and `routes/notes.ts` annotations) writes only to `facts.db → captured_notes`. One chokepoint.
- **Process** — `process-llm`, `distill-essences`, `synthesize-topics` read facts via ATTACH and write only `selene.db`.
- **Export/feedback** — `export-obsidian` (export hash) and `folio-feedback` (`status_folio`) redirect their writes off the fact row into `selene.db` tables. (Bookkeeping table TBD in plan — likely a per-note `processing_state` and an `export_state` keyed on note id.)
- **Read/UI/digest** — read `selene.db` with `facts.db` attached, joining derived rows to their facts.

### "Pending" becomes derivation-absence

The lone pending-detection query — `db.ts:77` `SELECT * FROM raw_notes WHERE status = 'pending' ...` — becomes *"facts in `captured_notes` with no `processed_notes` row."* **Existence of derived output IS the processed flag.** Consequence: wiping `selene.db` makes every fact pending again, so **rebuild-correctness is automatic** — no separate "reset status" step.

### Rebuild & merge (the regenerate path)

```
rebuild =
  1. wipe selene.db (drop/recreate derived tables)
  2. re-run the pipeline from facts.db (process-llm → distill → synthesize → export)
  3. re-apply the human layer LAST (overrides win — last-writer)
```

**Merge keys on survivors only** — note identity (`source_uuid`, or `id` while facts.db is the stable home) and category **slug**. Never a regenerated surrogate id. Overrides are **absolute statements** ("note X is category Health"), never relative to a prior derivation.

Why this is safe (verified against the code):
- `synthesize-topics.ts:111` does `DELETE FROM topic_clusters` + re-INSERT each run, so cluster surrogate ids churn — **but** clusters are keyed by `slug` (`slugForCategory(cat)`), deterministic from the 8 controlled categories. Slug is stable across rebuilds.
- Today's only human-state, `pkm_review_state`, stores `entity_type='note'` keyed on `CAST(raw_notes.id AS TEXT)` (`pkm-db.ts:53`) — never a cluster id. So no dangling-id problem exists today. The merge-key rule prevents one if category/concept review-state is added later (it must key on slug).

> ⚠️ **Regenerate RE-DERIVES, it does not RESTORE.** Because the LLM is non-deterministic (temperature > 0), a rebuilt category/cluster/essence may differ from what is there now. This is exactly the goal for *reprocess-on-upgrade*. For *disaster recovery* it means: **your notes and your corrections come back identical; the AI's interpretation is recomputed fresh.** Overrides survive precisely because they are absolute and applied on top.

### Concurrency & integrity (SQLite specifics)

- Both files use **WAL + `busy_timeout`** (the recent SQLITE_BUSY incident came from a missing `busy_timeout` on the single DB; two files + ATTACH multiply the locking story — the server writes `facts.db` while the pipeline reads it attached and writes `selene.db`).
- **Cross-database foreign keys are NOT enforced** across ATTACH. `processed_notes.raw_note_id → captured_notes.id` integrity becomes **app-level** (the design must not assume FK enforcement it won't have).

### Dormant legacy tables

~10 tables (`threads`, `conversations`, `chat_sessions`, `note_associations`, `note_relationships`, `detected_patterns`, `sentiment_history`, `processed_notes_apple`, `device_tokens`) are written by no live workflow (verified via `@map writes` annotations). The new `selene.db` simply does not recreate them — they are neither fact nor live-derived.

---

## Implementation Notes

### Phasing

- **Phase 1 — the split (foundational, < 1 week, this doc's "Ready" scope):**
  create `facts.db`; ATTACH plumbing in `db.ts` (WAL + `busy_timeout` on both files; app-level `raw_note_id` integrity); migrate `captured_notes` + `review_state` losslessly from current `selene.db`; repoint the one pending query (`db.ts:77`); redirect the two contaminating writers (`export-obsidian` hash, `folio-feedback` `status_folio`). **Behavior identical** to today.
- **Phase 2 — the `rebuild` command + full-regenerate validation.** The migration cutover *is* the first real rebuild test (rebuild prod's ~294 notes from facts, diff against the pre-migration derived state for sanity). Wire the backup target here.
- **Phase 3 — the human-override *feature*.** `category_overrides` is net-new (zero override data today, no correction UI/route exists). A real correction path + merge-on-rebuild. Feature, not refactor — correctly deferred.

### Affected files (Phase 1)

- `src/lib/config.ts` — add `factsDbPath` alongside `dbPath` (dev/prod/test variants), mirroring the existing env split.
- `src/lib/db.ts` — open `selene.db`, `ATTACH facts.db`; WAL + `busy_timeout` on both; rewrite the pending query (`:77`) to derivation-absence; repoint the capture INSERT (`:114`) to `captured_notes`.
- `src/workflows/export-obsidian.ts`, `src/workflows/folio-feedback.ts` — redirect fact-row bookkeeping writes to `selene.db`.
- `scripts/` — a migration script (extract facts → `facts.db`; copy `pkm_review_state` → `review_state`) and (Phase 2) a `rebuild` command.
- `scripts/selene-inspect.ts` — teach it the two-file layout.

### Backup

`facts.db` lives under `~/selene-data` (prod) / `~/selene-data-dev` (dev). **Time Machine already covers this Mac**, so facts inherit hourly local snapshots — the disaster-recovery baseline exists with zero new work. The architecture additionally makes an explicit off-box copy cheap (small, append-only) if wanted later; not required for "Ready."

### Out of scope / open

- **Does NOT fix the dev→prod vault-path bug** found during the bucket-1 verification (`export-obsidian` writes `config.vaultPath`, which resolves to the prod iCloud vault in dev because `.env`'s `SELENE_VAULT_PATH` overrides the intended dev path). Orthogonal; still open; the "intended for the A5 eyeball vs oversight" question is still unanswered. This design must not absorb or hide it. The new fact/derived isolation *reduces the blast radius* (a stray dev export is additive, recoverable) but does not repoint the path.
- `note_connections` is written by `process-llm` but is effectively empty (Constellation Phase B is gated on a separate diagnostic spike). Derived either way.
- Note-filename collisions in the Obsidian exporter (deferred follow-up from the idempotent-reexport work) are unaffected.

### Composes with recent work

- **Idempotent Obsidian re-export** (rendered-output content hash) makes export safe to re-run during any rebuild — it self-heals rather than duplicating.
- **Prod/Dev split** — both envs get the two-file layout (`facts.db`/`selene.db`, `facts-dev.db`/`selene-dev.db`), reinforcing the boundary the hardening work established.

---

## Ready for Implementation Checklist

Phase 1 (the split):

- [x] **Acceptance criteria defined** - see below
- [x] **ADHD check passed** - see below
- [x] **Scope check** - Phase 1 ships in < 1 week (one DB-layer refactor + a lossless migration; no new UI)
- [x] **No blockers** - fact boundary verified; merge-key safety verified against the code

### Acceptance Criteria (Phase 1)

- [ ] `facts.db` exists with `captured_notes` holding every current note's fact columns, lossless (row count + content_hash match the pre-migration `raw_notes`).
- [ ] `review_state` migrated 1:1 from `pkm_review_state`.
- [ ] All live workflows read facts via ATTACH and write only `selene.db`; **no workflow writes the fact row** (grep proves `export-obsidian`/`folio-feedback` no longer UPDATE `captured_notes`).
- [ ] Pending detection works via derivation-absence: a fresh capture is picked up and processed with `status` gone from the fact row.
- [ ] Both DBs open with WAL + `busy_timeout`; a concurrent server-write + pipeline-read does not raise SQLITE_BUSY in a stress test.
- [ ] End-to-end on the dev showcase corpus: capture → process → synthesize → export produces the same derived results as before the split (no regression).
- [ ] `selene-inspect` reports both files.

### Acceptance Criteria (Phase 2, sketched)

- [ ] A `rebuild` command wipes `selene.db`, re-derives from `facts.db`, and re-applies `review_state`; afterward every fact has a `processed_notes` row and review flags are intact.
- [ ] Rebuilding prod's corpus from facts completes with 0 errors and category/cluster counts within expected bounds (re-derive, not byte-identical).

### Acceptance Criteria (Phase 3, sketched)

- [ ] A correction path lets the user override a note's category/type; the override persists in `facts.db` and **wins** after a full rebuild.

### ADHD Design Check

- [x] **Reduces friction?** Removes the fear tax on experimentation/upgrades — "I can always rebuild from facts" means changes stop being scary, so they actually happen.
- [x] **Visible?** Two clearly-named files (precious vs disposable) make the system's structure legible; `selene-inspect` surfaces both.
- [x] **Externalizes cognition?** The system, not the user, guarantees recoverability — the user never has to remember "did that run corrupt my notes?"

---

## Links

- **Branch:** `feat/fact-store`
- **Plan:** [2026-05-31-fact-store-plan.md](2026-05-31-fact-store-plan.md) (Phase 1 — the split)
- **Related:** `2026-05-30-idempotent-obsidian-reexport-design.md` (idempotent export composes with rebuild), `2026-05-28-prod-dev-split-design.md` (two-env layout), `2026-05-29-dev-prod-boundary-hardening-design.md` (boundary the vault-path bug belongs to)
