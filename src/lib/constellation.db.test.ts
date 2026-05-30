import Database from 'better-sqlite3';
import { existsSync, readdirSync, readFileSync, mkdtempSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { loadNoteClusters, loadClusters, exportClusterNotes } from './constellation';

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
