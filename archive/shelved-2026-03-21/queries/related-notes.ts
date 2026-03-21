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
