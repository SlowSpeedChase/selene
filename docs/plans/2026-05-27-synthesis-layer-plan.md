# Synthesis Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add three layered synthesis signals to the 6am digest — topic clusters with synthesis narratives, evolution detection when understanding shifts, and connection detection when new notes link to older ones.

**Architecture:** Approach 2 (layered). Connection detection (C) runs inside `process-llm.ts` immediately after embedding generation. Topic clustering, synthesis, evolution detection (A), and proto-cluster detection (B) run nightly in a new `synthesize-topics.ts` workflow. `send-digest.ts` gains 4 new digest sections reading from new SQLite tables.

**Tech Stack:** TypeScript, better-sqlite3, Ollama (`nomic-embed-text` for embeddings, `mistral:7b` for synthesis), LanceDB (for connection similarity search), launchd (scheduling).

---

## Task 1: Database schema migrations

**Files:**
- Create: `src/lib/synthesis-db.ts`
- Test: `src/lib/synthesis-db.test.ts`

### Step 1: Write the failing test

```typescript
// src/lib/synthesis-db.test.ts
import Database from 'better-sqlite3';
import { initSynthesisSchema } from './synthesis-db';

describe('initSynthesisSchema', () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(':memory:');
  });

  afterEach(() => {
    db.close();
  });

  it('creates topic_clusters table', () => {
    initSynthesisSchema(db);
    const row = db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='topic_clusters'"
    ).get();
    expect(row).toBeDefined();
  });

  it('creates topic_note_links table', () => {
    initSynthesisSchema(db);
    const row = db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='topic_note_links'"
    ).get();
    expect(row).toBeDefined();
  });

  it('creates note_connections table', () => {
    initSynthesisSchema(db);
    const row = db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='note_connections'"
    ).get();
    expect(row).toBeDefined();
  });

  it('creates synthesis_meta table', () => {
    initSynthesisSchema(db);
    const row = db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='synthesis_meta'"
    ).get();
    expect(row).toBeDefined();
  });

  it('is idempotent — can be called twice without error', () => {
    expect(() => {
      initSynthesisSchema(db);
      initSynthesisSchema(db);
    }).not.toThrow();
  });
});
```

### Step 2: Run test to verify it fails

```bash
npx jest src/lib/synthesis-db.test.ts --no-coverage
```

Expected: FAIL — "Cannot find module './synthesis-db'"

### Step 3: Write minimal implementation

```typescript
// src/lib/synthesis-db.ts
import type { Database } from 'better-sqlite3';

export function initSynthesisSchema(db: Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS topic_clusters (
      id                    TEXT PRIMARY KEY,
      name                  TEXT NOT NULL,
      slug                  TEXT NOT NULL UNIQUE,
      parent_id             TEXT REFERENCES topic_clusters(id),
      synthesis_text        TEXT,
      prev_synthesis_text   TEXT,
      synthesis_updated_at  TEXT,
      evolution_detected_at TEXT,
      evolution_summary     TEXT,
      note_count            INTEGER NOT NULL DEFAULT 0,
      split_threshold       INTEGER NOT NULL DEFAULT 8,
      is_proto              INTEGER NOT NULL DEFAULT 0,
      created_at            TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS topic_note_links (
      topic_id  TEXT NOT NULL REFERENCES topic_clusters(id),
      note_id   INTEGER NOT NULL,
      added_at  TEXT NOT NULL,
      PRIMARY KEY (topic_id, note_id)
    );

    CREATE INDEX IF NOT EXISTS idx_tnl_topic ON topic_note_links(topic_id);
    CREATE INDEX IF NOT EXISTS idx_tnl_note  ON topic_note_links(note_id);

    CREATE TABLE IF NOT EXISTS note_connections (
      id               TEXT PRIMARY KEY,
      source_note_id   INTEGER NOT NULL,
      target_note_id   INTEGER NOT NULL,
      similarity_score REAL NOT NULL,
      found_at         TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_nc_source ON note_connections(source_note_id);
    CREATE INDEX IF NOT EXISTS idx_nc_found  ON note_connections(found_at);

    CREATE TABLE IF NOT EXISTS synthesis_meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  `);
}
```

### Step 4: Run test to verify it passes

```bash
npx jest src/lib/synthesis-db.test.ts --no-coverage
```

Expected: PASS — 5 tests green

### Step 5: Commit

```bash
git add src/lib/synthesis-db.ts src/lib/synthesis-db.test.ts
git commit -m "feat: synthesis DB schema — 4 new tables (topic_clusters, topic_note_links, note_connections, synthesis_meta)"
```

---

## Task 2: Cosine similarity utility

The clustering algorithm needs pairwise cosine similarity between note embedding vectors. This is a pure function — ideal for TDD.

**Files:**
- Create: `src/lib/cosine.ts`
- Test: `src/lib/cosine.test.ts`

### Step 1: Write the failing tests

```typescript
// src/lib/cosine.test.ts
import { cosineSimilarity } from './cosine';

describe('cosineSimilarity', () => {
  it('returns 1.0 for identical vectors', () => {
    const v = [1, 0, 0];
    expect(cosineSimilarity(v, v)).toBeCloseTo(1.0, 5);
  });

  it('returns 0.0 for orthogonal vectors', () => {
    expect(cosineSimilarity([1, 0], [0, 1])).toBeCloseTo(0.0, 5);
  });

  it('returns -1.0 for opposite vectors', () => {
    expect(cosineSimilarity([1, 0], [-1, 0])).toBeCloseTo(-1.0, 5);
  });

  it('handles 768-dimension vectors without overflow', () => {
    const a = new Array(768).fill(0.1);
    const b = new Array(768).fill(0.1);
    expect(cosineSimilarity(a, b)).toBeCloseTo(1.0, 3);
  });

  it('returns a value between -1 and 1', () => {
    const a = Array.from({ length: 768 }, () => Math.random() - 0.5);
    const b = Array.from({ length: 768 }, () => Math.random() - 0.5);
    const sim = cosineSimilarity(a, b);
    expect(sim).toBeGreaterThanOrEqual(-1.0);
    expect(sim).toBeLessThanOrEqual(1.0);
  });
});
```

### Step 2: Run test to verify it fails

```bash
npx jest src/lib/cosine.test.ts --no-coverage
```

Expected: FAIL — "Cannot find module './cosine'"

### Step 3: Write minimal implementation

```typescript
// src/lib/cosine.ts
export function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0;
  let magA = 0;
  let magB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }
  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  return denom === 0 ? 0 : dot / denom;
}
```

### Step 4: Run test to verify it passes

```bash
npx jest src/lib/cosine.test.ts --no-coverage
```

Expected: PASS — 5 tests green

### Step 5: Commit

```bash
git add src/lib/cosine.ts src/lib/cosine.test.ts
git commit -m "feat: cosineSimilarity utility for clustering"
```

---

## Task 3: Embedding generation in process-llm.ts

Extend the existing `processLlm` loop: after writing to `processed_notes`, generate an embedding and write to `note_embeddings` + index in LanceDB. This ensures every new note gets an embedding at process time.

**Files:**
- Modify: `src/workflows/process-llm.ts`

### Step 1: Understand the insertion point

In `src/workflows/process-llm.ts`, after line 110 (`log.info(..., 'Essence computed')`), add the embedding step inside the same `try` block. If embedding fails, log and continue — it is non-fatal (the backfill in Task 4 will catch it).

### Step 2: Add the embedding step

Insert after the essence block (around line 113, before `result.processed++`):

```typescript
// Generate and store embedding
try {
  const { embed, indexNote } = await import('../lib');
  const vector = await embed(note.content);

  db.prepare(
    `INSERT OR REPLACE INTO note_embeddings (raw_note_id, embedding, model_version, created_at)
     VALUES (?, ?, 'nomic-embed-text', ?)`
  ).run(note.id, JSON.stringify(vector), new Date().toISOString());

  await indexNote({
    id: note.id,
    vector,
    title: note.title,
    primary_theme: extracted.primary_theme || null,
    note_type: null,
    actionability: null,
    time_horizon: null,
    context: null,
    created_at: note.created_at ?? new Date().toISOString(),
    indexed_at: new Date().toISOString(),
  });

  log.info({ noteId: note.id }, 'Embedding generated and indexed');
} catch (embedErr) {
  log.warn({ noteId: note.id, err: embedErr as Error }, 'Embedding failed, will backfill later');
}
```

### Step 3: Test manually on dev database

```bash
# Insert a test note via the webhook first
TEST_RUN="test-synthesis-embed-$(date +%Y%m%d-%H%M%S)"
curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep WEBHOOK_SECRET .env | cut -d= -f2)" \
  -d "{\"title\":\"Synthesis test note\",\"content\":\"Testing embedding generation for synthesis layer\",\"test_run\":\"$TEST_RUN\"}"

# Run process-llm
SELENE_ENV=development npx ts-node src/workflows/process-llm.ts

# Verify embedding was written
sqlite3 data/selene.db "SELECT raw_note_id, model_version FROM note_embeddings ORDER BY created_at DESC LIMIT 3;"
```

Expected: new row in `note_embeddings` for the test note.

### Step 4: Clean up test data

```bash
./scripts/cleanup-tests.sh "$TEST_RUN"
```

### Step 5: Commit

```bash
git add src/workflows/process-llm.ts
git commit -m "feat: generate and store embeddings in process-llm.ts"
```

---

## Task 4: Connection detection in process-llm.ts

After the embedding step, search LanceDB for similar notes that are **older than 7 days** and write surprising connections to `note_connections`. Only notes with similarity ≥ 0.75 qualify (higher than the cluster threshold to surface genuinely surprising matches).

**Files:**
- Modify: `src/workflows/process-llm.ts`
- Modify: `src/lib/synthesis-db.ts` (add helper)

### Step 1: Add connection-writing helper to synthesis-db.ts

```typescript
// Add to src/lib/synthesis-db.ts
import { randomUUID } from 'crypto';

export function writeConnection(db: Database, sourceNoteId: number, targetNoteId: number, similarityScore: number): void {
  db.prepare(
    `INSERT OR IGNORE INTO note_connections (id, source_note_id, target_note_id, similarity_score, found_at)
     VALUES (?, ?, ?, ?, ?)`
  ).run(randomUUID(), sourceNoteId, targetNoteId, similarityScore, new Date().toISOString());
}
```

### Step 2: Write a test for writeConnection

```typescript
// Add to src/lib/synthesis-db.test.ts
import { initSynthesisSchema, writeConnection } from './synthesis-db';

describe('writeConnection', () => {
  it('inserts a connection row', () => {
    initSynthesisSchema(db);
    writeConnection(db, 1, 99, 0.82);
    const row = db.prepare('SELECT * FROM note_connections WHERE source_note_id = 1').get() as { target_note_id: number; similarity_score: number };
    expect(row.target_note_id).toBe(99);
    expect(row.similarity_score).toBeCloseTo(0.82, 2);
  });

  it('is idempotent — duplicate insert is ignored', () => {
    initSynthesisSchema(db);
    writeConnection(db, 1, 99, 0.82);
    expect(() => writeConnection(db, 1, 99, 0.82)).not.toThrow();
  });
});
```

Run: `npx jest src/lib/synthesis-db.test.ts --no-coverage` — should PASS.

### Step 3: Add connection detection in process-llm.ts

Add after the embedding step (inside the embedding try block, after `indexNote`):

```typescript
// Connection detection: find surprising links to older notes
const CONNECTION_THRESHOLD = 0.75;
const { searchSimilarNotes } = await import('../lib');
const { initSynthesisSchema, writeConnection } = await import('../lib/synthesis-db');

initSynthesisSchema(db);

const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
const similar = await searchSimilarNotes(vector, {
  limit: 5,
  excludeIds: [note.id],
});

for (const candidate of similar) {
  // Convert L2 distance to approximate cosine similarity (valid for normalized vectors)
  const approxSimilarity = 1 - (candidate.distance * candidate.distance) / 2;
  if (approxSimilarity < CONNECTION_THRESHOLD) continue;

  // Check if candidate note is older than 7 days
  const candidateNote = db.prepare(
    'SELECT created_at FROM raw_notes WHERE id = ? AND created_at < ?'
  ).get(candidate.id, sevenDaysAgo) as { created_at: string } | undefined;

  if (candidateNote) {
    writeConnection(db, note.id, candidate.id, approxSimilarity);
    log.info({ sourceId: note.id, targetId: candidate.id, similarity: approxSimilarity }, 'Connection found');
  }
}
```

### Step 4: Test manually on dev database

```bash
TEST_RUN="test-connections-$(date +%Y%m%d-%H%M%S)"
curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep WEBHOOK_SECRET .env | cut -d= -f2)" \
  -d "{\"title\":\"Procrastination and identity\",\"content\":\"I keep noticing that my resistance to starting tasks isn't about the tasks themselves, it's about who I think I am\",\"test_run\":\"$TEST_RUN\"}"

SELENE_ENV=development npx ts-node src/workflows/process-llm.ts

sqlite3 data/selene.db "SELECT source_note_id, target_note_id, similarity_score FROM note_connections ORDER BY found_at DESC LIMIT 5;"

./scripts/cleanup-tests.sh "$TEST_RUN"
```

### Step 5: Commit

```bash
git add src/workflows/process-llm.ts src/lib/synthesis-db.ts src/lib/synthesis-db.test.ts
git commit -m "feat: connection detection in process-llm.ts — writes note_connections on embedding"
```

---

## Task 5: synthesize-topics.ts — clustering and synthesis

Create the new nightly workflow. It runs the embedding backfill, loads all embeddings, clusters them by cosine similarity, then generates synthesis text per cluster.

**Files:**
- Create: `src/workflows/synthesize-topics.ts`

### Step 1: Create the file with schema init + backfill

```typescript
// src/workflows/synthesize-topics.ts
import { randomUUID } from 'crypto';
import { db, embed, generate, isAvailable, createWorkflowLogger } from '../lib';
import { initSynthesisSchema } from '../lib/synthesis-db';
import { cosineSimilarity } from '../lib/cosine';

const log = createWorkflowLogger('synthesize-topics');

const CLUSTER_SIMILARITY_THRESHOLD = 0.65;
const MIN_CLUSTER_SIZE = 4;
const REGROWTH_THRESHOLD = 0.20; // re-cluster if note count grew by 20%+

// -- Schema init --
initSynthesisSchema(db);

// -- Types --
interface NoteEmbedding {
  noteId: number;
  title: string;
  essence: string | null;
  concepts: string | null;
  createdAt: string;
  vector: number[];
}

// -- Backfill: ensure all processed notes have embeddings --
async function backfillEmbeddings(): Promise<number> {
  const missing = db.prepare(`
    SELECT rn.id, rn.content
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.test_run IS NULL
      AND rn.status = 'processed'
      AND NOT EXISTS (SELECT 1 FROM note_embeddings ne WHERE ne.raw_note_id = rn.id)
    LIMIT 200
  `).all() as Array<{ id: number; content: string }>;

  if (missing.length === 0) {
    log.info('No embeddings to backfill');
    return 0;
  }

  log.info({ count: missing.length }, 'Backfilling embeddings');

  let backfilled = 0;
  for (const note of missing) {
    try {
      const vector = await embed(note.content);
      db.prepare(
        `INSERT OR REPLACE INTO note_embeddings (raw_note_id, embedding, model_version, created_at)
         VALUES (?, ?, 'nomic-embed-text', ?)`
      ).run(note.id, JSON.stringify(vector), new Date().toISOString());
      backfilled++;
    } catch (err) {
      log.warn({ noteId: note.id, err }, 'Backfill embedding failed for note');
    }
  }

  log.info({ backfilled }, 'Embedding backfill complete');
  return backfilled;
}

// -- Load all embeddings --
function loadAllEmbeddings(): NoteEmbedding[] {
  const rows = db.prepare(`
    SELECT rn.id AS noteId, rn.title, rn.created_at AS createdAt,
           pn.essence, pn.concepts,
           ne.embedding
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    JOIN note_embeddings ne ON rn.id = ne.raw_note_id
    WHERE rn.test_run IS NULL AND rn.status = 'processed'
  `).all() as Array<{
    noteId: number; title: string; createdAt: string;
    essence: string | null; concepts: string | null; embedding: string;
  }>;

  return rows.map(r => ({
    noteId: r.noteId,
    title: r.title,
    createdAt: r.createdAt,
    essence: r.essence,
    concepts: r.concepts,
    vector: JSON.parse(r.embedding) as number[],
  }));
}

// -- Cluster notes by cosine similarity --
function clusterNotes(notes: NoteEmbedding[]): Map<string, number[]> {
  const assigned = new Set<number>();
  const clusters = new Map<string, number[]>(); // clusterId -> noteIds

  for (let i = 0; i < notes.length; i++) {
    if (assigned.has(notes[i].noteId)) continue;

    const members: number[] = [notes[i].noteId];

    for (let j = i + 1; j < notes.length; j++) {
      if (assigned.has(notes[j].noteId)) continue;
      const sim = cosineSimilarity(notes[i].vector, notes[j].vector);
      if (sim >= CLUSTER_SIMILARITY_THRESHOLD) {
        members.push(notes[j].noteId);
        assigned.add(notes[j].noteId);
      }
    }

    if (members.length >= 1) {
      assigned.add(notes[i].noteId);
      clusters.set(randomUUID(), members);
    }
  }

  return clusters;
}
```

### Step 2: Add synthesis generation function

Append to `src/workflows/synthesize-topics.ts`:

```typescript
async function generateClusterName(conceptStrings: string[]): Promise<string> {
  const topConcepts = conceptStrings.slice(0, 5).join(', ');
  const prompt = `Given these recurring concepts from a person's notes: ${topConcepts}
Give this cluster a 2-4 word topic name that captures the essence. No explanation, just the name.`;
  const response = await generate(prompt, { temperature: 0 });
  return response.trim().replace(/^["']|["']$/g, '');
}

async function generateSynthesis(clusterName: string, members: NoteEmbedding[]): Promise<string> {
  const noteLines = members
    .map(n => `Title: ${n.title}\nEssence: ${n.essence || n.title}`)
    .join('\n\n');

  const prompt = `You are synthesizing a personal knowledge base.
Topic: "${clusterName}"
Notes (${members.length} total):

${noteLines}

Write in second person ("You've been exploring..."):
1. 3-5 sentences capturing the recurring questions, tensions, and through-line.
2. The open question that keeps resurfacing (one sentence, start with "The open question:").
3. Keep it under 200 words total.

Do not invent information not present in the notes.`;

  return generate(prompt, { timeoutMs: 60000 });
}
```

### Step 3: Add the main run function

```typescript
export async function synthesizeTopics(): Promise<{ clusters: number; evolved: number; proto: number }> {
  log.info('Starting synthesize-topics');

  if (!(await isAvailable())) {
    log.error('Ollama not available');
    return { clusters: 0, evolved: 0, proto: 0 };
  }

  await backfillEmbeddings();

  const notes = loadAllEmbeddings();
  log.info({ noteCount: notes.length }, 'Loaded embeddings');

  if (notes.length < MIN_CLUSTER_SIZE) {
    log.info('Not enough notes to cluster');
    return { clusters: 0, evolved: 0, proto: 0 };
  }

  const rawClusters = clusterNotes(notes);
  const noteById = new Map(notes.map(n => [n.noteId, n]));

  let clustersProcessed = 0;
  let evolved = 0;
  let proto = 0;

  for (const [clusterId, noteIds] of rawClusters) {
    const isProto = noteIds.length < MIN_CLUSTER_SIZE;
    const members = noteIds.map(id => noteById.get(id)!).filter(Boolean);

    // Extract top concept strings for naming
    const allConcepts: string[] = [];
    for (const m of members) {
      if (m.concepts) {
        try {
          const parsed = JSON.parse(m.concepts) as string[];
          allConcepts.push(...parsed);
        } catch { /* ignore */ }
      }
    }
    const conceptFreq = new Map<string, number>();
    for (const c of allConcepts) {
      conceptFreq.set(c, (conceptFreq.get(c) ?? 0) + 1);
    }
    const sortedConcepts = [...conceptFreq.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([c]) => c);

    // Check if cluster already exists (by matching slug or note membership)
    const existingSlug = sortedConcepts[0]
      ? sortedConcepts[0].toLowerCase().replace(/[^a-z0-9]+/g, '-')
      : clusterId.substring(0, 8);

    const existing = db.prepare('SELECT * FROM topic_clusters WHERE slug = ?').get(existingSlug) as {
      id: string; synthesis_text: string | null; synthesis_updated_at: string | null;
    } | undefined;

    // Check delta guard: if cluster exists and no new notes, skip
    if (existing) {
      const hasNewNotes = db.prepare(`
        SELECT 1 FROM topic_note_links
        WHERE topic_id = ? AND added_at > ?
        LIMIT 1
      `).get(existing.id, existing.synthesis_updated_at ?? '1970-01-01') as { 1: number } | undefined;

      if (!hasNewNotes && !isProto) {
        log.debug({ slug: existingSlug }, 'Delta guard: skipping unchanged cluster');
        continue;
      }
    }

    const clusterName = sortedConcepts.length > 0
      ? await generateClusterName(sortedConcepts)
      : 'General Notes';

    const slug = clusterName.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const now = new Date().toISOString();
    const id = existing?.id ?? randomUUID();

    const prevSynthesis = existing?.synthesis_text ?? null;
    const newSynthesis = isProto ? null : await generateSynthesis(clusterName, members);

    // Upsert cluster
    db.prepare(`
      INSERT INTO topic_clusters
        (id, name, slug, synthesis_text, prev_synthesis_text, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(slug) DO UPDATE SET
        name = excluded.name,
        synthesis_text = excluded.synthesis_text,
        prev_synthesis_text = excluded.prev_synthesis_text,
        synthesis_updated_at = excluded.synthesis_updated_at,
        note_count = excluded.note_count,
        is_proto = excluded.is_proto
    `).run(id, clusterName, slug, newSynthesis, prevSynthesis, now, noteIds.length, isProto ? 1 : 0, now);

    // Write note links
    for (const noteId of noteIds) {
      db.prepare(
        `INSERT OR IGNORE INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)`
      ).run(id, noteId, now);
    }

    // Evolution detection
    if (!isProto && prevSynthesis && newSynthesis && prevSynthesis !== newSynthesis) {
      const evolutionPrompt = `Old synthesis: "${prevSynthesis.substring(0, 300)}"

New synthesis: "${newSynthesis.substring(0, 300)}"

Did the understanding meaningfully change (not just grow)? JSON only: { "changed": boolean, "summary": string }`;

      try {
        const response = await generate(evolutionPrompt, { temperature: 0, timeoutMs: 30000 });
        const jsonMatch = response.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          const result = JSON.parse(jsonMatch[0]) as { changed: boolean; summary: string };
          if (result.changed) {
            db.prepare(
              `UPDATE topic_clusters SET evolution_detected_at = ?, evolution_summary = ? WHERE id = ?`
            ).run(now, result.summary, id);
            evolved++;
          }
        }
      } catch (err) {
        log.warn({ clusterId: id, err }, 'Evolution detection failed');
      }
    }

    if (isProto) proto++; else clustersProcessed++;
  }

  // Sunday weekly rollup
  const isSunday = new Date().getDay() === 0;
  if (isSunday) {
    await generateWeeklyRollup();
  }

  log.info({ clusters: clustersProcessed, evolved, proto }, 'synthesize-topics complete');
  return { clusters: clustersProcessed, evolved, proto };
}

async function generateWeeklyRollup(): Promise<void> {
  const weekEvolutions = db.prepare(`
    SELECT name, evolution_summary
    FROM topic_clusters
    WHERE evolution_detected_at > datetime('now', '-7 days')
      AND is_proto = 0
      AND evolution_summary IS NOT NULL
  `).all() as Array<{ name: string; evolution_summary: string }>;

  if (weekEvolutions.length === 0) return;

  const lines = weekEvolutions.map(e => `${e.name}: ${e.evolution_summary}`).join('\n');
  const prompt = `Summarize this week's shifts in someone's personal notes in 2-3 sentences. Write in second person.

${lines}`;

  const rollup = await generate(prompt, { timeoutMs: 45000 });
  const now = new Date().toISOString();

  db.prepare(
    `INSERT INTO synthesis_meta (key, value, updated_at)
     VALUES ('weekly_evolution', ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
  ).run(rollup, now);

  log.info('Weekly rollup generated');
}

// CLI entry point
if (require.main === module) {
  synthesizeTopics()
    .then(result => {
      console.log('Synthesize-topics complete:', result);
      process.exit(0);
    })
    .catch(err => {
      console.error('Synthesize-topics failed:', err);
      process.exit(1);
    });
}
```

### Step 4: Run manually on dev database and inspect output

```bash
# Use dev database so we don't touch production
SELENE_ENV=development npx ts-node src/workflows/synthesize-topics.ts

# Check what was written
sqlite3 ~/selene-data-dev/selene.db "SELECT name, note_count, is_proto, substr(synthesis_text, 1, 100) FROM topic_clusters ORDER BY note_count DESC LIMIT 10;"
```

Expected: ≥ 3 cluster rows with synthesis text. Review them manually — do the names make sense? Does the synthesis text sound coherent? Tune `CLUSTER_SIMILARITY_THRESHOLD` (0.65) if clusters are too broad or too narrow.

**Tuning guide:**
- If clusters are too big and incoherent → raise threshold to 0.70
- If clusters are too small (< 4 notes each) → lower to 0.60
- If too many proto-clusters → lower `MIN_CLUSTER_SIZE` to 3

### Step 5: Run twice and verify delta guard

```bash
SELENE_ENV=development npx ts-node src/workflows/synthesize-topics.ts
# Second run with no new notes — should log "Delta guard: skipping unchanged cluster" for all
```

### Step 6: Commit

```bash
git add src/workflows/synthesize-topics.ts src/lib/synthesis-db.ts src/lib/cosine.ts
git commit -m "feat: synthesize-topics.ts — clustering, synthesis, evolution detection, proto-clusters, Sunday rollup"
```

---

## Task 6: Digest integration — 4 new sections in send-digest.ts

The existing `send-digest.ts` reads a pre-generated digest file and posts it to Apple Notes. The synthesis sections slot in alongside the existing content. The cleanest approach: add a `buildSynthesisSections()` function that queries the new tables and returns a text block, then append it to the digest before posting.

**Files:**
- Modify: `src/workflows/send-digest.ts`
- Create: `src/lib/synthesis-digest.ts`
- Test: `src/lib/synthesis-digest.test.ts`

### Step 1: Write failing tests

```typescript
// src/lib/synthesis-digest.test.ts
import Database from 'better-sqlite3';
import { initSynthesisSchema } from './synthesis-db';
import { buildSynthesisSections } from './synthesis-digest';

describe('buildSynthesisSections', () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(':memory:');
    // Minimal raw_notes for FK references
    db.exec(`
      CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, created_at TEXT, test_run TEXT);
      INSERT INTO raw_notes VALUES (1, 'Old note', datetime('now', '-30 days'), NULL);
      INSERT INTO raw_notes VALUES (2, 'New note', datetime('now'), NULL);
    `);
    initSynthesisSchema(db);
  });

  afterEach(() => {
    db.close();
  });

  it('returns empty string when no clusters exist', () => {
    const result = buildSynthesisSections(db);
    expect(result).toBe('');
  });

  it('includes Topics circling when clusters exist', () => {
    const now = new Date().toISOString();
    db.prepare(`
      INSERT INTO topic_clusters (id, name, slug, synthesis_text, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES ('c1', 'Procrastination', 'procrastination', 'You keep returning to this.', ?, 5, 0, ?)
    `).run(now, now);

    const result = buildSynthesisSections(db);
    expect(result).toContain('Topics circling');
    expect(result).toContain('Procrastination');
    expect(result).toContain('5 notes');
  });

  it('includes Understanding shifted when evolution was detected', () => {
    const now = new Date().toISOString();
    db.prepare(`
      INSERT INTO topic_clusters (id, name, slug, synthesis_text, evolution_detected_at, evolution_summary, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES ('c1', 'Focus', 'focus', 'You have been exploring focus.', ?, 'The angle shifted toward identity.', ?, 4, 0, ?)
    `).run(now, now, now);

    const result = buildSynthesisSections(db);
    expect(result).toContain('Understanding shifted');
    expect(result).toContain('The angle shifted toward identity');
  });

  it('includes Unexpected connections when note_connections has recent rows', () => {
    const now = new Date().toISOString();
    initSynthesisSchema(db);
    db.prepare(
      `INSERT INTO note_connections (id, source_note_id, target_note_id, similarity_score, found_at) VALUES ('conn1', 2, 1, 0.88, ?)`
    ).run(now);

    const result = buildSynthesisSections(db);
    expect(result).toContain('Unexpected connections');
    expect(result).toContain('New note');
    expect(result).toContain('Old note');
  });
});
```

### Step 2: Run test to verify it fails

```bash
npx jest src/lib/synthesis-digest.test.ts --no-coverage
```

Expected: FAIL — "Cannot find module './synthesis-digest'"

### Step 3: Write implementation

```typescript
// src/lib/synthesis-digest.ts
import type { Database } from 'better-sqlite3';

export function buildSynthesisSections(db: Database): string {
  const sections: string[] = [];

  // Section 1: Topics circling
  const clusters = db.prepare(`
    SELECT name, note_count, synthesis_text
    FROM topic_clusters
    WHERE is_proto = 0
      AND synthesis_updated_at > datetime('now', '-7 days')
    ORDER BY note_count DESC
    LIMIT 3
  `).all() as Array<{ name: string; note_count: number; synthesis_text: string | null }>;

  if (clusters.length === 0) {
    // Fallback: top by note_count regardless of recency
    clusters.push(...db.prepare(`
      SELECT name, note_count, synthesis_text
      FROM topic_clusters
      WHERE is_proto = 0 AND synthesis_text IS NOT NULL
      ORDER BY note_count DESC
      LIMIT 3
    `).all() as typeof clusters);
  }

  if (clusters.length > 0) {
    const lines = clusters.map(c => {
      const preview = c.synthesis_text
        ? c.synthesis_text.split('.')[0] + '.'
        : '';
      return `${c.name} (${c.note_count} notes) — ${preview}`;
    });
    sections.push(`Topics circling\n\n${lines.join('\n\n')}`);
  }

  // Section 2: Understanding shifted (A)
  const evolutions = db.prepare(`
    SELECT name, evolution_summary
    FROM topic_clusters
    WHERE evolution_detected_at > datetime('now', '-1 day')
      AND is_proto = 0
      AND evolution_summary IS NOT NULL
    ORDER BY evolution_detected_at DESC
    LIMIT 2
  `).all() as Array<{ name: string; evolution_summary: string }>;

  if (evolutions.length > 0) {
    const lines = evolutions.map(e => `${e.name}: ${e.evolution_summary}`);
    sections.push(`Understanding shifted\n\n${lines.join('\n')}`);
  }

  // Section 3: Unexpected connections (C)
  const connections = db.prepare(`
    SELECT
      src.title AS source_title,
      tgt.title AS target_title,
      nc.similarity_score,
      tgt.created_at AS target_created_at
    FROM note_connections nc
    JOIN raw_notes src ON nc.source_note_id = src.id
    JOIN raw_notes tgt ON nc.target_note_id = tgt.id
    WHERE nc.found_at > datetime('now', '-1 day')
      AND src.test_run IS NULL
    ORDER BY nc.similarity_score DESC
    LIMIT 3
  `).all() as Array<{
    source_title: string; target_title: string;
    similarity_score: number; target_created_at: string;
  }>;

  if (connections.length > 0) {
    const lines = connections.map(c => {
      const pct = Math.round(c.similarity_score * 100);
      const targetDate = new Date(c.target_created_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
      return `"${c.source_title}" → "${c.target_title}" (${targetDate}, ${pct}% match)`;
    });
    sections.push(`Unexpected connections\n\n${lines.join('\n')}`);
  }

  // Section 4: Pattern forming (B) or Sunday weekly rollup
  const isSunday = new Date().getDay() === 0;

  if (isSunday) {
    const rollup = db.prepare(
      `SELECT value FROM synthesis_meta WHERE key = 'weekly_evolution'`
    ).get() as { value: string } | undefined;

    if (rollup) {
      sections.push(`This week in your thinking\n\n${rollup.value}`);
    }
  } else {
    const protoClusters = db.prepare(`
      SELECT name, note_count
      FROM topic_clusters
      WHERE is_proto = 1
        AND created_at > datetime('now', '-3 days')
      ORDER BY note_count DESC
      LIMIT 2
    `).all() as Array<{ name: string; note_count: number }>;

    if (protoClusters.length > 0) {
      const lines = protoClusters.map(
        p => `${p.note_count} recent notes circling "${p.name}" — not a full cluster yet.`
      );
      sections.push(`Pattern forming\n\n${lines.join('\n')}`);
    }
  }

  if (sections.length === 0) return '';
  return '\n\n' + sections.map(s => `## ${s}`).join('\n\n');
}
```

### Step 4: Run test to verify it passes

```bash
npx jest src/lib/synthesis-digest.test.ts --no-coverage
```

Expected: PASS — 4 tests green

### Step 5: Wire into send-digest.ts

In `src/workflows/send-digest.ts`, add at the top:

```typescript
import { buildSynthesisSections } from '../lib/synthesis-digest';
import { db } from '../lib';
```

Inside `sendDigest()`, after reading `message` from the digest file (around line 113), append synthesis sections:

```typescript
const synthesisSections = buildSynthesisSections(db);
const fullMessage = message + synthesisSections;
```

Then replace the uses of `message` in the Apple Notes and TRMNL calls with `fullMessage`.

### Step 6: Test send-digest in test mode

```bash
SELENE_ENV=development npx ts-node src/workflows/send-digest.ts
# Check output file in logs/digests/sent/
cat ~/selene-data-dev/digests/sent/*-sent.txt | grep -A 10 "Topics circling"
```

### Step 7: Commit

```bash
git add src/lib/synthesis-digest.ts src/lib/synthesis-digest.test.ts src/workflows/send-digest.ts
git commit -m "feat: 4 synthesis sections in send-digest (Topics circling, Understanding shifted, Unexpected connections, Pattern forming)"
```

---

## Task 7: launchd plist, wrapper script, install-launchd.sh

**Files:**
- Create: `launchd/com.selene.synthesize-topics.plist`
- Create: `scripts/selene-synthesize-topics`
- Modify: `scripts/install-launchd.sh`

### Step 1: Create wrapper script

```bash
# scripts/selene-synthesize-topics
#!/bin/bash
exec /usr/local/bin/npx ts-node src/workflows/synthesize-topics.ts
```

```bash
chmod +x scripts/selene-synthesize-topics
```

### Step 2: Create launchd plist (2am daily)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.synthesize-topics</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/chaseeasterling/selene/scripts/selene-synthesize-topics</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>SELENE_ENV</key>
        <string>production</string>
        <key>SELENE_DB_PATH</key>
        <string>/Users/chaseeasterling/selene-data/selene.db</string>
    </dict>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/synthesize-topics.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/synthesize-topics.error.log</string>
</dict>
</plist>
```

### Step 3: Add to install-launchd.sh

In `scripts/install-launchd.sh`, add `"com.selene.synthesize-topics"` to the `AGENTS` array.

### Step 4: Install and verify

```bash
./scripts/install-launchd.sh
launchctl list | grep selene
```

Expected: `com.selene.synthesize-topics` appears in the list.

### Step 5: Commit

```bash
git add launchd/com.selene.synthesize-topics.plist scripts/selene-synthesize-topics scripts/install-launchd.sh
git commit -m "feat: launchd agent for synthesize-topics (2am daily)"
```

---

## Task 8: End-to-end calibration on production data

Run the full pipeline on production once, review output quality, and tune thresholds if needed.

### Step 1: Run on production

```bash
npx ts-node src/workflows/synthesize-topics.ts
```

### Step 2: Review clusters

```bash
sqlite3 ~/selene-data/selene.db "
SELECT name, note_count, is_proto,
       substr(synthesis_text, 1, 150) AS synthesis_preview
FROM topic_clusters
ORDER BY note_count DESC;"
```

**Review checklist:**
- [ ] ≥ 3 full clusters (is_proto = 0) with meaningful names
- [ ] No junk clusters (single-concept noise, proper names only, incoherent)
- [ ] Synthesis text reads coherently in second person
- [ ] Proto-clusters look like genuinely forming themes (not just noise)

**Tuning:**
- Too broad / incoherent → raise `CLUSTER_SIMILARITY_THRESHOLD` to 0.70
- Too many tiny clusters → lower to 0.60
- Too many proto-clusters never graduating → lower `MIN_CLUSTER_SIZE` to 3

### Step 3: Review connections

```bash
sqlite3 ~/selene-data/selene.db "
SELECT src.title AS source, tgt.title AS target, nc.similarity_score
FROM note_connections nc
JOIN raw_notes src ON nc.source_note_id = src.id
JOIN raw_notes tgt ON nc.target_note_id = tgt.id
ORDER BY nc.found_at DESC LIMIT 10;"
```

**Review checklist:**
- [ ] Connections feel genuinely surprising (not just "both mention procrastination")
- [ ] Target notes are meaningfully older (30+ days)
- [ ] Similarity scores make intuitive sense

**Tuning:** If connections are too obvious → raise `CONNECTION_THRESHOLD` to 0.80.

### Step 4: Trigger a test digest to verify sections appear

```bash
# Force today's digest to regenerate
npx ts-node src/workflows/daily-summary.ts

# Send digest (will post to Apple Notes)
npx ts-node src/workflows/send-digest.ts
```

Check Apple Notes for the "Selene Daily" note — confirm all 4 new sections appear.

### Step 5: Run smoke tests

```bash
curl http://localhost:5678/health
curl -s -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep WEBHOOK_SECRET .env | cut -d= -f2)" \
  -d '{"title":"Smoke test","content":"Smoke test note","test_run":"smoke-synthesis"}'

./scripts/cleanup-tests.sh smoke-synthesis
```

### Step 6: Final commit

```bash
git add .
git commit -m "feat: synthesis layer v1 — end-to-end calibrated and shipped"
```

---

## Acceptance Criteria Checklist

- [ ] All 285 processed notes have embeddings after first synthesize-topics.ts run
- [ ] `topic_clusters` contains ≥ 3 meaningful clusters (manual review pass)
- [ ] No junk clusters in first run output
- [ ] `note_connections` populated after process-llm.ts processes a new note
- [ ] Digest "Topics circling" section appears in Apple Notes
- [ ] Digest "Understanding shifted" section appears when a cluster evolves
- [ ] Digest "Unexpected connections" section appears with recent connections
- [ ] Digest "Pattern forming" section appears when proto-clusters exist
- [ ] Sunday digest includes weekly evolution rollup
- [ ] Delta guard: second synthesize-topics.ts run with no new notes makes zero Ollama calls
- [ ] `com.selene.synthesize-topics` appears in `launchctl list | grep selene`
- [ ] `GET /health` and `POST /webhook/api/drafts` pass smoke tests after changes
