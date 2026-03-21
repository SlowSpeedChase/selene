import { FastifyInstance } from 'fastify';
import { getActiveThreads, getThreadById, searchThreadByName, getThreadNotes, getTasksForThread } from '../lib/db';

export async function threadsRoutes(server: FastifyInstance) {
  // GET /api/threads?limit=10
  server.get<{ Querystring: { limit?: number } }>('/api/threads', async (request) => {
    const { limit = 10 } = request.query;
    const threads = getActiveThreads(limit);
    return { count: threads.length, threads };
  });

  // GET /api/threads/:id (with notes included)
  server.get<{ Params: { id: string } }>('/api/threads/:id', async (request, reply) => {
    const id = parseInt(request.params.id, 10);
    if (isNaN(id)) {
      reply.status(400);
      return { error: 'Invalid thread ID' };
    }
    const thread = getThreadById(id);
    if (!thread) {
      reply.status(404);
      return { error: 'Thread not found' };
    }
    const notes = getThreadNotes(id);
    return { ...thread, notes };
  });

  // GET /api/threads/search/:name (fuzzy name search)
  server.get<{ Params: { name: string } }>('/api/threads/search/:name', async (request, reply) => {
    const thread = searchThreadByName(request.params.name);
    if (!thread) {
      reply.status(404);
      return { error: 'Thread not found' };
    }
    const notes = getThreadNotes(thread.id);
    return { ...thread, notes };
  });

  // GET /api/threads/:id/tasks
  server.get<{ Params: { id: string } }>('/api/threads/:id/tasks', async (request, reply) => {
    const id = parseInt(request.params.id, 10);
    if (isNaN(id)) {
      reply.status(400);
      return { error: 'Invalid thread ID' };
    }
    const tasks = getTasksForThread(id);
    return { threadId: id, count: tasks.length, tasks };
  });
}
