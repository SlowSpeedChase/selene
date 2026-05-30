/**
 * PKM Browse — LAN web dashboard routes (Track 2), mounted under /pkm/* on the main server.
 *
 * Read-only HTML pages (no client JS). No bearer auth (reduce friction — LAN only), but a
 * preHandler restricts to private/loopback IPs so it can't leak if the host is ever exposed.
 * pkmRoutes(db) is a factory so tests can inject an in-memory database.
 */
import type { FastifyInstance, FastifyPluginAsync, FastifyReply } from 'fastify';
import type { Database as DatabaseType } from 'better-sqlite3';
import * as Q from '../lib/pkm-queries';
import * as R from '../lib/pkm-render';
import { initPkmSchema, markSurfaced, getDueForReview } from '../lib/pkm-db';

const PAGE_SIZE = 50;

/** Private/loopback ranges (IPv4 + IPv6 loopback + IPv4-mapped). */
export function isLanIp(ip: string): boolean {
  const v4 = ip.replace(/^::ffff:/, '');
  if (v4 === '::1' || v4 === '127.0.0.1') return true;
  if (/^127\./.test(v4)) return true;
  if (/^10\./.test(v4)) return true;
  if (/^192\.168\./.test(v4)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(v4)) return true;
  // Tailscale tailnet (CGNAT 100.64.0.0/10) — second octet 64–127. This is the
  // trusted, encrypted way the iPad reaches the Mac remotely.
  if (/^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(v4)) return true;
  return false;
}

function html(reply: FastifyReply, body: string): void {
  reply.header('content-type', 'text/html; charset=utf-8').send(body);
}

function parseConcepts(json: string | null): string[] {
  if (!json) return [];
  try {
    const parsed: unknown = JSON.parse(json);
    return Array.isArray(parsed) ? parsed.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
}

export function pkmRoutes(db: DatabaseType): FastifyPluginAsync {
  initPkmSchema(db);

  return async (fastify: FastifyInstance): Promise<void> => {
    // LAN-only guard.
    fastify.addHook('preHandler', async (request, reply) => {
      if (!isLanIp(request.ip)) {
        reply.code(403).header('content-type', 'text/plain').send('PKM browse is LAN-only.');
      }
    });

    fastify.get('/', async (_request, reply) => {
      html(reply, R.renderHome({
        essences: Q.getEssences(db, 10, 0),
        topConcepts: Q.getTopConcepts(db, 20),
        categoryCounts: Q.getCategoryCounts(db),
        onThisDay: Q.getOnThisDay(db),
        randomEssence: Q.getRandomEssence(db),
        dueCount: getDueForReview(db, 10000).length,
      }));
    });

    fastify.get('/categories', async (_request, reply) => {
      html(reply, R.renderCategories(Q.getCategoryCounts(db)));
    });

    fastify.get<{ Params: { name: string } }>('/categories/:name', async (request, reply) => {
      const name = decodeURIComponent(request.params.name);
      html(reply, R.renderCategory(name, Q.getNotesForCategory(db, name, 200)));
    });

    fastify.get('/concepts', async (_request, reply) => {
      html(reply, R.renderConcepts(Q.getTopConcepts(db, 200)));
    });

    fastify.get<{ Params: { name: string } }>('/concepts/:name', async (request, reply) => {
      const name = decodeURIComponent(request.params.name);
      html(reply, R.renderConcept(
        name,
        Q.getNotesForConcept(db, name, 200),
        Q.getCooccurringConcepts(db, name, 15)
      ));
    });

    fastify.get<{ Params: { id: string } }>('/notes/:id', async (request, reply) => {
      const id = parseInt(request.params.id, 10);
      const note = Number.isNaN(id) ? undefined : Q.getNoteDetail(db, id);
      if (!note) {
        reply.code(404);
        html(reply, R.renderError('Note not found'));
        return;
      }
      markSurfaced(db, 'note', String(id)); // resurfacing signal
      html(reply, R.renderNote({ ...note, concepts: parseConcepts(note.concepts) }));
    });

    fastify.get<{ Querystring: { page?: string } }>('/essences', async (request, reply) => {
      const page = Math.max(0, parseInt(request.query.page ?? '0', 10) || 0);
      html(reply, R.renderEssences(Q.getEssences(db, PAGE_SIZE, page * PAGE_SIZE), page));
    });

    fastify.get('/random', async (_request, reply) => {
      const id = Q.getRandomNoteId(db);
      if (id === undefined) {
        reply.code(404);
        html(reply, R.renderError('No notes yet'));
        return;
      }
      reply.redirect(`/pkm/notes/${id}`);
    });

    fastify.get('/review/today', async (_request, reply) => {
      const dueIds = getDueForReview(db, 25).map((d) => parseInt(d.entityId, 10));
      html(reply, R.renderReview(Q.getNoteSummariesByIds(db, dueIds), Q.getRandomEssence(db)));
    });

    fastify.get('/on-this-day', async (_request, reply) => {
      html(reply, R.renderOnThisDay(Q.getOnThisDay(db)));
    });
  };
}
