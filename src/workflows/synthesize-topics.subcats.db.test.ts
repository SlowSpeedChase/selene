import Database from 'better-sqlite3';

// synthesize-topics.ts has top-level side effects (opens the real Selene singleton +
// initSynthesisSchema(db)) that run on import. Replace the '../lib' barrel with an
// in-memory db so importing the workflow module never touches the real/prod database.
// The functions under test receive an EXPLICIT db; the module's `db` is never used here.
jest.mock('../lib', () => {
  const BetterSqlite3 = require('better-sqlite3') as typeof import('better-sqlite3');
  return {
    db: new BetterSqlite3(':memory:'),
    createWorkflowLogger: () => ({
      info() {},
      warn() {},
      debug() {},
      error() {},
    }),
    generate: jest.fn(),
    isAvailable: jest.fn(),
  };
});

import { initSynthesisSchema } from '../lib/synthesis-db';
import { materializeSubClusters, removeOrphanClusters } from './synthesize-topics';
import {
  groupNotesBySubCategory,
  slugForCategory,
  subSlug,
  type SubCategorizableNote,
} from '../lib/category-clusters';
import { CATEGORIES } from '../lib/prompts';

const NOW = '2026-06-06T00:00:00.000Z';

type DB = InstanceType<typeof Database>;

function seedCategoryCluster(
  db: DB,
  id: string,
  name: string,
  slug: string,
  synthesisText: string | null,
): void {
  db.prepare(`
    INSERT INTO topic_clusters (id, name, slug, parent_id, synthesis_text, note_count, is_proto, created_at)
    VALUES (?, ?, ?, NULL, ?, 0, 0, ?)
  `).run(id, name, slug, synthesisText, NOW);
}

function seedSubCluster(
  db: DB,
  id: string,
  name: string,
  slug: string,
  parentId: string,
): void {
  db.prepare(`
    INSERT INTO topic_clusters (id, name, slug, parent_id, synthesis_text, note_count, is_proto, created_at)
    VALUES (?, ?, ?, ?, NULL, 0, 0, ?)
  `).run(id, name, slug, parentId, NOW);
}

function link(db: DB, topicId: string, noteId: number): void {
  db.prepare('INSERT INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)')
    .run(topicId, noteId, NOW);
}

function clusterBySlug(db: DB, slug: string): { id: string; parent_id: string | null } | undefined {
  return db.prepare('SELECT id, parent_id FROM topic_clusters WHERE slug = ?').get(slug) as
    | { id: string; parent_id: string | null }
    | undefined;
}

function linkCount(db: DB, topicId: string): number {
  return (db.prepare('SELECT COUNT(*) AS c FROM topic_note_links WHERE topic_id = ?').get(topicId) as { c: number }).c;
}

describe('materializeSubClusters', () => {
  let db: DB;
  beforeEach(() => {
    db = new Database(':memory:');
    initSynthesisSchema(db);
  });
  afterEach(() => db.close());

  it('TRAP: materializes a sub-cluster even when the parent category is "unchanged"', () => {
    // Parent has a synthesis_text + existing links — simulating an "unchanged" parent that
    // the category loop's short-circuit would skip. Sub-clusters must still materialize.
    seedCategoryCluster(db, 'parent-hb', 'Health & Body', 'health-body', 'existing synthesis prose');
    link(db, 'parent-hb', 100);

    const subGroups = groupNotesBySubCategory([
      { noteId: 100, category: 'Health & Body', crossRefs: [], subCategories: { 'Health & Body': 'Running' } },
    ]);

    materializeSubClusters(db, subGroups, NOW);

    const sub = clusterBySlug(db, 'health-body/running');
    expect(sub).toBeDefined();
    expect(sub!.parent_id).toBe('parent-hb');

    const linkRow = db
      .prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?')
      .get(sub!.id) as { note_id: number } | undefined;
    expect(linkRow).toBeDefined();
    expect(linkRow!.note_id).toBe(100);
  });

  it('TRAP: deletes a sub-cluster (and its links) when its sub-category is emptied', () => {
    seedCategoryCluster(db, 'parent-hb', 'Health & Body', 'health-body', 'synthesis');
    seedSubCluster(db, 'sub-run', 'Running', 'health-body/running', 'parent-hb');
    link(db, 'sub-run', 100);

    // Empty grouping => no desired sub-clusters.
    materializeSubClusters(db, new Map(), NOW);

    expect(clusterBySlug(db, 'health-body/running')).toBeUndefined();
    expect(linkCount(db, 'sub-run')).toBe(0);
  });

  it('keeps included subs, deletes omitted subs', () => {
    seedCategoryCluster(db, 'parent-hb', 'Health & Body', 'health-body', 'synthesis');
    seedSubCluster(db, 'sub-run', 'Running', 'health-body/running', 'parent-hb');
    seedSubCluster(db, 'sub-sleep', 'Sleep', 'health-body/sleep', 'parent-hb');
    link(db, 'sub-run', 100);
    link(db, 'sub-sleep', 101);

    // Only "Running" remains in the new grouping.
    const subGroups = groupNotesBySubCategory([
      { noteId: 100, category: 'Health & Body', crossRefs: [], subCategories: { 'Health & Body': 'Running' } },
    ]);
    materializeSubClusters(db, subGroups, NOW);

    expect(clusterBySlug(db, 'health-body/running')).toBeDefined();
    expect(clusterBySlug(db, 'health-body/sleep')).toBeUndefined();
  });

  it('cross-parent multi-membership: note assigned a sub under two categories', () => {
    seedCategoryCluster(db, 'parent-hb', 'Health & Body', 'health-body', 'synthesis');
    seedCategoryCluster(db, 'parent-pt', 'Projects & Tech', 'projects-tech', 'synthesis');

    const subGroups = groupNotesBySubCategory([
      {
        noteId: 100,
        category: 'Health & Body',
        crossRefs: ['Projects & Tech'],
        subCategories: { 'Health & Body': 'Running', 'Projects & Tech': 'Selene' },
      },
    ]);
    materializeSubClusters(db, subGroups, NOW);

    const run = clusterBySlug(db, subSlug('Health & Body', 'Running'));
    const selene = clusterBySlug(db, subSlug('Projects & Tech', 'Selene'));
    expect(run).toBeDefined();
    expect(run!.parent_id).toBe('parent-hb');
    expect(selene).toBeDefined();
    expect(selene!.parent_id).toBe('parent-pt');

    expect(linkCount(db, run!.id)).toBe(1);
    expect(linkCount(db, selene!.id)).toBe(1);
  });
});

describe('rebuild-safety: wipe + regenerate sub-clusters', () => {
  let db: DB;
  beforeEach(() => {
    db = new Database(':memory:');
    initSynthesisSchema(db);
  });
  afterEach(() => db.close());

  type SubSnapshot = { slug: string; name: string; parentSlug: string | null; noteIds: number[] };

  // Snapshot the DERIVED sub-cluster layer by stable keys (slug, name, parent-by-slug,
  // sorted linked note ids). Deliberately omits the cluster `id` UUID — a rebuild
  // re-derives fresh UUIDs, so id equality is NOT part of the safety property.
  function snapshotSubClusters(database: DB): SubSnapshot[] {
    const rows = database
      .prepare("SELECT id, slug, name, parent_id FROM topic_clusters WHERE parent_id IS NOT NULL")
      .all() as { id: string; slug: string; name: string; parent_id: string }[];

    return rows
      .map((row) => {
        const parent = database
          .prepare('SELECT slug FROM topic_clusters WHERE id = ?')
          .get(row.parent_id) as { slug: string } | undefined;
        const noteIds = (
          database
            .prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ? ORDER BY note_id')
            .all(row.id) as { note_id: number }[]
        ).map((r) => r.note_id);
        return { slug: row.slug, name: row.name, parentSlug: parent ? parent.slug : null, noteIds };
      })
      .sort((a, b) => a.slug.localeCompare(b.slug));
  }

  // Re-derives the parent category clusters (a real rebuild re-creates these via the
  // category loop). The parent UUIDs intentionally differ from the pre-wipe ones to
  // prove the snapshot comparison does not depend on raw parent_id values.
  function seedParentCategories(database: DB, suffix: string): void {
    seedCategoryCluster(database, `parent-hb-${suffix}`, 'Health & Body', 'health-body', 'synthesis');
    seedCategoryCluster(database, `parent-pt-${suffix}`, 'Projects & Tech', 'projects-tech', 'synthesis');
  }

  it('a rebuild wipe + regenerate reproduces the same sub-clusters (faithful cycle)', () => {
    // ---- Derived state BEFORE the rebuild ----
    seedParentCategories(db, 'v1');

    // note 1 -> Health & Body/Running
    // note 2 -> Health & Body/Running + Projects & Tech/Selene (cross-parent multi-membership)
    // note 3 -> no sub assigned anywhere (a "misfit" at the sub level)
    const notes: SubCategorizableNote[] = [
      { noteId: 1, category: 'Health & Body', crossRefs: [], subCategories: { 'Health & Body': 'Running' } },
      {
        noteId: 2,
        category: 'Health & Body',
        crossRefs: ['Projects & Tech'],
        subCategories: { 'Health & Body': 'Running', 'Projects & Tech': 'Selene' },
      },
      { noteId: 3, category: 'Health & Body', crossRefs: [], subCategories: {} },
    ];
    const subGroups = groupNotesBySubCategory(notes);

    materializeSubClusters(db, subGroups, NOW);

    const before = snapshotSubClusters(db);

    // Sanity: the expected subs exist with the right parents + links; the misfit note made none.
    expect(before).toEqual([
      { slug: subSlug('Health & Body', 'Running'), name: 'Running', parentSlug: 'health-body', noteIds: [1, 2] },
      { slug: subSlug('Projects & Tech', 'Selene'), name: 'Selene', parentSlug: 'projects-tech', noteIds: [2] },
    ]);
    // Note 3 (subCategories {}) produced no sub-cluster row anywhere.
    expect(before.some((s) => s.noteIds.includes(3))).toBe(false);

    // ---- Simulate the rebuild wipe of the DISPOSABLE derived layer ----
    db.exec('DELETE FROM topic_note_links; DELETE FROM topic_clusters;');
    expect(
      (db.prepare('SELECT COUNT(*) AS c FROM topic_clusters').get() as { c: number }).c,
    ).toBe(0);

    // ---- Re-derive from the SAME (unchanged) derived inputs ----
    // Fresh parent UUIDs (suffix v2) to prove the comparison is parent-by-slug, not by id.
    seedParentCategories(db, 'v2');
    materializeSubClusters(db, subGroups, NOW);

    const after = snapshotSubClusters(db);

    // ---- Faithful regeneration: identical in every meaningful dimension ----
    expect(after).toEqual(before);
  });
});

describe('removeOrphanClusters', () => {
  let db: DB;
  beforeEach(() => {
    db = new Database(':memory:');
    initSynthesisSchema(db);
  });
  afterEach(() => db.close());

  it('keeps category + sub-slugs, deletes true orphans', () => {
    seedCategoryCluster(db, 'parent-hb', 'Health & Body', 'health-body', 'synthesis');
    seedSubCluster(db, 'sub-run', 'Running', 'health-body/running', 'parent-hb');
    // Legacy embedding-style orphan slug: <concept>-<hash>.
    seedCategoryCluster(db, 'orphan', 'Running', 'running-a1b2c3', 'old');
    link(db, 'orphan', 999);

    removeOrphanClusters(db, CATEGORIES.map(slugForCategory));

    expect(clusterBySlug(db, 'running-a1b2c3')).toBeUndefined();
    expect(linkCount(db, 'orphan')).toBe(0);
    expect(clusterBySlug(db, 'health-body')).toBeDefined();
    expect(clusterBySlug(db, 'health-body/running')).toBeDefined();
  });
});

describe('module-load sub_categories migration (deploy-order safety)', () => {
  // At a prod deploy, kickstart -k force-runs every agent at once, so this workflow can
  // fire against an existing DB BEFORE process-llm's identical migration has landed.
  // The module's own import-time guard must add the column it reads.
  it('importing the workflow adds processed_notes.sub_categories when absent', () => {
    const mockedDb = (jest.requireMock('../lib') as { db: DB }).db;
    // Simulate the pre-deploy prod shape: processed_notes exists WITHOUT sub_categories.
    mockedDb.exec('DROP TABLE IF EXISTS processed_notes');
    mockedDb.exec('CREATE TABLE processed_notes (raw_note_id INTEGER PRIMARY KEY, category TEXT)');

    jest.isolateModules(() => {
      require('./synthesize-topics'); // re-run module scope (initSynthesisSchema + column guard)
    });

    const cols = (mockedDb.prepare('PRAGMA table_info(processed_notes)').all() as Array<{ name: string }>)
      .map((c) => c.name);
    expect(cols).toContain('sub_categories');
  });
});
