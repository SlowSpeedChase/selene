# Constellation Phase B Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Emit `friend:: [[note-basename]]` Dataview fields in every exported Obsidian note so ExcaliBrain renders note↔note edges alongside the existing cluster→note hierarchy.

**Architecture:** Two new helpers in `constellation.ts` (`loadNoteFriends` + `buildFriendFields`) wired into `obsidian-render.ts` — the same pattern as the Phase A `parent::` block. `constellation.ts` returns raw note data (title + created_at) to avoid a circular import; `obsidian-render.ts` converts to wikilink basenames using `noteFilename`. Top-N cap = 5.

**Tech Stack:** TypeScript, better-sqlite3, Jest (in-memory DB for unit tests)

---

### Task 1: `buildFriendFields` — unit test + implementation

**Files:**
- Modify: `src/lib/constellation.ts`
- Modify: `src/lib/constellation.test.ts`

**Step 1: Write the failing tests**

In `constellation.test.ts`, add a `describe('buildFriendFields')` block after the existing `buildParentFields` tests:

```typescript
describe('buildFriendFields', () => {
  it('returns empty string for empty input', () => {
    expect(buildFriendFields([])).toBe('');
  });

  it('emits one friend:: line for a single basename', () => {
    expect(buildFriendFields(['2025-11-01-grammar-intuition']))
      .toBe('friend:: [[2025-11-01-grammar-intuition]]');
  });

  it('emits one line per basename, joined by newline', () => {
    expect(buildFriendFields(['2025-11-01-foo', '2025-11-02-bar']))
      .toBe('friend:: [[2025-11-01-foo]]\nfriend:: [[2025-11-02-bar]]');
  });
});
```

Update the import line at the top of `constellation.test.ts` to include `buildFriendFields`.

**Step 2: Run to confirm failure**

```bash
npx jest --testPathPatterns="constellation.test" 2>&1 | grep -E "FAIL|PASS|buildFriendFields"
```
Expected: FAIL — `buildFriendFields` is not exported.

**Step 3: Implement `buildFriendFields` in `constellation.ts`**

Add after `buildParentFields`:

```typescript
/** One `friend:: [[basename]]` line per connected note (top-N, pre-sorted by caller). */
export function buildFriendFields(basenames: string[]): string {
  return basenames.map((b) => `friend:: [[${b}]]`).join('\n');
}
```

**Step 4: Run to confirm passing**

```bash
npx jest --testPathPatterns="constellation.test" 2>&1 | tail -8
```
Expected: all `buildFriendFields` tests PASS.

**Step 5: Commit**

```bash
git add src/lib/constellation.ts src/lib/constellation.test.ts
git commit -m "feat(constellation): buildFriendFields — friend:: line emitter"
```

---

### Task 2: `loadNoteFriends` — DB test + implementation

**Files:**
- Modify: `src/lib/constellation.ts`
- Modify: `src/lib/constellation.db.test.ts`

**Step 1: Write the failing DB tests**

In `constellation.db.test.ts`, add a `seedFriends()` helper and a `describe('loadNoteFriends')` block. Add after the existing `loadClusters`/`exportClusterNotes` blocks:

```typescript
function seedFriends(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, created_at TEXT);
    CREATE TABLE note_connections (
      id TEXT PRIMARY KEY,
      source_note_id INTEGER NOT NULL,
      target_note_id INTEGER NOT NULL,
      similarity_score REAL NOT NULL,
      found_at TEXT NOT NULL
    );
  `);
  const note = db.prepare('INSERT INTO raw_notes VALUES (?,?,?)');
  note.run(1, 'Grammar Intuition', '2025-11-01T00:00:00.000Z');
  note.run(2, 'Sentence Diagramming', '2025-11-02T00:00:00.000Z');
  note.run(3, 'Running Notes', '2025-11-03T00:00:00.000Z');
  note.run(4, 'Unconnected Note', '2025-11-04T00:00:00.000Z');
  const conn = db.prepare('INSERT INTO note_connections VALUES (?,?,?,?,?)');
  // note 1 ↔ note 2 (high similarity)
  conn.run('c1', 1, 2, 0.92, 'now');
  // note 1 ↔ note 3 (lower similarity)
  conn.run('c2', 1, 3, 0.80, 'now');
  // note 2 ↔ note 3 (stored as target→source direction)
  conn.run('c3', 3, 2, 0.78, 'now');
  return db;
}

describe('loadNoteFriends', () => {
  it('maps note 1 to its two friends ordered by descending similarity', () => {
    const map = loadNoteFriends(seedFriends());
    const friends = map.get(1);
    expect(friends).toHaveLength(2);
    // highest similarity first
    expect(friends![0].title).toBe('Sentence Diagramming');
    expect(friends![1].title).toBe('Running Notes');
  });

  it('is bidirectional — note 2 includes note 1 even though conn is stored as source=1', () => {
    const map = loadNoteFriends(seedFriends());
    const friends = map.get(2);
    const titles = friends!.map((f) => f.title).sort();
    expect(titles).toContain('Grammar Intuition');
  });

  it('respects topN cap', () => {
    const db = new Database(':memory:');
    db.exec(`
      CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, created_at TEXT);
      CREATE TABLE note_connections (id TEXT PRIMARY KEY, source_note_id INTEGER NOT NULL,
        target_note_id INTEGER NOT NULL, similarity_score REAL NOT NULL, found_at TEXT NOT NULL);
    `);
    // note 1 connected to 10 others
    db.prepare('INSERT INTO raw_notes VALUES (?,?,?)').run(1, 'Hub', '2025-01-01T00:00:00.000Z');
    for (let i = 2; i <= 11; i++) {
      db.prepare('INSERT INTO raw_notes VALUES (?,?,?)').run(i, `Note ${i}`, '2025-01-01T00:00:00.000Z');
      db.prepare('INSERT INTO note_connections VALUES (?,?,?,?,?)').run(
        `c${i}`, 1, i, 0.75 + i / 100, 'now'
      );
    }
    const map = loadNoteFriends(db, 5);
    expect(map.get(1)).toHaveLength(5);
  });

  it('returns nothing for a note with no connections', () => {
    const map = loadNoteFriends(seedFriends());
    expect(map.get(4)).toBeUndefined();
  });
});
```

Update the import at the top of `constellation.db.test.ts` to include `loadNoteFriends`.

**Step 2: Run to confirm failure**

```bash
npx jest --testPathPatterns="constellation.db.test" 2>&1 | grep -E "FAIL|PASS|loadNoteFriends"
```
Expected: FAIL — `loadNoteFriends` is not exported.

**Step 3: Implement `loadNoteFriends` in `constellation.ts`**

Add after `loadNoteClusters`:

```typescript
/** Map each note id -> top-N most-similar connected notes (bidirectional), sorted by
 *  similarity_score DESC. Returns raw note data; callers convert to wikilink basenames. */
export function loadNoteFriends(
  database: DB,
  topN = 5
): Map<number, Array<{ title: string; created_at: string }>> {
  const rows = database
    .prepare(
      `SELECT nc.source_note_id AS noteId,
              rn.title AS title, rn.created_at AS createdAt,
              nc.similarity_score AS score
       FROM note_connections nc
       JOIN raw_notes rn ON rn.id = nc.target_note_id
       UNION ALL
       SELECT nc.target_note_id AS noteId,
              rn.title AS title, rn.created_at AS createdAt,
              nc.similarity_score AS score
       FROM note_connections nc
       JOIN raw_notes rn ON rn.id = nc.source_note_id
       ORDER BY noteId, score DESC`
    )
    .all() as Array<{ noteId: number; title: string; createdAt: string; score: number }>;
  const map = new Map<number, Array<{ title: string; created_at: string }>>();
  for (const r of rows) {
    const list = map.get(r.noteId) ?? [];
    if (list.length < topN) {
      list.push({ title: r.title, created_at: r.createdAt });
      map.set(r.noteId, list);
    }
  }
  return map;
}
```

**Step 4: Run to confirm passing**

```bash
npx jest --testPathPatterns="constellation.db.test" 2>&1 | tail -8
```
Expected: all `loadNoteFriends` tests PASS.

**Step 5: Commit**

```bash
git add src/lib/constellation.ts src/lib/constellation.db.test.ts
git commit -m "feat(constellation): loadNoteFriends — bidirectional top-N friend query"
```

---

### Task 3: Add `friendBasenames` to `renderNoteMarkdown` — unit test + impl

**Files:**
- Modify: `src/lib/obsidian-render.ts`
- Modify: `src/lib/obsidian-render.test.ts`

**Step 1: Write the failing unit test**

In `obsidian-render.test.ts`, find the existing `renderNoteMarkdown` test block and add:

```typescript
it('injects friend:: lines when friendBasenames are provided', () => {
  const md = renderNoteMarkdown(
    makeNote({ id: 1 }),
    [],   // parentClusters
    [],   // appliedFeedback
    ['2025-11-02-sentence-diagramming', '2025-11-03-running-notes']
  );
  expect(md).toContain('friend:: [[2025-11-02-sentence-diagramming]]');
  expect(md).toContain('friend:: [[2025-11-03-running-notes]]');
});

it('friend block appears before the Your note heading', () => {
  const md = renderNoteMarkdown(
    makeNote({ id: 1 }),
    [],
    [],
    ['2025-11-02-sentence-diagramming']
  );
  const friendPos = md.indexOf('friend::');
  const yourNotePos = md.indexOf('## ✍️ Your note');
  expect(friendPos).toBeGreaterThan(-1);
  expect(friendPos).toBeLessThan(yourNotePos);
});

it('renders cleanly with no friend basenames (default param)', () => {
  const md = renderNoteMarkdown(makeNote({ id: 1 }), []);
  expect(md).not.toContain('friend::');
});
```

Check what `makeNote` helper is already defined as in the test file and use the same shape.

**Step 2: Run to confirm failure**

```bash
npx jest --testPathPatterns="obsidian-render.test" 2>&1 | grep -E "friend|FAIL|PASS" | head -10
```
Expected: FAIL — the new `friendBasenames` param doesn't exist yet.

**Step 3: Update `renderNoteMarkdown` signature in `obsidian-render.ts`**

Change the signature from:
```typescript
export function renderNoteMarkdown(
  note: RenderableNote,
  parentClusters: string[],
  appliedFeedback: AppliedFeedback[] = []
): string {
```
To:
```typescript
export function renderNoteMarkdown(
  note: RenderableNote,
  parentClusters: string[],
  appliedFeedback: AppliedFeedback[] = [],
  friendBasenames: string[] = []
): string {
```

Add the friend block injection after the existing `parentBlock` injection (around line 156–157):

```typescript
  const parentBlock = buildParentFields(parentClusters);
  if (parentBlock) parts.push(``, parentBlock);

  const friendBlock = buildFriendFields(friendBasenames);
  if (friendBlock) parts.push(``, friendBlock);
```

Add `buildFriendFields` to the import from `./constellation` at the top of `obsidian-render.ts`:
```typescript
import { buildParentFields, buildFriendFields, loadNoteClusters } from './constellation';
```

**Step 4: Run to confirm passing**

```bash
npx jest --testPathPatterns="obsidian-render.test" 2>&1 | tail -8
```
Expected: all tests PASS.

**Step 5: Commit**

```bash
git add src/lib/obsidian-render.ts src/lib/obsidian-render.test.ts
git commit -m "feat(obsidian-render): friend:: block in renderNoteMarkdown"
```

---

### Task 4: Wire `loadNoteFriends` into `reconcileExportedNotes` — DB integration test

**Files:**
- Modify: `src/lib/obsidian-render.ts`
- Modify: `src/lib/obsidian-render.db.test.ts`

**Step 1: Write the failing DB integration test**

In `obsidian-render.db.test.ts`, find how the existing tests seed the DB and add a new test in the relevant `describe` block:

```typescript
it('exports note with friend:: fields when note_connections has data', () => {
  // Seed two processed notes and a connection between them
  // (use whatever seed helper the existing tests already use — e.g. insertProcessedNote)
  const noteAId = insertProcessedNote(db, { title: 'Grammar Intuition', createdAt: '2025-11-01T00:00:00.000Z' });
  const noteBId = insertProcessedNote(db, { title: 'Sentence Diagramming', createdAt: '2025-11-02T00:00:00.000Z' });
  db.prepare(
    `INSERT INTO note_connections (id, source_note_id, target_note_id, similarity_score, found_at)
     VALUES (?,?,?,?,?)`
  ).run('c1', noteAId, noteBId, 0.92, 'now');

  const result = reconcileExportedNotes(db, tmpVaultDir, {});
  expect(result.written).toBeGreaterThanOrEqual(1);

  // Read the exported file for note A and confirm it has a friend:: link to note B
  const files = readdirSync(join(tmpVaultDir, 'Notes'));
  const noteAFile = files.find((f) => f.includes('grammar-intuition'));
  expect(noteAFile).toBeDefined();
  const content = readFileSync(join(tmpVaultDir, 'Notes', noteAFile!), 'utf-8');
  expect(content).toContain('friend:: [[2025-11-02-sentence-diagramming]]');
});
```

> **Note:** look at how the existing DB tests in this file seed notes (they likely call an `insertProcessedNote` helper or insert rows directly). Use the same pattern — don't invent a new one.

**Step 2: Run to confirm failure**

```bash
npx jest --testPathPatterns="obsidian-render.db.test" 2>&1 | grep -E "friend|FAIL|PASS" | head -10
```
Expected: FAIL — `reconcileExportedNotes` doesn't pass friend basenames to the renderer yet.

**Step 3: Wire `loadNoteFriends` into `reconcileExportedNotes` in `obsidian-render.ts`**

In `reconcileExportedNotes`, after the line that calls `loadNoteClusters`:

```typescript
  const noteClusters = loadNoteClusters(database);
```

Add:

```typescript
  const noteFriends = loadNoteFriends(database);
```

Add `loadNoteFriends` to the import from `./constellation`.

In the render loop, after:
```typescript
      const parentClusters = noteClusters.get(note.id) ?? [];
      const applied = feedbackByNote.get(note.id) ?? [];
```

Add:
```typescript
      const friendNotes = noteFriends.get(note.id) ?? [];
      const friendBasenames = friendNotes.map((f) => noteFilename(f).replace(/\.md$/, ''));
```

Update the `renderNoteMarkdown` call to pass `friendBasenames`:
```typescript
      const markdown = renderNoteMarkdown(note, parentClusters, applied, friendBasenames);
```

**Step 4: Run to confirm passing**

```bash
npx jest --testPathPatterns="obsidian-render.db.test" 2>&1 | tail -8
```
Expected: all tests PASS.

**Step 5: Commit**

```bash
git add src/lib/obsidian-render.ts src/lib/obsidian-render.db.test.ts
git commit -m "feat(obsidian-render): wire loadNoteFriends into reconcileExportedNotes"
```

---

### Task 5: Full suite, guide update, and final commit

**Files:**
- Modify: `docs/guides/features/knowledge-constellation.md`
- Modify: `docs/plans/INDEX.md`

**Step 1: Run the full test suite**

```bash
npm test 2>&1 | tail -10
```
Expected: all suites PASS, no regressions.

**Step 2: Update the constellation user guide**

In `docs/guides/features/knowledge-constellation.md`, add a "Note-to-note connections" section
describing that each note now shows its top-5 most-similar notes as `friend::` edges in
ExcaliBrain. Verify any claims about what appears in the vault against the actual rendered output.

**Step 3: Mark the design doc In Progress → Done in INDEX.md**

In `docs/plans/INDEX.md`, move the constellation design entry to the Done section with today's
date and a note that Phase B is complete.

**Step 4: Final commit**

```bash
git add docs/guides/features/knowledge-constellation.md docs/plans/INDEX.md docs/plans/2026-06-11-constellation-phase-b-design.md docs/plans/2026-06-11-constellation-phase-b-plan.md
git commit -m "docs(constellation): Phase B guide + mark design Done"
```

**Step 5: Push and confirm the hourly export picks up friend edges**

```bash
git push origin main
```

The deploy watcher will compile and deploy within ~5 min. The next hourly `export-obsidian` run
will rewrite all notes whose hash changes (notes with connections will gain `friend::` lines).
Check one note in Obsidian/ExcaliBrain to confirm `friend::` edges appear.
