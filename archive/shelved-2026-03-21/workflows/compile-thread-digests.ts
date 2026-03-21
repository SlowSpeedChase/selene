import { createWorkflowLogger, db, generate, isAvailable } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('compile-thread-digests');

interface ThreadForDigest {
  id: number;
  name: string;
  summary: string | null;
  why: string | null;
  note_count: number;
}

interface NoteEssence {
  essence: string;
}

/**
 * Build the LLM prompt for thread digest compilation.
 */
export function buildDigestPrompt(
  name: string,
  summary: string | null,
  why: string | null,
  essences: NoteEssence[]
): string {
  const essenceList = essences
    .map((e, i) => `${i + 1}. ${e.essence}`)
    .join('\n');

  return `Thread: ${name}
Summary: ${summary || '(none)'}
Motivation: ${why || '(none)'}

Note essences (distilled meanings):
${essenceList}

Write a single paragraph (3-5 sentences) capturing this thread's arc: what started it, how it evolved, and where it stands now. Write in present tense. Be specific, not generic.

Paragraph:`;
}

export async function compileThreadDigests(): Promise<WorkflowResult> {
  log.info('Starting thread digest compilation');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Find active threads with 10+ notes where digest is missing or new essences
  // have been computed since the digest was last compiled (tracked via updated_at
  // on the thread_digest column — we update updated_at when writing the digest).
  const threads = db
    .prepare(
      `SELECT t.id, t.name, t.summary, t.why,
              (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) as note_count
       FROM threads t
       WHERE t.status = 'active'
         AND (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) >= 10
         AND (t.thread_digest IS NULL
              OR EXISTS (
                SELECT 1 FROM processed_notes pn
                JOIN thread_notes tn2 ON pn.raw_note_id = tn2.raw_note_id
                WHERE tn2.thread_id = t.id
                  AND pn.essence IS NOT NULL
                  AND pn.essence_at > t.updated_at
              ))
       ORDER BY t.momentum_score DESC NULLS LAST`
    )
    .all() as ThreadForDigest[];

  log.info({ threadCount: threads.length }, 'Threads needing digest compilation');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  for (const thread of threads) {
    try {
      const essences = db
        .prepare(
          `SELECT pn.essence
           FROM processed_notes pn
           JOIN thread_notes tn ON pn.raw_note_id = tn.raw_note_id
           WHERE tn.thread_id = ? AND pn.essence IS NOT NULL
           ORDER BY pn.essence_at DESC`
        )
        .all(thread.id) as NoteEssence[];

      if (essences.length < 5) {
        log.info(
          { threadId: thread.id, essenceCount: essences.length },
          'Not enough essences yet, skipping'
        );
        continue;
      }

      const prompt = buildDigestPrompt(thread.name, thread.summary, thread.why, essences);
      const response = await generate(prompt);
      const digest = response.trim();

      if (!digest || digest.length < 30) {
        log.warn({ threadId: thread.id }, 'Digest too short, skipping');
        result.errors++;
        result.details.push({ id: thread.id, success: false, error: 'Digest too short' });
        continue;
      }

      db.prepare(`UPDATE threads SET thread_digest = ?, updated_at = datetime('now') WHERE id = ?`).run(digest, thread.id);

      log.info({ threadId: thread.id, digestLength: digest.length }, 'Thread digest compiled');
      result.processed++;
      result.details.push({ id: thread.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ threadId: thread.id, err: error }, 'Failed to compile digest');
      result.errors++;
      result.details.push({ id: thread.id, success: false, error: error.message });
    }
  }

  log.info(
    { processed: result.processed, errors: result.errors },
    'Thread digest compilation complete'
  );
  return result;
}

// CLI entry point
if (require.main === module) {
  compileThreadDigests()
    .then((result) => {
      console.log('Compile-thread-digests complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Compile-thread-digests failed:', err);
      process.exit(1);
    });
}
