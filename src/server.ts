import Fastify from 'fastify';
import { config, db, logger } from './lib';
import { requireAuth } from './lib/auth';
import { ingest } from './workflows/ingest';
import { exportObsidian } from './workflows/export-obsidian';
import { getRelatedNotes, searchNotes } from './queries/related-notes';
import { notesRoutes } from './routes/notes';
import { threadsRoutes } from './routes/threads';
import { sessionsRoutes } from './routes/sessions';
import { memoriesRoutes } from './routes/memories';
import { llmRoutes } from './routes/llm';
import { briefingRoutes } from './routes/briefing';
import { devicesRoutes } from './routes/devices';
import type { IngestInput, WebhookResponse } from './types';

const server = Fastify({
  logger: false, // We use our own logger
});

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

server.get('/health', async () => {
  return {
    status: 'ok',
    env: config.env,
    port: config.port,
    timestamp: new Date().toISOString(),
  };
});

// ---------------------------------------------------------------------------
// Compression stats (tiered context)
// ---------------------------------------------------------------------------

server.get('/health/compression', async () => {
  const tierDistribution = db
    .prepare(
      `SELECT COALESCE(fidelity_tier, 'full') as tier, COUNT(*) as count
       FROM processed_notes
       WHERE raw_note_id IN (SELECT id FROM raw_notes WHERE test_run IS NULL)
       GROUP BY fidelity_tier`
    )
    .all() as Array<{ tier: string; count: number }>;

  const essenceProgress = db
    .prepare(
      `SELECT
         COUNT(*) as total,
         SUM(CASE WHEN essence IS NOT NULL THEN 1 ELSE 0 END) as with_essence
       FROM processed_notes
       WHERE raw_note_id IN (SELECT id FROM raw_notes WHERE test_run IS NULL)`
    )
    .get() as { total: number; with_essence: number };

  const threadDigests = db
    .prepare(
      `SELECT
         COUNT(*) as total_active,
         SUM(CASE WHEN thread_digest IS NOT NULL THEN 1 ELSE 0 END) as with_digest
       FROM threads
       WHERE status = 'active'`
    )
    .get() as { total_active: number; with_digest: number };

  return {
    status: 'ok',
    timestamp: new Date().toISOString(),
    tiers: Object.fromEntries(tierDistribution.map((r) => [r.tier, r.count])),
    essences: {
      total: essenceProgress.total,
      computed: essenceProgress.with_essence,
      remaining: essenceProgress.total - essenceProgress.with_essence,
      percent: essenceProgress.total > 0
        ? Math.round((essenceProgress.with_essence / essenceProgress.total) * 100)
        : 0,
    },
    threadDigests: {
      activeThreads: threadDigests.total_active,
      withDigest: threadDigests.with_digest,
    },
  };
});

// ---------------------------------------------------------------------------
// Auth hook - protects all /api/* routes
// ---------------------------------------------------------------------------

server.addHook('onRequest', async (request, reply) => {
  if (request.url.startsWith('/api/')) {
    await requireAuth(request, reply);
  }
});

// ---------------------------------------------------------------------------
// Webhook handlers (no auth required)
// ---------------------------------------------------------------------------

// POST /webhook/api/drafts - Note ingestion (called by Drafts app)
server.post<{ Body: IngestInput }>('/webhook/api/drafts', async (request, reply) => {
  const { title, content, created_at, test_run, capture_type } = request.body;

  logger.info({ title, test_run, capture_type }, 'Webhook received');

  // Validate required fields
  if (!title || !content) {
    logger.warn({ title: !!title, content: !!content }, 'Missing required fields');
    reply.status(400);
    return { status: 'error', message: 'Title and content are required' } as WebhookResponse;
  }

  try {
    const result = await ingest({ title, content, created_at, test_run, capture_type });

    if (result.duplicate) {
      logger.info({ title, existingId: result.existingId }, 'Duplicate skipped');
      return { status: 'duplicate', id: result.existingId } as WebhookResponse;
    }

    logger.info({ id: result.id, title }, 'Note created');
    return { status: 'created', id: result.id } as WebhookResponse;
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error, title }, 'Ingestion failed');
    reply.status(500);
    return { status: 'error', message: error.message } as WebhookResponse;
  }
});

// POST /webhook/api/export-obsidian - Manual Obsidian export trigger
server.post<{ Body: { noteId?: number } }>('/webhook/api/export-obsidian', async (request, reply) => {
  const { noteId } = request.body || {};

  logger.info({ noteId }, 'Export-obsidian webhook received');

  try {
    const result = await exportObsidian(noteId);
    return result;
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error }, 'Export-obsidian failed');
    reply.status(500);
    return { success: false, exported_count: 0, errors: 1, message: error.message };
  }
});

// ---------------------------------------------------------------------------
// Original API endpoints (backward compat for SeleneChat macOS app)
// These are inline handlers that pre-date the route module pattern.
// ---------------------------------------------------------------------------

// POST /api/search - Semantic search via LanceDB vectors
server.post<{
  Body: {
    query: string;
    limit?: number;
    noteType?: string;
    actionability?: string;
  };
}>('/api/search', async (request, reply) => {
  const { query, limit = 10, noteType, actionability } = request.body || {};

  if (!query || typeof query !== 'string') {
    reply.status(400);
    return { error: 'query is required and must be a string' };
  }

  try {
    const results = await searchNotes(query, { limit, noteType, actionability });
    return { query, count: results.length, results };
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error, query }, 'Semantic search failed');
    reply.status(500);
    return { error: error.message };
  }
});

// POST /api/related-notes - Vector similarity for a given note
server.post<{
  Body: { noteId: number; limit?: number; includeLive?: boolean };
}>('/api/related-notes', async (request, reply) => {
  const { noteId, limit = 10, includeLive = true } = request.body || {};

  if (!noteId || typeof noteId !== 'number') {
    reply.status(400);
    return { error: 'noteId is required and must be a number' };
  }

  try {
    const results = await getRelatedNotes(noteId, { limit, includeLive });
    return { noteId, count: results.length, results };
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error, noteId }, 'Related notes query failed');
    reply.status(500);
    return { error: error.message };
  }
});

// ---------------------------------------------------------------------------
// Route modules (new modular API - Phase 1: Mobile API)
// Each module registers its own routes under /api/*.
// ---------------------------------------------------------------------------

notesRoutes(server);       // /api/notes, /api/notes/:id
threadsRoutes(server);     // /api/threads, /api/threads/:id, /api/threads/:id/notes
sessionsRoutes(server);    // /api/sessions, /api/sessions/:id, /api/sessions/:id/messages
memoriesRoutes(server);    // /api/memories, /api/memories/:id
llmRoutes(server);         // /api/llm/health, /api/llm/chat, /api/llm/context
briefingRoutes(server);    // /api/briefing
devicesRoutes(server);     // /api/devices, /api/devices/:id

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------

async function start() {
  try {
    await server.listen({ port: config.port, host: config.host });
    logger.info({ port: config.port, host: config.host }, 'Selene webhook server started');
  } catch (err) {
    logger.error({ err }, 'Server failed to start');
    process.exit(1);
  }
}

start();
