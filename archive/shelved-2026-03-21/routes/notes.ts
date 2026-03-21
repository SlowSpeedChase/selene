import { FastifyInstance } from 'fastify';
import { getAllNotes, getNoteById, searchNotesKeyword, getRecentNotes, getNotesSince, getThreadAssignmentsForNotes } from '../lib/db';
import { getRelatedNotes, searchNotes } from '../queries/related-notes';
import { logger } from '../lib';

export async function notesRoutes(server: FastifyInstance) {
  // GET /api/notes?limit=100
  server.get<{ Querystring: { limit?: number } }>('/api/notes', async (request) => {
    const { limit = 100 } = request.query;
    const notes = getAllNotes(limit);
    return { count: notes.length, notes };
  });

  // GET /api/notes/:id
  server.get<{ Params: { id: string } }>('/api/notes/:id', async (request, reply) => {
    const id = parseInt(request.params.id, 10);
    if (isNaN(id)) {
      reply.status(400);
      return { error: 'Invalid note ID' };
    }
    const note = getNoteById(id);
    if (!note) {
      reply.status(404);
      return { error: 'Note not found' };
    }
    return note;
  });

  // POST /api/notes/search (keyword search)
  server.post<{ Body: { query: string; limit?: number } }>('/api/notes/search', async (request, reply) => {
    const { query, limit = 50 } = request.body || {};
    if (!query) {
      reply.status(400);
      return { error: 'query is required' };
    }
    const notes = searchNotesKeyword(query, limit);
    return { query, count: notes.length, notes };
  });

  // GET /api/notes/recent?days=7&limit=10
  server.get<{ Querystring: { days?: number; limit?: number } }>('/api/notes/recent', async (request) => {
    const { days = 7, limit = 10 } = request.query;
    const notes = getRecentNotes(days, limit);
    return { days, count: notes.length, notes };
  });

  // GET /api/notes/since/:date?limit=20
  server.get<{ Params: { date: string }; Querystring: { limit?: number } }>('/api/notes/since/:date', async (request) => {
    const { date } = request.params;
    const { limit = 20 } = request.query;
    const notes = getNotesSince(date, limit);
    return { since: date, count: notes.length, notes };
  });

  // GET /api/notes/:id/related?limit=10
  server.get<{ Params: { id: string }; Querystring: { limit?: number } }>('/api/notes/:id/related', async (request, reply) => {
    const id = parseInt(request.params.id, 10);
    if (isNaN(id)) {
      reply.status(400);
      return { error: 'Invalid note ID' };
    }
    try {
      const results = await getRelatedNotes(id, { limit: request.query.limit || 10 });
      return { noteId: id, count: results.length, results };
    } catch (err) {
      const error = err as Error;
      logger.error({ err: error, noteId: id }, 'Related notes query failed');
      reply.status(500);
      return { error: error.message };
    }
  });

  // POST /api/notes/thread-assignments
  server.post<{ Body: { noteIds: number[] } }>('/api/notes/thread-assignments', async (request, reply) => {
    const { noteIds } = request.body || {};
    if (!noteIds || !Array.isArray(noteIds)) {
      reply.status(400);
      return { error: 'noteIds array is required' };
    }
    const assignments = getThreadAssignmentsForNotes(noteIds);
    return { count: assignments.length, assignments };
  });

  // POST /api/notes/retrieve (hybrid: semantic + keyword fallback)
  server.post<{ Body: { query: string; limit?: number; noteType?: string; actionability?: string } }>('/api/notes/retrieve', async (request, reply) => {
    const { query, limit = 10, noteType, actionability } = request.body || {};
    if (!query) {
      reply.status(400);
      return { error: 'query is required' };
    }
    try {
      const results = await searchNotes(query, { limit, noteType, actionability });
      return { query, count: results.length, results };
    } catch (err) {
      // Fallback to keyword search
      const notes = searchNotesKeyword(query, limit);
      return { query, count: notes.length, results: notes, source: 'keyword_fallback' };
    }
  });
}
