/**
 * Vector similarity helpers for note connection detection.
 *
 * Background: nomic-embed-text (via Ollama) returns UN-normalized vectors (norm ~20),
 * and LanceDB's default `_distance` is SQUARED L2. The original connection code used
 * `1 - distance^2 / 2`, an identity valid only for unit vectors AND un-squared L2 — so
 * it produced large negatives that never cleared the 0.75 threshold (zero connections,
 * ever). Cosine similarity is magnitude-invariant, so it is the correct, normalization-free
 * basis for "are these two notes about the same thing?".
 */

/**
 * Cosine similarity in [-1, 1] between two equal-length vectors.
 * Magnitude-invariant — only direction matters. Returns 0 if either vector has no
 * magnitude (no direction to compare).
 */
export function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

/**
 * Convert a LanceDB cosine-metric `_distance` (which is `1 - cos`, range [0, 2]) back
 * to cosine similarity (range [-1, 1]). Use with `searchSimilarNotes`, which queries
 * with the cosine distance type.
 */
export function similarityFromCosineDistance(distance: number): number {
  return 1 - distance;
}

export interface EmbeddedNote {
  id: number;
  vector: number[];
  createdAt: string;
}

export interface Connection {
  sourceId: number;
  targetId: number;
  similarity: number;
}

/**
 * All-pairs connections among embedded notes whose cosine similarity >= `threshold`.
 * Each undirected pair is emitted at most once, oriented newer -> older (source = the
 * later `createdAt`, target = the earlier) to match process-llm's "a new note connects
 * back to an older note" convention. Ties on `createdAt` orient by higher id as source.
 *
 * Used by the one-shot connection backfill to populate the graph over the existing corpus.
 */
export function computeConnections(notes: EmbeddedNote[], threshold: number): Connection[] {
  const connections: Connection[] = [];
  for (let i = 0; i < notes.length; i++) {
    for (let j = i + 1; j < notes.length; j++) {
      const a = notes[i];
      const b = notes[j];
      const similarity = cosineSimilarity(a.vector, b.vector);
      if (similarity < threshold) continue;

      // Orient newer (later createdAt) -> older.
      let newer = a;
      let older = b;
      if (a.createdAt < b.createdAt) {
        newer = b;
        older = a;
      } else if (a.createdAt === b.createdAt) {
        newer = a.id >= b.id ? a : b;
        older = a.id >= b.id ? b : a;
      }
      connections.push({ sourceId: newer.id, targetId: older.id, similarity });
    }
  }
  return connections;
}
