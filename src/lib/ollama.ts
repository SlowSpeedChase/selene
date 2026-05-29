import { config } from './config';
import { logger } from './logger';

// Types for Ollama API responses
interface OllamaGenerateResponse {
  model: string;
  created_at: string;
  response: string;
  done: boolean;
  context?: number[];
  total_duration?: number;
  load_duration?: number;
  prompt_eval_count?: number;
  prompt_eval_duration?: number;
  eval_count?: number;
  eval_duration?: number;
}

interface OllamaEmbeddingResponse {
  embedding: number[];
}

// Options for generate function
export interface GenerateOptions {
  model?: string;
  timeoutMs?: number;
  temperature?: number;
  maxTokens?: number;
  /** Ollama context window (num_ctx). Omit to use the model default (mistral:7b = 2048).
   *  Set higher for large prompts that would otherwise be silently truncated. */
  numCtx?: number;
}

const ollamaLogger = logger.child({ module: 'ollama' });

/**
 * Generate text completion from Ollama
 * @param prompt The prompt to send to the model
 * @param options Configuration options
 * @returns The generated text response
 */
export async function generate(
  prompt: string,
  options: GenerateOptions = {}
): Promise<string> {
  const model = options.model || config.ollamaModel;
  const timeoutMs = options.timeoutMs || 120000; // 2 minutes default

  ollamaLogger.debug({ model, promptLength: prompt.length }, 'Starting generation');

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${config.ollamaUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        prompt,
        stream: false,
        options: {
          temperature: options.temperature,
          num_predict: options.maxTokens,
          num_ctx: options.numCtx,
        },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Ollama generate failed: ${response.status} ${errorText}`);
    }

    const data = (await response.json()) as OllamaGenerateResponse;

    ollamaLogger.info(
      {
        model,
        responseLength: data.response.length,
        totalDuration: data.total_duration,
        promptTokens: data.prompt_eval_count,
        responseTokens: data.eval_count,
      },
      'Generation complete'
    );

    return data.response;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      ollamaLogger.error({ model, timeoutMs }, 'Generation timed out');
      throw new Error(`Ollama generation timed out after ${timeoutMs}ms`);
    }
    ollamaLogger.error({ model, error }, 'Generation failed');
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Generate embeddings for text
 * @param text The text to embed
 * @param model Optional model override (defaults to config.embeddingModel)
 * @returns Array of embedding values
 */
export async function embed(text: string, model?: string): Promise<number[]> {
  const embeddingModel = model || config.embeddingModel;
  const timeoutMs = 30000; // 30 seconds for embeddings

  ollamaLogger.debug({ model: embeddingModel, textLength: text.length }, 'Starting embedding');

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${config.ollamaUrl}/api/embeddings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: embeddingModel,
        prompt: text,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Ollama embedding failed: ${response.status} ${errorText}`);
    }

    const data = (await response.json()) as OllamaEmbeddingResponse;

    ollamaLogger.info(
      {
        model: embeddingModel,
        dimensions: data.embedding.length,
      },
      'Embedding complete'
    );

    return data.embedding;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      ollamaLogger.error({ model: embeddingModel, timeoutMs }, 'Embedding timed out');
      throw new Error(`Ollama embedding timed out after ${timeoutMs}ms`);
    }
    ollamaLogger.error({ model: embeddingModel, error }, 'Embedding failed');
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Check if Ollama is available and responding
 * @returns true if Ollama is available, false otherwise
 */
export async function isAvailable(): Promise<boolean> {
  const timeoutMs = 5000; // 5 second timeout for health check

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${config.ollamaUrl}/api/tags`, {
      method: 'GET',
      signal: controller.signal,
    });

    const available = response.ok;
    ollamaLogger.debug({ available, url: config.ollamaUrl }, 'Ollama availability check');
    return available;
  } catch (error) {
    ollamaLogger.debug({ url: config.ollamaUrl, error }, 'Ollama not available');
    return false;
  } finally {
    clearTimeout(timeoutId);
  }
}

