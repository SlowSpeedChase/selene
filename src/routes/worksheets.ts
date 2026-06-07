import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../lib/auth';
import {
  buildTodayWorksheet,
  applyWorksheetAnswers,
} from '../workflows/generate-worksheet';
import { ingest } from '../workflows/ingest';
import { embed } from '../lib/ollama';
import { searchSimilarNotes } from '../lib/lancedb';
import { similarityFromCosineDistance } from '../lib/vector-similarity';
import { db } from '../lib/db';
import { testRunFilter } from '../lib/test-run';
import { logger } from '../lib/logger';
import type { WorksheetSubmission, ReviewNote, RelatedNote } from '../types/worksheets';

const log = logger.child({ module: 'worksheets-route' });

function fetchReviewNotes(): Promise<ReviewNote[]> {
  const rows = db.prepare(`
    SELECT id, title, content, created_at
    FROM raw_notes
    WHERE inbox_status = 'pending'
      ${testRunFilter()}
      AND created_at < datetime('now', '-1 day')
    ORDER BY created_at ASC
    LIMIT 3
  `).all() as Array<{ id: number; title: string; content: string; created_at: string }>;

  return Promise.resolve(rows.map(r => ({
    id: r.id,
    title: r.title,
    snippet: r.content.slice(0, 120).trimEnd(),
    date: r.created_at.slice(0, 10),
  })));
}

async function findRelatedNotes(text: string, excludeId: number): Promise<RelatedNote[]> {
  const vector = await embed(text);
  const similar = await searchSimilarNotes(vector, {
    limit: 3,
    excludeIds: [excludeId],
    maxDistance: 1.0,
  });

  // `s.distance` is cosine distance (searchSimilarNotes uses the cosine metric); similarity = 1 - distance.
  return similar.map(s => {
    const row = db.prepare('SELECT content, created_at FROM raw_notes WHERE id = ?').get(s.id) as { content: string; created_at: string } | undefined;
    return {
      noteId: s.id,
      title: s.title,
      snippet: row?.content.slice(0, 120).trimEnd() ?? '',
      date: row?.created_at.slice(0, 10) ?? '',
      score: Math.max(0, similarityFromCosineDistance(s.distance)),
    };
  });
}

export async function worksheetRoutes(fastify: FastifyInstance): Promise<void> {
  // Every route in this (encapsulated) plugin requires auth — apply once via a plugin hook
  // instead of repeating `{ preHandler: requireAuth }` per route.
  fastify.addHook('preHandler', requireAuth);

  fastify.get('/api/worksheets/today', async () => {
    return buildTodayWorksheet(new Date(), { fetchReviewNotes });
  });

  fastify.post<{
    Params: { id: string };
    Body: WorksheetSubmission & { test_run?: string };
  }>(
    '/api/worksheets/:id/answers',
    async (request, reply) => {
      const body = request.body;
      if (!body || !Array.isArray(body.answers)) {
        reply.status(400);
        return { error: 'answers array required' };
      }

      const worksheetId = request.params.id;
      return applyWorksheetAnswers(
        { worksheetId, answers: body.answers },
        {
          createNote: async (text: string) => {
            const res = await ingest({
              title: `Worksheet capture: ${worksheetId}`,
              content: text,
              capture_type: 'worksheet',
              test_run: body.test_run,
            });
            return (res.id ?? res.existingId) as number;
          },
          findRelatedNotes: body.test_run
            ? undefined   // skip Ollama during test runs
            : async (text, excludeId) => {
                try {
                  return await findRelatedNotes(text, excludeId);
                } catch (err) {
                  log.warn({ err }, 'findRelatedNotes failed in route — returning empty');
                  return [];
                }
              },
        },
      );
    },
  );
}
