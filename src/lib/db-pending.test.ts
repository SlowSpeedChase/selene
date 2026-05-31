/**
 * Fact-store split — pending detection via derivation-absence through the view.
 *
 * A freshly captured note lives in `facts.captured_notes` with NO `note_state` row. The
 * backward-compatible `raw_notes` view derives `status = COALESCE(ns.status, 'pending')`, so
 * absence of a derivation row IS "pending" — no physical `status='pending'` write anywhere.
 * `getPendingNotes` keeps the SAME SQL (`WHERE status = 'pending'`); through the view it now
 * means "no note_state row yet". `markProcessed` writes a `note_state` row → COALESCE flips →
 * the note leaves the pending set. This test characterizes that end-to-end against an EXPLICIT
 * two-file connection (the new DI param), never the singleton.
 *
 * `db.ts` opens a real connection on import via its module singleton. We redirect that
 * singleton to throwaway temp files (SELENE_DB_PATH / SELENE_FACTS_DB_PATH) BEFORE importing
 * it, so the import is harmless; the assertions drive the real helpers against `two.db`.
 */
import { tmpdir } from 'os';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';

// Redirect the db.ts singleton to throwaway files before it is imported. Force production env
// so the import skips the test/dev `_selene_metadata` verification (which would throw on a
// fresh throwaway DB). The singleton is never used for assertions — we inject `two.db`.
//
// Jest shares process.env across files in a worker without restoring it, so we snapshot the
// three vars and restore them in afterAll — otherwise a later file in the same worker would
// re-evaluate config.ts against our leaked env (order-dependent flakiness).
const ENV_KEYS = ['SELENE_ENV', 'SELENE_DB_PATH', 'SELENE_FACTS_DB_PATH'] as const;
const savedEnv: Record<string, string | undefined> = {};
for (const k of ENV_KEYS) savedEnv[k] = process.env[k];

process.env.SELENE_ENV = 'production';
const singletonDir = mkdtempSync(join(tmpdir(), 'selene-pending-singleton-'));
process.env.SELENE_DB_PATH = join(singletonDir, 'selene.db');
process.env.SELENE_FACTS_DB_PATH = join(singletonDir, 'facts.db');

import { insertNote, markProcessed, getPendingNotes } from './db';
import { makeTwoFileTestDb } from './test-two-file-db';

describe('getPendingNotes → derivation-absence through the raw_notes view (fact-store)', () => {
  let conn: ReturnType<typeof makeTwoFileTestDb>['db'];
  let dir: string;

  beforeEach(() => {
    const two = makeTwoFileTestDb();
    conn = two.db;
    dir = two.dir;
  });

  afterEach(() => {
    conn.close();
    rmSync(dir, { recursive: true, force: true });
  });

  afterAll(() => {
    // Restore env so this file can't pollute sibling test files in the same Jest worker.
    for (const k of ENV_KEYS) {
      if (savedEnv[k] === undefined) delete process.env[k];
      else process.env[k] = savedEnv[k];
    }
    rmSync(singletonDir, { recursive: true, force: true });
  });

  it('treats fresh captures as pending (no note_state row), drops a note once markProcessed writes its derivation, and honors ORDER BY created_at ASC + LIMIT', () => {
    const id1 = insertNote(
      { title: 'a', content: 'a', contentHash: 'ha', tags: [], createdAt: '2026-01-01T00:00:00Z' },
      conn
    );
    const id2 = insertNote(
      { title: 'b', content: 'b', contentHash: 'hb', tags: [], createdAt: '2026-01-02T00:00:00Z' },
      conn
    );

    // 1) Both fresh captures are pending purely via derivation-absence (no note_state rows).
    let pending = getPendingNotes(10, conn);
    expect(pending.map((n) => n.id).sort()).toEqual([id1, id2].sort());
    expect(pending.every((n) => n.status === 'pending')).toBe(true);

    // ORDER BY created_at ASC + LIMIT: with both pending, the single earliest is id1
    expect(getPendingNotes(1, conn).map((n) => n.id)).toEqual([id1]);

    // 2) After markProcessed writes a note_state row, COALESCE flips → that note leaves the set.
    markProcessed(id1, conn);
    pending = getPendingNotes(10, conn);
    expect(pending.map((n) => n.id)).toEqual([id2]);

    // 3) ORDER BY created_at ASC honored, LIMIT respected (only id2 remains pending).
    expect(getPendingNotes(1, conn).map((n) => n.id)).toEqual([id2]);
  });
});
