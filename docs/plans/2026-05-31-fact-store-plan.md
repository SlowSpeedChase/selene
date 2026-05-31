# Fact Store — Phase 1 (The Split) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the single `selene.db` into a precious `facts.db` (captured notes + human review state) and a disposable `selene.db` (all derived data + pipeline bookkeeping), with **zero behavior change**, so a later phase can wipe and regenerate the derived layer from facts.

**Architecture:** `selene.db` `ATTACH`es `facts.db AS facts`. Captured-note facts move to `facts.captured_notes`; pipeline bookkeeping (status, export hashes, folio status) moves to a new `selene.note_state` table. A backward-compatible **`raw_notes` VIEW** in `selene.db` joins the two so the ~14 existing read sites are untouched; only the 6 known write sites are redirected to the real tables. `pkm_review_state` migrates to `facts.review_state`. "Pending" is derivation-absence, surfaced as `COALESCE(note_state.status,'pending')` in the view.

**Tech Stack:** TypeScript, better-sqlite3, SQLite ATTACH + views (WAL + busy_timeout), Jest, ts-node.

**Scope note:** This is Phase 1 of the [fact-store design](2026-05-31-fact-store-design.md). Phase 2 (the `rebuild` command + full-regenerate validation) and Phase 3 (the category-override *feature*) are separate plans, written after Phase 1 lands.

---

## Amendments discovered during execution (after Task 3)

These override the original task text below where they conflict:

1. **The `raw_notes` view MUST be `CREATE TEMP VIEW`, not a persistent view.** SQLite forbids a *persistent* view in `main` from referencing an ATTACHed database (verified empirically + SQLite docs/forum). Consequence: the view is **per-connection** — every connection that reads `raw_notes` must `attachFacts(db)` **and** `ensureRawNotesView(db)` at open time. The guard checks `sqlite_master` for a physical table (temp views live in `sqlite_temp_master`, so they don't confuse it).
2. **Centralize connection creation → new sub-task (do in Task 9, before Task 8 flips any DB).** Add `openSeleneConnection(path?)` in `db.ts` that does `new Database` → `applyConnectionPragmas` → `ensureFactsDbInitialized` → `attachFacts` → `ensureNoteStateTable` → `ensureRawNotesView`. Repoint the **3 non-singleton readers** of `raw_notes`: `src/workflows/folio-feedback.ts:76`, `scripts/selene-inspect.ts:29` (READONLY — verify a TEMP VIEW can be created on a readonly connection; temp objects don't write the main file, so it should work — confirm when wiring), `scripts/seed-dev-data.ts:82`. (`voice-memos-reader.ts` opens a non-Selene Apple DB; `migrate-folio.ts` is legacy — ignore both.)
3. **`note_state` includes `inbox_status TEXT`; the view exposes `COALESCE(ns.inbox_status,'pending')`.** It's a *live* reader (`worksheets.ts:21`), not legacy. (Done in Task 3 fix `b0593c9`.)
4. **Proven droppable (zero live readers — audited):** `status_apple`, `processed_at_apple`, `suggested_type`, `suggested_project_id`, `tasks_extracted`, `tasks_extracted_at`. Task 8 does NOT carry these into the two-file layout.
5. **Task 8 ALTER rule:** idempotent `ALTER TABLE raw_notes ADD COLUMN X` blocks in `db.ts` (e.g. `:611` source_note_id, `:635` inbox_status) are *safe only because the view exposes those columns* — `PRAGMA table_info(raw_notes-view)` includes them, so the guard skips the ALTER. Any future column-add for a column the view does NOT expose must retarget `captured_notes` (a fact) or `note_state` (bookkeeping). Task 8 must convert these blocks accordingly.
6. **The existing test suite does NOT exercise the view path** (every fixture creates a physical `raw_notes` table, so the guard no-ops). Tasks 8 AND 10 MUST add **view-mode reader coverage**: a fixture that builds the two-file/TEMP-VIEW layout and runs the representative real read queries — `pkm-queries`, `synthesis-digest`, `daily-summary`, `folio-feedback`, `worksheets` — against it. Do not let the dev e2e be the first thing that exercises the view for real readers.

---

## Pre-flight (read before Task 1)

- **Branch:** work on `feat/fact-store` (already created; the design doc is committed there). If using a worktree: `git worktree add .worktrees/fact-store feat/fact-store`.
- **Never touch prod data.** All tests use the dev DB (`~/selene-data-dev/selene.db`) or temp DBs. The `prod-data-guard` hook will (correctly) block any prod path.
- **The fact column set** (what `captured_notes` holds), verified from `db.ts:114-129`:
  `id, title, content, content_hash, source_type, word_count, character_count, tags, created_at, imported_at, source_uuid, calendar_event, capture_type, source_note_id, test_run`.
- **The bookkeeping column set** (what `note_state` holds — everything live code writes/reads off the fact row):
  `raw_note_id` (PK, → captured_notes.id), `status`, `processed_at`, `exported_to_obsidian`, `obsidian_export_hash`, `exported_at`, `status_folio`.
- **The 6 write sites** (the only code that must change to write):
  1. `src/lib/db.ts:114` — capture INSERT → `facts.captured_notes`
  2. `src/routes/notes.ts:82` — annotation capture INSERT → `facts.captured_notes`
  3. `src/lib/db.ts:137` — `calendar_event` UPDATE → `facts.captured_notes` (calendar_event is a fact)
  4. `src/lib/db.ts:83` — `status`/`processed_at` UPDATE → `note_state` UPSERT
  5. `src/workflows/folio-feedback.ts:134` — `status_folio` UPDATE → `note_state` UPSERT
  6. `src/lib/obsidian-render.ts:173` — `obsidian_export_hash`/`exported_to_obsidian` UPDATE → `note_state` UPSERT

---

## Task 1: Add `factsDbPath` to config

**Files:**
- Modify: `src/lib/config.ts` (mirror `getDbPath()`/`dbPath`)
- Test: `src/lib/config.test.ts` (create if absent)

**Step 1 — Write the failing test:**
```ts
// src/lib/config.test.ts
import { config } from './config';
describe('factsDbPath', () => {
  it('sits beside dbPath in the same data root', () => {
    expect(config.factsDbPath).toMatch(/facts\.db$/);
    // facts.db lives in the same directory as selene.db
    const dir = (p: string) => p.replace(/\/[^/]+$/, '');
    expect(dir(config.factsDbPath)).toBe(dir(config.dbPath));
  });
});
```

**Step 2 — Run, expect FAIL:** `npx jest src/lib/config.test.ts` → `factsDbPath` undefined.

**Step 3 — Implement:** add a `getFactsDbPath()` mirroring `getDbPath()` (test → `data-test/facts.db`, dev → `<devDataRoot>/facts.db`, prod → `~/selene-data/facts.db`), honoring an optional `SELENE_FACTS_DB_PATH` override first. Add `factsDbPath: getFactsDbPath()` to the exported `config`.

**Step 4 — Run, expect PASS.**

**Step 5 — Commit:** `git commit -am "feat(fact-store): add config.factsDbPath beside dbPath"`

---

## Task 2: `facts.db` schema module (`captured_notes` + `review_state`)

**Files:**
- Create: `src/lib/facts-db.ts`
- Test: `src/lib/facts-db.test.ts`

**Step 1 — Write the failing test** (against a temp DB, not dev/prod):
```ts
import Database from 'better-sqlite3';
import { initFactsSchema } from './facts-db';
it('creates captured_notes and review_state idempotently', () => {
  const db = new Database(':memory:');
  initFactsSchema(db);
  initFactsSchema(db); // idempotent — must not throw
  const cols = db.prepare(`PRAGMA table_info(captured_notes)`).all().map((c: any) => c.name);
  expect(cols).toEqual(expect.arrayContaining(['id','title','content','content_hash','source_uuid','calendar_event','capture_type','test_run']));
  const rs = db.prepare(`PRAGMA table_info(review_state)`).all().map((c: any) => c.name);
  expect(rs).toEqual(expect.arrayContaining(['entity_type','entity_id','last_surfaced_at','surface_count']));
});
```

**Step 2 — Run, expect FAIL** (module missing).

**Step 3 — Implement** `initFactsSchema(db)` with `CREATE TABLE IF NOT EXISTS captured_notes (...)` using the fact column set above (`id INTEGER PRIMARY KEY AUTOINCREMENT`, `title`/`content`/`content_hash` `NOT NULL`, `created_at NOT NULL`, rest nullable) and `CREATE TABLE IF NOT EXISTS review_state (... PRIMARY KEY (entity_type, entity_id))` matching today's `pkm_review_state`. Add `CREATE UNIQUE INDEX IF NOT EXISTS idx_captured_content_hash ON captured_notes(content_hash)` (dedup parity with today).

**Step 4 — Run, expect PASS.**

**Step 5 — Commit:** `git commit -am "feat(fact-store): facts.db schema (captured_notes + review_state)"`

---

## Task 3: Attach `facts.db`, create `note_state` + the `raw_notes` compatibility view

**Files:**
- Modify: `src/lib/db.ts` (connection setup — currently opens one DB; the 19 refs here are the hub)
- Test: `src/lib/db-attach.test.ts`

**Step 1 — Write the failing test:**
```ts
// Build a two-file pair in a temp dir, attach, assert the view round-trips.
it('raw_notes view joins facts + note_state and defaults status to pending', () => {
  // ...open selene temp db, ATTACH facts temp db AS facts, initFactsSchema(facts),
  //    initStateAndView(selene)...
  facts.prepare(`INSERT INTO captured_notes (title,content,content_hash,created_at) VALUES ('t','c','h1',datetime('now'))`).run();
  const row = selene.prepare(`SELECT id, title, status FROM raw_notes WHERE content_hash='h1'`).get() as any;
  expect(row.title).toBe('t');
  expect(row.status).toBe('pending');         // no note_state row → COALESCE default
});
```

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement** in `db.ts`. **Order matters — `initFactsSchema` creates UNQUALIFIED tables (they go to the connection's `main`), so it must run on `facts.db` while `facts.db` IS main, i.e. a standalone connection — NOT after ATTACH (which would create the tables in `selene.db`).**

1. **Ensure facts.db exists with its schema (standalone):** `const f = new Database(config.factsDbPath); f.pragma('journal_mode = WAL'); initFactsSchema(f); f.close();`
2. **On the main `selene.db` connection:** `db.pragma('journal_mode = WAL'); db.pragma('busy_timeout = 5000');` (busy_timeout is per-connection — it covers the attached db too; no need to set it on `facts.`). Then `db.prepare("ATTACH DATABASE ? AS facts").run(config.factsDbPath)`. Best-effort `db.pragma('facts.journal_mode = WAL')`.
3. Create in **main** (`selene.db`):
```sql
CREATE TABLE IF NOT EXISTS note_state (
  raw_note_id INTEGER PRIMARY KEY,
  status TEXT, processed_at DATETIME, exported_at DATETIME,
  exported_to_obsidian INTEGER, obsidian_export_hash TEXT, status_folio TEXT
);
DROP VIEW IF EXISTS raw_notes;
CREATE VIEW raw_notes AS
  SELECT cn.id, cn.title, cn.content, cn.content_hash, cn.source_type,
         cn.word_count, cn.character_count, cn.tags, cn.created_at, cn.imported_at,
         cn.source_uuid, cn.calendar_event, cn.capture_type, cn.source_note_id, cn.test_run,
         COALESCE(ns.status,'pending') AS status,
         ns.processed_at, ns.exported_at,
         ns.exported_to_obsidian, ns.obsidian_export_hash, ns.status_folio
  FROM facts.captured_notes cn
  LEFT JOIN note_state ns ON ns.raw_note_id = cn.id;
```
> **Standardize the attach alias as `facts`** everywhere — the view DDL hard-codes it.
>
> **Guard the view against the pre-migration physical table.** Today `raw_notes` is a TABLE; post-migration it is a VIEW. Wrap view creation in `ensureRawNotesView(db)` that checks `sqlite_master`:
> - `raw_notes` exists as a **table** → do nothing (un-migrated DB; Task 8's migration converts it). Do not throw.
> - `raw_notes` exists as a **view** or is absent → `DROP VIEW IF EXISTS raw_notes; CREATE VIEW ...` (idempotent refresh).
>
> Add a test for the guard: on a main DB that already has a physical `raw_notes` table, `ensureRawNotesView` is a no-op (the table survives, no throw); on a fresh DB it creates the view.

**Step 4 — Run, expect PASS.**

**Step 5 — Commit:** `git commit -am "feat(fact-store): attach facts.db, add note_state + raw_notes compat view"`

---

## Task 4: Redirect the two capture INSERTs → `facts.captured_notes`

**Files:**
- Modify: `src/lib/db.ts:114` (`insertNote` helper), `src/routes/notes.ts:82`
- Test: `src/lib/db-capture.test.ts`

**Step 1 — Failing test:** insert a note via the real `insertNote()` path against the temp pair; assert (a) the row lands in `facts.captured_notes`, (b) it reads back through the `raw_notes` view with `status='pending'`, (c) `lastInsertRowid` is returned and usable as a FK.

**Step 2 — Run, expect FAIL** (insert still targets the view / old table → "cannot modify raw_notes" or wrong DB).

**Step 3 — Implement:** change both INSERT statements from `INSERT INTO raw_notes (...)` to `INSERT INTO facts.captured_notes (...)` with the **fact columns only** (drop `status`/`capture_type` defaults that belonged to bookkeeping — `capture_type` stays, it's a fact; `status` is gone). Keep the `content_hash` dedup `ON CONFLICT`/pre-check behavior.

**Step 4 — Run, expect PASS.**

**Step 5 — Commit.**

---

## Task 5: Redirect the `calendar_event` fact UPDATE → `facts.captured_notes`

**Files:** Modify `src/lib/db.ts:137` (`updateCalendarEvent`). Test: extend `db-capture.test.ts`.

**Steps:** Failing test asserts `updateCalendarEvent(id, ev)` is visible through the view's `calendar_event`. Implement: `UPDATE facts.captured_notes SET calendar_event = ? WHERE id = ?`. Run → PASS. Commit.

---

## Task 6: Redirect the 3 bookkeeping writes → `note_state` UPSERT

**Files:**
- Modify: `src/lib/db.ts:83` (status/processed_at), `src/workflows/folio-feedback.ts:134` (status_folio), `src/lib/obsidian-render.ts:173` (export hash)
- Create: `src/lib/note-state.ts` (one tested UPSERT helper — DRY, since 3 callers)
- Test: `src/lib/note-state.test.ts`

**Step 1 — Failing test** for a `setNoteState(db, rawNoteId, patch)` helper that UPSERTs only the provided columns and leaves others intact:
```ts
setNoteState(db, 7, { status: 'processed', processed_at: 't1' });
setNoteState(db, 7, { status_folio: 'written' });          // must not clobber status
const r = db.prepare('SELECT status, status_folio FROM note_state WHERE raw_note_id=7').get();
expect(r).toEqual({ status: 'processed', status_folio: 'written' });
```

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement** `setNoteState` (`INSERT ... ON CONFLICT(raw_note_id) DO UPDATE SET <only provided cols>`), then replace each of the 3 `UPDATE raw_notes SET ...` calls with `setNoteState(...)`. The view surfaces these unchanged to readers.

**Step 4 — Run, expect PASS** (also run the existing `obsidian-render.db.test.ts` — it asserts export-hash round-trips; update its fixtures to the two-file/view shape).

**Step 5 — Commit.**

---

## Task 7: Verify pending-detection still works (derivation-absence)

**Files:** Modify only if needed: `src/lib/db.ts:77` (`SELECT * FROM raw_notes WHERE status = 'pending'`). Test: `src/lib/db-pending.test.ts`.

**Step 1 — Failing test:** capture 2 notes; mark one `processed` via `setNoteState`; assert the pending query returns exactly the other. A fresh capture with **no** `note_state` row must appear as pending (the `COALESCE` default).

**Step 2 — Run.** If the existing query already works through the view (it should — `status` is COALESCED), the test PASSES with no code change; if a `SELECT *` consumer needs a missing column, fix the view, not the callers.

**Step 3 — Commit** (test-only or view tweak).

---

## Task 8: Migration script (dev DB → two-file split)

**Files:**
- Create: `scripts/migrate-to-fact-store.ts`
- Test: `scripts/migrate-to-fact-store.test.ts`

**Behavior:** Given an existing single `selene.db`, produce the two-file layout **losslessly and idempotently**:
1. Create/attach `facts.db`; `initFactsSchema`.
2. `INSERT INTO facts.captured_notes (<fact cols>) SELECT <fact cols> FROM raw_notes` (the *old physical* table — run this BEFORE the view replaces the name; the script operates on a pre-split DB).
3. `INSERT INTO facts.review_state SELECT * FROM pkm_review_state`.
4. Populate `note_state` from the old `raw_notes` bookkeeping columns (`status`, `processed_at`, `exported_to_obsidian`, `obsidian_export_hash`, `exported_at`, `status_folio`) for rows where any is non-default.
5. Rename the old physical table out of the way (`ALTER TABLE raw_notes RENAME TO raw_notes_legacy_backup`) and create the `raw_notes` VIEW. (Keep the backup table until Phase 2 validates; drop later.)

**Step 1 — Failing test:** seed a temp single-DB with 3 `raw_notes` (varied status) + 2 `pkm_review_state`; run the migration; assert: `facts.captured_notes` count == 3, `content_hash` set matches, `note_state` reflects the non-pending rows, `review_state` count == 2, and `SELECT count(*) FROM raw_notes` (now the view) == 3 with correct `status` values. Run it **twice** — second run is a no-op (idempotent), not a duplicate.

**Step 2 — Run, expect FAIL.** **Step 3 — Implement.** **Step 4 — Run, expect PASS.**

**Step 5 — Dry-run against a COPY of the dev DB** (never in place first):
```bash
cp ~/selene-data-dev/selene.db /tmp/selene-dev-migtest.db
SELENE_DB_PATH=/tmp/selene-dev-migtest.db SELENE_FACTS_DB_PATH=/tmp/facts-migtest.db \
  npx ts-node scripts/migrate-to-fact-store.ts
SELENE_DB_PATH=/tmp/selene-dev-migtest.db SELENE_FACTS_DB_PATH=/tmp/facts-migtest.db \
  npx ts-node scripts/selene-inspect.ts counts   # sanity
```
Expected: counts match the pre-migration dev DB (rawNotes/processed unchanged through the view).

**Step 6 — Commit.**

---

## Task 9: Teach `selene-inspect` / `pkm-db` the two-file layout

**Files:** Modify `src/lib/inspect.ts` (9 refs), `src/lib/pkm-db.ts` (repoint `pkm_review_state` → `review_state`; it's now in `facts.`), `src/lib/pkm-queries.ts` if it names the table. Tests: extend `inspect.test.ts`, `pkm-db.test.ts` to the view/two-file shape.

**Steps:** TDD each: inspector reports both files and reads counts through the view; PKM `markSurfaced`/queries hit `facts.review_state`. Run existing PKM + inspect suites green. Commit.

---

## Task 10: End-to-end + concurrency validation on the dev showcase corpus

**Files:** none (validation task); may add `scripts/verify-fact-store.sh`.

**Step 1 — Baseline:** on a fresh dev reset, run the current pipeline and record `selene-inspect coverage` (categories, clusters, essence counts).

**Step 2 — Migrate** the dev DB (Task 8) and run the **full pipeline through the view**: `SELENE_ENV=development ./scripts/dev-process-batch.sh --all`.

**Step 3 — Assert no regression:** `coverage` after == baseline (same processed/essence/cluster counts); a fresh webhook capture lands in `facts.captured_notes`, is picked up as pending, processed, and exported.

**Step 4 — Concurrency stress** (the SQLITE_BUSY guard): in parallel, hammer the ingest endpoint (writes `facts.db`) while running `process-llm` (reads `facts` attached, writes `selene.db`); assert 0 `SQLITE_BUSY` errors in logs. This is the acceptance test for WAL + busy_timeout across ATTACH.

**Step 5 — Commit** the verify script + a short note in `BRANCH-STATUS.md`.

---

## Definition of Done (Phase 1)

All boxes from the design doc's **Acceptance Criteria (Phase 1)**, plus: `npx jest` green, `npx tsc --noEmit` clean, dev e2e matches baseline, concurrency stress clean. **No user-facing change** → guide work deferred to Phase 3 (the override feature is the first user-visible piece). Leave `raw_notes_legacy_backup` in place until Phase 2's rebuild validates, then drop it.

## Risks / watch-items

- **Views are read-only** — any *new* write path added during execution must target `captured_notes`/`note_state`, never `raw_notes`. Grep `INSERT INTO raw_notes|UPDATE raw_notes` before finishing; expect zero.
- **Attach alias must be `facts` everywhere** (the view hard-codes it). Centralize in `db.ts`.
- **Cross-DB FKs unenforced** — `note_state.raw_note_id` / `processed_notes.raw_note_id` integrity is app-level; the migration must not orphan rows.
- **Does NOT fix the dev→prod vault-path bug** (orthogonal; still open).
```
