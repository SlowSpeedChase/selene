import { createWorkflowLogger, db, generate } from '../lib';
import { normalizeThreadName } from '../lib/strings';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('thread-lifecycle');

// Configuration
const STALE_THRESHOLD_DAYS = 60;
const MIN_SPLIT_NOTES = 6;
const MIN_COMPONENT_SIZE = 3;
const SPLIT_SIMILARITY_THRESHOLD = 0.65;
const MAX_NOTES_PER_SYNTHESIS = 15;
const MERGE_DISTANCE_THRESHOLD = 200; // L2 distance between thread centroids

// Types
interface AssociationRecord {
  note_a_id: number;
  note_b_id: number;
  similarity_score: number;
}

interface NoteRecord {
  id: number;
  title: string;
  content: string;
  created_at: string;
}

interface ThreadSynthesis {
  name: string;
  why: string;
  summary: string;
}

interface ThreadRecord {
  id: number;
  name: string;
  why: string | null;
  summary: string | null;
  status: string;
  note_count: number;
  last_activity_at: string | null;
}

/**
 * Archive threads that have been inactive for longer than STALE_THRESHOLD_DAYS.
 * Sets status to 'archived' and records the change in thread_history.
 */
function archiveStaleThreads(): number {
  const now = new Date();
  const cutoff = new Date(now.getTime() - STALE_THRESHOLD_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const nowIso = now.toISOString();

  // Find active threads with no activity in the threshold period
  const staleThreads = db
    .prepare(
      `SELECT id, name, why, summary, status, note_count, last_activity_at
       FROM threads
       WHERE status = 'active'
         AND (last_activity_at IS NULL OR last_activity_at < ?)
       ORDER BY last_activity_at ASC`
    )
    .all(cutoff) as ThreadRecord[];

  if (staleThreads.length === 0) {
    log.info({ cutoff, thresholdDays: STALE_THRESHOLD_DAYS }, 'No stale threads found');
    return 0;
  }

  log.info(
    { count: staleThreads.length, cutoff, thresholdDays: STALE_THRESHOLD_DAYS },
    'Found stale threads to archive'
  );

  const updateStmt = db.prepare(
    `UPDATE threads SET status = 'archived', updated_at = ? WHERE id = ?`
  );

  const historyStmt = db.prepare(
    `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
     VALUES (?, ?, ?, 'archived', ?)`
  );

  let archived = 0;

  for (const thread of staleThreads) {
    updateStmt.run(nowIso, thread.id);
    historyStmt.run(thread.id, thread.summary, thread.summary, nowIso);
    archived++;

    log.info(
      {
        threadId: thread.id,
        name: thread.name,
        lastActivity: thread.last_activity_at,
        noteCount: thread.note_count,
      },
      'Archived stale thread'
    );
  }

  log.info({ archived }, 'Stale thread archival complete');
  return archived;
}

/**
 * BFS to find connected components in a graph.
 */
function findConnectedComponents(adjacency: Map<number, Set<number>>): number[][] {
  const visited = new Set<number>();
  const components: number[][] = [];

  for (const nodeId of adjacency.keys()) {
    if (visited.has(nodeId)) continue;

    const component: number[] = [];
    const queue: number[] = [nodeId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      if (visited.has(current)) continue;

      visited.add(current);
      component.push(current);

      const neighbors = adjacency.get(current) || new Set();
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor)) {
          queue.push(neighbor);
        }
      }
    }

    components.push(component);
  }

  return components;
}

/**
 * Build LLM prompt for naming a new thread from a cluster of notes.
 */
function buildSynthesisPrompt(notes: NoteRecord[]): string {
  const noteTexts = notes
    .slice(0, MAX_NOTES_PER_SYNTHESIS)
    .map((n, i) => `--- Note ${i + 1} (${n.created_at}) ---\nTitle: ${n.title}\n${n.content}`)
    .join('\n\n');

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
  "summary": "What connects these notes together"
}`;
}

/**
 * Parse LLM JSON response into a ThreadSynthesis.
 */
function parseSynthesis(response: string): ThreadSynthesis | null {
  try {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;

    const parsed = JSON.parse(jsonMatch[0]);
    if (!parsed.name || !parsed.summary) return null;

    return {
      name: normalizeThreadName(parsed.name),
      why: parsed.why || '',
      summary: parsed.summary,
    };
  } catch {
    return null;
  }
}

/**
 * Build LLM prompt for re-synthesizing a thread after a split.
 */
function buildResynthesisPrompt(thread: ThreadRecord, notes: NoteRecord[]): string {
  const noteTexts = notes
    .slice(0, MAX_NOTES_PER_SYNTHESIS)
    .map((n, i) => `--- Note ${i + 1} (${n.created_at}) ---\nTitle: ${n.title}\n${n.content}`)
    .join('\n\n');

  return `Thread: ${thread.name}
Previous summary: ${thread.summary || '(none)'}
Previous "why": ${thread.why || '(none)'}

Notes in this thread (newest first):
${noteTexts}

Questions:
1. Has the direction of this thread shifted?
2. What is the updated summary?
3. Has the underlying motivation become clearer or changed?

Respond ONLY with valid JSON:
{
  "name": "${thread.name}",
  "summary": "...",
  "why": "..."
}`;
}

/**
 * Compute centroid (average embedding vector) for a thread's notes.
 * Reads from note_embeddings table (768-dim vectors stored as JSON BLOB).
 */
function computeThreadCentroid(threadId: number): number[] | null {
  const embeddings = db
    .prepare(
      `SELECT ne.embedding
       FROM note_embeddings ne
       JOIN thread_notes tn ON ne.raw_note_id = tn.raw_note_id
       WHERE tn.thread_id = ?`
    )
    .all(threadId) as { embedding: Buffer }[];

  if (embeddings.length === 0) return null;

  // Parse JSON vectors and average them
  const vectors = embeddings.map((e) => JSON.parse(e.embedding.toString()) as number[]);
  const dims = vectors[0].length;
  const centroid = new Array(dims).fill(0) as number[];

  for (const vec of vectors) {
    for (let i = 0; i < dims; i++) {
      centroid[i] += vec[i];
    }
  }

  for (let i = 0; i < dims; i++) {
    centroid[i] /= vectors.length;
  }

  return centroid;
}

/**
 * L2 (Euclidean) distance between two vectors.
 */
function l2Distance(a: number[], b: number[]): number {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const diff = a[i] - b[i];
    sum += diff * diff;
  }
  return Math.sqrt(sum);
}

/**
 * Detect threads whose notes have drifted into distinct sub-clusters
 * and split them into separate threads.
 */
async function splitDivergentThreads(): Promise<{ splits: number; errors: number }> {
  let splits = 0;
  let errors = 0;

  // Find active threads with enough notes to potentially split
  const threads = db
    .prepare(
      `SELECT id, name, why, summary, status, note_count, last_activity_at
       FROM threads
       WHERE status = 'active'
         AND note_count >= ?
       ORDER BY note_count DESC`
    )
    .all(MIN_SPLIT_NOTES) as ThreadRecord[];

  if (threads.length === 0) {
    log.info({ minNotes: MIN_SPLIT_NOTES }, 'No threads eligible for split detection');
    return { splits, errors };
  }

  log.info({ count: threads.length }, 'Checking threads for divergence');

  for (const thread of threads) {
    try {
      // Get note IDs belonging to this thread
      const threadNoteRows = db
        .prepare(`SELECT raw_note_id FROM thread_notes WHERE thread_id = ?`)
        .all(thread.id) as { raw_note_id: number }[];

      const noteIds = threadNoteRows.map((r) => r.raw_note_id);

      if (noteIds.length < MIN_SPLIT_NOTES) continue;

      // Get associations between these notes above the similarity threshold
      const placeholders = noteIds.map(() => '?').join(',');
      const associations = db
        .prepare(
          `SELECT note_a_id, note_b_id, similarity_score
           FROM note_associations
           WHERE note_a_id IN (${placeholders})
             AND note_b_id IN (${placeholders})
             AND similarity_score >= ?`
        )
        .all(...noteIds, ...noteIds, SPLIT_SIMILARITY_THRESHOLD) as AssociationRecord[];

      // Build adjacency graph
      const adjacency = new Map<number, Set<number>>();
      for (const noteId of noteIds) {
        adjacency.set(noteId, new Set());
      }
      for (const assoc of associations) {
        adjacency.get(assoc.note_a_id)?.add(assoc.note_b_id);
        adjacency.get(assoc.note_b_id)?.add(assoc.note_a_id);
      }

      // Find connected components
      const components = findConnectedComponents(adjacency);

      // Filter to viable components (>= MIN_COMPONENT_SIZE)
      const viableComponents = components.filter((c) => c.length >= MIN_COMPONENT_SIZE);

      if (viableComponents.length < 2) {
        log.debug(
          { threadId: thread.id, name: thread.name, components: components.length, viable: viableComponents.length },
          'Thread is cohesive, no split needed'
        );
        continue;
      }

      log.info(
        { threadId: thread.id, name: thread.name, components: viableComponents.length },
        'Thread has divergent clusters, splitting'
      );

      // Sort by size DESC - largest keeps the original thread
      viableComponents.sort((a, b) => b.length - a.length);

      const nowIso = new Date().toISOString();

      // Process new clusters (skip index 0, that stays with the original thread)
      for (let i = 1; i < viableComponents.length; i++) {
        const clusterNoteIds = viableComponents[i];

        // Get note content for synthesis
        const clusterPlaceholders = clusterNoteIds.map(() => '?').join(',');
        const clusterNotes = db
          .prepare(
            `SELECT id, title, content, created_at
             FROM raw_notes
             WHERE id IN (${clusterPlaceholders})
             ORDER BY created_at DESC`
          )
          .all(...clusterNoteIds) as NoteRecord[];

        // Ask LLM to name the new thread
        const prompt = buildSynthesisPrompt(clusterNotes);
        const response = await generate(prompt);
        const synthesis = parseSynthesis(response);

        if (!synthesis) {
          log.warn(
            { threadId: thread.id, cluster: i, noteCount: clusterNoteIds.length },
            'Failed to parse synthesis for split cluster'
          );
          errors++;
          continue;
        }

        // Create new thread
        const insertResult = db
          .prepare(
            `INSERT INTO threads (name, why, summary, status, note_count, last_activity_at, created_at, updated_at)
             VALUES (?, ?, ?, 'active', ?, ?, ?, ?)`
          )
          .run(
            synthesis.name,
            synthesis.why,
            synthesis.summary,
            clusterNoteIds.length,
            nowIso,
            nowIso,
            nowIso
          );

        const newThreadId = insertResult.lastInsertRowid as number;

        // Move notes from old thread to new thread
        const moveNotePlaceholders = clusterNoteIds.map(() => '?').join(',');
        db.prepare(
          `UPDATE thread_notes SET thread_id = ? WHERE thread_id = ? AND raw_note_id IN (${moveNotePlaceholders})`
        ).run(newThreadId, thread.id, ...clusterNoteIds);

        // Record history for the new thread
        db.prepare(
          `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
           VALUES (?, NULL, ?, 'created', ?)`
        ).run(newThreadId, synthesis.summary, nowIso);

        log.info(
          {
            originalThreadId: thread.id,
            newThreadId,
            newName: synthesis.name,
            noteCount: clusterNoteIds.length,
          },
          'Created split thread'
        );
      }

      // Update original thread's note_count to reflect remaining notes
      const remainingCount = viableComponents[0].length;
      db.prepare(`UPDATE threads SET note_count = ?, updated_at = ? WHERE id = ?`).run(
        remainingCount,
        nowIso,
        thread.id
      );

      // Record split history on original thread
      db.prepare(
        `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
         VALUES (?, ?, ?, 'split', ?)`
      ).run(thread.id, thread.summary, thread.summary, nowIso);

      // Re-synthesize original thread with remaining notes
      const remainingNoteIds = viableComponents[0];
      const remainingPlaceholders = remainingNoteIds.map(() => '?').join(',');
      const remainingNotes = db
        .prepare(
          `SELECT id, title, content, created_at
           FROM raw_notes
           WHERE id IN (${remainingPlaceholders})
           ORDER BY created_at DESC`
        )
        .all(...remainingNoteIds) as NoteRecord[];

      const resynthPrompt = buildResynthesisPrompt(thread, remainingNotes);
      const resynthResponse = await generate(resynthPrompt);
      const resynth = parseSynthesis(resynthResponse);

      if (resynth) {
        db.prepare(
          `UPDATE threads SET summary = ?, why = ?, updated_at = ? WHERE id = ?`
        ).run(resynth.summary, resynth.why, nowIso, thread.id);

        log.info(
          { threadId: thread.id, name: thread.name },
          'Re-synthesized original thread after split'
        );
      }

      splits++;
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, threadId: thread.id, name: thread.name }, 'Error splitting thread');
      errors++;
    }
  }

  log.info({ splits, errors }, 'Split detection complete');
  return { splits, errors };
}

/**
 * Detect pairs of active threads with high semantic overlap
 * and merge them into a single thread.
 */
async function mergeConvergingThreads(): Promise<{ merges: number; errors: number }> {
  let merges = 0;
  let errors = 0;

  // Get all active threads
  const threads = db
    .prepare(
      `SELECT id, name, why, summary, status, note_count, last_activity_at
       FROM threads
       WHERE status = 'active'
       ORDER BY note_count DESC`
    )
    .all() as ThreadRecord[];

  if (threads.length < 2) {
    log.info({ count: threads.length }, 'Fewer than 2 active threads, skipping merge detection');
    return { merges, errors };
  }

  // Compute centroids for each thread
  const centroids = new Map<number, number[]>();
  for (const thread of threads) {
    const centroid = computeThreadCentroid(thread.id);
    if (centroid) {
      centroids.set(thread.id, centroid);
    } else {
      log.debug({ threadId: thread.id, name: thread.name }, 'No embeddings for thread, skipping');
    }
  }

  const threadIds = Array.from(centroids.keys());
  if (threadIds.length < 2) {
    log.info('Fewer than 2 threads with embeddings, skipping merge detection');
    return { merges, errors };
  }

  // Build a lookup for thread records
  const threadMap = new Map<number, ThreadRecord>();
  for (const thread of threads) {
    threadMap.set(thread.id, thread);
  }

  // Compare all pairs and find candidates below the distance threshold
  interface MergeCandidate {
    threadA: number;
    threadB: number;
    distance: number;
  }

  const candidates: MergeCandidate[] = [];
  for (let i = 0; i < threadIds.length; i++) {
    for (let j = i + 1; j < threadIds.length; j++) {
      const idA = threadIds[i];
      const idB = threadIds[j];
      const dist = l2Distance(centroids.get(idA)!, centroids.get(idB)!);
      if (dist < MERGE_DISTANCE_THRESHOLD) {
        candidates.push({ threadA: idA, threadB: idB, distance: dist });
      }
    }
  }

  if (candidates.length === 0) {
    log.info({ threadsChecked: threadIds.length }, 'No merge candidates found');
    return { merges, errors };
  }

  // Sort by distance ASC (closest first)
  candidates.sort((a, b) => a.distance - b.distance);

  log.info({ candidates: candidates.length }, 'Found merge candidates');

  const mergedThisRun = new Set<number>();

  for (const candidate of candidates) {
    // Skip if either thread already merged this cycle
    if (mergedThisRun.has(candidate.threadA) || mergedThisRun.has(candidate.threadB)) {
      continue;
    }

    const threadA = threadMap.get(candidate.threadA)!;
    const threadB = threadMap.get(candidate.threadB)!;

    try {
      // Ask LLM to confirm the merge
      const mergePrompt = `Thread A: "${threadA.name}" — ${threadA.summary || '(no summary)'}
Thread B: "${threadB.name}" — ${threadB.summary || '(no summary)'}

Are these fundamentally about the same line of thinking? Would combining them make sense, or are they distinct topics that happen to be related?

Respond ONLY with valid JSON:
{ "should_merge": true or false, "reason": "Brief explanation" }`;

      const response = await generate(mergePrompt);

      // Parse LLM response
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        log.warn(
          { threadA: threadA.id, threadB: threadB.id },
          'Failed to parse merge LLM response'
        );
        errors++;
        continue;
      }

      let mergeDecision: { should_merge: boolean; reason: string };
      try {
        mergeDecision = JSON.parse(jsonMatch[0]);
      } catch {
        log.warn(
          { threadA: threadA.id, threadB: threadB.id, response },
          'Invalid JSON in merge LLM response'
        );
        errors++;
        continue;
      }

      if (!mergeDecision.should_merge) {
        log.info(
          {
            threadA: threadA.id,
            threadB: threadB.id,
            nameA: threadA.name,
            nameB: threadB.name,
            reason: mergeDecision.reason,
          },
          'LLM rejected merge'
        );
        continue;
      }

      // Determine keeper (larger by note_count) and absorbed
      const keeper = threadA.note_count >= threadB.note_count ? threadA : threadB;
      const absorbed = keeper.id === threadA.id ? threadB : threadA;

      const nowIso = new Date().toISOString();

      // Move notes from absorbed thread to keeper
      db.prepare(
        `UPDATE thread_notes SET thread_id = ? WHERE thread_id = ?`
      ).run(keeper.id, absorbed.id);

      // Update keeper's note_count
      const countRow = db
        .prepare(`SELECT COUNT(*) as cnt FROM thread_notes WHERE thread_id = ?`)
        .get(keeper.id) as { cnt: number };

      db.prepare(
        `UPDATE threads SET note_count = ?, updated_at = ? WHERE id = ?`
      ).run(countRow.cnt, nowIso, keeper.id);

      // Set absorbed thread status to 'merged'
      db.prepare(
        `UPDATE threads SET status = 'merged', updated_at = ? WHERE id = ?`
      ).run(nowIso, absorbed.id);

      // Record history on both threads
      db.prepare(
        `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
         VALUES (?, ?, ?, 'merged', ?)`
      ).run(keeper.id, keeper.summary, keeper.summary, nowIso);

      db.prepare(
        `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
         VALUES (?, ?, ?, 'merged', ?)`
      ).run(absorbed.id, absorbed.summary, absorbed.summary, nowIso);

      // Re-synthesize keeper with combined notes
      const keeperNotes = db
        .prepare(
          `SELECT id, title, content, created_at
           FROM raw_notes
           WHERE id IN (SELECT raw_note_id FROM thread_notes WHERE thread_id = ?)
           ORDER BY created_at DESC`
        )
        .all(keeper.id) as NoteRecord[];

      const resynthPrompt = buildResynthesisPrompt(keeper, keeperNotes);
      const resynthResponse = await generate(resynthPrompt);
      const resynth = parseSynthesis(resynthResponse);

      if (resynth) {
        db.prepare(
          `UPDATE threads SET name = ?, summary = ?, why = ?, updated_at = ? WHERE id = ?`
        ).run(resynth.name, resynth.summary, resynth.why, nowIso, keeper.id);
      }

      // Mark both as merged this run
      mergedThisRun.add(keeper.id);
      mergedThisRun.add(absorbed.id);

      merges++;

      log.info(
        {
          keeperId: keeper.id,
          keeperName: keeper.name,
          absorbedId: absorbed.id,
          absorbedName: absorbed.name,
          distance: candidate.distance,
          reason: mergeDecision.reason,
          newNoteCount: countRow.cnt,
        },
        'Merged threads'
      );
    } catch (err) {
      const error = err as Error;
      log.error(
        { err: error, threadA: threadA.id, threadB: threadB.id },
        'Error merging threads'
      );
      errors++;
      mergedThisRun.add(candidate.threadA);
      mergedThisRun.add(candidate.threadB);
    }
  }

  log.info({ merges, errors }, 'Merge detection complete');
  return { merges, errors };
}

/**
 * Main workflow: thread lifecycle management
 *
 * Phase 1: Archive stale threads (inactive > 60 days)
 * Phase 2: Split divergent threads (notes drifted into distinct sub-clusters)
 * Phase 3: Merge convergent threads (semantically similar thread pairs)
 */
export async function threadLifecycle(): Promise<WorkflowResult> {
  log.info('Starting thread lifecycle');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  // Phase 1: Archive stale threads
  try {
    const archivedCount = archiveStaleThreads();
    result.processed += archivedCount;
    if (archivedCount > 0) {
      result.details.push({ id: 0, success: true, error: `Archived ${archivedCount} stale threads` });
    }
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Error in archive phase');
    result.errors++;
    result.details.push({ id: 0, success: false, error: error.message });
  }

  // Phase 2: Split divergent threads
  try {
    const splitResult = await splitDivergentThreads();
    result.processed += splitResult.splits;
    result.errors += splitResult.errors;
    result.details.push({ id: 0, success: true, error: `Split ${splitResult.splits} threads` });
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Error in split phase');
    result.errors++;
    result.details.push({ id: 0, success: false, error: error.message });
  }

  // Phase 3: Merge converging threads
  try {
    const mergeResult = await mergeConvergingThreads();
    result.processed += mergeResult.merges;
    result.errors += mergeResult.errors;
    result.details.push({ id: 0, success: true, error: `Merged ${mergeResult.merges} thread pairs` });
  } catch (err) {
    const error = err as Error;
    log.error({ err: error }, 'Error in merge phase');
    result.errors++;
    result.details.push({ id: 0, success: false, error: error.message });
  }

  log.info(
    { processed: result.processed, errors: result.errors },
    'Thread lifecycle complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  threadLifecycle()
    .then((result) => {
      log.info({ result }, 'Thread lifecycle finished');
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      log.error({ err }, 'Thread lifecycle failed');
      process.exit(1);
    });
}
