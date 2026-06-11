import Database from 'better-sqlite3';
import { tmpdir } from 'os';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import {
  initFactsSchema,
  ensureFactsDbInitialized,
  attachFacts,
  ensureNoteStateTable,
  ensureRawNotesView,
} from './facts-db';

describe('initFactsSchema', () => {
  it('creates captured_notes + review_state, idempotently', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    initFactsSchema(db); // second call must NOT throw (IF NOT EXISTS)

    const capCols = (db.prepare(`PRAGMA table_info(captured_notes)`).all() as { name: string }[]).map(c => c.name);
    expect(capCols).toEqual(expect.arrayContaining([
      'id','title','content','content_hash','source_type','word_count','character_count',
      'tags','created_at','imported_at','source_uuid','calendar_event','capture_type',
      'source_note_id','test_run',
    ]));

    const rsCols = (db.prepare(`PRAGMA table_info(review_state)`).all() as { name: string }[]).map(c => c.name);
    expect(rsCols).toEqual(expect.arrayContaining([
      'entity_type','entity_id','last_surfaced_at','surface_count',
    ]));
    db.close();
  });

  it('enforces NOT NULL on each of title/content/content_hash/created_at', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);

    const required = ['title', 'content', 'content_hash', 'created_at'] as const;
    const values: Record<(typeof required)[number], string> = {
      title: "'t'",
      content: "'c'",
      content_hash: "'h'",
      created_at: "datetime('now')",
    };

    // For each required column, insert a row that supplies ALL required columns
    // EXCEPT that one — each omission must independently violate NOT NULL.
    for (const omit of required) {
      const cols = required.filter((c) => c !== omit);
      const sql = `INSERT INTO captured_notes (${cols.join(', ')}) VALUES (${cols
        .map((c) => values[c])
        .join(', ')})`;
      expect(() => db.prepare(sql).run()).toThrow();
    }
    db.close();
  });
});

describe('note_feedback (obsidian feedback loop)', () => {
  it('initFactsSchema creates note_feedback with the expected columns', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    const cols = (db.prepare(`PRAGMA table_info(note_feedback)`).all() as { name: string }[])
      .map((c) => c.name);
    expect(cols).toEqual(['id', 'raw_note_id', 'feedback_text', 'original_filing', 'created_at', 'applied_at']);
    db.close();
  });

  it('enforces NOT NULL on each of raw_note_id/feedback_text/created_at', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);

    const required = ['raw_note_id', 'feedback_text', 'created_at'] as const;
    const values: Record<(typeof required)[number], string> = {
      raw_note_id: '1',
      feedback_text: "'f'",
      created_at: "datetime('now')",
    };

    // For each required column, insert a row that supplies ALL required columns
    // EXCEPT that one — each omission must independently violate NOT NULL.
    for (const omit of required) {
      const cols = required.filter((c) => c !== omit);
      const sql = `INSERT INTO note_feedback (${cols.join(', ')}) VALUES (${cols
        .map((c) => values[c])
        .join(', ')})`;
      expect(() => db.prepare(sql).run()).toThrow();
    }
    db.close();
  });

  it('is idempotent (second init does not throw or drop rows)', () => {
    const db = new Database(':memory:');
    initFactsSchema(db);
    db.prepare(`INSERT INTO note_feedback (raw_note_id, feedback_text, created_at) VALUES (1, 'x', '2026-06-10')`).run();
    initFactsSchema(db);
    expect(db.prepare(`SELECT COUNT(*) AS n FROM note_feedback`).get()).toEqual({ n: 1 });
    db.close();
  });
});

describe('two-file wiring', () => {
  it('raw_notes view joins facts.captured_notes + note_state, defaulting status to pending', () => {
    const dir = mkdtempSync(join(tmpdir(), 'factstore-'));
    const factsPath = join(dir, 'facts.db');
    ensureFactsDbInitialized(factsPath);
    const main = new Database(join(dir, 'selene.db'));
    attachFacts(main, factsPath);
    ensureNoteStateTable(main);
    ensureRawNotesView(main);

    main.prepare(`INSERT INTO facts.captured_notes (title,content,content_hash,created_at)
                  VALUES ('t','c','h1', datetime('now'))`).run();
    const row = main.prepare(`SELECT id, title, status FROM raw_notes WHERE content_hash='h1'`)
      .get() as { id: number; title: string; status: string };
    expect(row.title).toBe('t');
    expect(row.status).toBe('pending');           // no note_state row -> COALESCE default

    main.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (?, 'processed')`).run(row.id);
    const row2 = main.prepare(`SELECT status FROM raw_notes WHERE id=?`).get(row.id) as { status: string };
    expect(row2.status).toBe('processed');         // note_state overrides default

    main.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('exposes inbox_status through the view, defaulting to pending', () => {
    const dir = mkdtempSync(join(tmpdir(), 'factstore-ib-'));
    const factsPath = join(dir, 'facts.db');
    ensureFactsDbInitialized(factsPath);
    const main = new Database(join(dir, 'selene.db'));
    attachFacts(main, factsPath);
    ensureNoteStateTable(main);
    ensureRawNotesView(main);

    main.prepare(`INSERT INTO facts.captured_notes (title,content,content_hash,created_at)
                  VALUES ('t','c','hib', datetime('now'))`).run();
    const fresh = main.prepare(`SELECT id, inbox_status FROM raw_notes WHERE content_hash='hib'`)
      .get() as { id: number; inbox_status: string };
    expect(fresh.inbox_status).toBe('pending');     // no note_state row -> default

    main.prepare(`INSERT INTO note_state (raw_note_id, inbox_status) VALUES (?, 'archived')`).run(fresh.id);
    const after = main.prepare(`SELECT inbox_status FROM raw_notes WHERE id=?`).get(fresh.id) as { inbox_status: string };
    expect(after.inbox_status).toBe('archived');    // note_state overrides default

    main.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('ensureRawNotesView is a no-op when a physical raw_notes TABLE exists (un-migrated DB)', () => {
    const main = new Database(':memory:');
    main.exec(`CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT)`);
    ensureRawNotesView(main); // must NOT throw, must NOT convert the table
    const t = main.prepare(`SELECT type FROM sqlite_master WHERE name='raw_notes'`).get() as { type: string };
    expect(t.type).toBe('table');                  // still a table, untouched
    main.close();
  });
});
