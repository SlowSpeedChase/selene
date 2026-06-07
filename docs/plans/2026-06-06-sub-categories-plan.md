# Sub-categories (Phase 1) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a second taxonomy level (sub-categories) under the fixed 8 categories — deterministic, git-seeded, zero drift risk — so the Obsidian constellation gains a navigable cluster → sub-cluster → note level.

**Architecture:** A git-tracked seed config (`config/sub-taxonomy.ts`) maps each of the 8 categories → its sub-category names (git *is* the precious layer; a fact-store `rebuild` can't touch it). `process-llm.ts` makes a per-note *closed-set* sub-category choice (one extra Ollama call, only for notes that landed in ≥1 category) stored as a JSON map on `processed_notes.sub_categories`. `synthesize-topics.ts` materializes sub-clusters as `topic_clusters` rows with `parent_id` set + a namespaced slug (`health-body/running`) in a **separate pass after the category loop** (decoupled from the `unchanged` short-circuit), structural-only (no LLM `synthesis_text`). The existing `constellation.ts` `parent_id` join then emits `parent::` edges automatically. A one-shot backfill applies sub-cats to the existing corpus.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (mistral via `generate()`), Jest. Source design: `docs/plans/2026-05-31-sub-categories-design.md`.

---

## Execution note (path correction)

The seed config lives at **`src/config/sub-taxonomy.ts`** (NOT `config/sub-taxonomy.ts` as originally drafted). Reason: `tsconfig.json` sets `rootDir: "./src"`, so a real `src/` file importing a sibling under `/config` errors with `TS6059: not under rootDir`. Relocating under `src/config/` keeps it git-tracked (still the precious layer surviving a fact-store `rebuild`) and makes its exhaustiveness guard fire in the main `tsc --noEmit`. Import paths: from `src/config/sub-taxonomy.ts` use `../lib/prompts`; from `src/lib/*` use `../config/sub-taxonomy`; from `src/workflows/*` use `../config/sub-taxonomy`.

## Design decisions baked in (from design + adversarial review)

These were settled before planning — do not re-litigate:

1. **Sub-cluster upsert is a SEPARATE pass AFTER the `for (const cat of CATEGORIES)` loop**, not nested inside it. The category loop has an `unchanged` short-circuit (`synthesize-topics.ts:177-182`) that `continue`s when *category-level* membership is stable. That guard never reads `sub_categories`, so nested sub-cluster code would silently never run on the steady-state corpus. The separate pass looks up each category cluster's id by slug for `parent_id`.
2. **Ph1 sub-clusters carry NO `synthesis_text`** — the constellation join only needs `name` + `parent_id`. This makes the pass pure, cheap DB work, safe to re-run with no delta guard. (LLM synthesis for sub-clusters is a Phase 2 concern.)
3. **One combined sub-choice LLM call per note**, returning a `{category: subName|"none"}` map. **Skip the call entirely** when the note matched zero valid categories.
4. **Orphan-cleanup uses a structural predicate** `isValidClusterSlug(slug, catSlugs)`: keep if `slug ∈ 8` OR `slug.split('/')[0] ∈ 8`. Safe because `slugForCategory` maps `[^a-z0-9]+ → -`, so no sub-name yields a `/` — the separator is unambiguous.
5. **New pure helpers live in `src/lib/category-clusters.ts`** next to `slugForCategory`/`groupNotesByCategory` — same domain, no new file. The seed *data* lives in `config/sub-taxonomy.ts`.
6. **Backfill is a first-class task** (existing 295 notes need sub-cats for the feature to have visible value) — do not lean on `rebuild`. Claude writes/tests on dev; the operator runs it.

## Verified code anchors (current `main`, checked 2026-06-06)

- `src/lib/category-clusters.ts` — `slugForCategory`, `normalizeToValidCategories`, `validCategoriesFor` (private), `groupNotesByCategory`, `uncategorizedNoteIds`, `extractCategoryFields`. `CATEGORIES` imported from `./prompts`.
- `src/lib/synthesis-db.ts:23-40` — `topic_clusters` already has `parent_id TEXT REFERENCES topic_clusters(id)` and a unique `slug`; `topic_note_links(topic_id, note_id, added_at)`. **No schema migration to these tables needed.**
- `src/lib/constellation.ts:60-69` — `loadClusters` already `LEFT JOIN topic_clusters p ON p.id = c.parent_id` and emits `parent::` for any cluster with a parent. Comment at line 32: "future-proof for sub-clusters." **Mostly just starts working.**
- `src/workflows/process-llm.ts:19-25` — idempotent `ALTER TABLE processed_notes ADD COLUMN ...` migration block (pattern to follow). `:88-103` — the `INSERT OR REPLACE INTO processed_notes` write. `:56-61` — `EXTRACT_PROMPT` call + `generate()`.
- `src/workflows/synthesize-topics.ts:24-43` — `loadClassifiedNotes` SELECT (add `pn.sub_categories`). `:132-248` — category loop. `:139-147` — empty-category cleanup branch. `:177-182` — the `unchanged` short-circuit. `:250-262` — orphan-cleanup guard.
- `src/lib/prompts.ts:1-12` — `CATEGORIES` (the fixed 8) + `Category` type.

## Pre-flight (once, before Task 1)

Worktree already created at `.worktrees/sub-categories` (branch `feat/sub-categories`), baseline green (197 tests). Copy the branch-status template:

```bash
cp templates/BRANCH-STATUS.md .worktrees/sub-categories/BRANCH-STATUS.md 2>/dev/null || cp templates/DESIGN-DOC-TEMPLATE.md /dev/null
```
(If `templates/BRANCH-STATUS.md` is absent, skip — it's tracking scaffolding, not a build artifact.)

All `npx jest` / `npx tsc` commands below run from the worktree root.

---

### Task 1: Seed sub-taxonomy config

**Files:**
- Create: `config/sub-taxonomy.ts`
- Test: `src/lib/sub-taxonomy.test.ts`

**Step 1 — Write the failing test:**

```typescript
import { CATEGORIES } from '../lib/prompts';
import { SUB_TAXONOMY, subCategoriesFor } from '../../config/sub-taxonomy';

describe('sub-taxonomy seed config', () => {
  it('has an entry for every one of the 8 categories', () => {
    for (const cat of CATEGORIES) {
      expect(Array.isArray(SUB_TAXONOMY[cat])).toBe(true);
    }
    expect(Object.keys(SUB_TAXONOMY).sort()).toEqual([...CATEGORIES].sort());
  });

  it('subCategoriesFor returns the seed list for a known category', () => {
    expect(subCategoriesFor('Health & Body')).toEqual(SUB_TAXONOMY['Health & Body']);
  });

  it('subCategoriesFor returns [] for an unknown category', () => {
    expect(subCategoriesFor('Not A Category')).toEqual([]);
  });

  it('has no duplicate sub-categories within a category', () => {
    for (const cat of CATEGORIES) {
      const list = SUB_TAXONOMY[cat];
      expect(new Set(list).size).toBe(list.length);
    }
  });
});
```

**Step 2 — Run, expect FAIL** (`Cannot find module '../../config/sub-taxonomy'`):
`npx jest sub-taxonomy.test.ts`

**Step 3 — Implement `config/sub-taxonomy.ts`:**

```typescript
import { CATEGORIES, type Category } from '../src/lib/prompts';

/**
 * Seed sub-taxonomy: each of the 8 fixed categories → its closed-set sub-categories.
 *
 * THIS FILE IS THE PRECIOUS LAYER. Git tracks it, so a fact-store `rebuild` of
 * selene.db cannot wipe it. To curate the taxonomy, edit this file (and re-run the
 * backfill). All names here are `firm` by declaration (Phase 2 firmness gradient).
 *
 * Keep lists SHORT and content-free-ish — these are facets, not source buckets.
 */
export const SUB_TAXONOMY: Record<Category, string[]> = {
  'Personal Growth':        ['Habits', 'Reflection', 'Learning', 'Identity'],
  'Relationships & Social': ['Family', 'Friends', 'Partner', 'Community'],
  'Health & Body':          ['Running', 'Sleep', 'Diet', 'Strength', 'Mental Health'],
  'Projects & Tech':        ['Selene', 'Side Projects', 'Tooling', 'Infrastructure'],
  'Career & Work':          ['Job', 'Skills', 'Networking', 'Finances'],
  'Creativity & Expression':['Writing', 'Music', 'Art', 'Ideas'],
  'Politics & Society':     ['Policy', 'Economics', 'Culture', 'Environment'],
  'Daily Systems':          ['Planning', 'Errands', 'Routines', 'Tools'],
};

// Compile-time guard: every category has a key (TS errors if CATEGORIES drifts).
const _exhaustive: Record<Category, string[]> = SUB_TAXONOMY;
void _exhaustive;
void CATEGORIES;

export function subCategoriesFor(category: string): string[] {
  return (SUB_TAXONOMY as Record<string, string[]>)[category] ?? [];
}
```

> **v0 taxonomy — locked with the user 2026-06-06.** These are an intentional starting point, NOT a final answer: the Task 8 `--report` instrument measures per-category `none%` against the real corpus, and the user tightens the lists by editing this one file + re-running the backfill. The mechanism is the deliverable; the taxonomy self-corrects via the measure-and-edit loop. Do not block on "are these the perfect names" — ship v0, measure, iterate.

**Step 4 — Run, expect PASS:** `npx jest sub-taxonomy.test.ts`

**Step 5 — Commit:**
```bash
git add config/sub-taxonomy.ts src/lib/sub-taxonomy.test.ts
git commit -m "feat(sub-cats): git-tracked seed sub-taxonomy config"
```

---

### Task 2: Slug + orphan-guard helpers (the landmine)

**Files:**
- Modify: `src/lib/category-clusters.ts`
- Test: `src/lib/category-clusters.test.ts` (extend existing)

**Step 1 — Write the failing tests:**

```typescript
import { subSlug, isValidClusterSlug, slugForCategory } from './category-clusters';
import { CATEGORIES } from './prompts';

describe('subSlug', () => {
  it('namespaces sub under category slug', () => {
    expect(subSlug('Health & Body', 'Running')).toBe('health-body/running');
  });
});

describe('isValidClusterSlug (orphan-cleanup guard)', () => {
  const cats = CATEGORIES.map(slugForCategory);
  it('keeps an exact category slug', () => {
    expect(isValidClusterSlug('health-body', cats)).toBe(true);
  });
  it('KEEPS a valid sub-slug (landmine: must not be deleted)', () => {
    expect(isValidClusterSlug('health-body/running', cats)).toBe(true);
  });
  it('DELETES a true orphan (old concept-hash slug)', () => {
    expect(isValidClusterSlug('running-a1b2c3', cats)).toBe(false);
  });
  it('DELETES a sub-slug whose parent is not a real category', () => {
    expect(isValidClusterSlug('bogus-parent/running', cats)).toBe(false);
  });
});
```

**Step 2 — Run, expect FAIL** (`subSlug is not a function`): `npx jest category-clusters.test.ts`

**Step 3 — Add to `src/lib/category-clusters.ts`:**

```typescript
/** Namespaced slug for a sub-cluster, e.g. "health-body/running". */
export function subSlug(category: string, sub: string): string {
  return `${slugForCategory(category)}/${slugForCategory(sub)}`;
}

/**
 * True if a topic_clusters slug is legitimate: either one of the 8 category slugs,
 * or a sub-slug `<categorySlug>/<sub>` whose prefix is a real category slug.
 * Used by synthesize-topics orphan cleanup. NOTE: slugForCategory maps any
 * non-alphanumeric run to '-', so a sub-name can never introduce a stray '/'.
 */
export function isValidClusterSlug(slug: string, categorySlugs: string[]): boolean {
  const set = new Set(categorySlugs);
  if (set.has(slug)) return true;
  const slash = slug.indexOf('/');
  if (slash === -1) return false;
  return set.has(slug.slice(0, slash));
}
```

**Step 4 — Run, expect PASS:** `npx jest category-clusters.test.ts`

**Step 5 — Commit:**
```bash
git add src/lib/category-clusters.ts src/lib/category-clusters.test.ts
git commit -m "feat(sub-cats): subSlug + isValidClusterSlug orphan guard helpers"
```

---

### Task 3: Closed-set sub-category prompt + parser

**Files:**
- Modify: `src/lib/category-clusters.ts`
- Test: `src/lib/category-clusters.test.ts`

**Step 1 — Write the failing tests:**

```typescript
import { parseSubCategories, buildSubCategoryPrompt } from './category-clusters';

describe('parseSubCategories (closed-set)', () => {
  const allowed = { 'Health & Body': ['Running', 'Sleep'], 'Projects & Tech': ['Selene'] };

  it('keeps only values in that category seed list', () => {
    const r = parseSubCategories('{"Health & Body":"Running","Projects & Tech":"Nope"}', allowed);
    expect(r).toEqual({ 'Health & Body': 'Running' });
  });
  it('drops "none"', () => {
    expect(parseSubCategories('{"Health & Body":"none"}', allowed)).toEqual({});
  });
  it('ignores categories not in the allowed map', () => {
    expect(parseSubCategories('{"Career & Work":"Job"}', allowed)).toEqual({});
  });
  it('returns {} on malformed JSON', () => {
    expect(parseSubCategories('not json', allowed)).toEqual({});
  });
  it('finds JSON embedded in chatty output', () => {
    expect(parseSubCategories('Sure! {"Health & Body":"Sleep"} ok', allowed))
      .toEqual({ 'Health & Body': 'Sleep' });
  });
});

describe('buildSubCategoryPrompt', () => {
  it('lists each assigned category with its seed options', () => {
    const p = buildSubCategoryPrompt('T', 'C', { 'Health & Body': ['Running', 'Sleep'] });
    expect(p).toContain('Health & Body');
    expect(p).toContain('Running');
    expect(p).toContain('none');
  });
});
```

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement in `src/lib/category-clusters.ts`:**

```typescript
/** Build the closed-set sub-category prompt for one note over its assigned categories. */
export function buildSubCategoryPrompt(
  title: string,
  content: string,
  allowedByCategory: Record<string, string[]>,
): string {
  const lines = Object.entries(allowedByCategory)
    .map(([cat, subs]) => `- ${cat}: ${[...subs, 'none'].join(' | ')}`)
    .join('\n');
  return `For each category below, pick the ONE best-fitting sub-category from its list, or "none".
Choose ONLY from the given options — do not invent sub-categories.

Title: ${title}
Note: ${content}

Categories and their allowed sub-categories:
${lines}

Reply with JSON mapping each category to one chosen value, e.g. {"Health & Body":"Running"}:`;
}

/**
 * Parse the sub-category LLM response. Closed-set: a value is kept only if it
 * exactly matches an entry in that category's allowed list. "none"/invalid/unknown
 * categories are dropped. Returns a category→sub map (omits unassigned categories).
 */
export function parseSubCategories(
  response: string,
  allowedByCategory: Record<string, string[]>,
): Record<string, string> {
  const match = response.match(/\{[\s\S]*\}/);
  if (!match) return {};
  let parsed: unknown;
  try { parsed = JSON.parse(match[0]); } catch { return {}; }
  if (parsed === null || typeof parsed !== 'object') return {};
  const out: Record<string, string> = {};
  for (const [cat, allowed] of Object.entries(allowedByCategory)) {
    const v = (parsed as Record<string, unknown>)[cat];
    if (typeof v === 'string' && allowed.includes(v)) out[cat] = v;
  }
  return out;
}
```

**Step 4 — Run, expect PASS.**

**Step 5 — Commit:**
```bash
git add src/lib/category-clusters.ts src/lib/category-clusters.test.ts
git commit -m "feat(sub-cats): closed-set sub-category prompt + parser"
```

---

### Task 4: groupNotesBySubCategory

**Files:**
- Modify: `src/lib/category-clusters.ts`
- Test: `src/lib/category-clusters.test.ts`

**Step 1 — Write the failing test** (proves cross-parent multi-membership):

```typescript
import { groupNotesBySubCategory } from './category-clusters';

describe('groupNotesBySubCategory', () => {
  it('groups a note under a sub-cat for EACH parent it belongs to', () => {
    const notes = [{
      noteId: 1,
      category: 'Health & Body',
      crossRefs: ['Projects & Tech'],
      subCategories: { 'Health & Body': 'Running', 'Projects & Tech': 'Side Projects' },
    }];
    const g = groupNotesBySubCategory(notes);
    expect(g.get('Health & Body')?.get('Running')).toEqual([1]);
    expect(g.get('Projects & Tech')?.get('Side Projects')).toEqual([1]);
  });

  it('omits a category whose sub-cat is unassigned', () => {
    const notes = [{ noteId: 2, category: 'Health & Body', crossRefs: [], subCategories: {} }];
    const g = groupNotesBySubCategory(notes);
    expect(g.get('Health & Body')?.size ?? 0).toBe(0);
  });

  it('ignores a sub-cat for a category the note is NOT actually in', () => {
    const notes = [{ noteId: 3, category: 'Health & Body', crossRefs: [],
      subCategories: { 'Career & Work': 'Job' } }];
    const g = groupNotesBySubCategory(notes);
    expect(g.get('Career & Work')?.size ?? 0).toBe(0);
  });
});
```

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement** (reuse `validCategoriesFor`; export the new type):

```typescript
export interface SubCategorizableNote extends CategorizableNote {
  subCategories: Record<string, string>;
}

/**
 * For each note, for each VALID category it belongs to, place it under the sub-cat
 * assigned for that category (if any). Returns category → (subName → noteIds[]).
 * A note's sub-cat for a category it isn't actually in is ignored (guards bad LLM maps).
 */
export function groupNotesBySubCategory(
  notes: SubCategorizableNote[],
): Map<string, Map<string, number[]>> {
  const groups = new Map<string, Map<string, Set<number>>>();
  for (const note of notes) {
    const cats = validCategoriesFor(note); // private helper already in this file
    for (const cat of cats) {
      const sub = note.subCategories[cat];
      if (!sub) continue;
      if (!groups.has(cat)) groups.set(cat, new Map());
      const subMap = groups.get(cat)!;
      if (!subMap.has(sub)) subMap.set(sub, new Set());
      subMap.get(sub)!.add(note.noteId);
    }
  }
  const out = new Map<string, Map<string, number[]>>();
  for (const [cat, subMap] of groups) {
    const m = new Map<string, number[]>();
    for (const [sub, set] of subMap) m.set(sub, [...set]);
    out.set(cat, m);
  }
  return out;
}
```

**Step 4 — Run, expect PASS.**

**Step 5 — Commit:**
```bash
git add src/lib/category-clusters.ts src/lib/category-clusters.test.ts
git commit -m "feat(sub-cats): groupNotesBySubCategory (cross-parent multi-membership)"
```

---

### Task 5: process-llm — persist the per-note sub-category choice

**Files:**
- Modify: `src/workflows/process-llm.ts`
- Test: `src/workflows/process-llm.subcats.test.ts` (new, focused)

**Step 1 — Write the failing test** (pure assembly logic, no live Ollama). Extract a small pure helper so it's testable without a model:

```typescript
import { buildAllowedFor } from './process-llm';

describe('buildAllowedFor', () => {
  it('returns seed lists only for the categories the note landed in', () => {
    const allowed = buildAllowedFor('Health & Body', ['Projects & Tech']);
    expect(Object.keys(allowed).sort()).toEqual(['Health & Body', 'Projects & Tech']);
    expect(allowed['Health & Body'].length).toBeGreaterThan(0);
  });
  it('returns {} when there are no valid categories', () => {
    expect(buildAllowedFor(null, [])).toEqual({});
  });
});
```

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement.** In `process-llm.ts`:

(a) Add the column migration alongside the existing ones (after line 25):
```typescript
try {
  db.exec('ALTER TABLE processed_notes ADD COLUMN sub_categories TEXT');
} catch { /* column already exists */ }
```

(b) Add the pure helper (near top-level, exported):
```typescript
import { normalizeToValidCategories, buildSubCategoryPrompt, parseSubCategories } from '../lib/category-clusters';
import { subCategoriesFor } from '../../config/sub-taxonomy';

/** Seed lists keyed by each valid category the note actually landed in. */
export function buildAllowedFor(category: string | null, crossRefs: string[]): Record<string, string[]> {
  const cats = new Set<string>();
  for (const c of normalizeToValidCategories(category)) cats.add(c);
  for (const cr of crossRefs) for (const c of normalizeToValidCategories(cr)) cats.add(c);
  const out: Record<string, string[]> = {};
  for (const c of cats) {
    const subs = subCategoriesFor(c);
    if (subs.length) out[c] = subs;
  }
  return out;
}
```

(c) In the per-note loop, AFTER `extracted` is finalized and BEFORE the `INSERT OR REPLACE`, compute the sub-map (skip the call when no categories):
```typescript
let subCategories: Record<string, string> = {};
const allowed = buildAllowedFor(extracted.category || null, extracted.cross_ref_categories || []);
if (Object.keys(allowed).length > 0) {
  try {
    const subPrompt = buildSubCategoryPrompt(note.title, note.content, allowed);
    const subResp = await generate(subPrompt, { temperature: 0 });
    subCategories = parseSubCategories(subResp, allowed);
  } catch (err) {
    log.warn({ noteId: note.id, err }, 'Sub-category classification failed; leaving empty');
  }
}
```

(d) Add `sub_categories` to the INSERT column list + values:
```typescript
// column list: ...energy_level, category, cross_ref_categories, sub_categories, processed_at)
// values: ... JSON.stringify(extracted.cross_ref_categories || []), JSON.stringify(subCategories), new Date().toISOString()
```

> Verify `generate`'s options signature accepts `{ temperature }` (it's used that way in `synthesize-topics.ts:222`). Keep the SAME model — no model override.

**Step 4 — Run, expect PASS:** `npx jest process-llm.subcats.test.ts`

**Step 5 — Commit:**
```bash
git add src/workflows/process-llm.ts src/workflows/process-llm.subcats.test.ts
git commit -m "feat(sub-cats): process-llm persists closed-set sub-category map"
```

---

### Task 6: synthesize-topics — sub-cluster pass + orphan fix + empty-category cleanup

**THE LOAD-BEARING TASK.** Read decisions #1, #2, #4 above before starting.

**Files:**
- Modify: `src/workflows/synthesize-topics.ts`
- Test: `src/workflows/synthesize-topics.subcats.db.test.ts` (new, DB-backed)

**Step 1 — Write the failing tests.** These three are mandatory; the first two are the traps an empty-DB test cannot catch.

```typescript
// Setup: in-memory/temp DB with synthesis schema, a few processed notes, then call synthesizeTopics()
// (mirror the harness in synthesize-topics' existing tests / synthesis-db tests).

describe('sub-cluster materialization', () => {
  it('TRAP: creates sub-clusters even when the parent category cluster is UNCHANGED', async () => {
    // Pre-seed a category cluster (slug "health-body") with stable membership AND
    // non-null synthesis_text so the `unchanged` short-circuit fires for it.
    // Notes already linked at category level; sub_categories set to {"Health & Body":"Running"}.
    await synthesizeTopics();
    const sub = db.prepare("SELECT * FROM topic_clusters WHERE slug = 'health-body/running'").get();
    expect(sub).toBeTruthy();
    expect((sub as any).parent_id).toBe(/* the health-body cluster id */);
    // note→sub link exists
    const links = db.prepare('SELECT COUNT(*) c FROM topic_note_links WHERE topic_id = ?').get((sub as any).id);
    expect((links as any).c).toBeGreaterThan(0);
  });

  it('TRAP: emptying a category removes its sub-clusters too (no dangling parent_id)', async () => {
    // Seed health-body + health-body/running, then reclassify all health notes away.
    await synthesizeTopics();
    expect(db.prepare("SELECT 1 FROM topic_clusters WHERE slug='health-body'").get()).toBeFalsy();
    expect(db.prepare("SELECT 1 FROM topic_clusters WHERE slug='health-body/running'").get()).toBeFalsy();
  });

  it('orphan cleanup keeps valid sub-slugs but deletes true orphans', async () => {
    // Insert a bogus 'running-a1b2c3' cluster + a real 'health-body/running'.
    await synthesizeTopics();
    expect(db.prepare("SELECT 1 FROM topic_clusters WHERE slug='running-a1b2c3'").get()).toBeFalsy();
    expect(db.prepare("SELECT 1 FROM topic_clusters WHERE slug='health-body/running'").get()).toBeTruthy();
  });
});
```

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement, in order:**

(a) Extend `CategoryMember` interface + `loadClassifiedNotes` SELECT to read `pn.sub_categories` and parse it:
```typescript
// interface: add  subCategories: Record<string, string>;
// SELECT: add  pn.sub_categories
// map: subCategories: (() => { try { return JSON.parse(r.sub_categories ?? '{}'); } catch { return {}; } })(),
```

(b) In the empty-category branch (`:139-147`), after deleting the category cluster, also delete its sub-clusters:
```typescript
// after deleting the category cluster row:
const catSlug = slug; // already in scope
const subRows = db.prepare("SELECT id FROM topic_clusters WHERE slug LIKE ?").all(`${catSlug}/%`) as Array<{id:string}>;
for (const s of subRows) {
  db.prepare('DELETE FROM topic_note_links WHERE topic_id = ?').run(s.id);
  db.prepare('DELETE FROM topic_clusters WHERE id = ?').run(s.id);
}
```

(c) **NEW separate pass, AFTER the `for (const cat of CATEGORIES)` loop closes (after line 248), BEFORE orphan cleanup (line 250).** Structural-only — no `generateSynthesis`:
```typescript
// --- Sub-cluster pass (decoupled from the category-loop `unchanged` short-circuit) ---
const subGroups = groupNotesBySubCategory(
  notes.map((n) => ({ noteId: n.noteId, category: n.category, crossRefs: n.crossRefs, subCategories: n.subCategories }))
);
for (const [cat, subMap] of subGroups) {
  const parent = db.prepare('SELECT id FROM topic_clusters WHERE slug = ?').get(slugForCategory(cat)) as { id: string } | undefined;
  if (!parent) continue; // category cluster absent (e.g. emptied) — skip its subs
  for (const [subName, noteIds] of subMap) {
    if (noteIds.length === 0) continue;
    const sslug = subSlug(cat, subName);
    const existing = db.prepare('SELECT id FROM topic_clusters WHERE slug = ?').get(sslug) as { id: string } | undefined;
    const sid = existing?.id ?? randomUUID();
    db.prepare(`
      INSERT INTO topic_clusters (id, name, slug, parent_id, note_count, is_proto, created_at)
      VALUES (?, ?, ?, ?, ?, 0, ?)
      ON CONFLICT(slug) DO UPDATE SET
        name = excluded.name, parent_id = excluded.parent_id, note_count = excluded.note_count, is_proto = 0
    `).run(sid, subName, sslug, parent.id, noteIds.length, now);
    // reconcile links (insert missing, delete stale) — mirror the category-level reconcile
    const desired = new Set(noteIds);
    for (const { note_id } of (db.prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?').all(sid) as Array<{note_id:number}>)) {
      if (!desired.has(note_id)) db.prepare('DELETE FROM topic_note_links WHERE topic_id = ? AND note_id = ?').run(sid, note_id);
    }
    for (const noteId of noteIds) {
      db.prepare('INSERT OR IGNORE INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)').run(sid, noteId, now);
    }
  }
}
```
> Also delete sub-clusters that have NO members this run (a sub-cat emptied but its parent survives). Add after the loop: query `slug LIKE '<eachCatSlug>/%'` for clusters whose slug wasn't upserted this run and `note_count` is now 0, OR simpler — fold into the structural orphan check by also removing sub-clusters with zero links. Implement the minimal version that makes the tests pass, then confirm with a "sub-cat emptied, parent kept" test if time allows.

(d) Replace the orphan-cleanup query (`:255-257`) with the structural predicate. Fetch all slugs, filter with `isValidClusterSlug`:
```typescript
const keepSlugs = CATEGORIES.map(slugForCategory);
const allClusters = db.prepare('SELECT id, slug FROM topic_clusters').all() as Array<{id:string; slug:string}>;
const orphanIds = allClusters.filter((c) => !isValidClusterSlug(c.slug, keepSlugs)).map((c) => c.id);
for (const oid of orphanIds) {
  db.prepare('DELETE FROM topic_note_links WHERE topic_id = ?').run(oid);
  db.prepare('DELETE FROM topic_clusters WHERE id = ?').run(oid);
}
```

(e) Add imports: `groupNotesBySubCategory`, `subSlug`, `isValidClusterSlug` from `../lib/category-clusters` (and ensure `randomUUID` already imported — it is).

**Step 4 — Run, expect PASS:** `npx jest synthesize-topics.subcats.db.test.ts`

**Step 5 — Commit:**
```bash
git add src/workflows/synthesize-topics.ts src/workflows/synthesize-topics.subcats.db.test.ts
git commit -m "feat(sub-cats): synthesize sub-clusters in a separate pass + structural orphan guard"
```

---

### Task 7: Constellation emits parent:: for sub-clusters

**Files:**
- Test: `src/lib/constellation.db.test.ts` (extend)
- Modify: only if the test reveals a gap (expected: none — the join is future-proofed)

**Step 1 — Write the failing test:**

```typescript
it('emits parent:: for a sub-cluster pointing at its category cluster', () => {
  // Insert category cluster "Health & Body" (id A) + sub-cluster "Running" with parent_id=A.
  const clusters = loadClusters(db);
  const running = clusters.find((c) => c.name === 'Running');
  expect(running?.parentName).toBe('Health & Body');
  // buildClusterNote(running) should contain a parent:: line
  expect(buildClusterNote({ name: 'Running' }, 'Health & Body')).toContain('parent::');
});
```

**Step 2 — Run.** If it PASSES immediately, that confirms the join needs no change — note that in the commit. If it fails, fix `constellation.ts` minimally.

**Step 3-4 — (only if needed) implement + re-run.**

**Step 5 — Commit:**
```bash
git add src/lib/constellation.db.test.ts src/lib/constellation.ts
git commit -m "test(sub-cats): constellation emits parent:: for sub-clusters"
```

---

### Task 8: Backfill + coverage report instrument

**Files:**
- Create: `scripts/backfill-sub-categories.ts`
- Test: `src/lib/backfill-sub-categories.test.ts` (test the pure selection/assembly + report aggregation, not the live model)

Pattern: mirror `scripts/backfill-categories.ts`. For each `processed_notes` row that has ≥1 valid category but `sub_categories IS NULL`, run the same `buildSubCategoryPrompt`/`parseSubCategories` path (reuse `buildAllowedFor` from process-llm) and UPDATE `sub_categories`. Respect `test_run` isolation; log progress; idempotent (skip already-filled rows).

**Two modes:**
- `--dry-run` — classify but do not write; useful to preview.
- `--report` — classify (or read existing `sub_categories`) and print a **per-category histogram of counts only** (each sub-category's note count + a `none` count + `none%`). NO note text in output — this is the guard-safe misfit measure the operator runs against prod. This is the "settle → measure → iterate" dial.

Extract a pure aggregator so the histogram is unit-testable without a model:
```typescript
// returns { [category]: { [sub|'none']: count } } from an array of {category-set, sub-map}
export function aggregateCoverage(
  rows: Array<{ categories: string[]; subCategories: Record<string, string> }>,
): Record<string, Record<string, number>>;
```

**Step 1 — Test** (pure): (a) row-selection predicate — "selects categorized notes with null sub_categories, skips filled ones, skips uncategorized"; (b) `aggregateCoverage` — a note categorized Health with sub Running counts 1 under Health/Running; a Health note with no sub counts 1 under Health/none.
**Step 2 — FAIL → Step 3 — implement → Step 4 — PASS.**
**Step 5 — Commit:** `feat(sub-cats): backfill + content-free coverage report`

> Claude runs this only against the **dev** DB to verify. The operator runs `--report` against prod (counts only — guard-safe).

---

### Task 9: Guard-safe sub-category coverage in inspect.ts

**Files:**
- Modify: `src/lib/inspect.ts` (+ its `CoverageReport` surface)
- Test: `src/lib/inspect.test.ts` (extend)

Add `subCategoryCoverage(db)` returning **counts only** (parent slug → sub-slug → count, plus per-category `none` count), wired into the existing `selene-inspect coverage` output. This gives the operator a standing, content-free prod read of taxonomy fit without running the LLM backfill — it reads whatever `sub_categories` already hold. Honor the file's invariant (line 4): "return ONLY schema, counts, and coverage numbers — never content."

**Step 1 — Test:** seed `processed_notes` with `category` + `sub_categories` JSON; assert the report yields the right counts and a `none` tally; assert no note text appears in the output object.
**Steps 2-4** as usual.
**Step 5 — Commit:** `feat(sub-cats): content-free sub-category coverage in selene-inspect`

---

### Task 10: Rebuild-safety regression

**Files:**
- Test: extend `src/lib/rebuild-core.db.test.ts` (or a new `*.db.test.ts`)

**Step 1 — Test:** given the git seed config + a re-derivation (process-llm assigns sub_categories → synthesize creates sub-clusters), Phase 1 sub-categories are reconstructed deterministically, and nothing human is lost (there is no human sub-cat data in Ph1 — assert sub-clusters reappear after a simulated wipe+rederive of `selene.db`).
**Steps 2-4** as usual.
**Step 5 — Commit:** `test(sub-cats): rebuild regenerates Phase 1 sub-clusters`

---

### Task 11: Wrap-up (verification + review + docs)

**Step 1 — Full gate** (from worktree root):
```bash
npx tsc --noEmit && npx jest
```
Expected: tsc clean; all suites pass (197 baseline + new). Use superpowers:verification-before-completion — paste real output, no "should pass."

**Step 2 — Ollama contract review.** A new prompt was added → dispatch the `ollama-dependency-reviewer` agent over `process-llm.ts` + the new prompt/parser. Address findings.

**Step 3 — Dev smoke** (real dev pipeline, not just units):
```bash
SELENE_ENV=development npx ts-node scripts/backfill-sub-categories.ts --dry-run
# then a real dev run: backfill → synthesize-topics → export-obsidian; eyeball sub-clusters + parent:: in the dev vault.
```

**Step 4 — Update guides** (verify every claim against the shipped code, per CLAUDE.md):
- `docs/guides/features/knowledge-constellation.md` — cluster → sub-cluster → note navigation.
- `docs/guides/features/synthesis-layer.md` — sub-cluster materialization + the seed config the user edits to curate.

**Step 5 — Docs/status:**
- Move the sub-categories design row in `docs/plans/INDEX.md` from Ready → Done (Phase 1; note Phase 2 remains).
- While there, fix the stale fact-store row (INDEX.md:49 still says "not yet merged" — it IS merged).
- Check the `docs`-stage box in `BRANCH-STATUS.md`.

**Step 6 — Finish the branch** with superpowers:finishing-a-development-branch (merge/PR decision).

---

## Acceptance criteria (from design — verify each at wrap-up)

- [ ] Git-tracked seed sub-taxonomy config maps each of the 8 categories → sub-categories. (Task 1)
- [ ] `process-llm.ts` assigns a closed-set sub-category (or none) per category, stored as a per-category JSON map on `processed_notes.sub_categories`. (Task 5)
- [ ] `synthesize-topics.ts` creates sub-cluster rows with `parent_id` + note→sub-cluster links, preserving category membership. (Task 6)
- [ ] Orphan-cleanup keeps valid sub-slugs and still deletes true orphans (regression-tested). (Tasks 2, 6)
- [ ] Constellation export emits `parent::` for sub-clusters with no new export code. (Task 7)
- [ ] A `rebuild` regenerates Phase 1 sub-categories deterministically (no human data lost). (Task 10)
- [ ] Misfit count is measurable per-category, content-free (operator-runnable on prod). (Tasks 8, 9)
- [ ] ADHD check: finer browsing without manual filing; deeper visual constellation; structure lives in the map.
- [ ] Scope: Phase 1 < 1 week.
```
