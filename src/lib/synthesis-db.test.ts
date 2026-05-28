import Database from 'better-sqlite3';
import { initSynthesisSchema, writeConnection, NoteConnection } from './synthesis-db';

describe('initSynthesisSchema', () => {
  let db: InstanceType<typeof Database>;

  beforeEach(() => {
    db = new Database(':memory:');
  });

  afterEach(() => {
    db.close();
  });

  it('creates topic_clusters table', () => {
    initSynthesisSchema(db);
    const row = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='topic_clusters'")
      .get();
    expect(row).toBeDefined();
  });

  it('creates topic_note_links table', () => {
    initSynthesisSchema(db);
    const row = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='topic_note_links'")
      .get();
    expect(row).toBeDefined();
  });

  it('creates note_connections table', () => {
    initSynthesisSchema(db);
    const row = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='note_connections'")
      .get();
    expect(row).toBeDefined();
  });

  it('creates synthesis_meta table', () => {
    initSynthesisSchema(db);
    const row = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='synthesis_meta'")
      .get();
    expect(row).toBeDefined();
  });

  it('is idempotent — calling twice does not throw', () => {
    expect(() => {
      initSynthesisSchema(db);
      initSynthesisSchema(db);
    }).not.toThrow();
  });
});

describe('writeConnection', () => {
  let db: InstanceType<typeof Database>;

  beforeEach(() => {
    db = new Database(':memory:');
    initSynthesisSchema(db);
  });

  afterEach(() => {
    db.close();
  });

  it('inserts a connection row with correct fields', () => {
    writeConnection(db, 1, 2, 0.85);
    const row = db.prepare('SELECT * FROM note_connections WHERE source_note_id = 1').get() as NoteConnection;
    expect(row).toBeDefined();
    expect(row!.source_note_id).toBe(1);
    expect(row!.target_note_id).toBe(2);
    expect(row!.similarity_score).toBeCloseTo(0.85);
  });

  it('is idempotent — duplicate calls do not throw', () => {
    expect(() => {
      writeConnection(db, 10, 20, 0.7);
      writeConnection(db, 10, 20, 0.7);
    }).not.toThrow();
  });
});
