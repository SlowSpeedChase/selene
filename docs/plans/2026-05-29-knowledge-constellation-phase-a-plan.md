# Knowledge Constellation — Phase A Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Teach `src/workflows/export-obsidian.ts` to emit Dataview `parent::` relationship fields and per-cluster index notes, so the ExcaliBrain Obsidian plugin renders a navigable cluster↔note constellation from the existing synthesis tables.

**Architecture:** Read-only over the synthesis tables (`topic_clusters`, `topic_note_links`). Extract all new logic into **pure, unit-testable functions** (no db singleton) plus one thin DB reader tested against a temp SQLite DB. Notes gain inline `parent:: [[<cluster>]]` fields (one per cluster they belong to — multi-membership safe); each cluster gets a regenerated index note under a new `Constellation/` directory, carrying `parent:: [[<parent cluster>]]` only when `parent_id` is present (flat today, future-proof). Output is fully regenerated each run (idempotent → re-run safe).

**Tech Stack:** TypeScript, better-sqlite3, jest. Obsidian + ExcaliBrain 0.2.17 + Dataview for verification.

**Out of scope (Phase B, gated on a separate spike):** note↔note `friend::` edges from the empty `note_connections` table.

---

## Design decisions (resolved)

1. **Cluster index notes live in a new `Constellation/` dir**, regenerated wholesale each export run. Decoupled from the 8-category `Maps/` MOCs and from the pending #52 rollout. Reconciling `Constellation/` vs `Maps/` is a deferred follow-up (see Open Items).
2. **`parent::` is the ExcaliBrain default parent field** — emitting `parent:: [[Cluster]]` on a note makes the cluster its parent (so ExcaliBrain shows cluster→notes as children, note→cluster as parent). No plugin config needed.
3. **Multi-membership:** emit one `parent::` line per cluster the note links to. Today every note has exactly one; post-#52 some will have several. Same code path.
4. **Filenames:** cluster index note basename = `clusterNoteFilename(name)` — a punctuation-safe slug. `parent:: [[<basename>]]` must reference that exact basename so Dataview/ExcaliBrain resolves it.
5. **Idempotency:** the `Constellation/` notes and the note `parent::` block are deterministic functions of DB state — a re-run overwrites identically. No append, no dedup needed.

---

## Task 1: Pure helper — `clusterNoteFilename(name)`

**Files:**
- Modify: `src/workflows/export-obsidian.ts` (add exported helper near `createSlug`)
- Test: `src/workflows/export-obsidian.test.ts` (create)

**Step 1: Write the failing test**

```typescript
import { clusterNoteFilename } from './export-obsidian';

describe('clusterNoteFilename', () => {
  it('slugs punctuation and spaces into a wikilink-safe basename', () => {
    expect(clusterNoteFilename('Freelance Service & Architecture')).toBe('Freelance Service  Architecture');
  });
  it('collapses to a stable basename for ExcaliBrain wikilinks', () => {
    expect(clusterNoteFilename('AI / Metadata Tools')).toBe('AI  Metadata Tools');
  });
  it('never returns an empty string', () => {
    expect(clusterNoteFilename('!!!').length).toBeGreaterThan(0);
  });
});
```

> Note: decide the exact transform when writing the test — the rule is "strip characters illegal in filenames / that break `[[wikilinks]]` (`[`, `]`, `/`, `\`, `:`, `#`, `^`, `|`), keep spaces, trim". Adjust the expected strings to match the rule you implement. Keep it reversible-by-eye (don't lowercase — cluster names are human-facing node labels).

**Step 2: Run test to verify it fails**

Run: `cd .worktrees/knowledge-constellation && npx jest export-obsidian -t clusterNoteFilename`
Expected: FAIL ("clusterNoteFilename is not a function").

**Step 3: Write minimal implementation**

```typescript
const WIKILINK_UNSAFE = /[[\]/\\:#^|]/g;
export function clusterNoteFilename(name: string): string {
  const cleaned = name.replace(WIKILINK_UNSAFE, ' ').replace(/\s+/g, ' ').trim();
  return cleaned.length > 0 ? cleaned : 'cluster';
}
```

**Step 4: Run test to verify it passes**

Run: `npx jest export-obsidian -t clusterNoteFilename`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/workflows/export-obsidian.ts src/workflows/export-obsidian.test.ts
git commit -m "feat(constellation): wikilink-safe cluster filename helper"
```

---

## Task 2: Pure helper — `buildParentFields(clusterNames)`

**Files:**
- Modify: `src/workflows/export-obsidian.ts`
- Test: `src/workflows/export-obsidian.test.ts`

**Step 1: Write the failing test**

```typescript
import { buildParentFields } from './export-obsidian';

describe('buildParentFields', () => {
  it('emits one parent:: line per cluster (multi-membership)', () => {
    expect(buildParentFields(['Relationships', 'Creativity'])).toBe(
      'parent:: [[Relationships]]\nparent:: [[Creativity]]'
    );
  });
  it('returns empty string when a note belongs to no cluster', () => {
    expect(buildParentFields([])).toBe('');
  });
  it('passes names through clusterNoteFilename so links resolve', () => {
    expect(buildParentFields(['AI / Tools'])).toBe('parent:: [[AI  Tools]]');
  });
});
```

**Step 2: Run → FAIL.** `npx jest export-obsidian -t buildParentFields`

**Step 3: Implement**

```typescript
export function buildParentFields(clusterNames: string[]): string {
  return clusterNames
    .map((n) => `parent:: [[${clusterNoteFilename(n)}]]`)
    .join('\n');
}
```

**Step 4: Run → PASS.**

**Step 5: Commit** `feat(constellation): build parent:: dataview fields for a note`

---

## Task 3: Pure helper — `buildClusterNote(cluster, parentName?)`

**Files:** same module + test.

**Step 1: Failing test**

```typescript
import { buildClusterNote } from './export-obsidian';

describe('buildClusterNote', () => {
  it('renders a cluster index note with type + title, no parent when root', () => {
    const md = buildClusterNote({ name: 'Relationships' });
    expect(md).toContain('type: cluster');
    expect(md).toContain('# Relationships');
    expect(md).not.toContain('parent::');
  });
  it('emits parent:: when the cluster has a parent (future hierarchy)', () => {
    const md = buildClusterNote({ name: 'Dating' }, 'Relationships');
    expect(md).toContain('parent:: [[Relationships]]');
  });
});
```

**Step 2: Run → FAIL.**

**Step 3: Implement** (mirror existing frontmatter style in `export-obsidian.ts`)

```typescript
export function buildClusterNote(
  cluster: { name: string },
  parentName?: string
): string {
  const parts: string[] = ['---', 'type: cluster', `cluster: ${cluster.name}`, '---', ''];
  if (parentName) parts.push(`parent:: [[${clusterNoteFilename(parentName)}]]`, '');
  parts.push(`# ${cluster.name}`, '');
  return parts.join('\n');
}
```

**Step 4: Run → PASS.**

**Step 5: Commit** `feat(constellation): render per-cluster index note`

---

## Task 4: Thin DB reader — `loadNoteClusters(db)` and `loadClusters(db)`

**Files:**
- Modify: `src/workflows/export-obsidian.ts` (add functions taking a `Database` arg — do NOT use the module `db` singleton, so they're testable)
- Test: `src/workflows/export-obsidian.db.test.ts` (create — integration-style against a temp DB, following `src/lib/synthesis-db.test.ts`)

**Step 1: Failing test** (seed a temp DB with 2 clusters + links, assert the maps)

```typescript
import Database from 'better-sqlite3';
import { loadNoteClusters, loadClusters } from './export-obsidian';

function seed(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`CREATE TABLE topic_clusters (id TEXT PRIMARY KEY, name TEXT, parent_id TEXT);
           CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER, added_at TEXT,
             PRIMARY KEY (topic_id, note_id));`);
  db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)').run('c1', 'Relationships', null);
  db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)').run('c2', 'Creativity', null);
  db.prepare('INSERT INTO topic_note_links VALUES (?,?,?)').run('c1', 10, 'now');
  db.prepare('INSERT INTO topic_note_links VALUES (?,?,?)').run('c2', 10, 'now');
  db.prepare('INSERT INTO topic_note_links VALUES (?,?,?)').run('c1', 20, 'now');
  return db;
}

describe('loadNoteClusters', () => {
  it('maps each note id to all its cluster names (multi-membership)', () => {
    const map = loadNoteClusters(seed());
    expect(map.get(10)).toEqual(['Relationships', 'Creativity']);
    expect(map.get(20)).toEqual(['Relationships']);
  });
});

describe('loadClusters', () => {
  it('returns every cluster with its (possibly null) parent name', () => {
    const clusters = loadClusters(seed());
    expect(clusters).toEqual([
      { name: 'Relationships', parentName: undefined },
      { name: 'Creativity', parentName: undefined },
    ]);
  });
});
```

**Step 2: Run → FAIL.** `npx jest export-obsidian.db`

**Step 3: Implement** (parameterized SQL, explicit types — no `ANY`)

```typescript
import type { Database as DB } from 'better-sqlite3';

export function loadNoteClusters(database: DB): Map<number, string[]> {
  const rows = database
    .prepare(
      `SELECT tnl.note_id AS noteId, tc.name AS name
       FROM topic_note_links tnl
       JOIN topic_clusters tc ON tc.id = tnl.topic_id
       ORDER BY tnl.note_id, tc.name`
    )
    .all() as Array<{ noteId: number; name: string }>;
  const map = new Map<number, string[]>();
  for (const r of rows) {
    const list = map.get(r.noteId) ?? [];
    list.push(r.name);
    map.set(r.noteId, list);
  }
  return map;
}

export function loadClusters(database: DB): Array<{ name: string; parentName?: string }> {
  const rows = database
    .prepare(
      `SELECT c.name AS name, p.name AS parentName
       FROM topic_clusters c
       LEFT JOIN topic_clusters p ON p.id = c.parent_id
       ORDER BY c.name`
    )
    .all() as Array<{ name: string; parentName: string | null }>;
  return rows.map((r) => ({ name: r.name, parentName: r.parentName ?? undefined }));
}
```

**Step 4: Run → PASS.**

**Step 5: Commit** `feat(constellation): DB readers for note↔cluster links`

---

## Task 5: Emit `parent::` into exported note markdown

**Files:**
- Modify: `src/workflows/export-obsidian.ts` — `exportNotes()` (around the frontmatter/links build, lines ~114-155) and load the note→cluster map once before the loop.
- Test: covered by Task 2 (field building) + Task 7 manual verification. Add one assertion test that a built note body contains the parent block when clusters exist (extract the per-note markdown assembly into a pure `buildNoteMarkdown(...)` if practical; otherwise assert via the field helper).

**Step 1:** Before the `for (const note of notes)` loop, call `const noteClusters = loadNoteClusters(db);`.

**Step 2:** In the per-note build, compute `const parentBlock = buildParentFields(noteClusters.get(note.id) ?? []);` and insert it into the note — placed in the body (Dataview inline fields work in body or frontmatter; put it just under the H1 or near the existing wiki-links block so it stays with relationship metadata). Keep it on its own lines.

**Step 3:** Run the full file's tests: `npx jest export-obsidian`. Expected: PASS.

**Step 4:** Manual smoke: run the export against a **dev-DB copy** (never prod) and grep a Notes file for `parent::`.

```bash
# from worktree, pointing at an isolated dev DB copy
SELENE_DB_PATH=/tmp/constellation-dev.db SELENE_VAULT_PATH=/tmp/constellation-vault \
  npx ts-node src/workflows/export-obsidian.ts
grep -r 'parent::' /tmp/constellation-vault/Notes | head
```

**Step 5: Commit** `feat(constellation): emit parent:: on exported notes`

---

## Task 6: Write `Constellation/` cluster index notes + wire into main

**Files:**
- Modify: `src/workflows/export-obsidian.ts` — add `exportClusterNotes(vaultPath)` and call it from `exportObsidian()` after Phase 1.
- Test: `src/workflows/export-obsidian.db.test.ts` — assert `exportClusterNotes` writes one file per cluster (use a temp vault dir via `os.tmpdir()`).

**Step 1: Failing test**

```typescript
it('writes one Constellation note per cluster, regenerated each run', () => {
  const db = seed();
  const vault = mkdtempSync(join(tmpdir(), 'vault-'));
  exportClusterNotes(db, vault);
  expect(existsSync(join(vault, 'Constellation', 'Relationships.md'))).toBe(true);
  expect(existsSync(join(vault, 'Constellation', 'Creativity.md'))).toBe(true);
  exportClusterNotes(db, vault); // re-run safe: no throw, same files
  expect(readdirSync(join(vault, 'Constellation')).length).toBe(2);
});
```

**Step 2: Run → FAIL.**

**Step 3: Implement**

```typescript
export function exportClusterNotes(database: DB, vaultPath: string): number {
  const clusters = loadClusters(database);
  const dir = join(vaultPath, 'Constellation');
  ensureDir(dir);
  let count = 0;
  for (const c of clusters) {
    const md = buildClusterNote({ name: c.name }, c.parentName);
    writeFileSync(join(dir, `${clusterNoteFilename(c.name)}.md`), md, 'utf-8');
    count++;
  }
  return count;
}
```

Then in `exportObsidian()`, after `exportNotes(vaultPath)`:

```typescript
let clusterNotes = 0;
try { clusterNotes = exportClusterNotes(db, vaultPath); }
catch (err) { log.error({ err: err as Error }, 'Cluster note export failed (non-blocking)'); }
```

Add `clusterNotes` to the returned `message`.

**Step 4: Run → PASS.** `npx jest export-obsidian`

**Step 5: Commit** `feat(constellation): export Constellation/ cluster index notes`

---

## Task 7: Manual ExcaliBrain verification (verification-before-completion)

**REQUIRED SUB-SKILL:** superpowers:verification-before-completion

**Steps:**
1. Make an isolated dev DB copy: `cp ~/selene-data-dev/selene.db /tmp/constellation-dev.db` (or seed one). Confirm it has `topic_clusters`/`topic_note_links` rows; if empty, run `synthesize-topics.ts` against it first.
2. Export into the dev vault that already has ExcaliBrain:
   `SELENE_DB_PATH=/tmp/constellation-dev.db SELENE_VAULT_PATH=~/selene-data-dev/vault npx ts-node src/workflows/export-obsidian.ts`
3. In Obsidian (dev vault): open a `Notes/` note → launch ExcaliBrain → confirm its cluster shows as a **parent**, and centering the cluster shows its member notes as **children**.
4. **Re-run safety:** run the export again; reopen ExcaliBrain; confirm no duplicate nodes, no broken links, fields intact.
5. Record the result in `BRANCH-STATUS.md` (Testing stage) with what you observed.

**Do NOT claim done until step 3 visibly works.** If clusters don't render: check `parent::` basename matches the `Constellation/` filename exactly (the #1 failure mode), and that Dataview is enabled.

---

## Task 8: Docs + wrap-up

1. **User-facing change → guide:** create `docs/guides/features/knowledge-constellation.md` from `docs/guides/features/_TEMPLATE.md` (verify every claim against the code), add its link to `docs/USER-EXPERIENCE.md`.
2. Check the `docs`-stage boxes in `BRANCH-STATUS.md`.
3. Leave the design doc in "In Progress" until merged (Phase B still pending).

---

## Open Items (carry, do not block Phase A)

- **`Constellation/` vs `Maps/` reconciliation:** post-#52, `topic_clusters` ≈ the 8 `Maps/` categories. Two parallel cluster representations may confuse ExcaliBrain/the vault. Decide after seeing both rendered — possibly fold cluster index notes into the existing `Maps/` MOCs (emit `parent::` pointing at `Maps/<category>`), retiring `Constellation/`.
- **Sequencing vs #52 prod rollout:** Phase A works on today's 83 flat single-membership clusters AND post-rollout's ~8 multi-membership ones. Best constellation arrives after the rollout — note it, don't wait on it.
- **Flat hierarchy:** `parent_id` is NULL today, so `Constellation/` notes are roots. The `buildClusterNote`/`loadClusters` parent handling is future-proofing for when sub-clusters exist.
- **Performance:** confirm ExcaliBrain responsiveness at full note volume during click-to-recenter.
