import { createWorkflowLogger, db, generate, embed, searchSimilarNotes, getIndexedNoteIds, ContextBuilder } from '../lib';
import type { FidelityTier } from '../lib/context-builder';
import { normalizeThreadName } from '../lib/strings';
import { notifyNewThread } from '../lib/apns';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('detect-threads');

// Configuration
// Tuned via US-046: 0.65 provides best balance between cluster detection and over-merging
const DEFAULT_SIMILARITY_THRESHOLD = 0.65;
const MIN_CLUSTER_SIZE = 3;
// Thread assignment configuration
// L2 distance threshold - based on observed data: median ~288, 75th percentile ~346
const MAX_ASSIGNMENT_DISTANCE = 350; // L2 distance threshold for thread assignment
const MIN_THREAD_NEIGHBORS = 2; // Require 2+ neighbors in same thread
const ASSIGNMENT_SEARCH_LIMIT = 10; // How many neighbors to check per note

// Types
interface NoteRecord {
  id: number;
  title: string;
  content: string;
  created_at: string;
  essence: string | null;
  primary_theme: string | null;
  concepts: string | null;
  fidelity_tier: FidelityTier;
}

interface AssociationRecord {
  note_a_id: number;
  note_b_id: number;
  similarity_score: number;
}

interface ThreadSynthesis {
  name: string;
  why: string;
  summary: string;
  direction: 'exploring' | 'emerging' | 'clear';
  emotional_tone: 'neutral' | 'positive' | 'negative' | 'mixed';
}

// Types for thread assignment
interface Neighbor {
  id: number;
  distance: number;
}

interface AssignmentOptions {
  maxDistance: number;
  minNeighbors: number;
}

interface ThreadMatch {
  threadId: number;
  relevanceScore: number;
}

/**
 * Given a note's nearest neighbors and which threads those neighbors belong to,
 * determine the best thread to assign the note to.
 * Returns null if no thread has enough close neighbors.
 */
export function findBestThread(
  neighbors: Neighbor[],
  threadMembership: Map<number, number>,
  options: AssignmentOptions
): ThreadMatch | null {
  // Count neighbors per thread, only considering close enough ones
  const threadCounts = new Map<number, { count: number; totalDistance: number }>();

  for (const neighbor of neighbors) {
    if (neighbor.distance > options.maxDistance) continue;

    const threadId = threadMembership.get(neighbor.id);
    if (threadId === undefined) continue;

    const existing = threadCounts.get(threadId) || { count: 0, totalDistance: 0 };
    existing.count++;
    existing.totalDistance += neighbor.distance;
    threadCounts.set(threadId, existing);
  }

  // Find the thread with the most neighbors (ties broken by avg distance)
  let best: { threadId: number; count: number; avgDistance: number } | null = null;

  for (const [threadId, stats] of threadCounts) {
    if (stats.count < options.minNeighbors) continue;

    const avgDistance = stats.totalDistance / stats.count;

    if (!best || stats.count > best.count || (stats.count === best.count && avgDistance < best.avgDistance)) {
      best = { threadId, count: stats.count, avgDistance };
    }
  }

  if (!best) return null;

  // Convert distance to a 0-1 relevance score (lower distance = higher relevance)
  const relevanceScore = Math.max(0, Math.min(1, 1 - best.avgDistance / options.maxDistance));

  return { threadId: best.threadId, relevanceScore };
}

/**
 * Build adjacency list from associations
 */
function buildAdjacencyList(
  associations: AssociationRecord[],
  threshold: number
): Map<number, Set<number>> {
  const adjacency = new Map<number, Set<number>>();

  for (const assoc of associations) {
    if (assoc.similarity_score < threshold) continue;

    if (!adjacency.has(assoc.note_a_id)) {
      adjacency.set(assoc.note_a_id, new Set());
    }
    if (!adjacency.has(assoc.note_b_id)) {
      adjacency.set(assoc.note_b_id, new Set());
    }

    adjacency.get(assoc.note_a_id)!.add(assoc.note_b_id);
    adjacency.get(assoc.note_b_id)!.add(assoc.note_a_id);
  }

  return adjacency;
}

/**
 * Find connected components (clusters) using BFS
 */
function findClusters(adjacency: Map<number, Set<number>>): number[][] {
  const visited = new Set<number>();
  const clusters: number[][] = [];

  for (const nodeId of adjacency.keys()) {
    if (visited.has(nodeId)) continue;

    // BFS to find all connected nodes
    const cluster: number[] = [];
    const queue: number[] = [nodeId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      if (visited.has(current)) continue;

      visited.add(current);
      cluster.push(current);

      const neighbors = adjacency.get(current) || new Set();
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor)) {
          queue.push(neighbor);
        }
      }
    }

    if (cluster.length >= MIN_CLUSTER_SIZE) {
      clusters.push(cluster);
    }
  }

  return clusters;
}

/**
 * Get notes that are already assigned to threads
 */
function getThreadedNoteIds(): Set<number> {
  const rows = db.prepare('SELECT raw_note_id FROM thread_notes').all() as Array<{ raw_note_id: number }>;
  return new Set(rows.map((r) => r.raw_note_id));
}

/**
 * Build a map of note ID -> thread ID for all threaded notes
 */
function getThreadMembership(): Map<number, number> {
  const rows = db.prepare('SELECT raw_note_id, thread_id FROM thread_notes').all() as Array<{
    raw_note_id: number;
    thread_id: number;
  }>;
  const map = new Map<number, number>();
  for (const row of rows) {
    map.set(row.raw_note_id, row.thread_id);
  }
  return map;
}

/**
 * Assign unthreaded notes to existing threads based on vector similarity.
 * Runs before new thread detection so notes get absorbed into existing threads first.
 */
async function assignToExistingThreads(): Promise<number> {
  const threadedNoteIds = getThreadedNoteIds();
  const threadMembership = getThreadMembership();

  if (threadMembership.size === 0) {
    log.info('No existing threads to assign to');
    return 0;
  }

  // Get unthreaded notes that have embeddings in LanceDB
  const indexedIds = await getIndexedNoteIds();
  const unthreadedIndexed: number[] = [];
  for (const id of indexedIds) {
    if (!threadedNoteIds.has(id)) {
      unthreadedIndexed.push(id);
    }
  }

  if (unthreadedIndexed.length === 0) {
    log.info('No unthreaded indexed notes to assign');
    return 0;
  }

  log.info({ count: unthreadedIndexed.length }, 'Checking unthreaded notes for thread assignment');

  let assigned = 0;
  const now = new Date().toISOString();

  const linkStmt = db.prepare(
    `INSERT OR IGNORE INTO thread_notes (thread_id, raw_note_id, added_at, relevance_score)
     VALUES (?, ?, ?, ?)`
  );
  const updateThreadStmt = db.prepare(
    `UPDATE threads SET note_count = note_count + 1, last_activity_at = ?, updated_at = ? WHERE id = ?`
  );

  for (const noteId of unthreadedIndexed) {
    try {
      // Get this note's content for embedding
      const note = db.prepare('SELECT title, content FROM raw_notes WHERE id = ?').get(noteId) as
        | { title: string; content: string }
        | undefined;
      if (!note) continue;

      const vector = await embed(`${note.title}\n\n${note.content}`);
      const neighbors = await searchSimilarNotes(vector, {
        limit: ASSIGNMENT_SEARCH_LIMIT,
        excludeIds: [noteId],
      });

      const match = findBestThread(
        neighbors.map((n) => ({ id: n.id, distance: n.distance })),
        threadMembership,
        { maxDistance: MAX_ASSIGNMENT_DISTANCE, minNeighbors: MIN_THREAD_NEIGHBORS }
      );

      if (match) {
        linkStmt.run(match.threadId, noteId, now, match.relevanceScore);
        updateThreadStmt.run(now, now, match.threadId);

        // Reactivate archived threads when new notes are assigned
        const threadStatus = db
          .prepare('SELECT status FROM threads WHERE id = ?')
          .get(match.threadId) as { status: string } | undefined;

        if (threadStatus?.status === 'archived') {
          db.prepare(
            `UPDATE threads SET status = 'active', updated_at = ? WHERE id = ?`
          ).run(now, match.threadId);

          db.prepare(
            `INSERT INTO thread_history (thread_id, trigger_note_id, change_type, created_at)
             VALUES (?, ?, 'reactivated', ?)`
          ).run(match.threadId, noteId, now);

          log.info({ threadId: match.threadId, noteId }, 'Reactivated archived thread');
        }

        threadMembership.set(noteId, match.threadId);
        assigned++;

        const threadName = db.prepare('SELECT name FROM threads WHERE id = ?').get(match.threadId) as
          | { name: string }
          | undefined;
        log.info(
          { noteId, threadId: match.threadId, threadName: threadName?.name, relevance: match.relevanceScore },
          'Assigned note to existing thread'
        );
      }
    } catch (err) {
      log.error({ err, noteId }, 'Error assigning note to thread');
    }
  }

  log.info({ assigned, checked: unthreadedIndexed.length }, 'Thread assignment complete');
  return assigned;
}

/**
 * Get note content for synthesis
 */
function getNoteContent(noteIds: number[]): NoteRecord[] {
  const placeholders = noteIds.map(() => '?').join(',');
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, rn.created_at,
              pn.essence, pn.primary_theme, pn.concepts,
              COALESCE(pn.fidelity_tier, 'full') as fidelity_tier
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.id IN (${placeholders})
       ORDER BY rn.created_at ASC`
    )
    .all(...noteIds) as NoteRecord[];
}

/**
 * Build LLM prompt for thread synthesis
 */
function buildSynthesisPrompt(notes: NoteRecord[]): string {
  const builder = new ContextBuilder(3000);

  for (const note of notes) {
    builder.addNote({
      id: note.id,
      title: `${note.title} (${note.created_at})`,
      content: note.content,
      essence: note.essence,
      primary_theme: note.primary_theme,
      concepts: note.concepts,
      fidelity_tier: note.fidelity_tier,
    });
  }

  const noteTexts = builder.build();

  return `These notes were written over time by the same person. They cluster together based on semantic similarity.

${noteTexts}

Questions:
1. What thread of thinking connects these notes?
2. What is the underlying want, need, or motivation?
3. Is there a clear direction or is this still exploring?
4. Suggest a short name for this thread (2-5 words)

Respond ONLY with valid JSON (no explanation):
{
  "name": "Short Thread Name",
  "why": "The underlying motivation or goal",
  "summary": "What connects these notes together",
  "direction": "exploring|emerging|clear",
  "emotional_tone": "neutral|positive|negative|mixed"
}`;
}

/**
 * Parse LLM response into ThreadSynthesis
 */
function parseSynthesis(response: string): ThreadSynthesis | null {
  try {
    // Extract JSON from response (handle markdown code blocks)
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      log.warn({ response }, 'No JSON found in LLM response');
      return null;
    }

    const parsed = JSON.parse(jsonMatch[0]);

    // Validate required fields
    if (!parsed.name || typeof parsed.name !== 'string') {
      log.warn({ parsed }, 'Missing or invalid name field');
      return null;
    }

    return {
      name: normalizeThreadName(parsed.name),
      why: parsed.why || '',
      summary: parsed.summary || '',
      direction: ['exploring', 'emerging', 'clear'].includes(parsed.direction)
        ? parsed.direction
        : 'exploring',
      emotional_tone: ['neutral', 'positive', 'negative', 'mixed'].includes(parsed.emotional_tone)
        ? parsed.emotional_tone
        : 'neutral',
    };
  } catch (err) {
    log.error({ err, response }, 'Failed to parse LLM response');
    return null;
  }
}

/**
 * Create a thread and link notes to it
 */
function createThread(synthesis: ThreadSynthesis, noteIds: number[]): number {
  const now = new Date().toISOString();

  // Insert thread
  const result = db
    .prepare(
      `INSERT INTO threads (name, why, summary, status, note_count, last_activity_at, created_at, updated_at)
       VALUES (?, ?, ?, 'active', ?, ?, ?, ?)`
    )
    .run(synthesis.name, synthesis.why, synthesis.summary, noteIds.length, now, now, now);

  const threadId = result.lastInsertRowid as number;

  // Link notes to thread
  const linkStmt = db.prepare(
    `INSERT INTO thread_notes (thread_id, raw_note_id, added_at, relevance_score)
     VALUES (?, ?, ?, 1.0)`
  );

  for (const noteId of noteIds) {
    linkStmt.run(threadId, noteId, now);
  }

  // Record creation in history
  db.prepare(
    `INSERT INTO thread_history (thread_id, summary_after, change_type, created_at)
     VALUES (?, ?, 'created', ?)`
  ).run(threadId, synthesis.summary, now);

  log.info({ threadId, name: synthesis.name, noteCount: noteIds.length }, 'Thread created');

  return threadId;
}

/**
 * Main workflow: detect threads from note associations
 */
export async function detectThreads(threshold = DEFAULT_SIMILARITY_THRESHOLD): Promise<WorkflowResult> {
  log.info({ threshold, minClusterSize: MIN_CLUSTER_SIZE }, 'Starting thread detection');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  // Phase 1: Assign unthreaded notes to existing threads
  try {
    const assignedCount = await assignToExistingThreads();
    result.details.push({ id: 0, success: true, error: `Assigned ${assignedCount} notes to existing threads` });
  } catch (err) {
    log.error({ err }, 'Error in thread assignment phase');
  }

  // Get all associations
  const associations = db
    .prepare('SELECT note_a_id, note_b_id, similarity_score FROM note_associations')
    .all() as AssociationRecord[];

  log.info({ associationCount: associations.length }, 'Loaded associations');

  if (associations.length === 0) {
    log.info('No associations found - run compute-associations first');
    return result;
  }

  // Build adjacency list and find clusters
  const adjacency = buildAdjacencyList(associations, threshold);
  const clusters = findClusters(adjacency);

  log.info({ clusterCount: clusters.length }, 'Found clusters');

  if (clusters.length === 0) {
    log.info('No clusters found above minimum size');
    return result;
  }

  // Get already-threaded notes to avoid duplicates
  const threadedNoteIds = getThreadedNoteIds();

  // Process each cluster
  for (const cluster of clusters) {
    // Filter out already-threaded notes
    const unthreadedNotes = cluster.filter((id) => !threadedNoteIds.has(id));

    if (unthreadedNotes.length < MIN_CLUSTER_SIZE) {
      log.info(
        { clusterSize: cluster.length, unthreadedCount: unthreadedNotes.length },
        'Cluster too small after filtering threaded notes'
      );
      continue;
    }

    try {
      // Get note content
      const notes = getNoteContent(unthreadedNotes);

      if (notes.length < MIN_CLUSTER_SIZE) {
        log.warn({ noteIds: unthreadedNotes }, 'Could not fetch enough notes');
        continue;
      }

      // Build prompt and call LLM
      const prompt = buildSynthesisPrompt(notes);
      log.info({ noteCount: notes.length, promptLength: prompt.length }, 'Calling LLM for synthesis');

      const llmResponse = await generate(prompt);

      // Parse response
      const synthesis = parseSynthesis(llmResponse);
      if (!synthesis) {
        log.error({ cluster: unthreadedNotes }, 'Failed to synthesize thread');
        result.errors++;
        result.details.push({ id: unthreadedNotes[0], success: false, error: 'LLM synthesis failed' });
        continue;
      }

      // Create thread
      const threadId = createThread(synthesis, unthreadedNotes);

      // Notify iOS devices about new thread
      await notifyNewThread(synthesis.name);

      // Mark these notes as threaded for subsequent iterations
      for (const noteId of unthreadedNotes) {
        threadedNoteIds.add(noteId);
      }

      result.processed++;
      result.details.push({ id: threadId, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, cluster }, 'Error processing cluster');
      result.errors++;
      result.details.push({ id: cluster[0], success: false, error: error.message });
    }
  }

  log.info(
    { threadsCreated: result.processed, errors: result.errors },
    'Thread detection complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  const threshold = process.argv[2] ? parseFloat(process.argv[2]) : DEFAULT_SIMILARITY_THRESHOLD;

  detectThreads(threshold)
    .then((result) => {
      console.log('Detect-threads complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Detect-threads failed:', err);
      process.exit(1);
    });
}
