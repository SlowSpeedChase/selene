#!/usr/bin/env npx ts-node
/**
 * fact-store-insert-probe — insert ONE fresh, unprocessed "probe" note into a two-file
 * (selene.db + facts.db) layout using the real capture write path, WITHOUT importing the
 * db.ts singleton (which would open an extra connection + run the env guard).
 *
 * It opens the two-file DB via openSeleneConnection and runs the SAME INSERT that
 * src/lib/db.ts:insertNote uses — writing the note as a FACT into facts.captured_notes with
 * NO note_state row, so the raw_notes view COALESCEs its status to 'pending' (derivation
 * absence). Used by scripts/verify-fact-store.sh (Task 10) to prove a fresh capture flows
 * capture → pending → processed → clustered → exported through the REAL pipeline.
 *
 * Prints the new note id and its distinctive title/content_hash so the caller can find it.
 * Strictly /tmp-isolated: refuses unless SELENE_DB_PATH / SELENE_FACTS_DB_PATH are under /tmp.
 */
import { createHash } from 'crypto';
import { openSeleneConnection, assertTmpIsolated } from '../src/lib/open-selene-connection';

const DB_PATH = process.env.SELENE_DB_PATH || '';
const FACTS_PATH = process.env.SELENE_FACTS_DB_PATH || '';

function main(): void {
  assertTmpIsolated(DB_PATH, FACTS_PATH);

  // Distinctive marker so the verifier can locate exactly this row.
  const marker = process.env.T10_PROBE_MARKER || `T10-PROBE-${Date.now()}`;
  const title = `${marker} fresh capture probe`;
  const content =
    `${marker}: a brand-new captured note about morning planning routines, externalizing ` +
    `working memory with a visual checklist, and reducing task-switching friction for ADHD. ` +
    `This sentence exists so the LLM has real content to extract concepts and a category from.`;
  const contentHash = createHash('sha256').update(content).digest('hex');
  const wordCount = content.split(/\s+/).filter(Boolean).length;
  const characterCount = content.length;
  const createdAt = new Date().toISOString();

  const db = openSeleneConnection(DB_PATH, FACTS_PATH); // read-write: WAL + busy_timeout + ATTACH
  try {
    // EXACTLY src/lib/db.ts:insertNote's statement — write to facts.captured_notes (a FACT),
    // set NO status → no note_state row → view reads it back as 'pending'.
    const result = db
      .prepare(
        `INSERT INTO facts.captured_notes
           (title, content, content_hash, tags, word_count, character_count, created_at, test_run, capture_type, source_uuid, source_note_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        title,
        content,
        contentHash,
        JSON.stringify(['t10', 'probe']),
        wordCount,
        characterCount,
        createdAt,
        null, // test_run NULL: a genuine non-test note, so it flows through every pipeline stage
        'drafts',
        null,
        null
      );
    const id = Number(result.lastInsertRowid);

    // Verify it reads back through the view as pending (no note_state row yet).
    const row = db
      .prepare(`SELECT id, status FROM raw_notes WHERE id = ?`)
      .get(id) as { id: number; status: string } | undefined;

    process.stdout.write(
      JSON.stringify({
        id,
        marker,
        title,
        contentHash,
        viewStatus: row?.status ?? null,
      }) + '\n'
    );
  } finally {
    db.close();
  }
}

main();
