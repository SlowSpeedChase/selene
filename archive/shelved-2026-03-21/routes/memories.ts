import { FastifyInstance } from 'fastify';
import {
  listMemories,
  getMemoryById,
  createMemory,
  updateMemory,
  deleteMemory,
  touchMemories,
} from '../lib/db';
import type { MemoryType } from '../lib/db';
import { logger } from '../lib';

const VALID_MEMORY_TYPES: MemoryType[] = ['preference', 'fact', 'pattern', 'context'];

// Request body type for POST /api/memories
interface CreateMemoryBody {
  content: string;
  type: MemoryType;
  confidence?: number;
  sourceSessionId?: string | null;
  embedding?: string | null;
}

// Request body type for PUT /api/memories/:id
interface UpdateMemoryBody {
  content?: string;
  confidence?: number;
  embedding?: string | null;
}

// Request body type for POST /api/memories/touch
interface TouchMemoriesBody {
  ids: number[];
}

export async function memoriesRoutes(server: FastifyInstance) {
  // GET /api/memories?limit=50 — List all memories ordered by confidence desc, last_accessed desc
  server.get<{ Querystring: { limit?: number } }>('/api/memories', async (request) => {
    const { limit = 50 } = request.query;
    const memories = listMemories(limit);
    return { count: memories.length, memories };
  });

  // POST /api/memories — Create a memory
  server.post<{ Body: CreateMemoryBody }>('/api/memories', async (request, reply) => {
    const { content, type, confidence, sourceSessionId, embedding } = request.body || {};

    if (!content) {
      reply.status(400);
      return { error: 'content is required' };
    }

    if (!type || !VALID_MEMORY_TYPES.includes(type)) {
      reply.status(400);
      return { error: `type must be one of: ${VALID_MEMORY_TYPES.join(', ')}` };
    }

    try {
      const id = createMemory({
        content,
        memory_type: type,
        confidence,
        source_session_id: sourceSessionId,
        embedding,
      });

      const memory = getMemoryById(id);
      reply.status(201);
      return memory;
    } catch (err) {
      const error = err as Error;
      logger.error({ err: error }, 'Failed to create memory');
      reply.status(500);
      return { error: error.message };
    }
  });

  // PUT /api/memories/:id — Update a memory
  server.put<{ Params: { id: string }; Body: UpdateMemoryBody }>(
    '/api/memories/:id',
    async (request, reply) => {
      const id = parseInt(request.params.id, 10);
      if (isNaN(id)) {
        reply.status(400);
        return { error: 'Invalid memory ID' };
      }

      const { content, confidence, embedding } = request.body || {};

      if (content === undefined && confidence === undefined && embedding === undefined) {
        reply.status(400);
        return { error: 'At least one field (content, confidence, embedding) must be provided' };
      }

      try {
        const updated = updateMemory(id, { content, confidence, embedding });
        if (!updated) {
          reply.status(404);
          return { error: 'Memory not found' };
        }

        const memory = getMemoryById(id);
        return memory;
      } catch (err) {
        const error = err as Error;
        logger.error({ err: error, memoryId: id }, 'Failed to update memory');
        reply.status(500);
        return { error: error.message };
      }
    }
  );

  // DELETE /api/memories/:id — Delete a memory
  server.delete<{ Params: { id: string } }>(
    '/api/memories/:id',
    async (request, reply) => {
      const id = parseInt(request.params.id, 10);
      if (isNaN(id)) {
        reply.status(400);
        return { error: 'Invalid memory ID' };
      }

      try {
        const deleted = deleteMemory(id);
        if (!deleted) {
          reply.status(404);
          return { error: 'Memory not found' };
        }
        return { status: 'deleted', id };
      } catch (err) {
        const error = err as Error;
        logger.error({ err: error, memoryId: id }, 'Failed to delete memory');
        reply.status(500);
        return { error: error.message };
      }
    }
  );

  // POST /api/memories/touch — Touch memories to update last_accessed_at
  server.post<{ Body: TouchMemoriesBody }>('/api/memories/touch', async (request, reply) => {
    const { ids } = request.body || {};

    if (!ids || !Array.isArray(ids) || ids.length === 0) {
      reply.status(400);
      return { error: 'ids array is required and must not be empty' };
    }

    // Validate all IDs are numbers
    const invalidIds = ids.filter((id) => typeof id !== 'number' || !Number.isInteger(id));
    if (invalidIds.length > 0) {
      reply.status(400);
      return { error: 'All ids must be integers' };
    }

    try {
      const touched = touchMemories(ids);
      return { status: 'ok', touched };
    } catch (err) {
      const error = err as Error;
      logger.error({ err: error, ids }, 'Failed to touch memories');
      reply.status(500);
      return { error: error.message };
    }
  });
}
