/**
 * Knowledge Constellation (Phase A) — pure helpers + read-only DB readers that turn the
 * synthesis tables (topic_clusters, topic_note_links) into the Dataview metadata ExcaliBrain
 * reads: `parent:: [[<cluster>]]` on each note, plus one cluster index note per cluster.
 *
 * Deliberately free of the db.ts singleton (the readers take a Database arg) so everything is
 * unit-testable in-memory — see src/lib/constellation.test.ts / constellation.db.test.ts.
 */
import type { Database as DB } from 'better-sqlite3';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

// Characters that break Obsidian filenames / [[wikilinks]]. `&` and spaces are safe and kept,
// so the 8 controlled category names (e.g. "Relationships & Social") pass through unchanged.
const WIKILINK_UNSAFE = /[[\]/\\:#^|]/g;

/** Wikilink-safe basename for a cluster index note. ExcaliBrain `parent::` links must reference
 *  this exact basename to resolve. Not lowercased — names are human-facing node labels. */
export function clusterNoteFilename(name: string): string {
  const cleaned = name.replace(WIKILINK_UNSAFE, ' ').replace(/\s+/g, ' ').trim();
  return cleaned.length > 0 ? cleaned : 'cluster';
}

/** One `parent:: [[cluster]]` line per cluster a note belongs to (multi-membership safe). */
export function buildParentFields(clusterNames: string[]): string {
  return clusterNames
    .map((n) => `parent:: [[${clusterNoteFilename(n)}]]`)
    .join('\n');
}

/** Markdown for a cluster index note. `parent::` only when the cluster itself has a parent
 *  (flat today since parent_id is NULL; future-proof for sub-clusters). */
export function buildClusterNote(cluster: { name: string }, parentName?: string): string {
  const parts: string[] = ['---', 'type: cluster', `cluster: ${cluster.name}`, '---', ''];
  if (parentName) parts.push(`parent:: [[${clusterNoteFilename(parentName)}]]`, '');
  parts.push(`# ${cluster.name}`, '');
  return parts.join('\n');
}

/** Map each note id -> all its cluster names (sorted), via topic_note_links ⋈ topic_clusters. */
export function loadNoteClusters(database: DB): Map<number, string[]> {
  const rows = database
    .prepare(
      `SELECT tnl.note_id AS noteId, tc.name AS name
       FROM topic_note_links tnl
       JOIN topic_clusters tc ON tc.id = tnl.topic_id
       ORDER BY tnl.note_id, tc.name`
    )
    .all() as Array<{ noteId: number; name: string }>;
  const map = new Map<number, string[]>();
  for (const r of rows) {
    const list = map.get(r.noteId) ?? [];
    list.push(r.name);
    map.set(r.noteId, list);
  }
  return map;
}

/** Every cluster with its (possibly undefined) parent cluster name, sorted by name. */
export function loadClusters(database: DB): Array<{ name: string; parentName?: string }> {
  const rows = database
    .prepare(
      `SELECT c.name AS name, p.name AS parentName
       FROM topic_clusters c
       LEFT JOIN topic_clusters p ON p.id = c.parent_id
       ORDER BY c.name`
    )
    .all() as Array<{ name: string; parentName: string | null }>;
  return rows.map((r) => ({ name: r.name, parentName: r.parentName ?? undefined }));
}

/** Regenerate the `Constellation/` directory: one index note per cluster. Idempotent —
 *  a re-run overwrites identically. Returns the number of cluster notes written. */
export function exportClusterNotes(database: DB, vaultPath: string): number {
  const clusters = loadClusters(database);
  const dir = join(vaultPath, 'Constellation');
  mkdirSync(dir, { recursive: true });
  let count = 0;
  for (const c of clusters) {
    const md = buildClusterNote({ name: c.name }, c.parentName);
    writeFileSync(join(dir, `${clusterNoteFilename(c.name)}.md`), md, 'utf-8');
    count++;
  }
  return count;
}
