# Synthesis Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a `synthesize-topics.ts` daily workflow that auto-detects topic clusters from existing note concepts, generates Ollama synthesis notes for each cluster, and writes them to `vault/Selene/Synthesis/` with hierarchical splitting when clusters grow large.

**Architecture:** Concept frequency scan over `processed_notes.concepts` → Jaccard merge for overlapping clusters → Ollama calls for naming, synthesis text, and split detection → Obsidian markdown files. Two new SQLite tables (`topic_clusters`, `topic_note_links`) designed for later use by the PKM browse layer at `/pkm/synthesis`.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (`generate()`), Node `fs` for file writes, existing `src/lib/` patterns.

---

## Schema Reality Check (read before starting)

```sql
-- raw_notes: id is INTEGER (not TEXT/UUID)
-- raw_notes: NO status column, NO test_run column — filter with is_archived = 0 ONLY
-- raw_notes: title is nullable — default to '(untitled)' in code
-- processed_notes: concepts is JSON array (text), summary is NULL for all notes
-- connections table: currently empty — do NOT use for cluster discovery
-- Obsidian layout: vault/Selene/Notes/, vault/Selene/Maps/, synthesis → vault/Selene/Synthesis/
-- Wikilinks in synthesis body must use full path: [[Selene/Notes/YYYY-MM-DD-slug]] not [[YYYY-MM-DD-slug]]
-- Vault path: use config.vaultPath directly (NOT process.env.OBSIDIAN_VAULT_PATH — that env var does not exist)
```

Verify before each task:
```bash
sqlite3 data/selene.db "SELECT COUNT(*) FROM processed_notes WHERE concepts IS NOT NULL;"
# Expected: 116+
```

---

### Task 1: Move `createSlug` to `src/lib/strings.ts`

`createSlug` is currently defined only in `export-obsidian.ts` (line 46). The synthesis writer needs the same function. Move it to the shared strings module.

**Files:**
- Modify: `src/lib/strings.ts`
- Modify: `src/workflows/export-obsidian.ts:46-52`

**Step 1: Add `createSlug` to `src/lib/strings.ts`**

Append to the end of `src/lib/strings.ts`:

```typescript
export function createSlug(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .slice(0, 50);
}
```

**Step 2: Update `export-obsidian.ts` to import from strings**

Remove the local `createSlug` definition (lines 46-52 of `export-obsidian.ts`) and add the import:

```typescript
import { createSlug } from '../lib/strings';
```

**Step 3: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

**Step 4: Commit**

```bash
git add src/lib/strings.ts src/workflows/export-obsidian.ts
git commit -m "refactor: move createSlug to shared strings module"
```

---

### Task 2: TypeScript types for synthesis layer

**Files:**
- Create: `src/types/synthesis.ts`

**Step 1: Write the types**

Create `src/types/synthesis.ts`:

```typescript
export interface TopicCluster {
  id: string;          // UUID (TEXT in SQLite)
  name: string;        // "Ergonomics & Workspace"
  slug: string;        // "ergonomics-workspace"
  parentId: string | null;
  synthesisText: string | null;
  synthesisUpdatedAt: string | null;
  splitThreshold: number;
  createdAt: string;
}

export interface TopicNoteLink {
  topicId: string;
  rawNoteId: number;   // FK to raw_notes.id (INTEGER)
  addedAt: string;
}

export interface NoteWithConcepts {
  rawNoteId: number;
  title: string;
  createdAt: string;
  concepts: string[];
}

export interface ClusterCandidate {
  seed: string;             // primary concept name (may be "concept1, concept2" after merges)
  noteIds: Set<number>;     // raw_note IDs
  allConcepts: Set<string>; // all concepts across member notes
}

export type SplitResult =
  | { split: false }
  | { split: true; children: Array<{ name: string; noteIds: number[] }> };
```

**Step 2: Export from `src/types/index.ts`** (or whichever barrel exists)

Check if `src/types/index.ts` exists:

```bash
ls src/types/
```

If there's an `index.ts`, add:

```typescript
export * from './synthesis';
```

**Step 3: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

**Step 4: Commit**

```bash
git add src/types/synthesis.ts src/types/index.ts
git commit -m "feat: add TypeScript types for synthesis layer"
```

---

### Task 3: DB helpers with built-in migration

Follow the exact pattern of `src/lib/agent-db.ts`: types at top, a `runSynthesisMigrations()` function that uses `CREATE TABLE IF NOT EXISTS`, then CRUD helpers.

**Files:**
- Create: `src/lib/synthesis-db.ts`

**Step 1: Write `src/lib/synthesis-db.ts`**

```typescript
import { db } from './db';
import { logger } from './logger';
import type { TopicCluster, TopicNoteLink, NoteWithConcepts } from '../types/synthesis';

const log = logger.child({ module: 'synthesis-db' });

// ── Migration ──────────────────────────────────────────────────────────────

export function runSynthesisMigrations(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS topic_clusters (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT NOT NULL UNIQUE,
      parent_id TEXT,
      synthesis_text TEXT,
      synthesis_updated_at TEXT,
      split_threshold INTEGER NOT NULL DEFAULT 8,
      created_at TEXT NOT NULL,
      FOREIGN KEY (parent_id) REFERENCES topic_clusters(id)
    );

    CREATE TABLE IF NOT EXISTS topic_note_links (
      topic_id TEXT NOT NULL,
      raw_note_id INTEGER NOT NULL,
      added_at TEXT NOT NULL,
      PRIMARY KEY (topic_id, raw_note_id),
      FOREIGN KEY (topic_id) REFERENCES topic_clusters(id),
      FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
    );
  `);
  log.info('Synthesis migrations complete');
}

// ── Queries ────────────────────────────────────────────────────────────────

export function getAllNotesWithConcepts(): NoteWithConcepts[] {
  const rows = db.prepare(`
    SELECT
      rn.id        AS rawNoteId,
      rn.title     AS title,
      rn.created_at AS createdAt,
      pn.concepts  AS conceptsJson
    FROM raw_notes rn
    JOIN processed_notes pn ON pn.raw_note_id = rn.id
    WHERE rn.is_archived = 0
      AND pn.concepts IS NOT NULL
  `).all() as Array<{ rawNoteId: number; title: string; createdAt: string; conceptsJson: string }>;

  return rows.map(r => ({
    rawNoteId: r.rawNoteId,
    title: r.title ?? '(untitled)',
    createdAt: r.createdAt,
    concepts: JSON.parse(r.conceptsJson) as string[],
  }));
}

export function getAllTopicClusters(): TopicCluster[] {
  return db.prepare(`
    SELECT
      id, name, slug,
      parent_id AS parentId,
      synthesis_text AS synthesisText,
      synthesis_updated_at AS synthesisUpdatedAt,
      split_threshold AS splitThreshold,
      created_at AS createdAt
    FROM topic_clusters
    ORDER BY created_at ASC
  `).all() as TopicCluster[];
}

export function getTopicClusterBySlug(slug: string): TopicCluster | null {
  return db.prepare(`
    SELECT
      id, name, slug,
      parent_id AS parentId,
      synthesis_text AS synthesisText,
      synthesis_updated_at AS synthesisUpdatedAt,
      split_threshold AS splitThreshold,
      created_at AS createdAt
    FROM topic_clusters
    WHERE slug = ?
  `).get(slug) as TopicCluster | null;
}

export function upsertTopicCluster(cluster: TopicCluster): void {
  db.prepare(`
    INSERT INTO topic_clusters
      (id, name, slug, parent_id, synthesis_text, synthesis_updated_at, split_threshold, created_at)
    VALUES
      (@id, @name, @slug, @parentId, @synthesisText, @synthesisUpdatedAt, @splitThreshold, @createdAt)
    ON CONFLICT(id) DO UPDATE SET
      name                 = excluded.name,
      slug                 = excluded.slug,
      synthesis_text       = excluded.synthesis_text,
      synthesis_updated_at = excluded.synthesis_updated_at
  `).run({
    id: cluster.id,
    name: cluster.name,
    slug: cluster.slug,
    parentId: cluster.parentId,
    synthesisText: cluster.synthesisText,
    synthesisUpdatedAt: cluster.synthesisUpdatedAt,
    splitThreshold: cluster.splitThreshold,
    createdAt: cluster.createdAt,
  });
}

export function getNoteIdsForCluster(topicId: string): number[] {
  const rows = db.prepare(`
    SELECT raw_note_id FROM topic_note_links WHERE topic_id = ?
  `).all(topicId) as Array<{ raw_note_id: number }>;
  return rows.map(r => r.raw_note_id);
}

export function getLatestLinkDateForCluster(topicId: string): string | null {
  const row = db.prepare(`
    SELECT MAX(added_at) AS latest FROM topic_note_links WHERE topic_id = ?
  `).get(topicId) as { latest: string | null };
  return row.latest;
}

export function linkNotesToCluster(topicId: string, noteIds: number[]): void {
  const stmt = db.prepare(`
    INSERT OR IGNORE INTO topic_note_links (topic_id, raw_note_id, added_at)
    VALUES (?, ?, ?)
  `);
  const now = new Date().toISOString();
  const insertMany = db.transaction((ids: number[]) => {
    for (const noteId of ids) {
      stmt.run(topicId, noteId, now);
    }
  });
  insertMany(noteIds);
}

export function clearClusterLinks(topicId: string): void {
  db.prepare('DELETE FROM topic_note_links WHERE topic_id = ?').run(topicId);
}

export function deleteTopicCluster(id: string): void {
  db.prepare('DELETE FROM topic_clusters WHERE id = ?').run(id);
}
```

**Step 2: Add new tables to `scripts/create-dev-db.sh`**

`runSynthesisMigrations()` handles runtime creation via `CREATE TABLE IF NOT EXISTS`, but `create-dev-db.sh` is the canonical schema document and must also include the new tables. Find the last `CREATE TABLE` block in the script and append after it:

```bash
sqlite3 "$DEV_DB" "
CREATE TABLE IF NOT EXISTS topic_clusters (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  parent_id TEXT,
  synthesis_text TEXT,
  synthesis_updated_at TEXT,
  split_threshold INTEGER NOT NULL DEFAULT 8,
  created_at TEXT NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES topic_clusters(id)
);

CREATE TABLE IF NOT EXISTS topic_note_links (
  topic_id TEXT NOT NULL,
  raw_note_id INTEGER NOT NULL,
  added_at TEXT NOT NULL,
  PRIMARY KEY (topic_id, raw_note_id),
  FOREIGN KEY (topic_id) REFERENCES topic_clusters(id),
  FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
"
```

**Step 3: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

**Step 4: Commit**

```bash
git add src/lib/synthesis-db.ts scripts/create-dev-db.sh
git commit -m "feat: add synthesis DB helpers and migration"
```

---

### Task 4: Concept clustering algorithm with tests

A pure function — no DB, no Ollama, no side effects. Takes an array of notes-with-concepts and returns cluster candidates. Test it thoroughly before anything else depends on it.

**Files:**
- Create: `src/lib/cluster-topics.ts`
- Create: `src/lib/cluster-topics.test.ts`

**Step 1: Write `src/lib/cluster-topics.ts`**

```typescript
import type { ClusterCandidate, NoteWithConcepts } from '../types/synthesis';

export interface ClusterOptions {
  minFrequency?: number;   // concept must appear in this many notes (default: 3)
  mergeThreshold?: number; // Jaccard similarity to merge two clusters (default: 0.6)
}

function jaccardSimilarity(a: Set<number>, b: Set<number>): number {
  let intersectionSize = 0;
  for (const id of a) {
    if (b.has(id)) intersectionSize++;
  }
  const unionSize = a.size + b.size - intersectionSize;
  return unionSize === 0 ? 0 : intersectionSize / unionSize;
}

export function discoverClusters(
  notes: NoteWithConcepts[],
  options: ClusterOptions = {}
): ClusterCandidate[] {
  const { minFrequency = 3, mergeThreshold = 0.6 } = options;

  // Step 1: Map each normalized concept → note IDs that contain it
  const conceptToNoteIds = new Map<string, number[]>();
  for (const note of notes) {
    for (const concept of note.concepts) {
      const normalized = concept.toLowerCase().trim();
      if (!normalized) continue;
      if (!conceptToNoteIds.has(normalized)) {
        conceptToNoteIds.set(normalized, []);
      }
      conceptToNoteIds.get(normalized)!.push(note.rawNoteId);
    }
  }

  // Step 2: Filter to seeds meeting minFrequency
  const clusters: ClusterCandidate[] = [];
  for (const [concept, noteIds] of conceptToNoteIds) {
    if (noteIds.length < minFrequency) continue;
    const noteSet = new Set(noteIds);
    const allConcepts = new Set<string>();
    for (const note of notes) {
      if (noteSet.has(note.rawNoteId)) {
        note.concepts.forEach(c => allConcepts.add(c.toLowerCase().trim()));
      }
    }
    clusters.push({ seed: concept, noteIds: noteSet, allConcepts });
  }

  // Step 3: Pairwise Jaccard merge — loop until no more merges
  let merged = true;
  while (merged) {
    merged = false;
    outer: for (let i = 0; i < clusters.length; i++) {
      for (let j = i + 1; j < clusters.length; j++) {
        if (jaccardSimilarity(clusters[i].noteIds, clusters[j].noteIds) >= mergeThreshold) {
          clusters[j].noteIds.forEach(id => clusters[i].noteIds.add(id));
          clusters[j].allConcepts.forEach(c => clusters[i].allConcepts.add(c));
          clusters[i].seed = `${clusters[i].seed}, ${clusters[j].seed}`;
          clusters.splice(j, 1);
          merged = true;
          break outer;
        }
      }
    }
  }

  return clusters;
}
```

**Step 2: Write `src/lib/cluster-topics.test.ts`**

```typescript
import assert from 'assert';
import { discoverClusters } from './cluster-topics';
import type { NoteWithConcepts } from '../types/synthesis';

async function runTests() {
  // Test 1: No clusters when all concepts appear in fewer notes than minFrequency
  {
    const notes: NoteWithConcepts[] = [
      { rawNoteId: 1, title: 'N1', createdAt: '2026-01-01', concepts: ['ergonomics', 'standing desk'] },
      { rawNoteId: 2, title: 'N2', createdAt: '2026-01-02', concepts: ['ergonomics'] },
    ];
    const result = discoverClusters(notes, { minFrequency: 3 });
    assert.strictEqual(result.length, 0, 'should find no clusters below minFrequency');
    console.log('  ✓ no clusters when below minFrequency');
  }

  // Test 2: Forms a cluster when a concept appears in minFrequency notes
  {
    const notes: NoteWithConcepts[] = [
      { rawNoteId: 1, title: 'N1', createdAt: '2026-01-01', concepts: ['ergonomics'] },
      { rawNoteId: 2, title: 'N2', createdAt: '2026-01-02', concepts: ['ergonomics'] },
      { rawNoteId: 3, title: 'N3', createdAt: '2026-01-03', concepts: ['ergonomics'] },
    ];
    const result = discoverClusters(notes, { minFrequency: 3 });
    assert.strictEqual(result.length, 1, 'should form one cluster');
    assert.strictEqual(result[0].noteIds.size, 3, 'cluster should have 3 notes');
    console.log('  ✓ forms cluster at minFrequency');
  }

  // Test 3: Merges two concepts when their note sets heavily overlap
  {
    const notes: NoteWithConcepts[] = [
      { rawNoteId: 1, title: 'N1', createdAt: '2026-01-01', concepts: ['ergonomics', 'standing desk'] },
      { rawNoteId: 2, title: 'N2', createdAt: '2026-01-02', concepts: ['ergonomics', 'standing desk'] },
      { rawNoteId: 3, title: 'N3', createdAt: '2026-01-03', concepts: ['ergonomics', 'standing desk'] },
    ];
    // Both 'ergonomics' and 'standing desk' appear in same 3 notes → Jaccard = 1.0 → merge
    const result = discoverClusters(notes, { minFrequency: 3, mergeThreshold: 0.6 });
    assert.strictEqual(result.length, 1, 'overlapping concepts should merge into one cluster');
    console.log('  ✓ merges highly overlapping clusters');
  }

  // Test 4: Keeps two clusters separate when overlap is below threshold
  {
    const notes: NoteWithConcepts[] = [
      { rawNoteId: 1, title: 'N1', createdAt: '2026-01-01', concepts: ['ergonomics'] },
      { rawNoteId: 2, title: 'N2', createdAt: '2026-01-02', concepts: ['ergonomics'] },
      { rawNoteId: 3, title: 'N3', createdAt: '2026-01-03', concepts: ['ergonomics'] },
      { rawNoteId: 4, title: 'N4', createdAt: '2026-01-04', concepts: ['morning routine'] },
      { rawNoteId: 5, title: 'N5', createdAt: '2026-01-05', concepts: ['morning routine'] },
      { rawNoteId: 6, title: 'N6', createdAt: '2026-01-06', concepts: ['morning routine'] },
    ];
    const result = discoverClusters(notes, { minFrequency: 3, mergeThreshold: 0.6 });
    assert.strictEqual(result.length, 2, 'distinct topics should produce separate clusters');
    console.log('  ✓ keeps distinct topics as separate clusters');
  }

  // Test 5: A note can belong to multiple clusters
  {
    const notes: NoteWithConcepts[] = [
      { rawNoteId: 1, title: 'N1', createdAt: '2026-01-01', concepts: ['ergonomics', 'morning routine'] },
      { rawNoteId: 2, title: 'N2', createdAt: '2026-01-02', concepts: ['ergonomics'] },
      { rawNoteId: 3, title: 'N3', createdAt: '2026-01-03', concepts: ['ergonomics'] },
      { rawNoteId: 4, title: 'N4', createdAt: '2026-01-04', concepts: ['morning routine'] },
      { rawNoteId: 5, title: 'N5', createdAt: '2026-01-05', concepts: ['morning routine'] },
    ];
    const result = discoverClusters(notes, { minFrequency: 3, mergeThreshold: 0.6 });
    // ergonomics: notes 1,2,3; morning routine: notes 1,4,5 — overlap is 1/5 = 0.2 < 0.6
    assert.strictEqual(result.length, 2, 'note 1 should appear in both clusters');
    const ergCluster = result.find(c => c.seed.includes('ergonomics'));
    assert.ok(ergCluster?.noteIds.has(1), 'note 1 should be in ergonomics cluster');
    console.log('  ✓ note can belong to multiple clusters');
  }

  console.log('\nAll cluster-topics tests passed!');
}

runTests().catch(err => {
  console.error('Tests failed:', err);
  process.exit(1);
});
```

**Step 3: Run the test — it should pass immediately (pure function)**

```bash
npx ts-node src/lib/cluster-topics.test.ts
```

Expected output:
```
  ✓ no clusters when below minFrequency
  ✓ forms cluster at minFrequency
  ✓ merges highly overlapping clusters
  ✓ keeps distinct topics as separate clusters
  ✓ note can belong to multiple clusters

All cluster-topics tests passed!
```

**Step 4: Commit**

```bash
git add src/lib/cluster-topics.ts src/lib/cluster-topics.test.ts
git commit -m "feat: add concept clustering algorithm with tests"
```

---

### Task 5: Add synthesis prompts to `src/lib/prompts.ts`

**Files:**
- Modify: `src/lib/prompts.ts`

**Step 1: Append prompts to `src/lib/prompts.ts`**

Add at the end of the file:

```typescript
// ── Synthesis Layer Prompts ────────────────────────────────────────────────

export const CLUSTER_NAME_PROMPT = `Given these concept keywords from a personal knowledge base:
{concept_seeds}

Return a 2-4 word topic name that captures what these notes are about.
Return ONLY the topic name, no explanation, no quotes.
Examples: "Ergonomics & Workspace", "Morning Routine", "TypeScript Patterns"`;

export const SYNTHESIS_PROMPT = `You are synthesizing a personal knowledge base.
Topic: "{cluster_name}"
Notes ({note_count} total):

{notes_list}

Write in second person ("You've been exploring..."):
1. A 3-5 sentence synthesis capturing the recurring questions, tensions, and through-line across these notes.
2. Any open question that keeps resurfacing.
3. List each note as "- [[{filename}]] — one sentence on why it belongs here."

Use the [[filename]] values exactly as provided. Do not invent links.
Do not add frontmatter or a top-level heading.`;

export const SPLIT_DETECT_PROMPT = `These {note_count} notes are all about "{cluster_name}".
Essences:
{essences_list}

Do you see 2 or more clearly distinct sub-themes?

Respond with JSON only — no explanation, no markdown:
{ "split": false }
OR
{ "split": true, "children": [
    { "name": "Sub-theme Name", "noteIds": [1, 2, 3] },
    { "name": "Other Sub-theme", "noteIds": [4, 5] }
  ]
}

Use only the noteIds provided. Every note must appear in exactly one child.`;
```

**Step 2: Type-check**

```bash
npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add src/lib/prompts.ts
git commit -m "feat: add synthesis prompts (name, synthesis, split detection)"
```

---

### Task 6: Synthesis generator (Ollama calls)

**Files:**
- Create: `src/lib/synthesis-generator.ts`

**Step 1: Write `src/lib/synthesis-generator.ts`**

```typescript
import { generate, isAvailable } from './ollama';
import { logger } from './logger';
import { createSlug } from './strings';
import { CLUSTER_NAME_PROMPT, SYNTHESIS_PROMPT, SPLIT_DETECT_PROMPT } from './prompts';
import type { NoteWithConcepts, SplitResult } from '../types/synthesis';

const log = logger.child({ module: 'synthesis-generator' });

function noteFilename(note: NoteWithConcepts): string {
  const date = note.createdAt.split('T')[0].replace(/-/g, '-');
  return `${date}-${createSlug(note.title)}`;
}

export async function nameCluster(conceptSeeds: string): Promise<string> {
  const prompt = CLUSTER_NAME_PROMPT.replace('{concept_seeds}', conceptSeeds);
  const name = (await generate(prompt, { maxTokens: 20, temperature: 0.3 })).trim();
  log.debug({ conceptSeeds, name }, 'Named cluster');
  return name;
}

export async function generateSynthesis(
  clusterName: string,
  notes: NoteWithConcepts[]
): Promise<string> {
  // Full Obsidian wikilink path — must include Selene/Notes/ prefix for links to resolve
  const notesList = notes
    .map(n => `Title: ${n.title}\nFilename: Selene/Notes/${noteFilename(n)}\nConcepts: ${n.concepts.slice(0, 5).join(', ')}`)
    .join('\n\n');

  const prompt = SYNTHESIS_PROMPT
    .replace('{cluster_name}', clusterName)
    .replace('{note_count}', String(notes.length))
    .replace('{notes_list}', notesList);

  // Synthesis can be slow for large clusters — allow 5 minutes
  const text = await generate(prompt, { maxTokens: 600, temperature: 0.4, timeoutMs: 300000 });
  log.debug({ clusterName, noteCount: notes.length }, 'Generated synthesis');
  return text.trim();
}

export async function detectSplit(
  clusterName: string,
  notes: NoteWithConcepts[]
): Promise<SplitResult> {
  const essencesList = notes
    .map(n => `[${n.rawNoteId}] ${n.title}: ${n.concepts.slice(0, 3).join(', ')}`)
    .join('\n');

  const prompt = SPLIT_DETECT_PROMPT
    .replace('{note_count}', String(notes.length))
    .replace('{cluster_name}', clusterName)
    .replace('{essences_list}', essencesList);

  const raw = await generate(prompt, { maxTokens: 300, temperature: 0.2 });

  // Extract JSON from response — LLM may add surrounding text
  const jsonMatch = raw.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    log.warn({ clusterName, raw }, 'Split detection returned no JSON — treating as no split');
    return { split: false };
  }

  try {
    const result = JSON.parse(jsonMatch[0]) as SplitResult;
    log.debug({ clusterName, result }, 'Split detection result');
    return result;
  } catch {
    log.warn({ clusterName, raw }, 'Failed to parse split detection JSON');
    return { split: false };
  }
}

export { noteFilename };
```

**Step 2: Type-check**

```bash
npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add src/lib/synthesis-generator.ts
git commit -m "feat: add synthesis generator (Ollama naming, synthesis, split detection)"
```

---

### Task 7: Obsidian file writer

**Files:**
- Create: `src/lib/synthesis-writer.ts`

**Step 1: Write `src/lib/synthesis-writer.ts`**

```typescript
import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { logger } from './logger';
import { createSlug } from './strings';
import type { TopicCluster, NoteWithConcepts } from '../types/synthesis';

const log = logger.child({ module: 'synthesis-writer' });

function synthesisDir(vaultPath: string): string {
  return join(vaultPath, 'Selene', 'Synthesis');
}

// Flat naming: all synthesis notes live at vault/Selene/Synthesis/{slug}.md
// Parent/child relationship is expressed via frontmatter and wikilinks, not file nesting
function clusterFilePath(vaultPath: string, cluster: TopicCluster): string {
  return join(synthesisDir(vaultPath), `${cluster.slug}.md`);
}

function noteWikilink(note: NoteWithConcepts): string {
  const date = note.createdAt.split('T')[0];
  const slug = createSlug(note.title);
  return `Selene/Notes/${date}-${slug}`;
}

export function writeSynthesisNote(
  cluster: TopicCluster,
  notes: NoteWithConcepts[],
  allClusters: TopicCluster[],
  vaultPath: string
): void {
  const dir = synthesisDir(vaultPath);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const children = allClusters.filter(c => c.parentId === cluster.id);
  const parent = cluster.parentId
    ? allClusters.find(c => c.id === cluster.parentId)
    : null;

  const frontmatter = [
    '---',
    `topic: ${cluster.name}`,
    `note_count: ${notes.length}`,
    `parent: ${parent ? parent.name : 'null'}`,
    children.length > 0
      ? `children: [${children.map(c => c.slug).join(', ')}]`
      : 'children: []',
    `last_updated: ${cluster.synthesisUpdatedAt?.split('T')[0] ?? new Date().toISOString().split('T')[0]}`,
    '---',
  ].join('\n');

  const sourceLinks = notes
    .map(n => `- [[${noteWikilink(n)}]] — ${n.title}`)
    .join('\n');

  const childLinks =
    children.length > 0
      ? '\n## Sub-topics\n' + children.map(c => `- [[Selene/Synthesis/${c.slug}]]`).join('\n')
      : '';

  const body = cluster.synthesisText ?? '*(synthesis pending)*';

  const content = [
    frontmatter,
    '',
    body,
    childLinks,
    '',
    '## Source notes',
    sourceLinks,
  ]
    .filter(s => s !== undefined)
    .join('\n');

  const filePath = clusterFilePath(vaultPath, cluster);
  writeFileSync(filePath, content, 'utf-8');
  log.debug({ slug: cluster.slug, noteCount: notes.length }, 'Wrote synthesis note');
}

export function writeSynthesisIndex(
  clusters: TopicCluster[],
  clusterNoteCounts: Map<string, number>,
  vaultPath: string
): void {
  const dir = synthesisDir(vaultPath);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const roots = clusters.filter(c => c.parentId === null);
  const totalNotes = [...clusterNoteCounts.values()].reduce((sum, n) => sum + n, 0);
  const today = new Date().toISOString().split('T')[0];

  function renderCluster(c: TopicCluster, depth: number): string {
    const indent = '  '.repeat(depth);
    const count = clusterNoteCounts.get(c.id) ?? 0;
    const children = clusters.filter(ch => ch.parentId === c.id);
    const line = `${indent}- [[Selene/Synthesis/${c.slug}]] — ${c.name} (${count} notes)`;
    return [line, ...children.map(ch => renderCluster(ch, depth + 1))].join('\n');
  }

  const tree = roots.map(c => renderCluster(c, 0)).join('\n');

  const content = [
    '# Synthesis Index',
    `*${clusters.length} topics across ${totalNotes} notes. Last updated: ${today}.*`,
    '',
    '## Topics',
    tree,
  ].join('\n');

  writeFileSync(join(dir, '_INDEX.md'), content, 'utf-8');
  log.info({ topicCount: clusters.length }, 'Wrote synthesis index');
}
```

**Step 2: Type-check**

```bash
npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add src/lib/synthesis-writer.ts
git commit -m "feat: add synthesis Obsidian file writer"
```

---

### Task 8: Main `synthesize-topics.ts` workflow

**Files:**
- Create: `src/workflows/synthesize-topics.ts`

**Step 1: Write the workflow**

```typescript
import { createWorkflowLogger } from '../lib';
import { isAvailable } from '../lib/ollama';
import { config } from '../lib/config';
import {
  runSynthesisMigrations,
  getAllNotesWithConcepts,
  getAllTopicClusters,
  upsertTopicCluster,
  linkNotesToCluster,
  clearClusterLinks,
  getNoteIdsForCluster,
  getLatestLinkDateForCluster,
  deleteTopicCluster,
} from '../lib/synthesis-db';
import { discoverClusters } from '../lib/cluster-topics';
import { nameCluster, generateSynthesis, detectSplit } from '../lib/synthesis-generator';
import { writeSynthesisNote, writeSynthesisIndex } from '../lib/synthesis-writer';
import type { TopicCluster, NoteWithConcepts } from '../types/synthesis';
import { randomUUID } from 'crypto';

const log = createWorkflowLogger('synthesize-topics');

async function main(): Promise<void> {
  log.info('Starting synthesize-topics workflow');

  // 1. Ensure tables exist
  runSynthesisMigrations();

  // 2. Check Ollama
  if (!(await isAvailable())) {
    log.warn('Ollama not available — skipping synthesis generation');
    return;
  }

  const vaultPath = config.vaultPath;

  // 3. Load all notes with concepts
  const allNotes = getAllNotesWithConcepts();
  log.info({ noteCount: allNotes.length }, 'Loaded notes with concepts');

  if (allNotes.length < 3) {
    log.info('Fewer than 3 notes — skipping cluster discovery');
    return;
  }

  // 4. Discover clusters from concept frequency
  const candidates = discoverClusters(allNotes, { minFrequency: 3, mergeThreshold: 0.6 });
  log.info({ candidateCount: candidates.length }, 'Discovered cluster candidates');

  // 5. Build note lookup map
  const noteById = new Map<number, NoteWithConcepts>(
    allNotes.map(n => [n.rawNoteId, n])
  );

  // 6. For each candidate: upsert cluster, link notes, generate synthesis if new notes arrived
  const now = new Date().toISOString();

  for (const candidate of candidates) {
    const noteIds = [...candidate.noteIds];
    const candidateNotes = noteIds.map(id => noteById.get(id)!).filter(Boolean);

    // Derive cluster name from seed concepts
    const seedConcepts = [...candidate.allConcepts].slice(0, 6).join(', ');
    const name = await nameCluster(seedConcepts);
    const slug = name
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .slice(0, 50);

    // Check if cluster already exists by slug (use targeted query, not full table scan)
    let cluster = getTopicClusterBySlug(slug);

    if (!cluster) {
      cluster = {
        id: randomUUID(),
        name,
        slug,
        parentId: null,
        synthesisText: null,
        synthesisUpdatedAt: null,
        splitThreshold: 8,
        createdAt: now,
      };
      upsertTopicCluster(cluster);
    }

    // Check if synthesis needs regeneration BEFORE clearing links
    // (after clear+re-add, latestLink would always equal now, making the comparison unreliable)
    const latestLinkBefore = getLatestLinkDateForCluster(cluster.id);
    const needsRegen =
      !cluster.synthesisUpdatedAt ||
      (latestLinkBefore && latestLinkBefore > cluster.synthesisUpdatedAt) ||
      noteIds.length !== getNoteIdsForCluster(cluster.id).length;

    // Re-link notes (clear and re-add to handle additions/removals)
    clearClusterLinks(cluster.id);
    linkNotesToCluster(cluster.id, noteIds);

    if (needsRegen) {
      log.info({ slug, noteCount: candidateNotes.length }, 'Generating synthesis');
      const synthesisText = await generateSynthesis(name, candidateNotes);
      cluster = {
        ...cluster,
        synthesisText,
        synthesisUpdatedAt: now,
      };
      upsertTopicCluster(cluster);
    }

    // Split check when cluster is at or above threshold
    const clusterNoteCount = getNoteIdsForCluster(cluster.id).length;
    if (clusterNoteCount >= cluster.splitThreshold) {
      log.info({ slug, noteCount: clusterNoteCount }, 'Running split detection');
      const splitResult = await detectSplit(name, candidateNotes);

      if (splitResult.split) {
        log.info({ slug, children: splitResult.children.length }, 'Splitting cluster');

        // Clear parent's own note links — notes now belong to children only
        clearClusterLinks(cluster.id);

        for (const child of splitResult.children) {
          const childSlug = child.name
            .toLowerCase()
            .replace(/[^a-z0-9\s-]/g, '')
            .replace(/\s+/g, '-')
            .slice(0, 50);

          let childCluster = getTopicClusterBySlug(childSlug);
          if (!childCluster) {
            childCluster = {
              id: randomUUID(),
              name: child.name,
              slug: childSlug,
              parentId: cluster.id,
              synthesisText: null,
              synthesisUpdatedAt: null,
              splitThreshold: 8,
              createdAt: now,
            };
            upsertTopicCluster(childCluster);
          }

          const childNotes = child.noteIds
            .map(id => noteById.get(id))
            .filter((n): n is NoteWithConcepts => n !== undefined);

          linkNotesToCluster(childCluster.id, child.noteIds);

          const childSynthesis = await generateSynthesis(child.name, childNotes);
          upsertTopicCluster({
            ...childCluster,
            synthesisText: childSynthesis,
            synthesisUpdatedAt: now,
          });
        }

        // Regenerate parent as hub
        const hubText = await generateSynthesis(name, candidateNotes);
        upsertTopicCluster({ ...cluster, synthesisText: hubText, synthesisUpdatedAt: now });
      }
    }
  }

  // 7. Write Obsidian files
  const finalClusters = getAllTopicClusters();
  const clusterNoteCounts = new Map<string, number>(
    finalClusters.map(c => [c.id, getNoteIdsForCluster(c.id).length])
  );

  for (const cluster of finalClusters) {
    const noteIds = getNoteIdsForCluster(cluster.id);
    const clusterNotes = noteIds.map(id => noteById.get(id)!).filter(Boolean);
    writeSynthesisNote(cluster, clusterNotes, finalClusters, vaultPath);
  }

  writeSynthesisIndex(finalClusters, clusterNoteCounts, vaultPath);

  log.info(
    { clusterCount: finalClusters.length },
    'synthesize-topics workflow complete'
  );
}

main().catch(err => {
  log.error({ err }, 'synthesize-topics workflow failed');
  process.exit(1);
});
```

**Step 2: Add to `package.json` scripts**

In `package.json`, add to the `"scripts"` section:

```json
"workflow:synthesize-topics": "ts-node src/workflows/synthesize-topics.ts"
```

**Step 3: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

**Step 4: Smoke test against dev DB (first real run)**

```bash
SELENE_ENV=development npx ts-node src/workflows/synthesize-topics.ts
```

Expected: workflow logs, cluster discovery, Ollama calls, files written to `~/selene-data-dev/vault/Selene/Synthesis/`.

If Ollama isn't running:
```bash
ollama serve
# then retry
```

Inspect output:
```bash
ls ~/selene-data-dev/vault/Selene/Synthesis/
cat ~/selene-data-dev/vault/Selene/Synthesis/_INDEX.md
```

**Calibration:** If too few clusters appear, lower `minFrequency` from 3 to 2. If too many noise clusters appear, raise it to 4. Adjust in the `discoverClusters()` call in the workflow.

**Step 5: Commit**

```bash
git add src/workflows/synthesize-topics.ts package.json
git commit -m "feat: add synthesize-topics workflow"
```

---

### Task 9: Add synthesis link to Dashboard.md

`export-obsidian.ts` generates `Dashboard.md` on every hourly run. Add a `## Synthesis` section pointing to `_INDEX.md`. This is the only change to the existing export workflow.

**Files:**
- Modify: `src/workflows/export-obsidian.ts`

**Step 1: Find where Dashboard.md is generated**

```bash
grep -n "Dashboard\|dashboardMarkdown" src/workflows/export-obsidian.ts | head -15
```

**Step 2: Add synthesis section**

In the dashboard markdown template inside `export-obsidian.ts`, add this section after the existing content:

```typescript
const synthesisSection = `\n## Synthesis\n\n[[Selene/Synthesis/_INDEX]] — Browse auto-generated topic clusters\n`;
```

Append `synthesisSection` to the dashboard markdown string before it's written to disk.

**Step 3: Type-check and run**

```bash
npx tsc --noEmit
SELENE_ENV=development npx ts-node src/workflows/export-obsidian.ts
```

Verify `Dashboard.md` now contains the Synthesis section.

**Step 4: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "feat: add synthesis link to Obsidian Dashboard.md"
```

---

### Task 10: launchd plist and install script

**Files:**
- Create: `launchd/com.selene.synthesize-topics.plist`
- Modify: `scripts/install-launchd.sh`

**Step 1: Create `launchd/com.selene.synthesize-topics.plist`**

Copy `launchd/com.selene.daily-summary.plist` as a starting point:

```bash
cp launchd/com.selene.daily-summary.plist launchd/com.selene.synthesize-topics.plist
```

Then edit the new plist — change these values:
- `Label`: `com.selene.synthesize-topics`
- `ProgramArguments` script reference: `synthesize-topics`
- `StartCalendarInterval` `Hour`: `2` (run at 2am)
- `StandardOutPath`: `logs/synthesize-topics.out.log`
- `StandardErrorPath`: `logs/synthesize-topics.err.log`

Verify the plist XML looks correct:
```bash
plutil -lint launchd/com.selene.synthesize-topics.plist
```

Expected: `launchd/com.selene.synthesize-topics.plist: OK`

**Step 2: Add to `scripts/install-launchd.sh`**

Find the pattern where other plists are installed (grep for `com.selene.daily-summary`) and add the same block for `synthesize-topics`.

**Step 3: Install and verify**

```bash
./scripts/install-launchd.sh
launchctl list | grep selene
```

Expected: `com.selene.synthesize-topics` appears in the output.

**Step 4: Test manual trigger**

```bash
launchctl start com.selene.synthesize-topics
sleep 3
tail -20 logs/synthesize-topics.out.log
```

**Step 5: Commit**

```bash
git add launchd/com.selene.synthesize-topics.plist scripts/install-launchd.sh
git commit -m "feat: add synthesize-topics launchd agent (daily 2am)"
```

---

### Task 11: End-to-end calibration pass against production DB

Run the full workflow against the real database, inspect cluster quality, and tune thresholds if needed.

**Step 1: Run against production DB**

```bash
npx ts-node src/workflows/synthesize-topics.ts
```

**Step 2: Inspect clusters in DB**

```bash
sqlite3 data/selene.db "
SELECT tc.name, tc.slug, COUNT(tnl.raw_note_id) AS note_count
FROM topic_clusters tc
LEFT JOIN topic_note_links tnl ON tnl.topic_id = tc.id
GROUP BY tc.id
ORDER BY note_count DESC;
"
```

**Step 3: Read synthesis files**

```bash
ls ~/selene-data/vault/Selene/Synthesis/
cat ~/selene-data/vault/Selene/Synthesis/_INDEX.md
cat ~/selene-data/vault/Selene/Synthesis/<first-cluster-slug>.md
```

**Step 4: Threshold tuning**

| Symptom | Fix |
|---------|-----|
| Too many small/noisy clusters | Raise `minFrequency` from 3 to 4 |
| Obvious topics not forming | Lower `minFrequency` to 2 |
| Related topics staying separate | Lower `mergeThreshold` from 0.6 to 0.5 |
| Unrelated topics merging | Raise `mergeThreshold` to 0.7 |

Edit the `discoverClusters()` call in `synthesize-topics.ts` and re-run.

**Step 5: Move design doc to Ready in INDEX**

Once calibration passes, update `docs/plans/INDEX.md`: move the synthesis-layer entry from Vision to Ready, and add the acceptance criteria checkboxes as verified.

**Step 6: Final commit**

```bash
git add docs/plans/INDEX.md
git commit -m "docs: mark synthesis layer design as Ready"
```

---

## Acceptance Criteria Checklist

Run these after Task 11:

```bash
# Tables exist
sqlite3 data/selene.db ".tables" | grep -E "topic_clusters|topic_note_links"

# Clusters detected
sqlite3 data/selene.db "SELECT COUNT(*) FROM topic_clusters;"

# Notes linked
sqlite3 data/selene.db "SELECT COUNT(*) FROM topic_note_links;"

# Synthesis files written
ls ~/selene-data/vault/Selene/Synthesis/
ls ~/selene-data/vault/Selene/Synthesis/_INDEX.md

# Workflow runs without error
npx ts-node src/workflows/synthesize-topics.ts 2>&1 | tail -5

# launchd agent registered
launchctl list | grep com.selene.synthesize-topics
```
