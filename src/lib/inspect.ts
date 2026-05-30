/**
 * Read-only structural inspector for a Selene SQLite database.
 *
 * Invariant: these functions return ONLY schema, counts, and coverage numbers — never a
 * content-bearing column value (content / title / essence / transcript / summary / raw text).
 * That invariant is what lets the prod-data guard allowlist `selene-inspect` while keeping real
 * note text out of Claude's context. See docs/plans/2026-05-29-dev-prod-boundary-hardening-design.md.
 *
 * Pure functions over a better-sqlite3 Database so they're unit-testable in-memory; the CLI
 * wrapper (scripts/selene-inspect.ts) opens a READONLY connection and dispatches to these.
 */
import Database from 'better-sqlite3';

type DB = InstanceType<typeof Database>;

export interface SchemaReport {
  tables: string[];
  table?: string;
  columns?: Array<{ name: string; type: string; notnull: number; pk: number }>;
}

export interface CountsReport {
  tables: Record<string, number>;
  rawNotesByStatus: Record<string, number>;
  testRunRows: number;
}

export interface CoverageReport {
  rawNotes: number;
  processedNotes: number;
  unprocessed: number;
  missingCategory: number;
  missingEssence: number;
  missingEmbedding: number | null;
  clusters: number | null;
  noteLinks: number | null;
  avgClustersPerNote: number | null;
  notesWithNoCluster: number | null;
}

// Tables we count when present. Order is cosmetic.
const KNOWN_TABLES = [
  'raw_notes', 'processed_notes', 'topic_clusters', 'topic_note_links',
  'note_connections', 'note_embeddings', 'threads', 'thread_notes',
  'note_associations', 'conversation_memories',
];

function tableExists(db: DB, name: string): boolean {
  return !!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name);
}

function scalar(db: DB, sql: string, ...params: unknown[]): number {
  const row = db.prepare(sql).get(...params) as { n: number } | undefined;
  return row ? row.n : 0;
}

function columnNames(db: DB, table: string): string[] {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>;
  return cols.map((c) => c.name);
}

export function inspectSchema(db: DB, table?: string): SchemaReport {
  const tables = (db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    .all() as Array<{ name: string }>).map((r) => r.name);

  if (!table) {
    return { tables };
  }

  const columns = (db.prepare(`PRAGMA table_info(${table})`).all() as Array<{
    name: string; type: string; notnull: number; pk: number;
  }>).map((c) => ({ name: c.name, type: c.type, notnull: c.notnull, pk: c.pk }));

  return { tables, table, columns };
}

export function inspectCounts(db: DB): CountsReport {
  const tables: Record<string, number> = {};
  for (const t of KNOWN_TABLES) {
    if (tableExists(db, t)) {
      tables[t] = scalar(db, `SELECT COUNT(*) AS n FROM ${t}`);
    }
  }

  const rawNotesByStatus: Record<string, number> = {};
  let testRunRows = 0;
  if (tableExists(db, 'raw_notes')) {
    const rows = db
      .prepare('SELECT status, COUNT(*) AS n FROM raw_notes GROUP BY status')
      .all() as Array<{ status: string | null; n: number }>;
    for (const r of rows) {
      rawNotesByStatus[r.status ?? 'null'] = r.n;
    }
    testRunRows = scalar(db, 'SELECT COUNT(*) AS n FROM raw_notes WHERE test_run IS NOT NULL');
  }

  return { tables, rawNotesByStatus, testRunRows };
}

export function inspectCoverage(db: DB): CoverageReport {
  const hasRaw = tableExists(db, 'raw_notes');
  const hasProcessed = tableExists(db, 'processed_notes');
  const hasClusters = tableExists(db, 'topic_clusters');
  const hasLinks = tableExists(db, 'topic_note_links');
  const hasEmbeddings = tableExists(db, 'note_embeddings');

  const rawNotes = hasRaw ? scalar(db, 'SELECT COUNT(*) AS n FROM raw_notes') : 0;
  const processedNotes = hasProcessed ? scalar(db, 'SELECT COUNT(*) AS n FROM processed_notes') : 0;

  const unprocessed = hasRaw && hasProcessed
    ? scalar(db, `SELECT COUNT(*) AS n FROM raw_notes r
                  LEFT JOIN processed_notes p ON p.raw_note_id = r.id
                  WHERE p.id IS NULL`)
    : (hasRaw ? rawNotes : 0);

  const missingCategory = hasProcessed
    ? scalar(db, "SELECT COUNT(*) AS n FROM processed_notes WHERE category IS NULL OR category = ''")
    : 0;
  const missingEssence = hasProcessed
    ? scalar(db, "SELECT COUNT(*) AS n FROM processed_notes WHERE essence IS NULL OR essence = ''")
    : 0;

  let missingEmbedding: number | null = null;
  if (hasRaw && hasEmbeddings) {
    const embCols = columnNames(db, 'note_embeddings');
    const linkCol = embCols.includes('raw_note_id') ? 'raw_note_id'
      : embCols.includes('note_id') ? 'note_id' : null;
    if (linkCol) {
      missingEmbedding = scalar(db, `SELECT COUNT(*) AS n FROM raw_notes r
        WHERE NOT EXISTS (SELECT 1 FROM note_embeddings e WHERE e.${linkCol} = r.id)`);
    }
  }

  const clusters = hasClusters ? scalar(db, 'SELECT COUNT(*) AS n FROM topic_clusters') : null;
  const noteLinks = hasLinks ? scalar(db, 'SELECT COUNT(*) AS n FROM topic_note_links') : null;

  let avgClustersPerNote: number | null = null;
  let notesWithNoCluster: number | null = null;
  if (hasLinks) {
    // Real schema links on note_id; tolerate a raw_note_id variant. Column name comes from
    // PRAGMA (not user input), so interpolation here is safe.
    const linkCols = columnNames(db, 'topic_note_links');
    const noteCol = linkCols.includes('note_id') ? 'note_id'
      : linkCols.includes('raw_note_id') ? 'raw_note_id' : null;
    if (noteCol) {
      const distinctLinked = scalar(db, `SELECT COUNT(DISTINCT ${noteCol}) AS n FROM topic_note_links`);
      avgClustersPerNote = distinctLinked > 0 ? (noteLinks as number) / distinctLinked : 0;
      if (hasRaw) {
        notesWithNoCluster = scalar(db, `SELECT COUNT(*) AS n FROM raw_notes r
          WHERE NOT EXISTS (SELECT 1 FROM topic_note_links l WHERE l.${noteCol} = r.id)`);
      }
    }
  }

  return {
    rawNotes, processedNotes, unprocessed,
    missingCategory, missingEssence, missingEmbedding,
    clusters, noteLinks, avgClustersPerNote, notesWithNoCluster,
  };
}
