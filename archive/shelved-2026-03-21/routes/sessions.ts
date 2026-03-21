import { FastifyInstance } from 'fastify';
import {
  listSessions,
  getSessionById,
  upsertSession,
  deleteSession,
  updateSessionPin,
  getSessionMessages,
  saveConversationMessage,
} from '../lib/db';
import { logger } from '../lib';

// Request body type for PUT /api/sessions/:id
interface UpsertSessionBody {
  title: string;
  created_at: string;
  updated_at: string;
  message_count: number;
  is_pinned: number;
  compression_state: string;
  compressed_at: string | null;
  full_messages_json: string | null;
  summary_text: string | null;
}

// Request body type for PATCH /api/sessions/:id/pin
interface PinSessionBody {
  isPinned: boolean;
}

// Request body type for POST /api/sessions/:id/messages
interface SaveMessageBody {
  role: 'user' | 'assistant';
  content: string;
}

export async function sessionsRoutes(server: FastifyInstance) {
  // GET /api/sessions — List all sessions ordered by updated_at desc
  server.get('/api/sessions', async () => {
    const sessions = listSessions();
    return { count: sessions.length, sessions };
  });

  // PUT /api/sessions/:id — Save/update a session (upsert)
  server.put<{ Params: { id: string }; Body: UpsertSessionBody }>(
    '/api/sessions/:id',
    async (request, reply) => {
      const { id } = request.params;
      const body = request.body;

      if (!id || !body) {
        reply.status(400);
        return { error: 'Session ID and body are required' };
      }

      if (!body.title || !body.created_at || !body.updated_at) {
        reply.status(400);
        return { error: 'title, created_at, and updated_at are required' };
      }

      try {
        upsertSession({
          id,
          title: body.title,
          created_at: body.created_at,
          updated_at: body.updated_at,
          message_count: body.message_count ?? 0,
          is_pinned: body.is_pinned ?? 0,
          compression_state: body.compression_state ?? 'full',
          compressed_at: body.compressed_at ?? null,
          full_messages_json: body.full_messages_json ?? null,
          summary_text: body.summary_text ?? null,
        });

        const session = getSessionById(id);
        return session;
      } catch (err) {
        const error = err as Error;
        logger.error({ err: error, sessionId: id }, 'Failed to upsert session');
        reply.status(500);
        return { error: error.message };
      }
    }
  );

  // DELETE /api/sessions/:id — Delete a session and its conversation messages
  server.delete<{ Params: { id: string } }>(
    '/api/sessions/:id',
    async (request, reply) => {
      const { id } = request.params;

      try {
        const deleted = deleteSession(id);
        if (!deleted) {
          reply.status(404);
          return { error: 'Session not found' };
        }
        return { status: 'deleted', id };
      } catch (err) {
        const error = err as Error;
        logger.error({ err: error, sessionId: id }, 'Failed to delete session');
        reply.status(500);
        return { error: error.message };
      }
    }
  );

  // PATCH /api/sessions/:id/pin — Toggle pin state
  server.patch<{ Params: { id: string }; Body: PinSessionBody }>(
    '/api/sessions/:id/pin',
    async (request, reply) => {
      const { id } = request.params;
      const { isPinned } = request.body || {};

      if (typeof isPinned !== 'boolean') {
        reply.status(400);
        return { error: 'isPinned (boolean) is required' };
      }

      try {
        const updated = updateSessionPin(id, isPinned);
        if (!updated) {
          reply.status(404);
          return { error: 'Session not found' };
        }

        const session = getSessionById(id);
        return session;
      } catch (err) {
        const error = err as Error;
        logger.error({ err: error, sessionId: id }, 'Failed to update pin state');
        reply.status(500);
        return { error: error.message };
      }
    }
  );

  // GET /api/sessions/:id/messages — Get conversation messages for a session
  server.get<{ Params: { id: string }; Querystring: { limit?: number } }>(
    '/api/sessions/:id/messages',
    async (request, reply) => {
      const { id } = request.params;
      const { limit = 100 } = request.query;

      // Verify session exists
      const session = getSessionById(id);
      if (!session) {
        reply.status(404);
        return { error: 'Session not found' };
      }

      const messages = getSessionMessages(id, limit);
      return { sessionId: id, count: messages.length, messages };
    }
  );

  // POST /api/sessions/:id/messages — Save a conversation message
  server.post<{ Params: { id: string }; Body: SaveMessageBody }>(
    '/api/sessions/:id/messages',
    async (request, reply) => {
      const { id } = request.params;
      const { role, content } = request.body || {};

      if (!role || !content) {
        reply.status(400);
        return { error: 'role and content are required' };
      }

      if (role !== 'user' && role !== 'assistant') {
        reply.status(400);
        return { error: 'role must be "user" or "assistant"' };
      }

      // Verify session exists
      const session = getSessionById(id);
      if (!session) {
        reply.status(404);
        return { error: 'Session not found' };
      }

      try {
        const messageId = saveConversationMessage({
          session_id: id,
          role,
          content,
        });
        return { id: messageId, session_id: id, role, content };
      } catch (err) {
        const error = err as Error;
        logger.error({ err: error, sessionId: id }, 'Failed to save message');
        reply.status(500);
        return { error: error.message };
      }
    }
  );
}
