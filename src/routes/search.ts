import type { FastifyInstance } from 'fastify';
import type { Database as DatabaseType } from 'better-sqlite3';
import { db as prodDb } from '../lib/db';
import { requireAuth } from '../lib/auth';
import { embed } from '../lib/ollama';
import { searchSimilarNotes } from '../lib/lancedb';
import { similarityFromCosineDistance } from '../lib/vector-similarity';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'search-route' });

const SNIPPET_LEN = 160;
const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 50;

/**
 * A single search result. `similarity` is the cosine similarity [0,1] for semantic hits, or
 * `null` for keyword-only hits (no vector match). `sourceUuid` / `essence` may be null on older
 * or not-yet-processed notes; callers (e.g. the SeleneApp "Ask Selene" tools) use `sourceUuid`
 * for deep links and `essence` for citation snippets, falling back to `snippet` when absent.
 */
export interface SearchHit {
  id: number;
  sourceUuid: string | null;
  title: string;
  essence: string | null;
  snippet: string;
  date: string;
  similarity: number | null;
}

type HitCore = Omit<SearchHit, 'similarity'>;

/** Clamp a raw `limit` query param to [1, MAX_LIMIT], defaulting when absent/invalid. */
export function clampLimit(raw: string | undefined): number {
  const n = parseInt(raw ?? '', 10);
  if (isNaN(n) || n < 1) return DEFAULT_LIMIT;
  return Math.min(n, MAX_LIMIT);
}

/**
 * Merge ranked semantic hits (with similarity) with keyword hits, semantic first, de-duplicated
 * by note id, capped at `limit`. Keyword hits become `similarity: null`.
 */
export function mergeHits(semantic: SearchHit[], keyword: HitCore[], limit: number): SearchHit[] {
  const seen = new Set<number>(semantic.map(h => h.id));
  const out: SearchHit[] = [...semantic];
  for (const k of keyword) {
    if (out.length >= limit) break;
    if (seen.has(k.id)) continue;
    seen.add(k.id);
    out.push({ ...k, similarity: null });
  }
  return out.slice(0, limit);
}

// ---------------------------------------------------------------------------
// DB helpers — extracted so tests can inject an in-memory database
// ---------------------------------------------------------------------------

export function buildSearchDb(db: DatabaseType) {
  function rowToCore(r: {
    id: number;
    source_uuid: string | null;
    title: string;
    content: string;
    created_at: string;
    essence: string | null;
  }): HitCore {
    return {
      id: r.id,
      sourceUuid: r.source_uuid,
      title: r.title,
      essence: r.essence,
      snippet: r.content.slice(0, SNIPPET_LEN).trimEnd(),
      date: r.created_at.slice(0, 10),
    };
  }

  /** Enrich a set of note ids (e.g. from semantic search) with title/essence/snippet/source_uuid. */
  function hitsByIds(ids: number[]): Map<number, HitCore> {
    const map = new Map<number, HitCore>();
    if (ids.length === 0) return map;
    const placeholders = ids.map(() => '?').join(',');
    const rows = db
      .prepare(
        `SELECT r.id, r.source_uuid, r.title, r.content, r.created_at, p.essence
         FROM raw_notes r
         LEFT JOIN processed_notes p ON p.raw_note_id = r.id
         WHERE r.id IN (${placeholders})
           AND r.test_run IS NULL`
      )
      .all(...ids) as Array<Parameters<typeof rowToCore>[0]>;
    for (const r of rows) map.set(r.id, rowToCore(r));
    return map;
  }

  /** Keyword complement: LIKE over title + content, newest first. */
  function keywordHits(query: string, limit: number): HitCore[] {
    const pattern = '%' + query + '%';
    const rows = db
      .prepare(
        `SELECT r.id, r.source_uuid, r.title, r.content, r.created_at, p.essence
         FROM raw_notes r
         LEFT JOIN processed_notes p ON p.raw_note_id = r.id
         WHERE r.test_run IS NULL
           AND (r.content LIKE ? OR r.title LIKE ?)
         ORDER BY r.created_at DESC
         LIMIT ?`
      )
      .all(pattern, pattern, limit) as Array<Parameters<typeof rowToCore>[0]>;
    return rows.map(rowToCore);
  }

  return { hitsByIds, keywordHits };
}

// ---------------------------------------------------------------------------
// Fastify plugin
// ---------------------------------------------------------------------------

export async function searchRoutes(fastify: FastifyInstance): Promise<void> {
  const q = buildSearchDb(prodDb);

  // Every route in this (encapsulated) plugin requires auth — apply once via a plugin hook.
  fastify.addHook('preHandler', requireAuth);

  // GET /api/search?q=<text>&limit=<n>
  // Hybrid retrieval seam for SeleneApp's "Ask Selene" conversational tools (and any client):
  // semantic (Ollama embeddings + LanceDB cosine) first, keyword (SQLite LIKE) as complement /
  // fallback. See docs/plans/2026-06-17-siri-conversational-ai-design.md.
  fastify.get<{ Querystring: { q?: string; limit?: string } }>(
    '/api/search',
    async (request, reply) => {
      const text = (request.query.q ?? '').trim();
      if (!text) {
        reply.status(400);
        return { error: 'q is required' };
      }
      const limit = clampLimit(request.query.limit);

      // Semantic search is best-effort: it needs Ollama (embeddings) + LanceDB and must never
      // take down the endpoint — fall back to keyword-only on failure (mirrors worksheets route).
      let semantic: SearchHit[] = [];
      try {
        const vector = await embed(text);
        const similar = await searchSimilarNotes(vector, { limit, maxDistance: 1.0 });
        const meta = q.hitsByIds(similar.map(s => s.id));
        semantic = similar
          .map((s): SearchHit | null => {
            const core = meta.get(s.id);
            if (!core) return null; // vector index can outlive a deleted/test note
            return { ...core, similarity: Math.max(0, similarityFromCosineDistance(s.distance)) };
          })
          .filter((h): h is SearchHit => h !== null);
      } catch (err) {
        log.warn({ err }, 'semantic search failed — falling back to keyword-only');
      }

      const keyword = q.keywordHits(text, limit);
      return { query: text, hits: mergeHits(semantic, keyword, limit) };
    }
  );
}
