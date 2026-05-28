import Database from 'better-sqlite3';
import { initSynthesisSchema } from './synthesis-db';
import { buildSynthesisSections } from './synthesis-digest';

describe('buildSynthesisSections', () => {
  let db: InstanceType<typeof Database>;

  beforeEach(() => {
    db = new Database(':memory:');
    // Minimal raw_notes for FK references
    db.exec(`
      CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, created_at TEXT, test_run TEXT);
      INSERT INTO raw_notes VALUES (1, 'Old note', datetime('now', '-30 days'), NULL);
      INSERT INTO raw_notes VALUES (2, 'New note', datetime('now'), NULL);
    `);
    initSynthesisSchema(db);
  });

  afterEach(() => {
    db.close();
  });

  it('returns empty string when no clusters exist', () => {
    const result = buildSynthesisSections(db);
    expect(result).toBe('');
  });

  it('includes Topics circling when clusters exist', () => {
    const now = new Date().toISOString();
    db.prepare(`
      INSERT INTO topic_clusters (id, name, slug, synthesis_text, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES ('c1', 'Procrastination', 'procrastination-abc12345', 'You keep returning to this.', ?, 5, 0, ?)
    `).run(now, now);

    const result = buildSynthesisSections(db);
    expect(result).toContain('Topics circling');
    expect(result).toContain('Procrastination');
    expect(result).toContain('5 notes');
  });

  it('includes Understanding shifted when evolution was detected', () => {
    const now = new Date().toISOString();
    db.prepare(`
      INSERT INTO topic_clusters (id, name, slug, synthesis_text, evolution_detected_at, evolution_summary, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES ('c1', 'Focus', 'focus-abc12345', 'You have been exploring focus.', ?, 'The angle shifted toward identity.', ?, 4, 0, ?)
    `).run(now, now, now);

    const result = buildSynthesisSections(db);
    expect(result).toContain('Understanding shifted');
    expect(result).toContain('The angle shifted toward identity');
  });

  it('includes Unexpected connections when note_connections has recent rows', () => {
    const now = new Date().toISOString();
    db.prepare(
      `INSERT INTO note_connections (id, source_note_id, target_note_id, similarity_score, found_at) VALUES ('conn1', 2, 1, 0.88, ?)`
    ).run(now);

    const result = buildSynthesisSections(db);
    expect(result).toContain('Unexpected connections');
    expect(result).toContain('New note');
    expect(result).toContain('Old note');
  });
});
