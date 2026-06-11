import * as lancedb from '@lancedb/lancedb';
import type { Table } from '@lancedb/lancedb';
import path from 'path';
import { config } from './config';
import { logger } from './logger';

const log = logger.child({ module: 'lancedb' });

// Vector dimensions for nomic-embed-text
export const VECTOR_DIMENSIONS = 768;

// Database connection (lazy initialized)
let dbConnection: Awaited<ReturnType<typeof lancedb.connect>> | null = null;

/**
 * Get or create database connection
 */
export async function getLanceDb() {
  if (!dbConnection) {
    // Use config.vectorsPath which is environment-aware
    log.info({ dbPath: config.vectorsPath }, 'Connecting to LanceDB');
    dbConnection = await lancedb.connect(config.vectorsPath);
  }
  return dbConnection;
}

/**
 * Close database connection (for cleanup)
 */
export async function closeLanceDb() {
  if (dbConnection) {
    dbConnection = null;
    log.info('LanceDB connection closed');
  }
}

// Schema for note vectors with metadata
export interface NoteVector {
  id: number;              // Matches raw_note_id
  vector: number[];        // 768-dim embedding from nomic-embed-text
  title: string;
  primary_theme: string | null;
  note_type: string | null;       // task, reflection, reference, idea, log
  actionability: string | null;   // actionable, someday, reference, done
  time_horizon: string | null;    // immediate, week, month, timeless
  context: string | null;         // JSON array of contexts
  created_at: string;
  indexed_at: string;
}

let notesTable: Table | null = null;

/**
 * Get or create the notes vector table
 */
export async function getNotesTable(): Promise<Table> {
  if (notesTable) return notesTable;

  const db = await getLanceDb();
  const tableNames = await db.tableNames();

  if (tableNames.includes('notes')) {
    log.info('Opening existing notes table');
    notesTable = await db.openTable('notes');
  } else {
    log.info('Creating new notes table with schema');
    // Create with placeholder to establish schema
    // Use empty strings for nullable fields so LanceDB can infer string type
    notesTable = await db.createTable('notes', [{
      id: -1,
      vector: new Array(VECTOR_DIMENSIONS).fill(0),
      title: '__schema_placeholder__',
      primary_theme: '',
      note_type: '',
      actionability: '',
      time_horizon: '',
      context: '',
      created_at: new Date().toISOString(),
      indexed_at: new Date().toISOString(),
    }]);
    // Delete placeholder
    await notesTable.delete('id = -1');
    log.info('Notes table created');
  }

  return notesTable;
}

/**
 * Convert NoteVector to storage format (nulls become empty strings)
 */
function toStorageFormat(note: NoteVector): Record<string, unknown> {
  return {
    id: note.id,
    vector: note.vector,
    title: note.title,
    primary_theme: note.primary_theme ?? '',
    note_type: note.note_type ?? '',
    actionability: note.actionability ?? '',
    time_horizon: note.time_horizon ?? '',
    context: note.context ?? '',
    created_at: note.created_at,
    indexed_at: note.indexed_at,
  };
}

/**
 * Index a note's vector with metadata (upsert)
 */
export async function indexNote(note: NoteVector): Promise<void> {
  const table = await getNotesTable();

  // Delete existing if present (upsert behavior)
  try {
    await table.delete(`id = ${note.id}`);
  } catch {
    // Ignore if doesn't exist
  }

  await table.add([toStorageFormat(note)]);
  log.debug({ noteId: note.id }, 'Note indexed');
}

/**
 * Index multiple notes in batch
 */
export async function indexNotes(notes: NoteVector[]): Promise<number> {
  if (notes.length === 0) return 0;

  const table = await getNotesTable();

  // Delete existing entries for these IDs
  const ids = notes.map(n => n.id);
  try {
    await table.delete(`id IN (${ids.join(',')})`);
  } catch {
    // Ignore if none exist
  }

  await table.add(notes.map(toStorageFormat));
  log.info({ count: notes.length }, 'Notes batch indexed');
  return notes.length;
}

/**
 * Delete a note from the index
 */
export async function deleteNoteVector(noteId: number): Promise<void> {
  const table = await getNotesTable();
  await table.delete(`id = ${noteId}`);
  log.debug({ noteId }, 'Note removed from index');
}

/**
 * Get all indexed note IDs (for sync checking)
 */
export async function getIndexedNoteIds(): Promise<Set<number>> {
  const table = await getNotesTable();
  const results = await table.query().select(['id']).toArray();
  return new Set(results.map(r => r.id as number));
}

/**
 * Result from similarity search
 */
export interface SimilarNote {
  id: number;
  title: string;
  primary_theme: string | null;
  note_type: string | null;
  distance: number;  // cosine distance (1 - cos, range [0,2]; lower = more similar)
}

/**
 * Options for similarity search
 */
export interface SearchOptions {
  limit?: number;
  maxDistance?: number;        // Filter results above this distance
  excludeIds?: number[];       // Don't return these note IDs
  filterNoteType?: string;     // Only return specific note types
  filterActionability?: string; // Only return specific actionability
}

/**
 * Search for similar notes by vector
 */
export async function searchSimilarNotes(
  queryVector: number[],
  options: SearchOptions = {}
): Promise<SimilarNote[]> {
  const {
    limit = 10,
    maxDistance,
    excludeIds = [],
    filterNoteType,
    filterActionability,
  } = options;

  const table = await getNotesTable();

  // Build filter conditions
  const filters: string[] = [];

  if (excludeIds.length > 0) {
    filters.push(`id NOT IN (${excludeIds.join(',')})`);
  }
  if (filterNoteType) {
    filters.push(`note_type = '${filterNoteType}'`);
  }
  if (filterActionability) {
    filters.push(`actionability = '${filterActionability}'`);
  }

  // Build and execute query.
  // Use COSINE distance: nomic-embed-text returns un-normalized vectors (norm ~20), so the
  // default (squared-L2) metric ranks by magnitude, not meaning. Cosine is magnitude-invariant.
  // `distance` in results is therefore cosine distance (1 - cos, range [0,2]); convert with
  // similarityFromCosineDistance().
  let query = table.vectorSearch(queryVector).distanceType('cosine');

  if (filters.length > 0) {
    query = query.where(filters.join(' AND '));
  }

  const results = await query
    .select(['id', 'title', 'primary_theme', 'note_type', '_distance'])
    .limit(limit * 2)  // Fetch extra for post-filtering
    .toArray();

  // Map and filter results
  const mapped: SimilarNote[] = results
    .map(r => ({
      id: r.id as number,
      title: r.title as string,
      primary_theme: (r.primary_theme as string) || null,
      note_type: (r.note_type as string) || null,
      distance: r._distance as number,
    }))
    .filter(r => maxDistance === undefined || r.distance <= maxDistance)
    .slice(0, limit);

  log.debug({
    queryLength: queryVector.length,
    resultsCount: mapped.length,
    filters
  }, 'Vector search complete');

  return mapped;
}
