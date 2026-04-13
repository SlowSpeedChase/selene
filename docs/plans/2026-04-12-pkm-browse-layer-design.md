# Selene PKM Browse Layer

**Status:** Vision
**Date:** 2026-04-12
**Scope:** ~1 week focused work across 4 small tracks
**Target surface:** iPad (LAN web) + Obsidian Mobile (secondary)

---

## Context

Selene already does the *Collect* and *Distill* stages of CODE (Forte, 2017). Drafts captures; `process-llm.ts` extracts concepts, categories, sentiment/energy signals; `distill-essences.ts` produces a one-line "essence" per note that is, functionally, what Tiago Forte calls Progressive Summarization output. What's missing is the **Express** layer — a place the user actually opens to *browse* their own thinking.

Today's browse surfaces are both broken for ADHD consumption:

1. **Obsidian vault.** The exporter already writes frontmatter, per-category MOCs, and a code-generated `Dashboard.md`. But Obsidian Mobile's plugin-load friction on iPad means the vault is effectively closed. Worse, the exporter's MOC generation depends on `processed_notes.category` — and 150 of 151 production notes have `category = NULL`, so the MOC phase is silently a no-op for existing data.
2. **SQLite directly.** Not a browse surface.

The lean answer: ship a **LAN web dashboard** served from the existing Fastify server on port 5678 — instant to open, no plugin load, zero new processes — and make it the primary iPad surface. In parallel, do the minimum exporter upgrades that keep Obsidian useful as a secondary offline-capable view (no duplication of web dashboard work).

### PKM principles applied

- **Zettelkasten** (Luhmann) — atomic units already extracted as `processed_notes` rows.
- **Progressive Summarization** (Forte) — `essence` column already exists; the browse layer makes essences *discoverable* across surfaces, which is the whole point.
- **Maps of Content / LYT** (Milo) — use existing 8 PARA-esque `CATEGORIES` constant (Personal Growth, Relationships & Social, Health & Body, Projects & Tech, Career & Work, Creativity & Expression, Politics & Society, Daily Systems) as the top-level browse axis. MOCs already exist in the vault generator; we just need them populated.
- **Evergreen notes** (Matuschak) — `fidelity_tier` column already grades distillation quality. Frontmatter-driven refinement tracking becomes possible once we emit it.
- **Spaced resurfacing** (fighting the forgetting curve) — new `pkm_review_state` table; not flashcard-grade SRS, just "haven't seen this in 7+ days, here it is again." Forte: PKM is *"resurfacing best chunks to fight the forgetting curve."*
- **Temporal anchoring** — on-this-day and daily review.
- **Visual over mental** (ADHD core principle) — out-of-sight-out-of-mind means the home page must *show* the top signals, not require searching.

### ADHD design alignment

Per `.claude/ADHD_Principles.md`:
- **Externalize working memory:** the home page surfaces recent essences, top concepts, and category activity without the user remembering what's in the system.
- **Visual over mental:** category grid, on-this-day, co-occurrence counts — all visible at a glance.
- **Reduce friction:** one URL, no app to load, no plugin rebuild, no auth. Tap a LAN bookmark.
- **Realistic over idealistic:** read-only v1; no editing; no sync-back; no graph view.

### Core insight vs. the prior design doc

An earlier design doc (`~/Downloads/2026-04-12-selene-pkm-browse-layer-design.md`) proposed this same browse layer but targeted a **Python stack** (stdlib `http.server`, `SQLiteStorageAdapter`, `obsidian_exporter.py`) that was replaced on 2026-01-09 when Selene was rewritten in TypeScript. More importantly, it assumed a knowledge graph (`themes`, `connections`, `patterns` tables) that doesn't exist in the production database — 0 rows in `connections`, themes table not present in prod at all, `primary_theme` is unnormalized free text. This design routes around those assumptions and uses only fields that are actually populated.

---

## Current ground truth

Verified against `~/selene-data/selene.db` on 2026-04-12:

```
raw_notes:       143 rows
processed_notes: 151 rows
```

**Populated fields we can query:** `rn.title`, `rn.content`, `rn.created_at`, `rn.status`, `rn.exported_to_obsidian`, `rn.test_run`, `pn.concepts` (JSON array), `pn.essence`, `pn.primary_theme` (free text, messy), `pn.sentiment_score`, `pn.emotional_tone`, `pn.energy_level`, `pn.fidelity_tier`, `pn.processed_at`.

**Empty / broken fields:** `pn.category` (150/151 NULL), `pn.cross_ref_categories` (same), `pn.secondary_themes` (mostly empty), no `themes` / `connections` / `patterns` tables.

**Exporter state:** `src/workflows/export-obsidian.ts` (454 lines) already writes per-note markdown with YAML frontmatter + LLM-generated MOCs (gated on `category` being populated) + a code-generated `Dashboard.md`. MOC generation has been running against mostly-empty category data, so only 1 MOC ("Politics & Society") has a note in it.

**Vault path:** `~/selene-data/vault/` (not the default `data/` path — `config.vaultPath` is overridden in env).

---

## Shipping order

| # | Track | Why this order | Est. |
|---|---|---|---|
| 0 | **Backfill categories** | Everything downstream assumes `category` is populated. Script already exists, just needs to run. Without this, Track 1's category pages and existing MOC generation are empty. | 30 min |
| 1 | **Review state table** | Tiny. Self-contained. Unblocks Track 2's `/pkm/review` route and Track 3's frontmatter. | 2 hr |
| 2 | **Web dashboard** (`/pkm/*`) | The iPad experience. Depends on 0 and 1. | 2 days |
| 3 | **Exporter slim upgrade** | Minimum work to keep the vault useful as offline view. Heavier exporter changes deferred until we see which surface is actually used. | 4 hr |
| — | ~~Graph view~~ | Stretch; dropped. No `connections` data to draw. |

Total: ~1 week. Within the `docs/plans/INDEX.md` scope check.

---

## Track 0 — Run category backfill

**Script already exists:** `scripts/backfill-categories.ts`. It iterates `processed_notes` where `category IS NULL AND rn.test_run IS NULL`, prompts Ollama with title/theme/essence/concepts, and writes back `category` + `cross_ref_categories`.

### Pre-flight

1. Confirm Ollama is up: `curl -s http://localhost:11434/api/tags | head`
2. Snapshot: `cp ~/selene-data/selene.db ~/selene-data/selene.db.backup-2026-04-12`
3. Check expected row count: `sqlite3 ~/selene-data/selene.db "SELECT COUNT(*) FROM processed_notes WHERE category IS NULL;"` — expect ~150.

### Run

```bash
npx ts-node scripts/backfill-categories.ts
```

Expected: ~150 LLM calls at mistral:7b speed → several minutes.

### Verification

```sql
SELECT category, COUNT(*)
FROM processed_notes
WHERE test_run IS NULL
GROUP BY category
ORDER BY 2 DESC;
```

Acceptance: every non-test row has a non-NULL category. At least 5 of the 8 canonical categories should have ≥1 note each (if fewer, the LLM is collapsing too much — stop and investigate prompt).

### Rollback

`cp ~/selene-data/selene.db.backup-2026-04-12 ~/selene-data/selene.db`

---

## Track 1 — Review state schema

A tiny table that both the web dashboard and the exporter can read from.

### Schema

```sql
CREATE TABLE IF NOT EXISTS pkm_review_state (
  entity_type       TEXT NOT NULL,          -- 'note' | 'category' | 'concept'
  entity_id         TEXT NOT NULL,          -- stringified int for notes, name for category/concept
  last_surfaced_at  TEXT,                    -- ISO8601 UTC
  surface_count     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_pkm_review_last ON pkm_review_state(last_surfaced_at);
```

### Migration strategy

Follow the existing `try { db.exec('ALTER TABLE ...'); } catch {}` pattern from `src/workflows/process-llm.ts` lines 12–18 and `src/workflows/export-obsidian.ts` lines 9–14. Place the `CREATE TABLE IF NOT EXISTS` in a new `src/lib/pkm-db.ts` module's init block so it runs once on import. Zero-downtime, idempotent.

### Methods (`src/lib/pkm-db.ts`)

```typescript
export function markSurfaced(entityType: string, entityId: string): void
export function getDueForReview(limit: number): ReviewItem[]
export function getLeastRecentlySurfaced(entityType: string, limit: number): ReviewItem[]
```

Logic:
- `markSurfaced`: UPSERT, `surface_count = surface_count + 1`, `last_surfaced_at = now()`.
- `getDueForReview`: notes where `last_surfaced_at IS NULL OR last_surfaced_at < datetime('now', '-7 days')`, ordered by `surface_count ASC, last_surfaced_at ASC NULLS FIRST`, limit N.
- 7-day window is a `const REVIEW_WINDOW_DAYS = 7` — tune after usage.

### Wiring (deferred to Track 2)

- `GET /pkm/notes/:id` calls `markSurfaced('note', id)` on render.
- `GET /pkm/review/today` reads `getDueForReview`.

### Verification

```bash
sqlite3 ~/selene-data/selene.db "INSERT INTO pkm_review_state VALUES ('note', '5', datetime('now','-10 days'), 1);"
# hit /pkm/review/today after Track 2
# confirm note 5 appears, then drops out on next load
```

---

## Track 2 — LAN Web Dashboard (`/pkm/*`)

### Port and server decision

**Extend Fastify on port 5678.** The existing `src/server.ts` is 90 lines and already runs in launchd (`com.selene.server`). A second port = a second process to babysit + a second firewall prompt + a second set of logs. New routes live under `/pkm/*`, cleanly isolated from `/webhook/api/drafts` and `/health`.

### Files to create

```
src/lib/pkm-queries.ts      # All SQL for the browse layer; returns typed rows
src/lib/pkm-render.ts       # HTML rendering via TS template literals
src/routes/pkm.ts           # Fastify plugin: route handlers + register()
```

### Files to modify

- `src/server.ts` — one line: `app.register(pkmRoutes, { prefix: '/pkm' })`. Bind already covers LAN (`0.0.0.0`); if not, change `host` in `app.listen()`.
- `.claude/OPERATIONS.md` — add a "Browse on iPad" section with LAN URL + privacy note.

### Templating decision

**Plain TS template literals** in `src/lib/pkm-render.ts`. No React, no Handlebars, no JSX, no build step. One exported function per page: `renderHome`, `renderCategory`, `renderConcept`, `renderNote`, `renderEssences`, `renderReview`, `renderOnThisDay`, `renderError`. Each wraps a shared `layout(title, body)` that emits a full HTML document with one inline `<style>` block.

Why template literals: the existing codebase is pure TypeScript with zero frontend tooling. Adding a templating dep for 8 pages is overkill. TS template literals have one gotcha — HTML escaping — handled by a small `esc()` helper.

### CSS

One inline `<style>` block in `layout()`:
- System font stack (`-apple-system, …`)
- `max-width: 760px; margin: 0 auto; padding: 1.5rem;`
- `@media (prefers-color-scheme: dark)` flipped palette
- `font-size: 17px` base (iPad readable one-handed)
- Tap targets ≥ 44px (Apple HIG)
- No JS framework. No `<script>` tags at all in v1.

### Routes

| Path | Purpose | Data source |
|---|---|---|
| `GET /pkm/` | **Home.** Recent 10 essences, top 20 concepts, category activity strip, on-this-day card, one random resurface, due-for-review count | `pkm-queries` fns below |
| `GET /pkm/categories` | Category grid with counts + last activity + one representative essence per category | `GROUP BY category` + subquery |
| `GET /pkm/categories/:name` | Notes in category + cross-ref notes (via `json_each(cross_ref_categories)`) | `getNotesForCategory` |
| `GET /pkm/concepts` | Concept frequency list derived on the fly from `json_each(concepts)` | `getConceptFrequencies` |
| `GET /pkm/concepts/:name` | Notes containing concept + top co-occurring concepts | `getNotesForConcept`, `getCooccurringConcepts` |
| `GET /pkm/notes/:id` | One processed note: title, essence, content, concepts, category, fidelity tier, sentiment chips, "other notes in this category" | `getNoteById` — also calls `markSurfaced('note', id)` |
| `GET /pkm/essences` | Gallery of essence lines across all notes, paginated 50/page | `SELECT essence FROM processed_notes WHERE essence IS NOT NULL` |
| `GET /pkm/random` | 302 → `/pkm/notes/<random id>` | `ORDER BY RANDOM() LIMIT 1` |
| `GET /pkm/review/today` | Due-for-review + 1 random essence card | `getDueForReview` + random |
| `GET /pkm/on-this-day` | Notes from this calendar day in prior years | `strftime('%m-%d', created_at) = strftime('%m-%d', 'now')` |

### Core queries (`src/lib/pkm-queries.ts`)

All read-only. All gate on `rn.test_run IS NULL AND rn.status = 'processed'`.

```sql
-- top concepts
SELECT je.value AS concept, COUNT(*) AS n
FROM processed_notes pn
JOIN raw_notes rn ON rn.id = pn.raw_note_id
, json_each(pn.concepts) je
WHERE rn.test_run IS NULL AND rn.status = 'processed'
GROUP BY je.value
ORDER BY n DESC
LIMIT ?;

-- notes for concept (JSON membership)
SELECT rn.id, rn.title, rn.created_at, pn.essence, pn.primary_theme, pn.category
FROM processed_notes pn
JOIN raw_notes rn ON rn.id = pn.raw_note_id
, json_each(pn.concepts) je
WHERE je.value = ?
  AND rn.test_run IS NULL AND rn.status = 'processed'
ORDER BY rn.created_at DESC
LIMIT ?;

-- co-occurring concepts
SELECT jb.value AS co_concept, COUNT(*) AS n
FROM processed_notes pn
, json_each(pn.concepts) ja
, json_each(pn.concepts) jb
JOIN raw_notes rn ON rn.id = pn.raw_note_id
WHERE ja.value = ? AND jb.value != ?
  AND rn.test_run IS NULL AND rn.status = 'processed'
GROUP BY jb.value
ORDER BY n DESC
LIMIT ?;

-- notes for category (including cross-refs via json_each)
SELECT rn.id, rn.title, rn.created_at, pn.essence, pn.primary_theme
FROM processed_notes pn
JOIN raw_notes rn ON rn.id = pn.raw_note_id
WHERE (pn.category = ?
       OR EXISTS (
         SELECT 1 FROM json_each(pn.cross_ref_categories) x
         WHERE x.value = ?
       ))
  AND rn.test_run IS NULL AND rn.status = 'processed'
ORDER BY rn.created_at DESC
LIMIT ?;

-- on-this-day
SELECT rn.id, rn.title, rn.created_at, pn.essence
FROM raw_notes rn
JOIN processed_notes pn ON rn.id = pn.raw_note_id
WHERE strftime('%m-%d', rn.created_at) = strftime('%m-%d', 'now')
  AND date(rn.created_at) < date('now')
  AND rn.test_run IS NULL AND rn.status = 'processed';

-- random essence
SELECT rn.id, rn.title, pn.essence
FROM processed_notes pn
JOIN raw_notes rn ON rn.id = pn.raw_note_id
WHERE pn.essence IS NOT NULL
  AND rn.test_run IS NULL AND rn.status = 'processed'
ORDER BY RANDOM() LIMIT 1;
```

Performance note: at 151 notes, `json_each` on every request is fine. At ~10K notes it will still be fine (SQLite is fast; this is ~ms). Past that, add a materialized `concept_counts` view refreshed by a workflow.

### Auth decision

**None in v1.** Per the design doc's spirit and `ADHD_Principles.md` (reduce friction). Bind to `0.0.0.0:5678`, document in `OPERATIONS.md` as LAN-only. Existing `/webhook/api/drafts` bearer-token auth is unchanged.

**Risk:** if the Mac is ever exposed beyond LAN (VPN, hotel Wi-Fi bridge), `/pkm/*` contents leak. Mitigation: prefix the route register with a `request.ip` CIDR check against `10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`, `127.0.0.0/8`. 10 lines of Fastify preHandler. **Recommend including this.**

### Verification

- `curl -s http://localhost:5678/pkm/ | head -30` on the Mac returns HTML, not JSON
- `curl -s http://localhost:5678/health` still returns ok
- `curl -s -X POST http://localhost:5678/webhook/api/drafts -H "Authorization: Bearer $TOKEN" -d '{"title":"smoke","content":"smoke","test_run":"test-pkm-smoke"}'` still 200s
- Open `http://<mac-lan-ip>:5678/pkm/` in iPad Safari; tap every nav link; confirm readable one-handed; confirm dark mode flips
- Run ingestion test, hit `/pkm/notes/<new id>`, verify `pkm_review_state` row appears
- Cleanup: `./scripts/cleanup-tests.sh test-pkm-smoke`

### Risks

1. **JSON query cost at scale** — not a v1 problem.
2. **Free-text `primary_theme` looks messy if surfaced** — mitigation: don't expose `primary_theme` as a first-class browse axis in v1. Show it as a subtle chip on the note detail page only. `category` is the browse axis; `concepts` is the zoom-in axis.
3. **Test-run noise** — every query must gate on `test_run IS NULL`. Centralize in a `baseNoteFilter()` helper in `pkm-queries.ts` to avoid drift.
4. **Fastify route ordering** — register `/pkm` *after* `/health` and `/webhook` to keep prefix isolation predictable.

---

## Track 3 — Obsidian exporter slim upgrade

**Principle:** the TS exporter already does most of what the original Python design doc wanted (frontmatter, per-category MOCs, code-generated dashboard). Don't duplicate it. The web dashboard is the primary browse surface; Obsidian is the secondary offline view. This track is the *minimum* edit to keep the vault useful without re-inventing what the web does.

### Files to modify

`src/workflows/export-obsidian.ts` only.

### Changes

1. **Add `essence` to frontmatter.** Currently only appears as italic body text (line 143–145). Adding it to the YAML block enables Dataview queries like `WHERE essence != ""`. ~3 lines.
2. **Add `last_surfaced` and `surface_count` to frontmatter** — from `pkm_review_state` via Track 1's methods. Enables `SORT last_surfaced ASC` Dataview queries for "least surfaced" browsing in Obsidian Mobile. ~5 lines + one query.
3. **Source `updated:` from `pn.processed_at`, never `Date.now()`.** This is the single most important iCloud-churn rule from the original design doc and applies verbatim to the TS exporter. Every run stamping `Date.now()` would dirty every file and re-sync the whole vault through iCloud.
4. **Content-hash guard on re-export.** The current `exportNotes()` only processes `exported_to_obsidian = 0` rows (line 91), so most of the time no file is re-written. But when we *do* regenerate (e.g., after a backfill adds category data), compare the SHA-256 of the new rendered body to the existing file. Skip `writeFileSync` when equal. ~8 lines.

### What we are **not** doing

- ❌ New Home.md generator — the web dashboard *is* the home page.
- ❌ New theme MOCs — we have category MOCs already; themes are unnormalized and not worth surfacing.
- ❌ New daily/weekly review markdown — web `/pkm/review/today` owns this.
- ❌ Dataview blocks beyond what's already in `Dashboard.md`.

Revisit after 2 weeks of actual iPad usage. If Obsidian turns out to be used heavily (unlikely given plugin friction), port more of the web features into it.

### Verification

- Export to `/tmp/selene-vault-test`: `OBSIDIAN_VAULT_PATH=/tmp/selene-vault-test npx ts-node src/workflows/export-obsidian.ts`
- Parse YAML of one note: `python3 -c "import yaml,sys; d=open(sys.argv[1]).read().split('---',2)[1]; print(yaml.safe_load(d))" /tmp/selene-vault-test/Selene/Notes/*.md | head`
- Run exporter twice back-to-back: second run should write 0 files (content-hash guard)
- Open a note in Obsidian desktop, confirm Dataview block `WHERE essence != ""` returns rows
- Cleanup: `rm -rf /tmp/selene-vault-test`

### Risks

1. **Breaking existing exporter.** Mitigation: all changes are additive + guarded. Rollback = revert the single file.
2. **`pkm_review_state` join slows export.** Mitigation: one `LEFT JOIN` per note batch, indexed on `(entity_type, entity_id)`.

---

## Out of scope (explicit, future work)

- Editing / write-back from web
- Embedding or FTS5 search (existing `vectors.lance` dir is from archived features)
- WebSocket live updates
- Auth
- Native iOS app
- Sync-back from Obsidian edits
- Graph view (no `connections` data to draw)
- Themes as a browse axis (requires normalization pass first)
- Backfilling `fidelity_tier` retroactively
- Time-series sentiment/energy trends (data exists, not essential for v1)

---

## Critical files summary

**Create:**
- `src/lib/pkm-db.ts` — review state schema init + CRUD (Track 1)
- `src/lib/pkm-queries.ts` — read-only browse queries (Track 2)
- `src/lib/pkm-render.ts` — HTML rendering (Track 2)
- `src/routes/pkm.ts` — Fastify plugin (Track 2)

**Modify:**
- `src/server.ts` — register `/pkm` plugin (Track 2)
- `src/workflows/export-obsidian.ts` — frontmatter upgrades + hash guard (Track 3)
- `.claude/OPERATIONS.md` — "Browse on iPad" section + LAN privacy note (Track 2)
- `.claude/PROJECT-STATUS.md` — mark browse layer shipped (at end)
- `docs/plans/INDEX.md` — move this doc to "Done" at end

**Run once:**
- `scripts/backfill-categories.ts` (Track 0, existing)

---

## ADHD check

- [x] **Externalizes working memory** — home page surfaces recent essences, category activity, due-for-review without the user remembering what's in the system
- [x] **Visual over mental** — category grid, concept frequencies, on-this-day card; zero searching required to start browsing
- [x] **Reduces friction** — LAN URL, no app load, no plugin rebuild, no auth
- [x] **Realistic over idealistic** — read-only; 4 small tracks; each shippable alone; stretch features explicitly dropped

## Scope check

- [x] Fits in ~1 week of focused work (Track 0: 30min, Track 1: 2hr, Track 2: 2d, Track 3: 4hr)
- [x] No blockers — category backfill script exists; Ollama is up; no new deps
- [x] All dependencies within the repo — no new npm packages

## Acceptance criteria

1. `scripts/backfill-categories.ts` has run and every non-test processed note has a non-NULL `category`
2. `GET http://<mac-lan-ip>:5678/pkm/` returns HTML on iPad Safari
3. Every nav link on the home page loads without error
4. `pkm_review_state` records a row when a note is viewed
5. `/pkm/review/today` surfaces at least one note after a week of inactivity on that note
6. Existing `/health` and `/webhook/api/drafts` pass their smoke tests after the refactor
7. Running `export-obsidian.ts` twice in a row writes 0 files on the second run
8. A processed note's `.md` in the vault has `essence:` in its frontmatter

---

## PKM research references

Background on techniques referenced above:

- [Progressive Summarization: A Practical Technique for Designing Discoverable Notes — Forte Labs](https://fortelabs.com/blog/progressive-summarization-a-practical-technique-for-designing-discoverable-notes/)
- [Progressive Summarization VI: Core Principles of Knowledge Capture — Forte Labs](https://fortelabs.com/blog/progressive-summarization-vi-core-principles-of-knowledge-capture/)
- [PKM for ADHD: Strategies to Boost Productivity — Better Note Taking](https://betternotetaking.com/what-is-pkm/pkm-applications-in-various-domains/pkm-for-adhd/)
- [Designing A Personal Knowledge Management System For People With ADHD — Malmö University thesis](http://mau.diva-portal.org/smash/record.jsf?pid=diva2:1777365&dswid=4328)
- [Is PKM the secret weapon for neurodivergent minds at work? — Radiant](https://radiantapp.com/blog/personal-knowledge-management-and-neurodivergent-minds)
