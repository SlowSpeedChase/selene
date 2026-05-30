# Idempotent Obsidian Re-Export Design

**Status:** In Progress (implementation complete on `feat/idempotent-obsidian-reexport`; merge held for operator review)
**Created:** 2026-05-30
**Updated:** 2026-05-30

---

## Problem

`export-obsidian.ts` exports each note exactly **once**. `exportNotes()` selects only
`WHERE rn.exported_to_obsidian = 0` (export-obsidian.ts:93), writes the file, then sets
`exported_to_obsidian = 1` (lines 172–175). After that the note's markdown is **never rewritten**.

Consequence: any change to a note's *rendered* output after first export never reaches the vault.
This bit us with **Knowledge Constellation Phase A** — the `parent:: [[cluster]]` edges are built
inside that per-note loop (lines 162–163), so they only land on notes exported *after* Phase A
shipped (2026-05-30). Production log evidence: exactly **one 40-note run** wrote edges, then every
subsequent run exported 0. The ~254 notes exported before Phase A have **no `parent::` edges and
never will** under the current code. In ExcaliBrain that renders as 8 cluster nodes with only ~40
notes connected; the rest of the corpus floats free.

Same root cause produces a second, latent staleness: re-clustering (the nightly `synthesize-topics`
run), essence backfill, or theme changes never propagate to already-exported note files.

(Related, already fixed manually this session: an orphaned `Topics/` folder from a retired export
scheme — current code doesn't own that path. Pruning of unowned folders is an optional add below.)

---

## Solution

Replace the write-once boolean gate with a **rendered-output content hash**. Each run renders every
eligible processed note's *full* markdown and writes the file only when its hash differs from the
stored hash (or no file/hash exists yet). The export becomes **idempotent and self-healing**: a
cluster-membership change, essence change, or theme change flips the hash → the file is rewritten;
an unchanged note is skipped cheaply (no write, no churn).

The first run after deploy finds no stored hash for any note → rewrites all → **backfills `parent::`
to the entire corpus** with no separate migration script.

This is the same churn-guard work already flagged for **PKM Track 3** (see INDEX caveat: "make the
content-hash churn-guard cover the full rendered output — body + frontmatter + Dataview fields — so
it can't freeze the `parent::` edges"). RC1 and Track 3's exporter upgrade should be built as **one
piece of work**, not two.

---

## Design

### The hash must cover the FULL rendered output

This is the one correctness constraint that, if gotten wrong, silently re-creates the bug:

> Hash the **entire rendered markdown string** — frontmatter (`theme`, `concepts`), the `parent::`
> Dataview block, the body blockquote, and the essence — **not just the note body**.

If the hash covers only the body, a note whose body is unchanged but whose cluster membership
changed will be seen as "unchanged" and skipped — re-freezing the exact `parent::` edges this design
exists to fix.

### Data model

Add one column (via the existing harmless `ALTER TABLE ... ADD COLUMN` try/catch pattern already in
export-obsidian.ts:11–16, so no separate migration):

- `raw_notes.obsidian_export_hash TEXT` — SHA-256 (or the existing content-hash helper) of the last
  rendered markdown written for that note. NULL = never exported / needs (re)write.

Keep `exported_to_obsidian` / `exported_at` for now (other code/queries read them; `generateMocs`
filters on `exported_to_obsidian = 1`). Set `exported_to_obsidian = 1` on first successful write as
today; the **hash** becomes the authoritative "is the file current?" signal.

### Export loop changes (`exportNotes`)

1. Query **all** processed, non-test notes (drop the `exported_to_obsidian = 0` filter; keep
   `status = 'processed'` and `testRunFilter`). Load `noteClusters` once as today.
2. For each note: render the full markdown (unchanged rendering logic), compute its hash.
3. Compare to `obsidian_export_hash`. If equal → **skip** (no write). If different/NULL → write the
   file, update `obsidian_export_hash`, set `exported_to_obsidian = 1`, `exported_at`.
4. Replace the blanket `LIMIT 50` with a **per-run write cap** (e.g. 200) applied only to the
   *changed* set, so the one-time backfill (~294 writes) drains in ≤2 runs without a single run
   hanging. Steady-state runs write ~0.

`hasNewNotes` (drives MOC regen) becomes "any note (re)written this run" (`writtenCount > 0`).

### RC2 — MOC staleness (in scope, cost-aware)

MOCs (`Maps/<category>.md`) regenerate only when `hasNewNotes` and call Ollama per category
(`generate(prompt)` per non-empty category — up to 8 LLM calls). With the change above, the
backfill run will set `hasNewNotes = true` and regenerate all 8 once — desired. Steady state: only
regenerate when a note actually changed, which is correct and bounds LLM cost. No further change
needed, but document that taxonomy-only changes (re-cluster with no note edits) still flip per-note
hashes via the `parent::` block, so MOCs will refresh on the next run.

### Optional: prune unowned folders

Add a small step that removes vault subfolders the exporter no longer writes (e.g. a stale `Topics/`).
Out of scope for the core fix; list as a follow-up so future scheme changes self-clean.

### Known follow-up: note filename collisions (deferred)

`noteFilename` is `YYYY-MM-DD-<slug>.md`. Two notes with the same date and slugged title map to the
same path; the second overwrites the first. This is **pre-existing** (the old write-once exporter
derived filenames identically) and not introduced by this change — but the idempotent model masks it
harder: both notes persist matching hashes, so neither self-corrects. Fixing it means disambiguating
the filename (e.g. appending the note id), which **re-paths the entire vault on deploy** (every note
rewritten to a new filename, old files orphaned) and needs an orphan-cleanup story — a separate,
breaking migration. Deferred deliberately; do not bundle into this bugfix. (Surfaced in code review,
2026-05-30.)

---

## Implementation Notes

**Affected files:**
- `src/workflows/export-obsidian.ts` — column ALTER, query, per-note hash compare, write cap, `hasNewNotes`.
- `src/lib/constellation.ts` — no change (readers already correct).
- A hash helper — reuse existing content-hash util if one exists (ingest computes `content_hash`),
  else `crypto.createHash('sha256')`.
- Tests: extend `export-obsidian` tests — (a) unchanged note → not rewritten, (b) cluster-membership
  change → rewritten with new `parent::`, (c) first run with NULL hash → all rewritten.

**Dependencies / coupling:**
- **PKM Track 3** (`2026-04-12-pkm-browse-layer-design.md`) — same exporter edit; build together.
- **Knowledge Constellation Phase A/B** (`2026-05-29-knowledge-constellation-design.md`) — this is
  what makes Phase A's edges reach the full corpus; unblocks the operator ExcaliBrain visual check.

**Rollout:** merge → prod deploy-watcher builds & ships → first hourly export run backfills (≤2 runs
to drain ~294 notes) → iCloud syncs `parent::`-bearing note files to iPad. No manual flag reset needed.

**Risk:** idempotent rewrite clobbers any hand-edits to exported note files. These are generated
artifacts (blockquoted source + essence + links); treat as non-editable. Note in the user guide.

---

## Ready for Implementation Checklist

- [x] **Acceptance criteria defined** - see below
- [x] **ADHD check passed** - see below
- [x] **Scope check** - ~half-day; well under 1 week
- [x] **No blockers** - root cause confirmed from code + prod logs this session

### Acceptance Criteria

- [ ] After deploy + full drain, every processed non-test note file in `Notes/` carries a
      `parent:: [[cluster]]` line for each cluster it belongs to (multi-membership).
- [ ] Re-running `synthesize-topics` so a note's cluster membership changes causes **only that
      note's** file to be rewritten on the next export, with updated `parent::`.
- [ ] A note with no changes is **not** rewritten (hash skip; file mtime unchanged across two runs).
- [ ] The hash covers frontmatter + `parent::` + body + essence (regression test proves a
      cluster-only change triggers a rewrite).
- [ ] Operator: ExcaliBrain shows the bulk of the corpus connected to cluster nodes.

### ADHD Design Check

- [x] **Reduces friction?** Vault self-heals; no manual re-export or flag-reset ritual.
- [x] **Visible?** The constellation actually shows note↔cluster connections instead of orphans.
- [x] **Externalizes cognition?** Export state tracked by hash in the DB, not in the user's head.

---

## Links

- **Branch:** (added when implementation starts)
- **Root-cause session:** 2026-05-30 (code reading + prod-log evidence in conversation)
- **Couples with:** `2026-04-12-pkm-browse-layer-design.md` (Track 3), `2026-05-29-knowledge-constellation-design.md` (Phase A)
