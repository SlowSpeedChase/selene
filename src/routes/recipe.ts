import type { FastifyInstance } from 'fastify';
import { config } from '../lib/config';
import { logger } from '../lib/logger';
import { ingest } from '../workflows/ingest';
import type { IngestInput, WebhookResponse } from '../types';

const log = logger.child({ module: 'recipe-route' });

/**
 * Forward a captured recipe to KitchenOS for parsing + saving to the Obsidian vault.
 *
 * Fire-and-forget: the caller does NOT await this. KitchenOS parses the text with
 * a local LLM (which can take ~2 minutes), so blocking the Drafts response on it
 * would make the capture hang. If KitchenOS is down the note is still safely stored
 * in Selene; the failure is logged for retry.
 */
async function forwardToKitchenOS(title: string, content: string): Promise<void> {
  try {
    const response = await fetch(`${config.kitchenosApiUrl}/api/recipes/import-text`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, text: content, source: 'selene' }),
    });

    if (!response.ok) {
      log.error({ status: response.status, statusText: response.statusText, title }, 'KitchenOS import failed');
    } else {
      log.info({ title }, 'Recipe forwarded to KitchenOS');
    }
  } catch (err) {
    log.error({ err, title }, 'Failed to forward recipe to KitchenOS');
  }
}

/**
 * POST /webhook/api/recipe — capture a recipe from Drafts.
 *
 * Stores the note in Selene like any other capture (reusing ingest()), returns
 * immediately, then forwards the raw text to KitchenOS in the background.
 * No auth, matching the /webhook/api/drafts convention.
 */
export async function recipeRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.post<{ Body: IngestInput }>('/webhook/api/recipe', async (request, reply) => {
    const { title, content, created_at, test_run, capture_type, source_uuid } = request.body;

    log.info({ title, test_run }, 'Recipe webhook received');

    if (!title || !content) {
      reply.status(400);
      return { status: 'error', message: 'Title and content are required' } as WebhookResponse;
    }

    try {
      const result = await ingest({ title, content, created_at, test_run, capture_type, source_uuid });

      if (result.duplicate) {
        log.info({ title, existingId: result.existingId }, 'Duplicate recipe skipped');
        return { status: 'duplicate', id: result.existingId } as WebhookResponse;
      }

      // Forward to KitchenOS in the background — do not await (see forwardToKitchenOS).
      // Test captures stay in Selene only and are not pushed to the recipe vault.
      if (!test_run) {
        void forwardToKitchenOS(title, content);
      }

      log.info({ id: result.id, title }, 'Recipe note created');
      return { status: 'created', id: result.id } as WebhookResponse;
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, title }, 'Recipe ingestion failed');
      reply.status(500);
      return { status: 'error', message: error.message } as WebhookResponse;
    }
  });
}
