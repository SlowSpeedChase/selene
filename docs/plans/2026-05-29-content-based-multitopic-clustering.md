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
- **Never write to the live prod DB during testing.** Validation (Task 4) runs on a `cp` of prod in `/tmp`.
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

**Files:**
- Create: `scripts/backfill-categories.ts`

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
    WHERE pn.category IS NULL
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

**Step 3: Widen `generateSynthesis`.** Change its `members` parameter type from `NoteEmbedding[]` to a structural type it actually uses, e.g. `Array<{ title: string; essence: string | null }>`, so `CategoryMember[]` is accepted. Cap members passed to the prompt (e.g. first 40) to bound prompt size; `log.info` when capped (no silent truncation).

**Step 4: Replace the build loop.** Rewrite `synthesizeTopics()` so it:
1. (One-shot guard — see Step 5) optionally wipes the tables.
2. Loads classified notes; logs `uncategorizedNoteIds(...)` length (no silent drops).
3. Computes `const groups = groupNotesByCategory(notes)` and a `Map` from noteId → member for synthesis.
4. For each `cat` in `CATEGORIES` with `groups.get(cat)!.length >= 1`:
   - `slug = slugForCategory(cat)`, `name = cat`.
   - Look up existing row by slug (reuse existing pattern) → stable `id` or `randomUUID()`.
   - **Delta-guard:** only regenerate `synthesis_text` when the member set changed since last run (reuse the existing `synthesis_updated_at` vs link `added_at` comparison, adapted: compare current member set to existing links).
   - Upsert `topic_clusters` (`is_proto = 0`, `note_count = members.length`) via the existing `INSERT … ON CONFLICT(slug) DO UPDATE`.
   - **Reconcile** `topic_note_links` (insert missing, delete stale), then set `note_count`:
     ```ts
     const desired = new Set(noteIds);
     const existingLinks = db.prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?')
       .all(id) as Array<{ note_id: number }>;
     for (const { note_id } of existingLinks) {
       if (!desired.has(note_id)) {
         db.prepare('DELETE FROM topic_note_links WHERE topic_id = ? AND note_id = ?').run(id, note_id);
       }
     }
     for (const noteId of noteIds) {
       db.prepare('INSERT OR IGNORE INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)')
         .run(id, noteId, now);
     }
     db.prepare('UPDATE topic_clusters SET note_count = ? WHERE id = ?').run(noteIds.length, id);
     ```
   - Keep the existing evolution-detection block (prev vs new synthesis).
5. Keep the weekly-rollup call. Return `{ clusters, evolved, proto }` with `proto = 0` (keep the key for callers).

**Step 5: One-shot full-rebuild guard.** At the very start of `synthesizeTopics()` (after the `isAvailable` check), support the clean transition from old embedding clusters:
```ts
if (process.env.SELENE_REBUILD_CLUSTERS === '1') {
  db.exec('DELETE FROM topic_note_links; DELETE FROM topic_clusters;');
  log.info('Full cluster rebuild: wiped topic_clusters + topic_note_links');
}
```
Normal scheduled runs (flag unset) upsert + reconcile in place.

**Step 6: Type-check + run.** `npx tsc --noEmit` → clean. Then on a dev/copy DB: `SELENE_ENV=development SELENE_REBUILD_CLUSTERS=1 npx ts-node src/workflows/synthesize-topics.ts`. Expect a log line per non-empty category and a sane cluster count.

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

**Step 2: Point the DB env at the copy.** Confirm the exact override in `src/lib/config.ts` (the spike used a `SPIKE_DB`-style env var; replicate that mechanism, add a temporary one to `config.ts` if none exists, or symlink). Use a **prod-like** `SELENE_ENV` so `testRunFilter` applies the real guard. Then run, in order:
```bash
npx ts-node scripts/backfill-categories.ts
SELENE_REBUILD_CLUSTERS=1 npx ts-node src/workflows/synthesize-topics.ts
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
