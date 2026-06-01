/**
 * Fact-store split — capture insert redirection.
 *
 * `insertNote` must write the immutable note FACTS to `facts.captured_notes` (NOT the
 * read-only `raw_notes` view), set NO `status` (a captured note has no `note_state` row;
 * the view's COALESCE makes it read back as 'pending'), and create NO `note_state` row.
 *
 * `db.ts` opens a real connection on import via its module singleton. We redirect that
 * singleton to throwaway temp files (SELENE_DB_PATH / SELENE_FACTS_DB_PATH) BEFORE importing
 * it, so the import is harmless; the assertions then drive `insertNote` against an EXPLICIT
 * two-file connection (the new DI param), never the singleton.
 */
import { tmpdir } from 'os';
import { mkdtempSync } from 'fs';
import { join } from 'path';

// Redirect the db.ts singleton to throwaway files before it is imported. Force production
// env so the import skips the test/dev `_selene_metadata` verification (which would throw on
// a fresh throwaway DB). The singleton is never used for assertions — we inject `two.db`.
//
// Jest shares process.env across files in a worker without restoring it, so we snapshot the
// three vars and restore them in afterAll — otherwise a later file in the same worker would
// re-evaluate config.ts against our leaked env (order-dependent flakiness).
const ENV_KEYS = ['SELENE_ENV', 'SELENE_DB_PATH', 'SELENE_FACTS_DB_PATH'] as const;
const savedEnv: Record<string, string | undefined> = {};
for (const k of ENV_KEYS) savedEnv[k] = process.env[k];

process.env.SELENE_ENV = 'production';
const singletonDir = mkdtempSync(join(tmpdir(), 'selene-capture-singleton-'));
process.env.SELENE_DB_PATH = join(singletonDir, 'selene.db');
process.env.SELENE_FACTS_DB_PATH = join(singletonDir, 'facts.db');

import { insertNote } from './db';
import { makeTwoFileTestDb } from './test-two-file-db';

describe('insertNote → facts.captured_notes (fact-store capture redirect)', () => {
  let two: ReturnType<typeof makeTwoFileTestDb>;

  beforeEach(() => {
    two = makeTwoFileTestDb();
  });

  afterEach(() => {
    two.db.close();
  });

  afterAll(() => {
    // Restore env so this file can't pollute sibling test files in the same Jest worker.
    for (const k of ENV_KEYS) {
      if (savedEnv[k] === undefined) delete process.env[k];
      else process.env[k] = savedEnv[k];
    }
  });

  it('writes exactly one row to facts.captured_notes with the right content_hash, no note_state row, and reads back via the view as pending', () => {
    const note = {
      title: 'Capture Title',
      content: 'one two three four',
      contentHash: 'hash-capture-1',
      tags: ['#alpha', '#beta'],
      createdAt: '2026-05-31T12:00:00.000Z',
      testRun: 'dev-seed',
      captureType: 'drafts',
      sourceUuid: 'uuid-123',
      sourceNoteId: 7,
    };

    const id = insertNote(note, two.db);

    // (a) exactly one fact row, with the right content_hash
    const factRows = two.db
      .prepare('SELECT id, content_hash, capture_type, test_run, source_uuid, source_note_id, word_count, character_count FROM facts.captured_notes')
      .all() as Array<{
        id: number;
        content_hash: string;
        capture_type: string;
        test_run: string | null;
        source_uuid: string | null;
        source_note_id: number | null;
        word_count: number;
        character_count: number;
      }>;
    expect(factRows).toHaveLength(1);
    expect(factRows[0].content_hash).toBe('hash-capture-1');
    expect(factRows[0].capture_type).toBe('drafts');
    expect(factRows[0].test_run).toBe('dev-seed');
    expect(factRows[0].source_uuid).toBe('uuid-123');
    expect(factRows[0].source_note_id).toBe(7);
    expect(factRows[0].word_count).toBe(4);
    expect(factRows[0].character_count).toBe('one two three four'.length);

    // (b) reading back through the view yields status='pending' (no note_state row) + right capture_type
    const viewRow = two.db
      .prepare('SELECT id, status, capture_type FROM raw_notes WHERE content_hash = ?')
      .get('hash-capture-1') as { id: number; status: string; capture_type: string } | undefined;
    expect(viewRow).toBeDefined();
    expect(viewRow!.status).toBe('pending');
    expect(viewRow!.capture_type).toBe('drafts');

    // (c) returned id equals the row's id
    expect(id).toBe(factRows[0].id);
    expect(id).toBe(viewRow!.id);

    // (d) NO note_state row was created at capture
    const stateCount = two.db
      .prepare('SELECT COUNT(*) AS n FROM note_state WHERE raw_note_id = ?')
      .get(id) as { n: number };
    expect(stateCount.n).toBe(0);
  });

  it('stamps imported_at automatically on capture (restores the old raw_notes DEFAULT CURRENT_TIMESTAMP)', () => {
    // insertNote does NOT pass imported_at — the column must default-stamp it, exactly as the
    // pre-split raw_notes.imported_at DATETIME DEFAULT CURRENT_TIMESTAMP did. Otherwise every new
    // capture reads back NULL while the RawNote type declares imported_at a non-null string.
    const id = insertNote(
      {
        title: 'Stamped',
        content: 'body',
        contentHash: 'hash-imported-at',
        tags: [],
        createdAt: '2026-05-31T13:00:00.000Z',
      },
      two.db
    );

    const row = two.db
      .prepare('SELECT imported_at FROM facts.captured_notes WHERE id = ?')
      .get(id) as { imported_at: string | null };
    expect(row.imported_at).not.toBeNull();
    // SQLite CURRENT_TIMESTAMP format: 'YYYY-MM-DD HH:MM:SS'
    expect(row.imported_at).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);

    // and it reads back through the view too
    const viewRow = two.db
      .prepare('SELECT imported_at FROM raw_notes WHERE id = ?')
      .get(id) as { imported_at: string | null };
    expect(viewRow.imported_at).not.toBeNull();
  });

  it('preserves defaults: a note with no testRun/sourceUuid/sourceNoteId stores NULLs and defaults capture_type to drafts', () => {
    const id = insertNote(
      {
        title: 'Minimal',
        content: 'body',
        contentHash: 'hash-minimal',
        tags: [],
        createdAt: '2026-05-31T13:00:00.000Z',
      },
      two.db
    );

    const row = two.db
      .prepare('SELECT capture_type, test_run, source_uuid, source_note_id FROM facts.captured_notes WHERE id = ?')
      .get(id) as {
        capture_type: string;
        test_run: string | null;
        source_uuid: string | null;
        source_note_id: number | null;
      };
    expect(row.capture_type).toBe('drafts');
    expect(row.test_run).toBeNull();
    expect(row.source_uuid).toBeNull();
    expect(row.source_note_id).toBeNull();
  });
});
