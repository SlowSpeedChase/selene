import Database from 'better-sqlite3';
import { buildNotesDb } from './notes';

describe('notes route helpers', () => {
  let db: InstanceType<typeof Database>;

  beforeEach(() => {
    db = new Database(':memory:');
    db.exec(`
      CREATE TABLE raw_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT UNIQUE NOT NULL,
        source_type TEXT DEFAULT 'drafts',
        word_count INTEGER DEFAULT 0,
        character_count INTEGER DEFAULT 0,
        tags TEXT,
        created_at DATETIME NOT NULL,
        imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        status TEXT DEFAULT 'pending',
        capture_type TEXT DEFAULT 'drafts',
        source_note_id INTEGER
      );
      CREATE TABLE topic_clusters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        slug TEXT NOT NULL,
        synthesis_text TEXT,
        note_count INTEGER NOT NULL DEFAULT 0,
        is_proto INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
      CREATE TABLE topic_note_links (
        topic_id TEXT NOT NULL,
        note_id INTEGER NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (topic_id, note_id)
      );
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

  it('getClusters returns non-proto clusters ordered by note_count', () => {
    db.prepare(`INSERT INTO topic_clusters VALUES (?,?,?,?,?,?,?)`).run(
      'c1', 'Focus', 'focus', 'synthesis about focus', 3, 0, '2026-01-01'
    );
    db.prepare(`INSERT INTO topic_clusters VALUES (?,?,?,?,?,?,?)`).run(
      'c2', 'Proto', 'proto', null, 1, 1, '2026-01-01'
    );
    const { getClusters } = buildNotesDb(db);
    const result = getClusters();
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('c1');
  });

  it('getNotesForCluster returns raw notes linked to a cluster', () => {
    db.prepare(`INSERT INTO raw_notes (title, content, content_hash, created_at) VALUES (?,?,?,?)`).run(
      'Note A', 'Body A', 'hash-a', '2026-01-01'
    );
    db.prepare(`INSERT INTO topic_note_links VALUES (?,?,?)`).run('c1', 1, '2026-01-01');
    const { getNotesForCluster } = buildNotesDb(db);
    const result = getNotesForCluster('c1');
    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('Note A');
  });

  it('getNoteById returns note with processed metadata', () => {
    db.prepare(`INSERT INTO raw_notes (title, content, content_hash, created_at) VALUES (?,?,?,?)`).run(
      'My Note', 'Content here', 'hash-1', '2026-01-01'
    );
    db.prepare(`INSERT INTO processed_notes (raw_note_id, essence, concepts, primary_theme) VALUES (?,?,?,?)`).run(
      1, 'A short essence', '["idea","focus"]', 'Productivity'
    );
    const { getNoteById } = buildNotesDb(db);
    const result = getNoteById(1);
    expect(result).not.toBeNull();
    expect(result!.title).toBe('My Note');
    expect(result!.essence).toBe('A short essence');
    expect(result!.primary_theme).toBe('Productivity');
  });

  it('insertAnnotation creates a new raw note linked to parent', () => {
    db.prepare(`INSERT INTO raw_notes (title, content, content_hash, created_at) VALUES (?,?,?,?)`).run(
      'Parent', 'Parent content', 'hash-p', '2026-01-01'
    );
    const { insertAnnotation, getNoteById } = buildNotesDb(db);
    const newId = insertAnnotation({ parentNoteId: 1, text: 'My annotation ink' });
    const note = getNoteById(newId);
    expect(note).not.toBeNull();
    expect(note!.source_note_id).toBe(1);
    expect(note!.content).toBe('My annotation ink');
    expect(note!.capture_type).toBe('annotation');
  });
});
