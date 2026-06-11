import Database from 'better-sqlite3';
import { existsSync, readdirSync, readFileSync, mkdtempSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { loadNoteClusters, loadClusters, exportClusterNotes, buildClusterNote, loadNoteFriends } from './constellation';

type DB = InstanceType<typeof Database>;

function seed(): DB {
  const db = new Database(':memory:');
  // Real schema shape: topic_clusters(id, name, parent_id); topic_note_links(topic_id, note_id, added_at).
  db.exec(`
    CREATE TABLE topic_clusters (id TEXT PRIMARY KEY, name TEXT, parent_id TEXT);
    CREATE TABLE topic_note_links (topic_id TEXT, note_id INTEGER, added_at TEXT,
      PRIMARY KEY (topic_id, note_id));
  `);
  db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)').run('c1', 'Relationships & Social', null);
  db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)').run('c2', 'Creativity & Expression', null);
  const link = db.prepare('INSERT INTO topic_note_links VALUES (?,?,?)');
  link.run('c1', 10, 'now'); // note 10 -> both (multi-membership)
  link.run('c2', 10, 'now');
  link.run('c1', 20, 'now'); // note 20 -> Relationships only
  return db;
}

describe('loadNoteClusters', () => {
  it('maps each note id to all its cluster names (multi-membership)', () => {
    const map = loadNoteClusters(seed());
    expect(map.get(10)).toEqual(['Creativity & Expression', 'Relationships & Social']);
    expect(map.get(20)).toEqual(['Relationships & Social']);
  });
});

describe('loadClusters', () => {
  it('returns every cluster with its (possibly undefined) parent name', () => {
    const clusters = loadClusters(seed());
    expect(clusters).toEqual([
      { name: 'Creativity & Expression', parentName: undefined },
      { name: 'Relationships & Social', parentName: undefined },
    ]);
  });

  it('emits parent:: for a sub-cluster pointing at its category cluster', () => {
    const db = new Database(':memory:');
    db.exec('CREATE TABLE topic_clusters (id TEXT PRIMARY KEY, name TEXT, parent_id TEXT);');
    const insert = db.prepare('INSERT INTO topic_clusters VALUES (?,?,?)');
    // Parent category cluster (parent_id = NULL) and a sub-cluster whose
    // parent_id = the parent's id, with a namespaced slug id (health-body/running).
    insert.run('health-body', 'Health & Body', null);
    insert.run('health-body/running', 'Running', 'health-body');

    const clusters = loadClusters(db);
    const running = clusters.find((c) => c.name === 'Running');
    expect(running?.parentName).toBe('Health & Body');
    // The rendered note for the sub-cluster contains a parent:: edge.
    expect(buildClusterNote({ name: 'Running' }, running?.parentName)).toContain('parent::');
  });
});

describe('exportClusterNotes', () => {
  it('writes one Constellation note per cluster, regenerated each run', () => {
    const db = seed();
    const vault = mkdtempSync(join(tmpdir(), 'vault-'));
    const count = exportClusterNotes(db, vault);
    expect(count).toBe(2);
    expect(existsSync(join(vault, 'Constellation', 'Relationships & Social.md'))).toBe(true);
    expect(existsSync(join(vault, 'Constellation', 'Creativity & Expression.md'))).toBe(true);
    // Re-run is safe and idempotent: same files, no duplicates.
    exportClusterNotes(db, vault);
    expect(readdirSync(join(vault, 'Constellation')).length).toBe(2);
    expect(readFileSync(join(vault, 'Constellation', 'Relationships & Social.md'), 'utf-8'))
      .toContain('# Relationships & Social');
  });
});

function seedFriends(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, created_at TEXT);
    CREATE TABLE note_connections (
      id TEXT PRIMARY KEY,
      source_note_id INTEGER NOT NULL,
      target_note_id INTEGER NOT NULL,
      similarity_score REAL NOT NULL,
      found_at TEXT NOT NULL
    );
  `);
  const note = db.prepare('INSERT INTO raw_notes VALUES (?,?,?)');
  note.run(1, 'Grammar Intuition', '2025-11-01T00:00:00.000Z');
  note.run(2, 'Sentence Diagramming', '2025-11-02T00:00:00.000Z');
  note.run(3, 'Running Notes', '2025-11-03T00:00:00.000Z');
  note.run(4, 'Unconnected Note', '2025-11-04T00:00:00.000Z');
  const conn = db.prepare('INSERT INTO note_connections VALUES (?,?,?,?,?)');
  conn.run('c1', 1, 2, 0.92, 'now');  // note 1 ↔ note 2 (high)
  conn.run('c2', 1, 3, 0.80, 'now');  // note 1 ↔ note 3 (lower)
  conn.run('c3', 3, 2, 0.78, 'now');  // note 3 ↔ note 2 (stored as 3→2)
  return db;
}

describe('loadNoteFriends', () => {
  it('maps note 1 to its two friends ordered by descending similarity', () => {
    const map = loadNoteFriends(seedFriends());
    const friends = map.get(1);
    expect(friends).toHaveLength(2);
    expect(friends![0].title).toBe('Sentence Diagramming'); // 0.92 first
    expect(friends![1].title).toBe('Running Notes');        // 0.80 second
  });

  it('is bidirectional — note 2 includes note 1 (stored as source=1)', () => {
    const map = loadNoteFriends(seedFriends());
    const titles = (map.get(2) ?? []).map((f) => f.title);
    expect(titles).toContain('Grammar Intuition');
  });

  it('respects topN cap', () => {
    const db = new Database(':memory:');
    db.exec(`
      CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, created_at TEXT);
      CREATE TABLE note_connections (id TEXT PRIMARY KEY, source_note_id INTEGER NOT NULL,
        target_note_id INTEGER NOT NULL, similarity_score REAL NOT NULL, found_at TEXT NOT NULL);
    `);
    db.prepare('INSERT INTO raw_notes VALUES (?,?,?)').run(1, 'Hub', '2025-01-01T00:00:00.000Z');
    for (let i = 2; i <= 11; i++) {
      db.prepare('INSERT INTO raw_notes VALUES (?,?,?)').run(i, `Note ${i}`, '2025-01-01T00:00:00.000Z');
      db.prepare('INSERT INTO note_connections VALUES (?,?,?,?,?)').run(
        `c${i}`, 1, i, 0.75 + i / 100, 'now'
      );
    }
    const map = loadNoteFriends(db, 5);
    expect(map.get(1)).toHaveLength(5);
  });

  it('returns nothing for a note with no connections', () => {
    const map = loadNoteFriends(seedFriends());
    expect(map.get(4)).toBeUndefined();
  });
});
