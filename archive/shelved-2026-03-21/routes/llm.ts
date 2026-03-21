import { FastifyInstance } from 'fastify';
import { generate, embed, isAvailable } from '../lib/ollama';
import { logger } from '../lib';

export async function llmRoutes(server: FastifyInstance) {
  // GET /api/llm/health — Check if Ollama is available
  server.get('/api/llm/health', async () => {
    const available = await isAvailable();
    return { available };
  });

  // POST /api/llm/generate — Proxy text generation to Ollama
  server.post<{
    Body: { prompt: string; model?: string; temperature?: number };
  }>('/api/llm/generate', async (request, reply) => {
    const { prompt, model, temperature } = request.body || {};

    if (!prompt || typeof prompt !== 'string') {
      reply.status(400);
      return { error: 'prompt is required and must be a string' };
    }

    try {
      const response = await generate(prompt, { model, temperature });
      return { response };
    } catch (err) {
      const error = err as Error;
      logger.error({ err: error }, 'LLM generation failed');
      reply.status(502);
      return { error: 'LLM generation failed', message: error.message };
    }
  });

  // POST /api/llm/embed — Proxy embeddings to Ollama
  server.post<{
    Body: { text: string; model?: string };
  }>('/api/llm/embed', async (request, reply) => {
    const { text, model } = request.body || {};

    if (!text || typeof text !== 'string') {
      reply.status(400);
      return { error: 'text is required and must be a string' };
    }

    try {
      const embedding = await embed(text, model);
      return { embedding };
    } catch (err) {
      const error = err as Error;
      logger.error({ err: error }, 'LLM embedding failed');
      reply.status(502);
      return { error: 'LLM embedding failed', message: error.message };
    }
  });
}
