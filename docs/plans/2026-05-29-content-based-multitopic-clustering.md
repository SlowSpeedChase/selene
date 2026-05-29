# Category-Derived Clustering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task.

**Goal:** Replace the iPad Notes "E-Ink Empowerment" mega-bucket by deriving `topic_clusters` / `topic_note_links` from the controlled 8-category taxonomy (`processed_notes.category` + `cross_ref_categories`) instead of from whole-note embeddings.

**Architecture:** Three pieces. (1) A small pure-function module (`src/lib/category-clusters.ts`) that turns each note's `category` + `cross_ref_categories` into multi-membership category groups. (2) A one-shot backfill script that classifies the ~148 older notes (mostly drafts) that predate the category feature. (3) A rewrite of `synthesize-topics.ts` that builds one `topic_clusters` row per non-empty category and links each note to *every* category it belongs to, reusing the existing per-cluster synthesis/delta-guard/evolution machinery. No schema migration; embedding-clustering code is deleted.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (`generate` via `mistral:7b`), Jest, ts-node.

**Design doc:** `docs/plans/2026-05-29-content-based-multitopic-clustering-design.md` (read it first — it records the spike that killed the embedding approach and the decision to unify drafts + e-ink on categories).

---

## Conventions & gotchas (read before starting)

- **No `any`.** Use explicit types / `unknown` + narrowing (project rule).
- **Parameterized SQL only.** Never string-interpolate values.
- **`test_run` filter is environment-aware.** Use `testRunFilter('rn')` from `src/lib/test-run.ts` in every `raw_notes` query — it returns `''` in dev (the dev DB is all `dev-seed` fixtures) and `AND rn.test_run IS NULL` in prod. Do **not** hardcode the guard.
- **Jest uses an explicit `testMatch` allowlist** (`jest.config.js`). A new `*.test.ts` file will **not run** unless you add its path to that array.
- **Never write to the live prod DB during testing.** Validation (Task 4) runs on a `cp` of prod in `/tmp`. **Danger:** `data/selene.db` is a **symlink to `~/selene-data/selene.db` (prod)**. The safe way to point any run at a copy is the `SELENE_DB_PATH` env var, which "always wins" in `config.ts`. **Always** combine it with `SELENE_ENV=production` (which skips the `.env.development` override that could otherwise clobber `SELENE_DB_PATH`) **and** with the real prod-style `testRunFilter`. Canonical safe run:
  `SELENE_ENV=production SELENE_DB_PATH=/tmp/selene-rebuild-test.db npx ts-node <script>`. Before any such run, echo `node -e "console.log(require('./dist/lib/config').config.dbPath)"` (or a ts-node equivalent) and confirm it prints the `/tmp` path, never `~/selene-data/...`.
- **`CATEGORIES`** (the canonical 8) is exported from `src/lib/prompts.ts`. `cross_ref_categories` is stored as a JSON-stringified `string[]`; `category` is a single TEXT value.
- **Do NOT touch `process-llm.ts`.** Its `embed()` call also feeds LanceDB (`indexNote`) and connection detection (`note_connections`); only the clustering *reader* of `note_embeddings` is going away.
- Run tests with `npx jest <path>`; run a workflow with `npx ts-node src/workflows/<name>.ts`.

---

## Task 1: Pure category-membership helpers

**Files:**
- Create: `src/lib/category-clusters.ts`
- Test: `src/lib/category-clusters.test.ts`
- Modify: `jest.config.js` (add the new test path to `testMatch`)

**Step 1: Write the failing test.** Create `src/lib/category-clusters.test.ts`:

```ts
import {
  slugForCategory,
  parseCrossRefs,
  groupNotesByCategory,
  uncategorizedNoteIds,
  extractCategoryFields,
} from './category-clusters';

describe('slugForCategory', () => {
  it('lowercases and replaces non-alphanumerics with single hyphens', () => {
    expect(slugForCategory('Relationships & Social')).toBe('relationships-social');
    expect(slugForCategory('Health & Body')).toBe('health-body');
    expect(slugForCategory('Personal Growth')).toBe('personal-growth');
  });
});

describe('parseCrossRefs', () => {
  it('parses a JSON string array', () => {
    expect(parseCrossRefs('["Health & Body","Career & Work"]'))
      .toEqual(['Health & Body', 'Career & Work']);
  });
  it('returns [] for null, empty, or malformed input', () => {
    expect(parseCrossRefs(null)).toEqual([]);
    expect(parseCrossRefs('')).toEqual([]);
    expect(parseCrossRefs('not json')).toEqual([]);
    expect(parseCrossRefs('{"a":1}')).toEqual([]);
  });
  it('drops non-string entries', () => {
    expect(parseCrossRefs('["Health & Body",3,null]')).toEqual(['Health & Body']);
  });
});

describe('groupNotesByCategory', () => {
  it('places a note under its primary category and every valid cross-ref (multi-membership)', () => {
    const groups = groupNotesByCategory([
      { noteId: 1, category: 'Personal Growth', crossRefs: ['Health & Body', 'Career & Work'] },
    ]);
    expect(groups.get('Personal Growth')).toEqual([1]);
    expect(groups.get('Health & Body')).toEqual([1]);
    expect(groups.get('Career & Work')).toEqual([1]);
    expect(groups.get('Politics & Society')).toEqual([]);
  });
  it('dedups when a cross-ref repeats the primary category', () => {
    const groups = groupNotesByCategory([
      { noteId: 7, category: 'Daily Systems', crossRefs: ['Daily Systems'] },
    ]);
    expect(groups.get('Daily Systems')).toEqual([7]);
  });
  it('ignores categories outside the controlled list', () => {
    const groups = groupNotesByCategory([
      { noteId: 9, category: 'Made Up', crossRefs: ['Also Fake'] },
    ]);
    for (const ids of groups.values()) expect(ids).not.toContain(9);
  });
});

describe('uncategorizedNoteIds', () => {
  it('returns notes that match zero valid categories', () => {
    expect(uncategorizedNoteIds([
      { noteId: 1, category: 'Personal Growth', crossRefs: [] },
      { noteId: 2, category: null, crossRefs: [] },
      { noteId: 3, category: 'Bogus', crossRefs: ['Nope'] },
    ])).toEqual([2, 3]);
  });
});

describe('extractCategoryFields', () => {
  it('extracts category + valid cross-refs from an LLM JSON blob with surrounding text', () => {
    const r = 'Sure!\n{"category":"Health & Body","cross_ref_categories":["Personal Growth","Bogus"]}\nDone';
    expect(extractCategoryFields(r)).toEqual({
      category: 'Health & Body',
      crossRefs: ['Personal Growth'],
    });
  });
  it('returns null category when missing/invalid and [] cross-refs on parse failure', () => {
    expect(extractCategoryFields('no json here')).toEqual({ category: null, crossRefs: [] });
    expect(extractCategoryFields('{"category":"Invalid"}')).toEqual({ category: null, crossRefs: [] });
  });
});
```

**Step 2: Run it, confirm it fails.** First make the Step 3 `jest.config.js` edit (otherwise the file is not picked up), then `npx jest src/lib/category-clusters.test.ts` → FAIL with "Cannot find module './category-clusters'".

**Step 3: Add the test to the allowlist.** In `jest.config.js`, add to the `testMatch` array:
```js
    '**/src/lib/category-clusters.test.ts',
```

**Step 4: Implement `src/lib/category-clusters.ts`:**

```ts
import { CATEGORIES } from './prompts';

const VALID = new Set<string>(CATEGORIES);

export interface CategorizableNote {
  noteId: number;
  category: string | null;
  crossRefs: string[];
}

export function slugForCategory(category: string): string {
  return category.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function parseCrossRefs(json: string | null): string[] {
  if (!json) return [];
  try {
    const parsed: unknown = JSON.parse(json);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((x): x is string => typeof x === 'string');
  } catch {
    return [];
  }
}

function validCategoriesFor(note: CategorizableNote): Set<string> {
  const cats = new Set<string>();
  if (note.category && VALID.has(note.category)) cats.add(note.category);
  for (const cr of note.crossRefs) if (VALID.has(cr)) cats.add(cr);
  return cats;
}

/** Map every controlled category → the distinct note IDs that belong to it
 *  (via primary `category` OR any valid `cross_ref`). All 8 keys always present. */
export function groupNotesByCategory(notes: CategorizableNote[]): Map<string, number[]> {
  const groups = new Map<string, Set<number>>();
  for (const cat of CATEGORIES) groups.set(cat, new Set<number>());
  for (const note of notes) {
    for (const cat of validCategoriesFor(note)) groups.get(cat)!.add(note.noteId);
  }
  const out = new Map<string, number[]>();
  for (const [cat, set] of groups) out.set(cat, [...set]);
  return out;
}

/** Notes that matched zero valid categories — used for "no silent drop" logging. */
export function uncategorizedNoteIds(notes: CategorizableNote[]): number[] {
  return notes.filter((n) => validCategoriesFor(n).size === 0).map((n) => n.noteId);
}

/** Parse an Ollama EXTRACT_PROMPT response into validated category fields. */
export function extractCategoryFields(response: string): {
  category: string | null;
  crossRefs: string[];
} {
  const match = response.match(/\{[\s\S]*\}/);
  if (!match) return { category: null, crossRefs: [] };
  try {
    const parsed = JSON.parse(match[0]) as {
      category?: unknown;
      cross_ref_categories?: unknown;
    };
    const category =
      typeof parsed.category === 'string' && VALID.has(parsed.category)
        ? parsed.category
        : null;
    const crossRefs = Array.isArray(parsed.cross_ref_categories)
      ? parsed.cross_ref_categories.filter(
          (x): x is string => typeof x === 'string' && VALID.has(x)
        )
      : [];
    return { category, crossRefs };
  } catch {
    return { category: null, crossRefs: [] };
  }
}
```

**Step 5: Run tests, confirm pass.** `npx jest src/lib/category-clusters.test.ts` → all green.

**Step 6: Commit.**
```bash
git add src/lib/category-clusters.ts src/lib/category-clusters.test.ts jest.config.js
git commit -m "feat(clustering): pure category-membership helpers (multi-membership + slug)"
```

---

## Task 2: One-shot classification backfill

Classifies the ~148 notes that have `processed_notes.category IS NULL` (mostly older drafts predating the category feature) so they participate in category clusters. Reuses `EXTRACT_PROMPT` and `extractCategoryFields` from Task 1; updates **only** `category` + `cross_ref_categories` (preserves existing concepts/essence/sentiment).

> **Note — this REPLACES an existing script.** `scripts/backfill-categories.ts` already exists on `main` (commit `10b4d20`). The old version classified on the *distilled* note (a custom `BACKFILL_PROMPT` over theme/essence/concepts) with a hardcoded `test_run IS NULL` guard. The rewrite is intentional: classify on full content via the shared `EXTRACT_PROMPT` (so backfilled notes get the *same* category they'd get at ingest via `process-llm.ts`), the shared `extractCategoryFields`, and the env-aware `testRunFilter`. **Preserve** the old version's one beneficial side effect — resetting `exported_to_obsidian = 0` after a successful backfill so the Obsidian MOCs rebuild with the new categories (the design unifies *both* surfaces on categories).

**Files:**
- Modify (replace): `scripts/backfill-categories.ts`

**Step 1: Implement the script:**

```ts
// scripts/backfill-categories.ts
// One-shot: classify processed_notes that still lack a category (predate the feature).
// Reads title+content from raw_notes, runs EXTRACT_PROMPT, writes ONLY category +
// cross_ref_categories. Idempotent: rows that already have a category are skipped.
// Run (dev/copy): SELENE_ENV=development npx ts-node scripts/backfill-categories.ts
import { db, generate, isAvailable, createWorkflowLogger } from '../src/lib';
import { EXTRACT_PROMPT } from '../src/lib/prompts';
import { extractCategoryFields } from '../src/lib/category-clusters';
import { testRunFilter } from '../src/lib/test-run';

const log = createWorkflowLogger('backfill-categories');

async function backfillCategories(): Promise<{ updated: number; failed: number }> {
  if (!(await isAvailable())) {
    log.error('Ollama not available');
    return { updated: 0, failed: 0 };
  }

  const rows = db.prepare(`
    SELECT rn.id AS id, rn.title AS title, rn.content AS content
    FROM raw_notes rn
    JOIN processed_notes pn ON pn.raw_note_id = rn.id
    WHERE pn.category IS NULL ${testRunFilter('rn')}
  `).all() as Array<{ id: number; title: string; content: string }>;

  log.info({ count: rows.length }, 'Notes to classify');
  let updated = 0;
  let failed = 0;

  for (const note of rows) {
    try {
      const prompt = EXTRACT_PROMPT
        .replace('{title}', note.title)
        .replace('{content}', note.content);
      const response = await generate(prompt);
      const { category, crossRefs } = extractCategoryFields(response);
      if (!category) {
        failed++;
        log.warn({ noteId: note.id }, 'No valid category extracted; left NULL');
        continue;
      }
      db.prepare(
        `UPDATE processed_notes SET category = ?, cross_ref_categories = ? WHERE raw_note_id = ?`
      ).run(category, JSON.stringify(crossRefs), note.id);
      updated++;
      if (updated % 25 === 0) log.info({ updated }, 'progress');
    } catch (err) {
      failed++;
      log.warn({ noteId: note.id, err: err as Error }, 'Classification failed');
    }
  }

  // Preserve main's behavior: force the Obsidian MOCs to rebuild with the new
  // categories on the next export run (the design unifies both surfaces on categories).
  if (updated > 0) {
    const reset = db.prepare(
      `UPDATE raw_notes SET exported_to_obsidian = 0 WHERE status = 'processed' ${testRunFilter()}`
    ).run();
    log.info({ resetCount: reset.changes }, 'Reset export flags for MOC rebuild');
  }

  log.info({ updated, failed }, 'Backfill complete');
  return { updated, failed };
}

if (require.main === module) {
  backfillCategories()
    .then((r) => { console.log('backfill-categories:', r); process.exit(0); })
    .catch((err) => { console.error('backfill-categories failed:', err); process.exit(1); });
}

export { backfillCategories };
```

**Step 2: Type-check.** `npx tsc --noEmit` → no errors. (No unit test: the body is Ollama I/O; its only pure logic, `extractCategoryFields`, is already tested in Task 1. Confirm the exact symbols re-exported by `src/lib/index.ts` — `db`, `generate`, `isAvailable`, `createWorkflowLogger` — match the import; adjust the import path if any differ.)

**Step 3: Commit.**
```bash
git add scripts/backfill-categories.ts
git commit -m "feat(clustering): one-shot backfill to classify uncategorized notes"
```

---

## Task 3: Rewrite `synthesize-topics.ts` to build category-derived clusters

Replace embedding clustering with category grouping. Keep per-cluster synthesis, the delta-guard, evolution detection, and the weekly rollup — they operate on a cluster regardless of how its membership was derived.

**Files:**
- Modify: `src/workflows/synthesize-topics.ts`

**Step 1: Remove the embedding-clustering code.** Delete `backfillEmbeddings()`, `loadAllEmbeddings()`, `clusterNotes()`, and `generateClusterName()`. Remove the now-unused imports `embed` and `cosineSimilarity` and the constant `CLUSTER_SIMILARITY_THRESHOLD`. Keep `MIN_CLUSTER_SIZE` only if still referenced (it should not be after this rewrite — remove it). Keep `generate`, `isAvailable`, `randomUUID`. `createHash` was only for concept-based slugs — remove if unused.

**Step 2: Add imports + a member loader.** Load all classified notes and group them with the Task 1 helper:

```ts
import { CATEGORIES } from '../lib/prompts';
import { groupNotesByCategory, parseCrossRefs, slugForCategory, uncategorizedNoteIds } from '../lib/category-clusters';
import { testRunFilter } from '../lib/test-run';

interface CategoryMember {
  noteId: number;
  title: string;
  essence: string | null;
  concepts: string | null;
  category: string | null;
  crossRefs: string[];
}

function loadClassifiedNotes(): CategoryMember[] {
  const rows = db.prepare(`
    SELECT rn.id AS noteId, rn.title AS title,
           pn.essence, pn.concepts, pn.category, pn.cross_ref_categories
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.status = 'processed' ${testRunFilter('rn')}
  `).all() as Array<{
    noteId: number; title: string; essence: string | null;
    concepts: string | null; category: string | null; cross_ref_categories: string | null;
  }>;
  return rows.map((r) => ({
    noteId: r.noteId,
    title: r.title,
    essence: r.essence,
    concepts: r.concepts,
    category: r.category,
    crossRefs: parseCrossRefs(r.cross_ref_categories),
  }));
}
```

**Step 3: Widen `generateSynthesis` + make it concept-aware.** The user explicitly cares about "the concepts I spoke about," so surface them. Change its `members` parameter type from `NoteEmbedding[]` to a structural type it actually uses (`Array<{ title: string; essence: string | null }>`) so `CategoryMember[]` is accepted, and add a `topConcepts: string[]` parameter. Cap members passed to the prompt (e.g. first 40) to bound prompt size; `log.info` when capped (no silent truncation). Inject the concepts into the existing prompt, e.g. after the notes list:

```ts
async function generateSynthesis(
  clusterName: string,
  members: Array<{ title: string; essence: string | null }>,
  topConcepts: string[],
): Promise<string> {
  const capped = members.slice(0, 40);
  if (capped.length < members.length) {
    log.info({ clusterName, shown: capped.length, total: members.length }, 'Capped synthesis members');
  }
  const noteLines = capped.map((n) => `Title: ${n.title}\nEssence: ${n.essence ?? n.title}`).join('\n\n');
  const conceptLine = topConcepts.length
    ? `\nRecurring concepts across these notes: ${topConcepts.slice(0, 15).join(', ')}\n`
    : '';
  const prompt = `You are synthesizing a personal knowledge base.
Topic: "${clusterName}"
${conceptLine}Notes (${members.length} total):

${noteLines}

Write in second person ("You've been exploring..."):
1. 3-5 sentences capturing the recurring questions, tensions, and through-line.
2. The open question that keeps resurfacing (one sentence, start with "The open question:").
3. Keep it under 200 words total.

Do not invent information not present in the notes.`;
  return generate(prompt, { timeoutMs: 60000 });
}
```

**Step 4: Replace the build loop.** Rewrite `synthesizeTopics()` so it:
1. (One-shot guard + orphan cleanup — see Step 5) wipes/​reconciles non-category clusters.
2. Loads classified notes; logs `uncategorizedNoteIds(...)` length (no silent drops).
3. Computes `const groups = groupNotesByCategory(notes)` and a `Map<number, CategoryMember>` from noteId → member.
4. For each `cat` in `CATEGORIES` where `groups.get(cat)!.length >= 1`:
   - `const noteIds = groups.get(cat)!`, `slug = slugForCategory(cat)`, `name = cat`.
   - `members = noteIds.map(id => byId.get(id)!)`.
   - **Aggregate top concepts** for this category (retain the deleted `conceptFreq` logic, now per-category): parse each member's `concepts` JSON, count frequencies, sort desc → `topConcepts: string[]`. Wrap the `JSON.parse` in try/catch (`log.debug` on malformed) exactly as the old code did.
   - Look up the existing row by slug (reuse the existing `SELECT id, synthesis_text … WHERE slug = ?` pattern) → `existing`. `const id = existing?.id ?? randomUUID()`.
   - **Delta-guard (pure set comparison, BEFORE reconcile).** Compare the desired member set to the links currently stored. This must happen before we touch `topic_note_links`, or the new members wouldn't be visible yet:
     ```ts
     const desired = new Set(noteIds);
     const currentLinks = existing
       ? new Set((db.prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?')
           .all(existing.id) as Array<{ note_id: number }>).map((r) => r.note_id))
       : new Set<number>();
     const unchanged =
       existing != null &&
       existing.synthesis_text != null &&
       desired.size === currentLinks.size &&
       [...desired].every((n) => currentLinks.has(n));
     if (unchanged) { clustersProcessed++; continue; }  // same members ⇒ same count ⇒ nothing to write
     ```
     (`continue` is safe: an unchanged set implies an unchanged `note_count`, and we never reach the upsert, so `synthesis_text` is never overwritten with null.)
   - **Regenerate + upsert.** `const prevSynthesis = existing?.synthesis_text ?? null;` `const newSynthesis = await generateSynthesis(name, members, topConcepts);` then upsert `topic_clusters` (`is_proto = 0`, `note_count = noteIds.length`) via the existing `INSERT … ON CONFLICT(slug) DO UPDATE` (name = cat, not an LLM-generated name).
   - **Reconcile** `topic_note_links` (insert missing, delete stale):
     ```ts
     for (const { note_id } of (db.prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?')
         .all(id) as Array<{ note_id: number }>)) {
       if (!desired.has(note_id)) {
         db.prepare('DELETE FROM topic_note_links WHERE topic_id = ? AND note_id = ?').run(id, note_id);
       }
     }
     for (const noteId of noteIds) {
       db.prepare('INSERT OR IGNORE INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)')
         .run(id, noteId, now);
     }
     ```
     (`note_count` is already set by the upsert; no separate UPDATE needed.)
   - Keep the existing evolution-detection block (prev vs new synthesis), `clustersProcessed++`.
5. Keep the weekly-rollup call. Return `{ clusters: clustersProcessed, evolved, proto: 0 }` (keep the `proto` key for callers).

**Step 5: One-shot rebuild guard + always-on orphan cleanup.** Two mechanisms remove the old embedding clusters so the iPad never shows stale `${concept}-${hash}` buckets.

At the **start** of `synthesizeTopics()` (after the `isAvailable` check), the explicit one-shot wipe:
```ts
if (process.env.SELENE_REBUILD_CLUSTERS === '1') {
  db.exec('DELETE FROM topic_note_links; DELETE FROM topic_clusters;');
  log.info('Full cluster rebuild: wiped topic_clusters + topic_note_links');
}
```

At the **end** of the build (after the category loop), self-heal so the workflow does NOT depend on anyone remembering the flag — if the scheduled prod agent fires before the one-shot, it would otherwise leave the old embedding clusters as `is_proto=0` orphans in the browse view:
```ts
const keepSlugs = CATEGORIES.map(slugForCategory);
const placeholders = keepSlugs.map(() => '?').join(',');
const orphanIds = (db.prepare(
  `SELECT id FROM topic_clusters WHERE slug NOT IN (${placeholders})`
).all(...keepSlugs) as Array<{ id: string }>).map((r) => r.id);
for (const oid of orphanIds) {
  db.prepare('DELETE FROM topic_note_links WHERE topic_id = ?').run(oid);
  db.prepare('DELETE FROM topic_clusters WHERE id = ?').run(oid);
}
if (orphanIds.length) log.info({ removed: orphanIds.length }, 'Removed non-category (orphan) clusters');
```
(The `placeholders` list is built from a fixed-length constant array, so the SQL is still effectively parameterized — no user input is interpolated. Category slugs like `personal-growth` cannot collide with the old `${concept}-${hash}` slugs, so this only ever deletes legacy clusters.)

**Step 6: Type-check + smoke run on a prod COPY (never live).** `npx tsc --noEmit` → clean. Then run on a throwaway copy using the safe mechanism from Conventions (a `SELENE_ENV=development` run would instead hit the `dev-seed` fixtures, whose `category` population is unverified — so use a prod copy):
```bash
cp ~/selene-data/selene.db /tmp/selene-smoke.db
SELENE_ENV=production SELENE_DB_PATH=/tmp/selene-smoke.db SELENE_REBUILD_CLUSTERS=1 \
  npx ts-node src/workflows/synthesize-topics.ts
```
Expect a log line per non-empty category and a sane cluster count. (Full validation is Task 4.)

**Step 7: `synthesis-reviewer` subagent review.** Dispatch the `synthesis-reviewer` agent on the `synthesize-topics.ts` diff (workflow + DB contract + Ollama prompt). Address findings.

**Step 8: Commit.**
```bash
git add src/workflows/synthesize-topics.ts
git commit -m "feat(clustering): derive topic_clusters from categories, drop embedding clustering"
```

---

## Task 4: Validate end-to-end on a prod COPY (never the live DB)

**Step 1: Make a writable copy of prod.**
```bash
cp ~/selene-data/selene.db /tmp/selene-rebuild-test.db
```

**Step 2: Point the DB env at the copy — safely.** No config change is needed: `config.ts` already honors `SELENE_DB_PATH` (it "always wins"), and `SELENE_ENV=production` both applies the real `testRunFilter` guard and skips the `.env.development` override. **First confirm the path resolves to `/tmp`, not prod**, then run in order:
```bash
SELENE_ENV=production SELENE_DB_PATH=/tmp/selene-rebuild-test.db \
  npx ts-node -e "import('./src/lib/config').then(m => console.log('DB =>', m.config.dbPath))"
# must print: DB => /tmp/selene-rebuild-test.db   (NEVER ~/selene-data/selene.db)

SELENE_ENV=production SELENE_DB_PATH=/tmp/selene-rebuild-test.db \
  npx ts-node scripts/backfill-categories.ts
SELENE_ENV=production SELENE_DB_PATH=/tmp/selene-rebuild-test.db SELENE_REBUILD_CLUSTERS=1 \
  npx ts-node src/workflows/synthesize-topics.ts
```

**Step 3: Eyeball the result exactly as the app sees it.**
```bash
sqlite3 /tmp/selene-rebuild-test.db \
  "SELECT name, note_count FROM topic_clusters WHERE is_proto = 0 ORDER BY note_count DESC;"
```
Expect: ~8 content-themed categories, no "E-Ink Empowerment", sane counts. Verify multi-membership:
```bash
sqlite3 /tmp/selene-rebuild-test.db \
  "SELECT note_id, COUNT(*) c FROM topic_note_links GROUP BY note_id HAVING c > 1 LIMIT 5;"
```
Expect: at least one note in >1 category.

**Step 4: Iterate** the synthesis member-cap / any naming details until the list looks right. Re-run Steps 1–3 on a fresh copy as needed. **Do not** point any of this at `~/selene-data/selene.db`.

---

## Task 5: Docs wrap-up (user-facing change)

**Step 1:** Create/update `docs/guides/features/notes-browse.md` (from `_TEMPLATE.md`) describing the category-based Notes browse: how notes are grouped (8 content categories), multi-category membership, date-as-reference, and that `capture_type` is metadata only. Verify every claim against the final code.

**Step 2:** Add/confirm its link in the hub `docs/USER-EXPERIENCE.md`.

**Step 3:** Move the design doc to "Done" in `docs/plans/INDEX.md`; check the `docs`-stage box in `BRANCH-STATUS.md`.

**Step 4: Commit.**
```bash
git add docs/
git commit -m "docs(clustering): notes-browse guide + design doc done"
```

---

## Production rollout (after merge — not part of branch work)

After merge + prod deploy (compiled `dist/`), run once against prod: `node dist/scripts/backfill-categories.js` then `SELENE_REBUILD_CLUSTERS=1 node dist/workflows/synthesize-topics.js`, then verify on the iPad. The scheduled `com.selene.prod.synthesize-topics` agent maintains clusters in place thereafter (no rebuild flag).

---

## Acceptance criteria (from the design)

- [ ] After backfill, every note has a `category` (uncategorized count logged, none silently dropped).
- [ ] `topic_clusters` = one row per non-empty category, named from the fixed list (no source/format words).
- [ ] On the prod copy, the 104-note e-ink bucket is gone; e-ink spreads across content categories.
- [ ] ≥1 note appears under multiple categories (multi-membership).
- [ ] Drafts + e-ink grouped by the same mechanism.
- [ ] All Task 1 unit tests pass; `synthesis-reviewer` approves Task 3.
