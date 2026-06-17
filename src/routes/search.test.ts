import { makeTwoFileTestDb } from '../lib/test-two-file-db';
import type { Database as DatabaseType } from 'better-sqlite3';
import { buildSearchDb, mergeHits, clampLimit, type SearchHit } from './search';

describe('clampLimit', () => {
  it('defaults to 10 when absent or invalid', () => {
    expect(clampLimit(undefined)).toBe(10);
    expect(clampLimit('')).toBe(10);
    expect(clampLimit('abc')).toBe(10);
    expect(clampLimit('0')).toBe(10);
    expect(clampLimit('-5')).toBe(10);
  });

  it('passes through valid values and caps at 50', () => {
    expect(clampLimit('3')).toBe(3);
    expect(clampLimit('50')).toBe(50);
    expect(clampLimit('1000')).toBe(50);
  });
});

describe('mergeHits', () => {
  const core = (id: number): Omit<SearchHit, 'similarity'> => ({
    id,
    sourceUuid: `uuid-${id}`,
    title: `Note ${id}`,
    essence: null,
    snippet: 'snip',
    date: '2026-01-01',
  });

  it('keeps semantic hits first, then appends unseen keyword hits as similarity:null', () => {
    const semantic: SearchHit[] = [{ ...core(1), similarity: 0.9 }];
    const keyword = [core(1), core(2)]; // id 1 is a dup
    const out = mergeHits(semantic, keyword, 10);
    expect(out.map(h => h.id)).toEqual([1, 2]);
    expect(out[0].similarity).toBe(0.9);
    expect(out[1].similarity).toBeNull();
  });

  it('caps at limit', () => {
    const out = mergeHits([], [core(1), core(2), core(3)], 2);
    expect(out.map(h => h.id)).toEqual([1, 2]);
  });
});

describe('buildSearchDb', () => {
  let db: DatabaseType;

  beforeEach(() => {
    // Fact-store split: raw_notes is a TEMP VIEW over facts.captured_notes + note_state.
    ({ db } = makeTwoFileTestDb());
    db.exec(`
      CREATE TABLE processed_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_note_id INTEGER NOT NULL,
        essence TEXT,
        concepts TEXT,
        primary_theme TEXT
      );
    `);
  });

  afterEach(() => db.close());

  function insertNote(title: string, content: string, opts: { sourceUuid?: string; testRun?: string } = {}) {
    db.prepare(
      `INSERT INTO facts.captured_notes (title, content, content_hash, created_at, source_uuid, test_run)
       VALUES (?,?,?,?,?,?)`
    ).run(title, content, `hash-${title}`, '2026-01-01', opts.sourceUuid ?? null, opts.testRun ?? null);
  }

  it('keywordHits matches title or content, newest first, excluding test_run notes', () => {
    insertNote('Focus and sleep', 'thoughts about deep work', { sourceUuid: 'u1' });
    insertNote('Grocery list', 'milk and focus pills', { sourceUuid: 'u2' });
    insertNote('Test note', 'focus focus', { testRun: 'run-1' }); // must be excluded

    const { keywordHits } = buildSearchDb(db);
    const hits = keywordHits('focus', 10);
    expect(hits.map(h => h.id).sort()).toEqual([1, 2]);
    expect(hits.find(h => h.id === 1)?.sourceUuid).toBe('u1');
  });

  it('keywordHits respects the limit', () => {
    insertNote('A', 'focus a');
    insertNote('B', 'focus b');
    insertNote('C', 'focus c');
    const { keywordHits } = buildSearchDb(db);
    expect(keywordHits('focus', 2)).toHaveLength(2);
  });

  it('hitsByIds enriches ids with essence + truncated snippet, skipping test notes', () => {
    insertNote('Real', 'x'.repeat(300), { sourceUuid: 'u1' });
    insertNote('Hidden', 'y', { testRun: 'run-1' });
    db.prepare(`INSERT INTO processed_notes (raw_note_id, essence) VALUES (?,?)`).run(1, 'the essence');

    const { hitsByIds } = buildSearchDb(db);
    const map = hitsByIds([1, 2, 999]);
    expect(map.has(1)).toBe(true);
    expect(map.has(2)).toBe(false); // test_run excluded
    expect(map.has(999)).toBe(false); // missing id
    const hit = map.get(1)!;
    expect(hit.essence).toBe('the essence');
    expect(hit.snippet.length).toBeLessThanOrEqual(160);
  });

  it('hitsByIds returns an empty map for no ids (no SQL run)', () => {
    const { hitsByIds } = buildSearchDb(db);
    expect(hitsByIds([]).size).toBe(0);
  });
});
