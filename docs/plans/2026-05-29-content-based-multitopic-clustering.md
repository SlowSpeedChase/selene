# Content-Based Multi-Topic Clustering — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the iPad Notes "E-Ink Empowerment" 104-note bucket with content-themed topics, where a multi-topic brain-dump note appears under every topic it touches.

**Architecture:** Move the clustering unit from whole-note → chunk. `process-llm.ts` de-biases source boilerplate, segments each note into topical chunks (structural split + local-LLM refine/label), and embeds each chunk into `note_chunks`. `synthesize-topics.ts` clusters chunk vectors (greedy, re-tuned threshold) and links each parent note to **every** topic its chunks land in via the existing many-to-many `topic_note_links`. No schema migration. Full clean rebuild on a prod→dev snapshot first, gated by a Phase 0 spike.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (`mistral:7b` via `generate()`, `nomic-embed-text` via `embed()`), Jest (ts-jest), launchd.

---

## Design reference

Full design: `docs/plans/2026-05-29-content-based-multitopic-clustering-design.md`. Read it before starting — especially the **Phase 0 spike gate**: if chunks do not separate distinct topics at a usable threshold, STOP and rethink before building Phases 1–5.

## Conventions for this plan

- **Tests:** Jest style (`describe`/`it`, in-memory `better-sqlite3`), modeled on `src/routes/notes.test.ts`. Run a single file with `npx jest <path> --runInBand`.
- **Never test against the prod DB** (`~/selene-data/selene.db`). The spike and reprocess run against the dev DB (`~/selene-data-dev/selene.db`), seeded from a prod snapshot.
- **Reviewer:** after editing `synthesize-topics.ts`, invoke the `synthesis-reviewer` subagent. After editing Ollama-touching code, invoke `ollama-dependency-reviewer`.
- **Commit after every green step.**

---

## Phase 0 — SPIKE (GATE — do this first, build nothing else until it passes)

### Task 0: Measure whether in-note topics separate

**Files:**
- Create: `scripts/spike-chunk-separation.ts` (throwaway; delete or archive after).

**Step 1: Confirm the dev DB exists and is prod-seeded**

Run:
```bash
ls -la ~/selene-data-dev/selene.db && \
sqlite3 ~/selene-data-dev/selene.db "SELECT name, note_count FROM topic_clusters ORDER BY note_count DESC LIMIT 3;"
```
Expected: the dev DB exists and the "E-Ink Empowerment" cluster is present. If not, snapshot first:
```bash
cp ~/selene-data-dev/selene.db ~/selene-data-dev/selene.db.bak.$(date +%s) 2>/dev/null; \
cp ~/selene-data/selene.db ~/selene-data-dev/selene.db
```

**Step 2: Write the spike script**

```typescript
// scripts/spike-chunk-separation.ts
// Throwaway: does chunking actually separate distinct topics, or re-collapse?
import { embed } from '../src/lib/ollama';
import { cosineSimilarity } from '../src/lib/cosine';
import Database from 'better-sqlite3';
import { homedir } from 'os';
import { join } from 'path';

const db = new Database(join(homedir(), 'selene-data-dev', 'selene.db'), { readonly: true });

// Pull ~8 e-ink notes from the mega-cluster.
const rows = db.prepare(`
  SELECT r.id, r.content
  FROM raw_notes r
  JOIN topic_note_links l ON l.note_id = r.id
  JOIN topic_clusters t ON t.id = l.topic_id
  WHERE r.capture_type = 'eink' AND t.note_count > 50
  ORDER BY LENGTH(r.content) DESC
  LIMIT 8
`).all() as Array<{ id: number; content: string }>;

// Naive structural segmentation for the spike (page/heading/blank-line).
function naiveSegment(content: string): string[] {
  return content
    .replace(/^#\s*E-Ink:.*$/gim, '')
    .split(/\n-{2,}\s*Page\s*\d+\s*-{2,}\n|\n#{1,6}\s|\n\s*\n/g)
    .map(s => s.trim())
    .filter(s => s.length > 40);
}

(async () => {
  const chunks: Array<{ noteId: number; idx: number; text: string; vec: number[] }> = [];
  for (const r of rows) {
    const segs = naiveSegment(r.content);
    for (let i = 0; i < segs.length; i++) {
      chunks.push({ noteId: r.id, idx: i, text: segs[i], vec: await embed(segs[i]) });
    }
  }
  console.log(`Notes: ${rows.length}, chunks: ${chunks.length}`);

  // Within-note chunk similarity (do a note's own topics pull apart?)
  let withinPairs = 0, withinSum = 0;
  for (let a = 0; a < chunks.length; a++)
    for (let b = a + 1; b < chunks.length; b++)
      if (chunks[a].noteId === chunks[b].noteId) {
        withinSum += cosineSimilarity(chunks[a].vec, chunks[b].vec); withinPairs++;
      }

  // Cross-note chunk similarity (do different notes' chunks still all look alike?)
  let crossPairs = 0, crossSum = 0;
  for (let a = 0; a < chunks.length; a++)
    for (let b = a + 1; b < chunks.length; b++)
      if (chunks[a].noteId !== chunks[b].noteId) {
        crossSum += cosineSimilarity(chunks[a].vec, chunks[b].vec); crossPairs++;
      }

  console.log(`Mean within-note chunk sim:  ${(withinSum / withinPairs).toFixed(3)}`);
  console.log(`Mean cross-note chunk sim:   ${(crossSum / crossPairs).toFixed(3)}`);
  console.log('Threshold sweep (chunks merged at θ as fraction of all cross pairs):');
  for (const th of [0.55, 0.6, 0.65, 0.7, 0.75, 0.8]) {
    let merged = 0;
    for (let a = 0; a < chunks.length; a++)
      for (let b = a + 1; b < chunks.length; b++)
        if (cosineSimilarity(chunks[a].vec, chunks[b].vec) >= th) merged++;
    console.log(`  θ=${th}: ${merged}/${(chunks.length * (chunks.length - 1)) / 2} pairs merge`);
  }
})();
```

**Step 3: Run the spike**

Run: `npx ts-node scripts/spike-chunk-separation.ts`
Expected: prints within-note mean, cross-note mean, and a θ sweep.

**Step 4: GATE decision (write it down in the design doc's spike section)**

- **PASS** if there is a θ where chunks from *different* topics within a note separate (within-note mean noticeably below ~0.8) AND that θ does not merge nearly all cross-note pairs (so distinct topics across notes stay distinct). Record the candidate θ — it becomes `CLUSTER_SIMILARITY_THRESHOLD` in Task 7.
- **FAIL** if within-note and cross-note means are both high and close (chunks re-collapse). → STOP. Do not build Phases 1–5. Return to brainstorming for an alternative (hierarchical topics, or accept broad themes). 

**Step 5: Commit the spike + recorded decision**

```bash
git add scripts/spike-chunk-separation.ts docs/plans/2026-05-29-content-based-multitopic-clustering-design.md
git commit -m "spike: measure chunk topic separation on dev e-ink notes"
```

> Proceed past this line ONLY if the gate PASSED.

---

## Phase 1 — De-bias source boilerplate (pure, TDD)

### Task 1: `debiasContent()`

**Files:**
- Create: `src/lib/segmentation.ts`
- Test: `src/lib/segmentation.test.ts`

**Step 1: Write the failing test**

```typescript
// src/lib/segmentation.test.ts
import { debiasContent } from './segmentation';

describe('debiasContent', () => {
  it('strips the "# E-Ink: ..." header line', () => {
    const input = '# E-Ink: 2026-01-05 kindle journal\n\nReal content here.';
    expect(debiasContent(input, 'E-Ink: 2026-01-05 kindle journal')).toBe('Real content here.');
  });

  it('strips "--- Page N ---" separators but keeps the text between them', () => {
    const input = '--- Page 1 ---\nAlpha\n--- Page 2 ---\nBeta';
    expect(debiasContent(input, 't')).toBe('Alpha\nBeta');
  });

  it('leaves a normal drafts note untouched', () => {
    const input = 'Just a normal thought about pedestrian safety.';
    expect(debiasContent(input, 'Pedestrian safety')).toBe(input);
  });
});
```

**Step 2: Run to verify it fails**

Run: `npx jest src/lib/segmentation.test.ts --runInBand`
Expected: FAIL — "Cannot find module './segmentation'" / `debiasContent is not a function`.

**Step 3: Minimal implementation**

```typescript
// src/lib/segmentation.ts

/** Remove source-capture boilerplate so embeddings reflect content, not origin. */
export function debiasContent(content: string, _title: string): string {
  return content
    .replace(/^#\s*E-Ink:.*$/gim, '')              // "# E-Ink: <date> kindle journal"
    .replace(/^-{2,}\s*Page\s*\d+\s*-{2,}\s*$/gim, '') // "--- Page N ---"
    .replace(/\n{3,}/g, '\n\n')                      // collapse blank runs left behind
    .trim();
}
```

**Step 4: Run to verify it passes**

Run: `npx jest src/lib/segmentation.test.ts --runInBand`
Expected: PASS (3 tests).

**Step 5: Commit**

```bash
git add src/lib/segmentation.ts src/lib/segmentation.test.ts
git commit -m "feat: debiasContent strips source boilerplate before clustering"
```

---

## Phase 2 — Structural segmentation (pure, TDD)

### Task 2: `segmentStructural()`

**Files:**
- Modify: `src/lib/segmentation.ts`
- Modify: `src/lib/segmentation.test.ts`

**Step 1: Write the failing test**

```typescript
import { debiasContent, segmentStructural } from './segmentation';

describe('segmentStructural', () => {
  it('splits on page markers and headings, dropping tiny fragments', () => {
    const input = [
      '--- Page 1 ---',
      '**Title:** Vision Board',
      'A long enough first segment about clarifying life direction and drivers.',
      '--- Page 2 ---',
      '## Finances',
      'A second long enough segment about budgeting and savings goals over time.',
      'ok', // too short -> dropped
    ].join('\n');
    const segs = segmentStructural(input);
    expect(segs.length).toBe(2);
    expect(segs[0]).toContain('life direction');
    expect(segs[1]).toContain('budgeting');
  });

  it('returns the whole note as one segment when there are no boundaries', () => {
    const input = 'A single coherent paragraph with no markers but plenty of length to keep.';
    expect(segmentStructural(input)).toEqual([input]);
  });
});
```

**Step 2: Run to verify it fails**

Run: `npx jest src/lib/segmentation.test.ts --runInBand`
Expected: FAIL — `segmentStructural is not a function`.

**Step 3: Minimal implementation (append to `segmentation.ts`)**

```typescript
const MIN_SEGMENT_CHARS = 40;

/** First-pass split on natural boundaries: page markers, headings, blank lines. */
export function segmentStructural(content: string): string[] {
  const segs = content
    .split(/\n-{2,}\s*Page\s*\d+\s*-{2,}\n|\n#{1,6}\s|\n\s*\n/g)
    .map(s => s.trim())
    .filter(s => s.length >= MIN_SEGMENT_CHARS);
  return segs.length > 0 ? segs : [content.trim()];
}
```

**Step 4: Run to verify it passes**

Run: `npx jest src/lib/segmentation.test.ts --runInBand`
Expected: PASS (5 tests total).

**Step 5: Commit**

```bash
git add src/lib/segmentation.ts src/lib/segmentation.test.ts
git commit -m "feat: segmentStructural splits notes on page/heading/blank boundaries"
```

---

## Phase 3 — LLM refine + label (Ollama wrapper)

### Task 3: `SEGMENT_PROMPT` + `segmentNote()`

**Files:**
- Modify: `src/lib/prompts.ts` (add `SEGMENT_PROMPT`, export it)
- Modify: `src/lib/index.ts` (export `SEGMENT_PROMPT`)
- Modify: `src/lib/segmentation.ts`
- Modify: `src/lib/segmentation.test.ts`

**Step 1: Add the prompt**

In `src/lib/prompts.ts`:
```typescript
export const SEGMENT_PROMPT = `You are splitting a brain-dump note into distinct TOPICAL segments.
Rules:
- Each segment covers ONE coherent topic. Merge fragments that share a topic; split blocks that mix topics.
- Do NOT mention how/where the note was captured (no "e-ink", "kindle", "page", "handwritten").
- Return ONLY a JSON array: [{"topic":"2-4 word theme","text":"the segment text"}]

Pre-split segments:
{segments}`;
```
Add `SEGMENT_PROMPT` to the `prompts` export in `src/lib/index.ts` (the existing `export { ... } from './prompts'` line).

**Step 2: Write the failing test (LLM is injected so the test is deterministic)**

```typescript
import { segmentNote } from './segmentation';

describe('segmentNote', () => {
  it('de-biases, structurally splits, then maps the LLM JSON to chunks', async () => {
    const fakeLLM = async () =>
      '[{"topic":"life direction","text":"clarify drivers"},{"topic":"finances","text":"budget goals"}]';
    const chunks = await segmentNote(
      '# E-Ink: x\n--- Page 1 ---\nclarify drivers and direction here\n## Finances\nbudget and savings goals here',
      'E-Ink: x',
      fakeLLM,
    );
    expect(chunks).toEqual([
      { topic: 'life direction', text: 'clarify drivers' },
      { topic: 'finances', text: 'budget goals' },
    ]);
  });

  it('falls back to structural chunks (topic=null) when the LLM returns junk', async () => {
    const fakeLLM = async () => 'sorry I cannot do that';
    const chunks = await segmentNote(
      'A single coherent paragraph long enough to survive the minimum length filter.',
      't',
      fakeLLM,
    );
    expect(chunks.length).toBe(1);
    expect(chunks[0].topic).toBeNull();
  });
});
```

**Step 3: Run to verify it fails**

Run: `npx jest src/lib/segmentation.test.ts --runInBand`
Expected: FAIL — `segmentNote is not a function`.

**Step 4: Implement (append to `segmentation.ts`)**

```typescript
export interface NoteChunk { topic: string | null; text: string; }

type LLM = (prompt: string) => Promise<string>;

/** De-bias → structural split → LLM refine/label. LLM injected for testability. */
export async function segmentNote(content: string, title: string, llm: LLM): Promise<NoteChunk[]> {
  const clean = debiasContent(content, title);
  const structural = segmentStructural(clean);
  const fallback: NoteChunk[] = structural.map(text => ({ topic: null, text }));

  const { SEGMENT_PROMPT } = await import('./prompts');
  try {
    const raw = await llm(SEGMENT_PROMPT.replace('{segments}', structural.join('\n---\n')));
    const match = raw.match(/\[[\s\S]*\]/);
    if (!match) return fallback;
    const parsed = JSON.parse(match[0]) as Array<{ topic?: string; text?: string }>;
    const chunks = parsed
      .filter(c => c.text && c.text.trim().length > 0)
      .map(c => ({ topic: c.topic?.trim() || null, text: c.text!.trim() }));
    return chunks.length > 0 ? chunks : fallback;
  } catch {
    return fallback;
  }
}
```

**Step 5: Run to verify it passes**

Run: `npx jest src/lib/segmentation.test.ts --runInBand`
Expected: PASS.

**Step 6: Commit, then review**

```bash
git add src/lib/segmentation.ts src/lib/segmentation.test.ts src/lib/prompts.ts src/lib/index.ts
git commit -m "feat: segmentNote refines+labels chunks via local LLM with structural fallback"
```
Then invoke the `ollama-dependency-reviewer` subagent on the prompt/response contract.

---

## Phase 4 — Persist chunks + embeddings in process-llm

### Task 4: Write `note_chunks` during processing

**Files:**
- Modify: `src/workflows/process-llm.ts` (after the whole-note `embed`/`indexNote` block, ~line 145)
- Test: `src/workflows/process-llm.chunks.test.ts`

**Step 1: Write the failing test (pure helper, DB injected)**

Extract a small persistence helper so it is testable without Ollama. Add to `process-llm.ts`:
```typescript
export function replaceNoteChunks(
  database: import('better-sqlite3').Database,
  noteId: number,
  chunks: Array<{ topic: string | null; text: string; vector: number[] }>,
  now: string,
): void {
  database.prepare('DELETE FROM note_chunks WHERE note_id = ?').run(noteId);
  const ins = database.prepare(
    `INSERT INTO note_chunks (note_id, chunk_index, content, topic, token_count, embedding, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  );
  chunks.forEach((c, i) =>
    ins.run(noteId, i, c.text, c.topic, Math.ceil(c.text.length / 4), JSON.stringify(c.vector), now)
  );
}
```

Test:
```typescript
// src/workflows/process-llm.chunks.test.ts
import Database from 'better-sqlite3';
import { replaceNoteChunks } from './process-llm';

describe('replaceNoteChunks', () => {
  let db: InstanceType<typeof Database>;
  beforeEach(() => {
    db = new Database(':memory:');
    db.exec(`CREATE TABLE note_chunks (id INTEGER PRIMARY KEY AUTOINCREMENT, note_id INTEGER NOT NULL,
      chunk_index INTEGER NOT NULL, content TEXT NOT NULL, topic TEXT, token_count INTEGER NOT NULL,
      embedding BLOB, created_at TEXT NOT NULL, UNIQUE(note_id, chunk_index));`);
  });

  it('replaces prior chunks idempotently', () => {
    replaceNoteChunks(db, 1, [{ topic: 'a', text: 'x', vector: [0.1] }], 't');
    replaceNoteChunks(db, 1, [
      { topic: 'b', text: 'y', vector: [0.2] },
      { topic: 'c', text: 'z', vector: [0.3] },
    ], 't');
    const rows = db.prepare('SELECT topic, embedding FROM note_chunks WHERE note_id=1 ORDER BY chunk_index').all() as Array<{topic:string;embedding:string}>;
    expect(rows.map(r => r.topic)).toEqual(['b', 'c']);
    expect(JSON.parse(rows[0].embedding)).toEqual([0.2]);
  });
});
```

**Step 2: Run to verify it fails**

Run: `npx jest src/workflows/process-llm.chunks.test.ts --runInBand`
Expected: FAIL — `replaceNoteChunks is not a function`.

**Step 3: Implement** the helper (above) and wire it into the per-note loop after the whole-note embedding succeeds:
```typescript
        // Chunk-level segmentation for multi-topic clustering
        try {
          const { segmentNote } = await import('../lib/segmentation');
          const segs = await segmentNote(note.content, note.title, generate);
          const withVecs = [];
          for (const s of segs) withVecs.push({ ...s, vector: await embed(s.text) });
          replaceNoteChunks(db, note.id, withVecs, new Date().toISOString());
          log.info({ noteId: note.id, chunks: withVecs.length }, 'Chunks embedded');
        } catch (chunkErr) {
          log.warn({ noteId: note.id, err: chunkErr as Error }, 'Chunking failed, will retry next run');
        }
```

**Step 4: Run to verify it passes**

Run: `npx jest src/workflows/process-llm.chunks.test.ts --runInBand`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/workflows/process-llm.ts src/workflows/process-llm.chunks.test.ts
git commit -m "feat: process-llm segments and embeds note_chunks per note"
```

---

## Phase 5 — Cluster chunks + multi-topic membership

### Task 5: Membership union helper (pure, TDD)

**Files:**
- Modify: `src/workflows/synthesize-topics.ts`
- Test: `src/workflows/synthesize-topics.membership.test.ts`

**Step 1: Write the failing test**

```typescript
import { notesPerCluster } from './synthesize-topics';

describe('notesPerCluster', () => {
  it('maps chunk clusters to DISTINCT parent notes (dedup within a cluster)', () => {
    // cluster -> chunk owners (noteId); note 7 contributes two chunks to cluster A
    const clusters = new Map<string, number[]>([
      ['A', [7, 7, 9]],   // note 7 twice -> counted once
      ['B', [7, 12]],     // note 7 also here -> multi-membership
    ]);
    const result = notesPerCluster(clusters);
    expect(result.get('A')).toEqual([7, 9]);
    expect(result.get('B')).toEqual([7, 12]);
  });
});
```

**Step 2: Run to verify it fails**

Run: `npx jest src/workflows/synthesize-topics.membership.test.ts --runInBand`
Expected: FAIL — `notesPerCluster is not a function`.

**Step 3: Implement (export from `synthesize-topics.ts`)**

```typescript
/** Chunk-cluster (clusterId -> chunk-owner noteIds) -> distinct parent notes per cluster. */
export function notesPerCluster(clusters: Map<string, number[]>): Map<string, number[]> {
  const out = new Map<string, number[]>();
  for (const [id, owners] of clusters) out.set(id, [...new Set(owners)]);
  return out;
}
```

**Step 4: Run to verify it passes**

Run: `npx jest src/workflows/synthesize-topics.membership.test.ts --runInBand`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/workflows/synthesize-topics.ts src/workflows/synthesize-topics.membership.test.ts
git commit -m "feat: notesPerCluster derives distinct multi-topic note membership"
```

### Task 6: Cluster over chunk vectors

**Files:**
- Modify: `src/workflows/synthesize-topics.ts`

**Step 1: Add `loadAllChunkEmbeddings()`** (parallels `loadAllEmbeddings`, but per chunk):
```typescript
interface ChunkEmbedding { noteId: number; chunkId: number; topic: string | null; vector: number[]; }

function loadAllChunkEmbeddings(): ChunkEmbedding[] {
  const rows = db.prepare(`
    SELECT c.id AS chunkId, c.note_id AS noteId, c.topic, c.embedding
    FROM note_chunks c
    WHERE c.embedding IS NOT NULL
  `).all() as Array<{ chunkId: number; noteId: number; topic: string | null; embedding: string }>;
  return rows.map(r => ({ chunkId: r.chunkId, noteId: r.noteId, topic: r.topic, vector: JSON.parse(r.embedding) as number[] }));
}
```

**Step 2: Add `clusterChunks()`** (greedy over chunk vectors, returns clusterId → chunk-owner noteIds):
```typescript
function clusterChunks(chunks: ChunkEmbedding[]): { clusters: Map<string, number[]>; topics: Map<string, (string|null)[]> } {
  const assigned = new Set<number>();           // by chunkId
  const clusters = new Map<string, number[]>(); // clusterId -> owner noteIds
  const topics = new Map<string, (string|null)[]>();
  for (let i = 0; i < chunks.length; i++) {
    if (assigned.has(chunks[i].chunkId)) continue;
    assigned.add(chunks[i].chunkId);
    const owners = [chunks[i].noteId];
    const tlist = [chunks[i].topic];
    for (let j = i + 1; j < chunks.length; j++) {
      if (assigned.has(chunks[j].chunkId)) continue;
      if (cosineSimilarity(chunks[i].vector, chunks[j].vector) >= CLUSTER_SIMILARITY_THRESHOLD) {
        owners.push(chunks[j].noteId); tlist.push(chunks[j].topic); assigned.add(chunks[j].chunkId);
      }
    }
    const id = randomUUID();
    clusters.set(id, owners);
    topics.set(id, tlist);
  }
  return { clusters, topics };
}
```

**Step 3:** In `synthesizeTopics()`, replace `loadAllEmbeddings()`/`clusterNotes()` usage with `loadAllChunkEmbeddings()` → `clusterChunks()` → `notesPerCluster()`. For each cluster: `noteIds = distinct parents`; `is_proto = noteIds.length < MIN_CLUSTER_SIZE`; insert into `topic_clusters`; insert one `topic_note_links(topicId, noteId)` per distinct parent. Keep the existing delta-guard/evolution logic keyed off `noteIds`.

**Step 4: Type-check**

Run: `npx tsc --noEmit`
Expected: no errors.

**Step 5: Commit, then review**

```bash
git add src/workflows/synthesize-topics.ts
git commit -m "feat: cluster over chunk vectors with multi-topic note membership"
```
Invoke the `synthesis-reviewer` subagent on `synthesize-topics.ts` + the `topic_clusters`/`topic_note_links` contract.

### Task 7: Re-tune threshold + de-bias naming

**Files:**
- Modify: `src/workflows/synthesize-topics.ts`

**Step 1:** Set `CLUSTER_SIMILARITY_THRESHOLD` to the value recorded in Task 0's gate. Add a one-line comment citing the spike.

**Step 2:** In `generateClusterName()`, append to the prompt: *"Name the topic by its CONTENT theme only. Never use capture-source or format words (e-ink, kindle, page, handwritten, draft, voice)."*

**Step 3: Type-check + commit**

Run: `npx tsc --noEmit`
```bash
git add src/workflows/synthesize-topics.ts
git commit -m "tune: chunk-similarity threshold from spike; forbid source words in cluster names"
```

---

## Phase 6 — Reprocess (dev first, then prod)

### Task 8: Full clean rebuild on the dev snapshot

**Step 1: Re-snapshot prod → dev (fresh)**
```bash
cp ~/selene-data-dev/selene.db ~/selene-data-dev/selene.db.bak.$(date +%s)
cp ~/selene-data/selene.db ~/selene-data-dev/selene.db
```

**Step 2: Wipe stale chunks + clusters (dev DB only)**
```bash
sqlite3 ~/selene-data-dev/selene.db "DELETE FROM note_chunks; DELETE FROM topic_note_links; DELETE FROM topic_clusters;"
```

**Step 3: Reprocess to regenerate chunks, then cluster**

`processLlm(limit = 10)` (selected via `getPendingNotes`, status `pending` → `processed`) handles only 10 notes per run, so loop until no pending notes remain (~293 notes ≈ 30 batches). The repo already has `./scripts/dev-process-batch.sh` for exactly this batching.
```bash
# Re-queue every note so process-llm re-chunks all of them.
sqlite3 ~/selene-data-dev/selene.db "UPDATE raw_notes SET status='pending';"
# Loop batches until none remain (or run ./scripts/dev-process-batch.sh repeatedly / --status).
while [ "$(sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) FROM raw_notes WHERE status='pending';")" != "0" ]; do
  SELENE_ENV=development npx ts-node src/workflows/process-llm.ts
done
# Now cluster the freshly embedded chunks.
SELENE_ENV=development npx ts-node src/workflows/synthesize-topics.ts
```

**Step 4: Inspect the resulting browse view (acceptance check)**
```bash
sqlite3 ~/selene-data-dev/selene.db "SELECT name, note_count FROM topic_clusters WHERE is_proto=0 ORDER BY note_count DESC LIMIT 20;"
# eink concentration of the biggest cluster (should NOT be ~all eink):
sqlite3 ~/selene-data-dev/selene.db "SELECT tc.name, r.capture_type, COUNT(*) FROM topic_clusters tc JOIN topic_note_links l ON l.topic_id=tc.id JOIN raw_notes r ON r.id=l.note_id WHERE tc.is_proto=0 GROUP BY tc.id, r.capture_type ORDER BY tc.note_count DESC LIMIT 15;"
# multi-membership exists (at least one note in >1 cluster):
sqlite3 ~/selene-data-dev/selene.db "SELECT note_id, COUNT(*) c FROM topic_note_links GROUP BY note_id HAVING c>1 ORDER BY c DESC LIMIT 5;"
```
Verify against `## Acceptance criteria` in the design doc. If the view is a wall of singletons or still source-dominated, iterate `CLUSTER_SIMILARITY_THRESHOLD` / `MIN_CLUSTER_SIZE` and re-run Step 3.

**Step 5:** Optional — point the dev server at the rebuilt dev DB and confirm `/api/clusters` on the iPad shows content themes.

### Task 9: Ship to prod

**Step 1:** Open a PR from the feature branch; merge to `main` (the gated deploy-watcher builds + deploys `dist/` per `docs/guides/features/releases.md`).

**Step 2:** After deploy, run the one-shot rebuild against the **prod** DB on the prod host:
```bash
sqlite3 ~/selene-data/selene.db ".backup ~/selene-data/selene.db.prebackup"
sqlite3 ~/selene-data/selene.db "DELETE FROM note_chunks; DELETE FROM topic_note_links; DELETE FROM topic_clusters;"
# Trigger prod process-llm + synthesize-topics (compiled): kick the launchd agents.
# process-llm runs 10 notes/run — kick it repeatedly (or let its schedule drain the queue)
# until no pending notes remain, THEN run synthesize-topics once.
while [ "$(sqlite3 ~/selene-data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE status='pending';")" != "0" ]; do
  launchctl start com.selene.prod.process-llm
  sleep 60   # allow the run to finish before re-kicking
done
launchctl start com.selene.prod.synthesize-topics
```
(Confirm exact prod invocation against `releases.md`; prefer the launchd agents over ad-hoc `node dist/...`. Re-queueing prod notes with `UPDATE raw_notes SET status='pending'` reprocesses everything — acceptable here because the rebuild is the whole point, but note it also recomputes essences/embeddings.)

**Step 3:** Verify on the iPad Notes section: no source-named mega-bucket; multi-topic notes appear under multiple themes.

### Task 10: Wrap-up

- Update/create `docs/guides/features/` entry for clustering / notes browse (multi-topic membership, content-themed names); link it in `docs/USER-EXPERIENCE.md`.
- Move the design doc to **Done** in `docs/plans/INDEX.md`.
- Delete or archive `scripts/spike-chunk-separation.ts`.
- `./scripts/cleanup-tests.sh --list` and clean any stray `test_run` rows.

---

## Acceptance criteria (mirror of the design)

- [ ] Phase 0 spike PASSED and θ recorded.
- [ ] On the dev snapshot, the 104-note e-ink bucket is gone; topics are content-themed.
- [ ] At least one note appears under multiple topics.
- [ ] No source/format words in cluster names.
- [ ] Browse view is neither one mega-bucket nor a wall of singletons.
- [ ] Prod iPad Notes section reflects the above after deploy + rebuild.
