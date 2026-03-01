# LanceDB Transition Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace O(n²) embedding associations with LanceDB vector search, add typed relationships (BT/NT/RT), and enable faceted queries.

**Architecture:** LanceDB stores vectors with metadata (facets) for O(log n) similarity search. SQLite keeps typed relationships (BT/NT/RT/TEMPORAL) derived from LLM extraction and high-confidence embeddings. Hybrid queries combine precomputed relationships with live vector search.

**Tech Stack:** LanceDB (@lancedb/lancedb), better-sqlite3, Ollama (nomic-embed-text), TypeScript

---

## Phase 1: LanceDB Foundation

### Task 1: Install LanceDB and Create Connection Module

**Files:**
- Modify: `package.json`
- Create: `src/lib/lancedb.ts`
- Modify: `src/lib/index.ts`

**Step 1: Install LanceDB**

Run:
```bash
npm install @lancedb/lancedb
```

Expected: Package added to node_modules, package.json updated

**Step 2: Create LanceDB connection module**

Create `src/lib/lancedb.ts`:

```typescript
import * as lancedb from '@lancedb/lancedb';
import type { Table } from '@lancedb/lancedb';
import path from 'path';
import { config } from './config';
import { logger } from './logger';

const log = logger.child({ module: 'lancedb' });

// Vector dimensions for nomic-embed-text
export const VECTOR_DIMENSIONS = 768;

// Database connection (lazy initialized)
let dbConnection: Awaited<ReturnType<typeof lancedb.connect>> | null = null;

/**
 * Get or create database connection
 */
export async function getLanceDb() {
  if (!dbConnection) {
    const dbPath = path.join(path.dirname(config.dbPath), 'vectors.lance');
    log.info({ dbPath }, 'Connecting to LanceDB');
    dbConnection = await lancedb.connect(dbPath);
  }
  return dbConnection;
}

/**
 * Close database connection (for cleanup)
 */
export async function closeLanceDb() {
  if (dbConnection) {
    dbConnection = null;
    log.info('LanceDB connection closed');
  }
}
```

**Step 3: Export from lib/index.ts**

Modify `src/lib/index.ts`, add at the end:

```typescript
export { getLanceDb, closeLanceDb, VECTOR_DIMENSIONS } from './lancedb';
```

**Step 4: Verify module loads**

Run:
```bash
npx ts-node -e "import { getLanceDb } from './src/lib'; getLanceDb().then(db => { console.log('Connected:', !!db); process.exit(0); })"
```

Expected: `Connected: true`

**Step 5: Commit**

```bash
git add package.json package-lock.json src/lib/lancedb.ts src/lib/index.ts
git commit -m "$(cat <<'EOF'
feat: add LanceDB connection module

Foundation for vector search migration. LanceDB will replace
JSON blob embeddings and O(n²) association computation.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Create Notes Vector Table Schema

**Files:**
- Modify: `src/lib/lancedb.ts`

**Step 1: Add NoteVector interface and table management**

Add to `src/lib/lancedb.ts` after the connection code:

```typescript
// Schema for note vectors with metadata
export interface NoteVector {
  id: number;              // Matches raw_note_id
  vector: number[];        // 768-dim embedding from nomic-embed-text
  title: string;
  primary_theme: string | null;
  note_type: string | null;       // task, reflection, reference, idea, log
  actionability: string | null;   // actionable, someday, reference, done
  time_horizon: string | null;    // immediate, week, month, timeless
  context: string | null;         // JSON array of contexts
  created_at: string;
  indexed_at: string;
}

let notesTable: Table | null = null;

/**
 * Get or create the notes vector table
 */
export async function getNotesTable(): Promise<Table> {
  if (notesTable) return notesTable;

  const db = await getLanceDb();
  const tableNames = await db.tableNames();

  if (tableNames.includes('notes')) {
    log.info('Opening existing notes table');
    notesTable = await db.openTable('notes');
  } else {
    log.info('Creating new notes table with schema');
    // Create with placeholder to establish schema
    notesTable = await db.createTable('notes', [{
      id: -1,
      vector: new Array(VECTOR_DIMENSIONS).fill(0),
      title: '__schema_placeholder__',
      primary_theme: null,
      note_type: null,
      actionability: null,
      time_horizon: null,
      context: null,
      created_at: new Date().toISOString(),
      indexed_at: new Date().toISOString(),
    }]);
    // Delete placeholder
    await notesTable.delete('id = -1');
    log.info('Notes table created');
  }

  return notesTable;
}
```

**Step 2: Verify table creation**

Run:
```bash
npx ts-node -e "
import { getNotesTable } from './src/lib/lancedb';
getNotesTable().then(t => {
  console.log('Table ready:', !!t);
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
"
```

Expected: `Table ready: true`

**Step 3: Verify data directory created**

Run:
```bash
ls -la data/vectors.lance
```

Expected: Directory exists with LanceDB files

**Step 4: Commit**

```bash
git add src/lib/lancedb.ts
git commit -m "$(cat <<'EOF'
feat(lancedb): add notes table schema with facet metadata

NoteVector schema includes:
- 768-dim vector for nomic-embed-text embeddings
- Facets: note_type, actionability, time_horizon, context
- Metadata: title, primary_theme, timestamps

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add Vector CRUD Operations

**Files:**
- Modify: `src/lib/lancedb.ts`

**Step 1: Add indexNote function**

Add to `src/lib/lancedb.ts`:

```typescript
/**
 * Index a note's vector with metadata (upsert)
 */
export async function indexNote(note: NoteVector): Promise<void> {
  const table = await getNotesTable();

  // Delete existing if present (upsert behavior)
  try {
    await table.delete(`id = ${note.id}`);
  } catch {
    // Ignore if doesn't exist
  }

  await table.add([note]);
  log.debug({ noteId: note.id }, 'Note indexed');
}

/**
 * Index multiple notes in batch
 */
export async function indexNotes(notes: NoteVector[]): Promise<number> {
  if (notes.length === 0) return 0;

  const table = await getNotesTable();

  // Delete existing entries for these IDs
  const ids = notes.map(n => n.id);
  try {
    await table.delete(`id IN (${ids.join(',')})`);
  } catch {
    // Ignore if none exist
  }

  await table.add(notes);
  log.info({ count: notes.length }, 'Notes batch indexed');
  return notes.length;
}

/**
 * Delete a note from the index
 */
export async function deleteNoteVector(noteId: number): Promise<void> {
  const table = await getNotesTable();
  await table.delete(`id = ${noteId}`);
  log.debug({ noteId }, 'Note removed from index');
}

/**
 * Get all indexed note IDs (for sync checking)
 */
export async function getIndexedNoteIds(): Promise<Set<number>> {
  const table = await getNotesTable();
  const results = await table.query().select(['id']).toArray();
  return new Set(results.map(r => r.id as number));
}
```

**Step 2: Update exports in lib/index.ts**

Modify `src/lib/index.ts`, update the lancedb export:

```typescript
export {
  getLanceDb,
  closeLanceDb,
  VECTOR_DIMENSIONS,
  getNotesTable,
  indexNote,
  indexNotes,
  deleteNoteVector,
  getIndexedNoteIds,
  type NoteVector,
} from './lancedb';
```

**Step 3: Test CRUD operations**

Run:
```bash
npx ts-node -e "
import { indexNote, getIndexedNoteIds, deleteNoteVector, VECTOR_DIMENSIONS } from './src/lib/lancedb';

async function test() {
  // Create test vector
  const testNote = {
    id: 99999,
    vector: new Array(VECTOR_DIMENSIONS).fill(0.1),
    title: 'Test Note',
    primary_theme: 'testing',
    note_type: 'reference',
    actionability: null,
    time_horizon: null,
    context: null,
    created_at: new Date().toISOString(),
    indexed_at: new Date().toISOString(),
  };

  // Index
  await indexNote(testNote);
  console.log('Indexed test note');

  // Verify exists
  let ids = await getIndexedNoteIds();
  console.log('Contains test ID:', ids.has(99999));

  // Delete
  await deleteNoteVector(99999);
  console.log('Deleted test note');

  // Verify gone
  ids = await getIndexedNoteIds();
  console.log('Still contains test ID:', ids.has(99999));

  process.exit(0);
}
test().catch(e => { console.error(e); process.exit(1); });
"
```

Expected:
```
Indexed test note
Contains test ID: true
Deleted test note
Still contains test ID: false
```

**Step 4: Commit**

```bash
git add src/lib/lancedb.ts src/lib/index.ts
git commit -m "$(cat <<'EOF'
feat(lancedb): add CRUD operations for note vectors

- indexNote: upsert single note
- indexNotes: batch upsert
- deleteNoteVector: remove from index
- getIndexedNoteIds: list all indexed IDs for sync

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add Vector Search Function

**Files:**
- Modify: `src/lib/lancedb.ts`

**Step 1: Add search interfaces and function**

Add to `src/lib/lancedb.ts`:

```typescript
/**
 * Result from similarity search
 */
export interface SimilarNote {
  id: number;
  title: string;
  primary_theme: string | null;
  note_type: string | null;
  distance: number;  // L2 distance (lower = more similar)
}

/**
 * Options for similarity search
 */
export interface SearchOptions {
  limit?: number;
  maxDistance?: number;        // Filter results above this distance
  excludeIds?: number[];       // Don't return these note IDs
  filterNoteType?: string;     // Only return specific note types
  filterActionability?: string; // Only return specific actionability
}

/**
 * Search for similar notes by vector
 */
export async function searchSimilarNotes(
  queryVector: number[],
  options: SearchOptions = {}
): Promise<SimilarNote[]> {
  const {
    limit = 10,
    maxDistance,
    excludeIds = [],
    filterNoteType,
    filterActionability,
  } = options;

  const table = await getNotesTable();

  // Build filter conditions
  const filters: string[] = [];

  if (excludeIds.length > 0) {
    filters.push(`id NOT IN (${excludeIds.join(',')})`);
  }
  if (filterNoteType) {
    filters.push(`note_type = '${filterNoteType}'`);
  }
  if (filterActionability) {
    filters.push(`actionability = '${filterActionability}'`);
  }

  // Build and execute query
  let query = table.vectorSearch(queryVector);

  if (filters.length > 0) {
    query = query.where(filters.join(' AND '));
  }

  const results = await query
    .select(['id', 'title', 'primary_theme', 'note_type', '_distance'])
    .limit(limit * 2)  // Fetch extra for post-filtering
    .toArray();

  // Map and filter results
  const mapped: SimilarNote[] = results
    .map(r => ({
      id: r.id as number,
      title: r.title as string,
      primary_theme: r.primary_theme as string | null,
      note_type: r.note_type as string | null,
      distance: r._distance as number,
    }))
    .filter(r => maxDistance === undefined || r.distance <= maxDistance)
    .slice(0, limit);

  log.debug({
    queryLength: queryVector.length,
    resultsCount: mapped.length,
    filters
  }, 'Vector search complete');

  return mapped;
}
```

**Step 2: Update exports**

Modify `src/lib/index.ts`, add to lancedb exports:

```typescript
export {
  getLanceDb,
  closeLanceDb,
  VECTOR_DIMENSIONS,
  getNotesTable,
  indexNote,
  indexNotes,
  deleteNoteVector,
  getIndexedNoteIds,
  searchSimilarNotes,
  type NoteVector,
  type SimilarNote,
  type SearchOptions,
} from './lancedb';
```

**Step 3: Test search (requires indexed data)**

Run:
```bash
npx ts-node -e "
import { indexNote, searchSimilarNotes, VECTOR_DIMENSIONS } from './src/lib/lancedb';

async function test() {
  // Index test notes with different vectors
  const notes = [
    { id: 10001, title: 'Alpha Note', vector: [0.9, ...new Array(VECTOR_DIMENSIONS - 1).fill(0.1)] },
    { id: 10002, title: 'Beta Note', vector: [0.1, 0.9, ...new Array(VECTOR_DIMENSIONS - 2).fill(0.1)] },
    { id: 10003, title: 'Gamma Note', vector: [0.8, ...new Array(VECTOR_DIMENSIONS - 1).fill(0.1)] },
  ];

  for (const n of notes) {
    await indexNote({
      ...n,
      primary_theme: 'test',
      note_type: null,
      actionability: null,
      time_horizon: null,
      context: null,
      created_at: new Date().toISOString(),
      indexed_at: new Date().toISOString(),
    });
  }
  console.log('Indexed 3 test notes');

  // Search for notes similar to Alpha (should return Alpha, Gamma)
  const queryVector = [0.85, ...new Array(VECTOR_DIMENSIONS - 1).fill(0.1)];
  const results = await searchSimilarNotes(queryVector, { limit: 3 });

  console.log('Search results:');
  for (const r of results) {
    console.log(\`  \${r.title}: distance=\${r.distance.toFixed(4)}\`);
  }

  // Cleanup
  const { deleteNoteVector } = await import('./src/lib/lancedb');
  for (const n of notes) {
    await deleteNoteVector(n.id);
  }
  console.log('Cleaned up test notes');

  process.exit(0);
}
test().catch(e => { console.error(e); process.exit(1); });
"
```

Expected: Alpha and Gamma notes should have lower distances than Beta

**Step 4: Commit**

```bash
git add src/lib/lancedb.ts src/lib/index.ts
git commit -m "$(cat <<'EOF'
feat(lancedb): add vector similarity search with filters

searchSimilarNotes supports:
- L2 distance-based similarity
- Exclusion list (excludeIds)
- Facet filtering (note_type, actionability)
- Distance threshold (maxDistance)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Vector Indexing Workflow

### Task 5: Create index-vectors Workflow

**Files:**
- Create: `src/workflows/index-vectors.ts`
- Modify: `package.json`

**Step 1: Create the workflow file**

Create `src/workflows/index-vectors.ts`:

```typescript
import {
  createWorkflowLogger,
  db,
  embed,
  isAvailable,
  indexNotes,
  getIndexedNoteIds,
  type NoteVector,
  VECTOR_DIMENSIONS,
} from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('index-vectors');

interface NoteForIndexing {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string | null;
}

/**
 * Index vectors for processed notes not yet in LanceDB
 */
export async function indexVectors(limit = 50): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting vector indexing run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Get already indexed IDs from LanceDB
  const indexedIds = await getIndexedNoteIds();
  log.info({ indexedCount: indexedIds.size }, 'Found existing indexed notes');

  // Get processed notes from SQLite
  const notes = db.prepare(`
    SELECT
      rn.id,
      rn.title,
      rn.content,
      rn.created_at,
      pn.primary_theme
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.test_run IS NULL
      AND rn.status = 'processed'
    ORDER BY rn.created_at DESC
    LIMIT ?
  `).all(limit * 2) as NoteForIndexing[];

  // Filter out already indexed
  const needsIndexing = notes.filter(n => !indexedIds.has(n.id)).slice(0, limit);

  log.info({
    fetchedCount: notes.length,
    needsIndexing: needsIndexing.length
  }, 'Notes to index');

  if (needsIndexing.length === 0) {
    log.info('No notes need indexing');
    return { processed: 0, errors: 0, details: [] };
  }

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };
  const toIndex: NoteVector[] = [];

  for (const note of needsIndexing) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Computing embedding');

      const text = `${note.title}\n\n${note.content}`;
      const vector = await embed(text);

      if (vector.length !== VECTOR_DIMENSIONS) {
        throw new Error(`Unexpected embedding dimensions: ${vector.length}`);
      }

      toIndex.push({
        id: note.id,
        vector,
        title: note.title,
        primary_theme: note.primary_theme,
        note_type: null,      // Will be populated by facet extraction later
        actionability: null,
        time_horizon: null,
        context: null,
        created_at: note.created_at,
        indexed_at: new Date().toISOString(),
      });

      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to compute embedding');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  // Batch insert to LanceDB
  if (toIndex.length > 0) {
    try {
      await indexNotes(toIndex);
      log.info({ count: toIndex.length }, 'Batch indexed to LanceDB');
    } catch (err) {
      const error = err as Error;
      log.error({ err: error }, 'Failed to batch index to LanceDB');
      result.errors = toIndex.length;
      result.processed = 0;
    }
  }

  log.info(result, 'Vector indexing run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  const limit = process.argv[2] ? parseInt(process.argv[2], 10) : 50;

  indexVectors(limit)
    .then((result) => {
      console.log('Index-vectors complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Index-vectors failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Add npm script**

Modify `package.json`, add to scripts:

```json
"workflow:index-vectors": "ts-node src/workflows/index-vectors.ts"
```

**Step 3: Test workflow runs (dry run)**

Run:
```bash
npm run workflow:index-vectors
```

Expected: Either indexes notes or reports "No notes need indexing"

**Step 4: Commit**

```bash
git add src/workflows/index-vectors.ts package.json
git commit -m "$(cat <<'EOF'
feat: add index-vectors workflow

Replaces compute-embeddings with LanceDB-based indexing:
- Computes embeddings via Ollama nomic-embed-text
- Stores in LanceDB with metadata
- Skips already-indexed notes
- Batch inserts for efficiency

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Create Migration Script for Existing Data

**Files:**
- Create: `scripts/migrate-to-lancedb.ts`

**Step 1: Create migration script**

Create `scripts/migrate-to-lancedb.ts`:

```typescript
/**
 * Migration script: Populate LanceDB from existing processed notes
 *
 * Run once to backfill vectors for all existing notes.
 * Safe to run multiple times (skips already indexed).
 */

import {
  db,
  embed,
  isAvailable,
  indexNotes,
  getIndexedNoteIds,
  type NoteVector,
  VECTOR_DIMENSIONS,
} from '../src/lib';

interface NoteRow {
  id: number;
  title: string;
  content: string;
  created_at: string;
  primary_theme: string | null;
}

async function migrate() {
  console.log('=== LanceDB Migration ===\n');

  // Check Ollama
  if (!(await isAvailable())) {
    console.error('ERROR: Ollama is not available. Start Ollama first.');
    process.exit(1);
  }
  console.log('Ollama: OK\n');

  // Get existing indexed IDs
  const indexedIds = await getIndexedNoteIds();
  console.log(`Already indexed: ${indexedIds.size} notes\n`);

  // Get all processed notes
  const notes = db.prepare(`
    SELECT
      rn.id, rn.title, rn.content, rn.created_at,
      pn.primary_theme
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.test_run IS NULL
    ORDER BY rn.created_at
  `).all() as NoteRow[];

  // Filter to unindexed
  const toMigrate = notes.filter(n => !indexedIds.has(n.id));

  console.log(`Total processed notes: ${notes.length}`);
  console.log(`Need migration: ${toMigrate.length}\n`);

  if (toMigrate.length === 0) {
    console.log('Nothing to migrate. All notes already indexed.');
    process.exit(0);
  }

  // Process in batches
  const batchSize = 20;
  let success = 0;
  let errors = 0;

  for (let i = 0; i < toMigrate.length; i += batchSize) {
    const batch = toMigrate.slice(i, i + batchSize);
    const vectors: NoteVector[] = [];

    for (const note of batch) {
      const progress = `[${i + batch.indexOf(note) + 1}/${toMigrate.length}]`;
      process.stdout.write(`${progress} ${note.title.slice(0, 50)}...`);

      try {
        const text = `${note.title}\n\n${note.content}`;
        const vector = await embed(text);

        if (vector.length !== VECTOR_DIMENSIONS) {
          throw new Error(`Bad dimensions: ${vector.length}`);
        }

        vectors.push({
          id: note.id,
          vector,
          title: note.title,
          primary_theme: note.primary_theme,
          note_type: null,
          actionability: null,
          time_horizon: null,
          context: null,
          created_at: note.created_at,
          indexed_at: new Date().toISOString(),
        });

        console.log(' OK');
        success++;
      } catch (err) {
        console.log(' FAILED');
        console.error(`  Error: ${(err as Error).message}`);
        errors++;
      }
    }

    // Batch insert
    if (vectors.length > 0) {
      try {
        await indexNotes(vectors);
        console.log(`Batch ${Math.floor(i / batchSize) + 1} indexed (${vectors.length} notes)\n`);
      } catch (err) {
        console.error(`Batch insert failed: ${(err as Error).message}`);
        errors += vectors.length;
        success -= vectors.length;
      }
    }
  }

  console.log('\n=== Migration Complete ===');
  console.log(`Success: ${success}`);
  console.log(`Errors: ${errors}`);

  process.exit(errors > 0 ? 1 : 0);
}

migrate().catch(err => {
  console.error('Migration crashed:', err);
  process.exit(1);
});
```

**Step 2: Test migration (if you have data)**

Run:
```bash
npx ts-node scripts/migrate-to-lancedb.ts
```

Expected: Processes all unindexed notes, shows progress

**Step 3: Commit**

```bash
git add scripts/migrate-to-lancedb.ts
git commit -m "$(cat <<'EOF'
feat: add LanceDB migration script

One-time backfill of existing processed notes into LanceDB.
Safe to run multiple times (skips already indexed).

Usage: npx ts-node scripts/migrate-to-lancedb.ts

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Typed Relationships

### Task 7: Create Relationship Tables in SQLite

**Files:**
- Create: `scripts/migrations/003-relationships.sql`
- Create: `scripts/run-migration.ts`

**Step 1: Create migration SQL file**

Create directory and file `scripts/migrations/003-relationships.sql`:

```sql
-- Typed relationships between notes (library science model)
-- BT = Broader Term, NT = Narrower Term, RT = Related Term

CREATE TABLE IF NOT EXISTS note_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    relationship_type TEXT NOT NULL CHECK(relationship_type IN
        ('BT', 'NT', 'RT', 'TEMPORAL', 'SAME_THREAD', 'SAME_PROJECT')),
    strength REAL,  -- 0.0 to 1.0, NULL for structural types
    source TEXT NOT NULL CHECK(source IN
        ('llm_extracted', 'embedding_high', 'temporal', 'structural', 'user_explicit')),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id, relationship_type)
);

CREATE INDEX IF NOT EXISTS idx_relationships_a ON note_relationships(note_a_id);
CREATE INDEX IF NOT EXISTS idx_relationships_b ON note_relationships(note_b_id);
CREATE INDEX IF NOT EXISTS idx_relationships_type ON note_relationships(relationship_type);
CREATE INDEX IF NOT EXISTS idx_relationships_source ON note_relationships(source);

-- Concept hierarchy for BT/NT derivation
CREATE TABLE IF NOT EXISTS concept_hierarchy (
    concept TEXT PRIMARY KEY,
    parent_concept TEXT,
    level INTEGER DEFAULT 0,  -- 0 = root, higher = more specific
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_concept_parent ON concept_hierarchy(parent_concept);

-- Note facets for filtering (populated by enhanced LLM extraction)
CREATE TABLE IF NOT EXISTS note_facets (
    raw_note_id INTEGER PRIMARY KEY,
    note_type TEXT CHECK(note_type IN ('task', 'reflection', 'reference', 'idea', 'log')),
    actionability TEXT CHECK(actionability IN ('actionable', 'someday', 'reference', 'done')),
    time_horizon TEXT CHECK(time_horizon IN ('immediate', 'week', 'month', 'timeless')),
    context TEXT,  -- JSON array of contexts
    classified_at TEXT,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);
```

**Step 2: Create migration runner**

Create `scripts/run-migration.ts`:

```typescript
/**
 * Run SQL migration files against the database
 */

import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { db } from '../src/lib';

const migrationsDir = join(__dirname, 'migrations');

function runMigrations() {
  console.log('=== Running Migrations ===\n');

  const files = readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    console.log(`Running: ${file}`);
    const sql = readFileSync(join(migrationsDir, file), 'utf-8');

    try {
      db.exec(sql);
      console.log(`  OK\n`);
    } catch (err) {
      console.error(`  FAILED: ${(err as Error).message}\n`);
      // Continue with other migrations
    }
  }

  console.log('=== Migrations Complete ===');
}

runMigrations();
```

**Step 3: Run migration**

Run:
```bash
mkdir -p scripts/migrations
# (after creating the files above)
npx ts-node scripts/run-migration.ts
```

Expected: Tables created successfully

**Step 4: Verify tables exist**

Run:
```bash
sqlite3 data/selene.db ".schema note_relationships"
```

Expected: Shows the CREATE TABLE statement

**Step 5: Commit**

```bash
git add scripts/migrations/003-relationships.sql scripts/run-migration.ts
git commit -m "$(cat <<'EOF'
feat: add typed relationships schema

Library science-inspired relationship model:
- BT/NT: hierarchical (broader/narrower term)
- RT: associative (related term)
- TEMPORAL: same time period
- SAME_THREAD/SAME_PROJECT: structural

Also adds:
- concept_hierarchy: for deriving BT/NT
- note_facets: for ADHD-optimized filtering

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Create Relationship Computation Workflow

**Files:**
- Create: `src/workflows/compute-relationships.ts`
- Modify: `package.json`

**Step 1: Create the workflow**

Create `src/workflows/compute-relationships.ts`:

```typescript
import { createWorkflowLogger, db } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compute-relationships');

// Thresholds
const TEMPORAL_WINDOW_HOURS = 24;

interface TemporalNote {
  id: number;
  created_at: string;
}

/**
 * Compute TEMPORAL relationships between notes created close in time
 */
function computeTemporalRelationships(): number {
  log.info('Computing temporal relationships');

  // Get all notes ordered by creation time
  const notes = db.prepare(`
    SELECT id, created_at FROM raw_notes
    WHERE test_run IS NULL AND status = 'processed'
    ORDER BY created_at
  `).all() as TemporalNote[];

  const insert = db.prepare(`
    INSERT OR IGNORE INTO note_relationships
    (note_a_id, note_b_id, relationship_type, strength, source)
    VALUES (?, ?, 'TEMPORAL', NULL, 'temporal')
  `);

  let count = 0;

  for (let i = 0; i < notes.length; i++) {
    const noteA = notes[i];
    const timeA = new Date(noteA.created_at).getTime();

    // Look at subsequent notes within the window
    for (let j = i + 1; j < notes.length; j++) {
      const noteB = notes[j];
      const timeB = new Date(noteB.created_at).getTime();
      const diffHours = (timeB - timeA) / (1000 * 60 * 60);

      if (diffHours > TEMPORAL_WINDOW_HOURS) break;

      // Ensure note_a_id < note_b_id for consistency
      const [smallerId, largerId] = noteA.id < noteB.id
        ? [noteA.id, noteB.id]
        : [noteB.id, noteA.id];

      try {
        insert.run(smallerId, largerId);
        count++;
      } catch {
        // Ignore duplicates
      }
    }
  }

  log.info({ count }, 'Temporal relationships computed');
  return count;
}

/**
 * Compute SAME_THREAD relationships from threads table
 */
function computeThreadRelationships(): number {
  log.info('Computing thread relationships');

  const result = db.prepare(`
    INSERT OR IGNORE INTO note_relationships
    (note_a_id, note_b_id, relationship_type, strength, source)
    SELECT
      MIN(tn1.raw_note_id, tn2.raw_note_id),
      MAX(tn1.raw_note_id, tn2.raw_note_id),
      'SAME_THREAD',
      NULL,
      'structural'
    FROM thread_notes tn1
    JOIN thread_notes tn2 ON tn1.thread_id = tn2.thread_id
    WHERE tn1.raw_note_id < tn2.raw_note_id
  `).run();

  const count = result.changes;
  log.info({ count }, 'Thread relationships computed');
  return count;
}

/**
 * Compute SAME_PROJECT relationships from project_notes table
 */
function computeProjectRelationships(): number {
  log.info('Computing project relationships');

  const result = db.prepare(`
    INSERT OR IGNORE INTO note_relationships
    (note_a_id, note_b_id, relationship_type, strength, source)
    SELECT
      MIN(pn1.raw_note_id, pn2.raw_note_id),
      MAX(pn1.raw_note_id, pn2.raw_note_id),
      'SAME_PROJECT',
      NULL,
      'structural'
    FROM project_notes pn1
    JOIN project_notes pn2 ON pn1.project_id = pn2.project_id
    WHERE pn1.raw_note_id < pn2.raw_note_id
  `).run();

  const count = result.changes;
  log.info({ count }, 'Project relationships computed');
  return count;
}

/**
 * Main workflow: compute all relationship types
 */
export async function computeRelationships(): Promise<WorkflowResult> {
  log.info('Starting relationship computation');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  try {
    const temporal = computeTemporalRelationships();
    result.processed += temporal;
    result.details.push({ id: 0, success: true, error: `temporal: ${temporal}` });
  } catch (err) {
    log.error({ err }, 'Failed temporal relationships');
    result.errors++;
  }

  try {
    const thread = computeThreadRelationships();
    result.processed += thread;
    result.details.push({ id: 0, success: true, error: `thread: ${thread}` });
  } catch (err) {
    log.error({ err }, 'Failed thread relationships');
    result.errors++;
  }

  try {
    const project = computeProjectRelationships();
    result.processed += project;
    result.details.push({ id: 0, success: true, error: `project: ${project}` });
  } catch (err) {
    log.error({ err }, 'Failed project relationships');
    result.errors++;
  }

  log.info(result, 'Relationship computation complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  computeRelationships()
    .then((result) => {
      console.log('Compute-relationships complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compute-relationships failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Add npm script**

Modify `package.json`, add to scripts:

```json
"workflow:compute-relationships": "ts-node src/workflows/compute-relationships.ts"
```

**Step 3: Test workflow**

Run:
```bash
npm run workflow:compute-relationships
```

Expected: Reports relationships computed

**Step 4: Verify data**

Run:
```bash
sqlite3 data/selene.db "SELECT relationship_type, COUNT(*) FROM note_relationships GROUP BY relationship_type"
```

Expected: Shows counts by type

**Step 5: Commit**

```bash
git add src/workflows/compute-relationships.ts package.json
git commit -m "$(cat <<'EOF'
feat: add compute-relationships workflow

Computes typed relationships:
- TEMPORAL: notes created within 24 hours
- SAME_THREAD: notes in same thread
- SAME_PROJECT: notes in same project

Replaces brute-force similarity associations with
meaningful, queryable relationship types.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Query Layer

### Task 9: Create Hybrid Related Notes Query

**Files:**
- Create: `src/queries/related-notes.ts`

**Step 1: Create the query module**

Create `src/queries/related-notes.ts`:

```typescript
import {
  createWorkflowLogger,
  db,
  embed,
  searchSimilarNotes,
  type SimilarNote,
} from '../lib';

const log = createWorkflowLogger('related-notes');

/**
 * A related note with relationship context
 */
export interface RelatedNote {
  id: number;
  title: string;
  primary_theme: string | null;
  relationship_type: 'BT' | 'NT' | 'RT' | 'TEMPORAL' | 'SAME_THREAD' | 'SAME_PROJECT' | 'EMBEDDING';
  strength: number | null;
  source: 'precomputed' | 'live';
}

interface StoredRelationship {
  related_id: number;
  relationship_type: string;
  strength: number | null;
}

/**
 * Get precomputed relationships for a note
 */
function getPrecomputedRelationships(noteId: number): StoredRelationship[] {
  return db.prepare(`
    SELECT
      CASE
        WHEN note_a_id = ? THEN note_b_id
        ELSE note_a_id
      END as related_id,
      relationship_type,
      strength
    FROM note_relationships
    WHERE note_a_id = ? OR note_b_id = ?
    ORDER BY
      CASE relationship_type
        WHEN 'BT' THEN 1
        WHEN 'NT' THEN 2
        WHEN 'RT' THEN 3
        WHEN 'SAME_PROJECT' THEN 4
        WHEN 'SAME_THREAD' THEN 5
        WHEN 'TEMPORAL' THEN 6
      END,
      strength DESC NULLS LAST
  `).all(noteId, noteId, noteId) as StoredRelationship[];
}

/**
 * Get note details by IDs
 */
function getNoteDetails(ids: number[]): Map<number, { title: string; primary_theme: string | null }> {
  if (ids.length === 0) return new Map();

  const results = db.prepare(`
    SELECT rn.id, rn.title, pn.primary_theme
    FROM raw_notes rn
    LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.id IN (${ids.join(',')})
  `).all() as Array<{ id: number; title: string; primary_theme: string | null }>;

  return new Map(results.map(r => [r.id, { title: r.title, primary_theme: r.primary_theme }]));
}

/**
 * Get related notes combining precomputed + live search
 */
export async function getRelatedNotes(
  noteId: number,
  options: {
    limit?: number;
    includeLive?: boolean;
    liveMaxDistance?: number;
  } = {}
): Promise<RelatedNote[]> {
  const { limit = 10, includeLive = true, liveMaxDistance = 1.5 } = options;

  log.info({ noteId, options }, 'Getting related notes');

  const related: RelatedNote[] = [];
  const seenIds = new Set<number>([noteId]);

  // 1. Get precomputed relationships
  const precomputed = getPrecomputedRelationships(noteId);
  const precomputedIds = precomputed.map(r => r.related_id);
  const noteDetails = getNoteDetails(precomputedIds);

  for (const rel of precomputed) {
    if (seenIds.has(rel.related_id)) continue;
    seenIds.add(rel.related_id);

    const details = noteDetails.get(rel.related_id);
    if (!details) continue;

    related.push({
      id: rel.related_id,
      title: details.title,
      primary_theme: details.primary_theme,
      relationship_type: rel.relationship_type as RelatedNote['relationship_type'],
      strength: rel.strength,
      source: 'precomputed',
    });

    if (related.length >= limit) break;
  }

  // 2. Live embedding search if we need more
  if (includeLive && related.length < limit) {
    const note = db.prepare(`
      SELECT title, content FROM raw_notes WHERE id = ?
    `).get(noteId) as { title: string; content: string } | undefined;

    if (note) {
      try {
        const queryVector = await embed(`${note.title}\n\n${note.content}`);

        const liveResults = await searchSimilarNotes(queryVector, {
          limit: (limit - related.length) + 5,
          maxDistance: liveMaxDistance,
          excludeIds: Array.from(seenIds),
        });

        for (const result of liveResults) {
          if (seenIds.has(result.id)) continue;
          if (related.length >= limit) break;

          seenIds.add(result.id);
          related.push({
            id: result.id,
            title: result.title,
            primary_theme: result.primary_theme,
            relationship_type: 'EMBEDDING',
            strength: 1 - (result.distance / liveMaxDistance), // Normalize to 0-1
            source: 'live',
          });
        }
      } catch (err) {
        log.warn({ err, noteId }, 'Live search failed, returning precomputed only');
      }
    }
  }

  log.info({
    noteId,
    total: related.length,
    precomputed: related.filter(r => r.source === 'precomputed').length,
    live: related.filter(r => r.source === 'live').length,
  }, 'Related notes retrieved');

  return related.slice(0, limit);
}

/**
 * Search notes by semantic query with optional filters
 */
export async function searchNotes(
  query: string,
  options: {
    limit?: number;
    noteType?: string;
    actionability?: string;
  } = {}
): Promise<SimilarNote[]> {
  const { limit = 10, noteType, actionability } = options;

  log.info({ query, options }, 'Searching notes');

  const queryVector = await embed(query);

  return searchSimilarNotes(queryVector, {
    limit,
    filterNoteType: noteType,
    filterActionability: actionability,
  });
}
```

**Step 2: Test the query**

Run:
```bash
npx ts-node -e "
import { getRelatedNotes } from './src/queries/related-notes';

// Replace with an actual note ID from your database
const noteId = 1;

getRelatedNotes(noteId, { limit: 5 })
  .then(results => {
    console.log('Related notes:');
    for (const r of results) {
      console.log(\`  [\${r.relationship_type}] \${r.title} (source: \${r.source})\`);
    }
    process.exit(0);
  })
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
"
```

Expected: Shows related notes with relationship types

**Step 3: Commit**

```bash
git add src/queries/related-notes.ts
git commit -m "$(cat <<'EOF'
feat: add hybrid related notes query

getRelatedNotes combines:
1. Precomputed relationships (BT/NT/RT/TEMPORAL/etc)
2. Live embedding search via LanceDB

Results ranked by relationship type priority,
then by strength/distance.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5: Cleanup

### Task 10: Deprecate Old Workflows

**Files:**
- Rename: `src/workflows/compute-embeddings.ts` → `src/workflows/_deprecated_compute-embeddings.ts`
- Rename: `src/workflows/compute-associations.ts` → `src/workflows/_deprecated_compute-associations.ts`
- Modify: `package.json`

**Step 1: Rename old files**

Run:
```bash
mv src/workflows/compute-embeddings.ts src/workflows/_deprecated_compute-embeddings.ts
mv src/workflows/compute-associations.ts src/workflows/_deprecated_compute-associations.ts
```

**Step 2: Update package.json scripts**

Modify `package.json`, replace old scripts:

```json
"workflow:compute-embeddings": "echo 'DEPRECATED: Use workflow:index-vectors instead' && exit 1",
"workflow:compute-associations": "echo 'DEPRECATED: Use workflow:compute-relationships instead' && exit 1"
```

**Step 3: Verify old scripts warn**

Run:
```bash
npm run workflow:compute-embeddings
```

Expected: Shows deprecation message and exits with error

**Step 4: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: deprecate old embedding/association workflows

Replaced by:
- compute-embeddings → index-vectors (LanceDB)
- compute-associations → compute-relationships (typed)

Old files kept as _deprecated_* for reference.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Update Launchd Configuration

**Files:**
- Modify: `launchd/com.selene.compute-embeddings.plist` (or create new)

**Step 1: Check existing launchd config**

Run:
```bash
ls -la launchd/
```

**Step 2: Create/update plist for index-vectors**

If `com.selene.compute-embeddings.plist` exists, update it. Otherwise create `launchd/com.selene.index-vectors.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.index-vectors</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>src/workflows/index-vectors.ts</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/index-vectors.out.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/index-vectors.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Step 3: Install updated launchd agent**

Run:
```bash
# Unload old if exists
launchctl unload ~/Library/LaunchAgents/com.selene.compute-embeddings.plist 2>/dev/null || true

# Copy and load new
cp launchd/com.selene.index-vectors.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.selene.index-vectors.plist
```

**Step 4: Verify running**

Run:
```bash
launchctl list | grep selene
```

Expected: Shows com.selene.index-vectors

**Step 5: Commit**

```bash
git add launchd/
git commit -m "$(cat <<'EOF'
chore: update launchd for index-vectors workflow

Replaces compute-embeddings scheduled job with
new LanceDB-based index-vectors workflow.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

| Phase | What | Files Changed |
|-------|------|---------------|
| 1 | LanceDB foundation | `src/lib/lancedb.ts`, `package.json` |
| 2 | Vector indexing workflow | `src/workflows/index-vectors.ts`, migration script |
| 3 | Typed relationships | `note_relationships` table, `src/workflows/compute-relationships.ts` |
| 4 | Query layer | `src/queries/related-notes.ts` |
| 5 | Cleanup | Deprecate old workflows, update launchd |

**After completing all tasks:**
1. Run migration: `npx ts-node scripts/migrate-to-lancedb.ts`
2. Run relationships: `npm run workflow:compute-relationships`
3. Test queries work
4. Delete `_deprecated_*` files after confirming everything works
