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
import type { WorksheetSubmission, ReviewNote, RelatedNote, GiftItem, GiftSlotRole, GiftReaction } from '../types/worksheets';

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

function fetchGiftItems(): GiftItem[] {
  const items: GiftItem[] = [];

  // Slot 1: buried_treasure — random old note with no prior reactions
  let buried: { id: number; title: string; content: string; created_at: string } | undefined;
  try {
    buried = db.prepare(`
      SELECT rn.id, rn.title, rn.content, rn.created_at
      FROM raw_notes rn
      LEFT JOIN facts.attention_log al ON rn.id = al.note_id
      WHERE al.id IS NULL
        AND rn.created_at < datetime('now', '-14 days')
        AND rn.test_run IS NULL
      ORDER BY RANDOM()
      LIMIT 1
    `).get() as { id: number; title: string; content: string; created_at: string } | undefined;

    if (buried) {
      items.push({
        noteId: buried.id,
        title: buried.title,
        snippet: buried.content.slice(0, 160).trimEnd(),
        date: buried.created_at.slice(0, 10),
        slotRole: 'buried_treasure',
      });
    }
  } catch (err) {
    log.warn({ err }, 'fetchGiftItems slot 1 (buried_treasure) failed — skipping');
  }

  // Slot 2: connection — highest-similarity pair (recent source, old target).
  // note_connections is created by the synthesize-topics workflow and may not exist on a
  // cold/fresh DB; failure here is benign and drops only this slot.
  let conn: { sourceId: number; sourceTitle: string; sourceContent: string; sourceDate: string; targetId: number; targetTitle: string } | undefined;
  try {
    conn = db.prepare(`
      SELECT
        rn1.id AS sourceId, rn1.title AS sourceTitle, rn1.content AS sourceContent, rn1.created_at AS sourceDate,
        rn2.id AS targetId, rn2.title AS targetTitle
      FROM note_connections nc
      JOIN raw_notes rn1 ON nc.source_note_id = rn1.id
      JOIN raw_notes rn2 ON nc.target_note_id = rn2.id
      WHERE rn1.created_at >= datetime('now', '-7 days')
        AND rn2.created_at < datetime('now', '-14 days')
        AND rn1.test_run IS NULL
        AND rn2.test_run IS NULL
      ORDER BY nc.similarity_score DESC
      LIMIT 1
    `).get() as typeof conn;

    if (conn) {
      items.push({
        noteId: conn.sourceId,
        title: conn.sourceTitle,
        snippet: conn.sourceContent.slice(0, 160).trimEnd(),
        date: conn.sourceDate.slice(0, 10),
        slotRole: 'connection',
        connectionNote: { noteId: conn.targetId, title: conn.targetTitle },
      });
    }
  } catch (err) {
    log.warn({ err }, 'fetchGiftItems slot 2 (connection) failed — skipping (note_connections may not exist yet)');
  }

  // Slot 3: heating_up — most recent unreacted note (deduplicated against slot 1)
  try {
    const heating = db.prepare(`
      SELECT rn.id, rn.title, rn.content, rn.created_at
      FROM raw_notes rn
      LEFT JOIN facts.attention_log al ON rn.id = al.note_id
      WHERE al.id IS NULL
        AND rn.test_run IS NULL
      ORDER BY rn.created_at DESC
      LIMIT 1
    `).get() as { id: number; title: string; content: string; created_at: string } | undefined;

    if (heating && heating.id !== buried?.id && heating.id !== conn?.sourceId) {
      items.push({
        noteId: heating.id,
        title: heating.title,
        snippet: heating.content.slice(0, 160).trimEnd(),
        date: heating.created_at.slice(0, 10),
        slotRole: 'heating_up',
      });
    }
  } catch (err) {
    log.warn({ err }, 'fetchGiftItems slot 3 (heating_up) failed — skipping');
  }

  return items;
}

function logReaction(args: {
  worksheetId: string;
  noteId: number;
  slotRole: GiftSlotRole;
  reaction: GiftReaction;
  reactedAt: string;
}): void {
  db.prepare(`
    INSERT INTO facts.attention_log (worksheet_id, note_id, slot_role, reaction, reacted_at)
    VALUES (?, ?, ?, ?, ?)
  `).run(args.worksheetId, args.noteId, args.slotRole, args.reaction, args.reactedAt);
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
    return buildTodayWorksheet(new Date(), {
      fetchReviewNotes,
      fetchGiftItems: async () => fetchGiftItems(),
    });
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
          logReaction: body.test_run
            ? undefined
            : async (args) => logReaction(args),
        },
      );
    },
  );
}
