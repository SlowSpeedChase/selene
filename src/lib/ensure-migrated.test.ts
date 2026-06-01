/**
 * ensureMigrated startup guard.
 *
 * Drives `ensureMigrated(dbPath, factsPath, env)` directly against throwaway temp DBs (NEVER a
 * real DB under ~/selene-data*). Env is passed EXPLICITLY (not read from cached `config.env`,
 * which is fixed at module load and unreliable under jest) so each case is deterministic.
 *
 * Cases:
 *   - development + un-migrated  → AUTO-MIGRATES (dev/clone self-heal),
 *   - production  + un-migrated  → THROWS loud, migrates NOTHING (refuses the incoherent split),
 *   - test        + un-migrated  → SKIPS (tests manage their own DBs),
 *   - already two-file (no physical raw_notes) → no-op in ANY env (even prod).
 */
import Database from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { ensureMigrated } from './ensure-migrated';
import { makeTwoFileTestDb } from './test-two-file-db';

/**
 * Build a throwaway legacy single-file selene.db with a PHYSICAL raw_notes table. It carries all
 * 15 FACT_COLUMNS the migration copies (the extra 10 nullable + unpopulated) PLUS status/inbox_status
 * bookkeeping — the migration's fact copy is NOT intersected (it names every fact column), so a
 * thinner schema would throw `no such column` from inside the migration on the dev case. Only the
 * development case actually invokes the migration; production throws before it and test returns
 * before it, but one full-shape helper keeps all cases honest.
 */
function legacyDb(dir: string): string {
  const p = join(dir, 'selene.db');
  const db = new Database(p);
  db.exec(`CREATE TABLE raw_notes (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            source_type TEXT,
            word_count INTEGER,
            character_count INTEGER,
            tags TEXT,
            created_at DATETIME NOT NULL,
            imported_at DATETIME,
            source_uuid TEXT,
            calendar_event TEXT,
            capture_type TEXT,
            source_note_id INTEGER,
            test_run TEXT,
            status TEXT,
            inbox_status TEXT);`);
  db.prepare(`INSERT INTO raw_notes (id,title,content,content_hash,created_at,status)
              VALUES (1,'t','c','h',datetime('now'),'processed')`).run();
  db.close();
  return p;
}

describe('ensureMigrated', () => {
  it('development + un-migrated → migrates', () => {
    const dir = mkdtempSync(join(tmpdir(), 'em-dev-'));
    const dbPath = legacyDb(dir); const factsPath = join(dir, 'facts.db');
    ensureMigrated(dbPath, factsPath, 'development');
    const facts = new Database(factsPath);
    expect((facts.prepare(`SELECT COUNT(*) c FROM captured_notes`).get() as { c: number }).c).toBe(1);
    facts.close();
    const main = new Database(dbPath);
    expect(main.prepare(`SELECT name FROM sqlite_master WHERE name='raw_notes_legacy_backup'`).get()).toBeTruthy();
    main.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('production + un-migrated → throws loud, does NOT migrate', () => {
    const dir = mkdtempSync(join(tmpdir(), 'em-prod-'));
    const dbPath = legacyDb(dir); const factsPath = join(dir, 'facts.db');
    expect(() => ensureMigrated(dbPath, factsPath, 'production')).toThrow(/not migrated|cutover/i);
    expect(existsSync(factsPath)).toBe(false);
    const main = new Database(dbPath);
    expect((main.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes'`).get() as { type: string }).type).toBe('table');
    main.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('test env + un-migrated → skips (no migrate, no throw)', () => {
    const dir = mkdtempSync(join(tmpdir(), 'em-test-'));
    const dbPath = legacyDb(dir); const factsPath = join(dir, 'facts.db');
    expect(() => ensureMigrated(dbPath, factsPath, 'test')).not.toThrow();
    expect(existsSync(factsPath)).toBe(false);
    rmSync(dir, { recursive: true, force: true });
  });

  it('already two-file (no physical raw_notes) → no-op in any env', () => {
    const two = makeTwoFileTestDb();
    const dbName = two.db.name; const dir = two.dir; two.db.close();
    expect(() => ensureMigrated(dbName, join(dir, 'facts.db'), 'production')).not.toThrow();
    rmSync(dir, { recursive: true, force: true });
  });
});
