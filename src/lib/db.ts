import Database, { Database as DatabaseType } from 'better-sqlite3';
import { config } from './config';
import { logger } from './logger';
import type { CalendarEvent } from '../types';

// Initialize database connection
export const db: DatabaseType = new Database(config.dbPath);

// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');

logger.info({ dbPath: config.dbPath, env: config.env }, 'Database connected');

// Fail-safe: Verify non-production environment is using correct database
if (config.isTestEnv || config.isDevEnv) {
  const expectedEnv = config.env; // 'test' or 'development'
  try {
    const result = db.prepare(
      "SELECT value FROM _selene_metadata WHERE key = 'environment'"
    ).get() as { value: string } | undefined;

    if (!result || result.value !== expectedEnv) {
      logger.error(
        { dbPath: config.dbPath, expected: expectedEnv, actual: result?.value },
        `SELENE_ENV=${expectedEnv} but database environment mismatch. Run scripts/create-dev-db.sh first.`
      );
      throw new Error(
        `SELENE_ENV=${expectedEnv} but database is not marked as ${expectedEnv} environment.\n` +
        `Expected _selene_metadata.environment = '${expectedEnv}'.\n` +
        `Run scripts/create-dev-db.sh to create the database.`
      );
    }

    logger.info({ env: expectedEnv }, 'Environment verified');
  } catch (err: unknown) {
    if (err instanceof Error && err.message.includes('no such table')) {
      logger.error(
        { dbPath: config.dbPath },
        `SELENE_ENV=${expectedEnv} but _selene_metadata table not found. Run scripts/create-dev-db.sh first.`
      );
      throw new Error(
        `SELENE_ENV=${expectedEnv} but _selene_metadata table not found.\n` +
        `Run scripts/create-dev-db.sh to create the database.`
      );
    }
    throw err;
  }
}

// Type for raw_notes table
export interface RawNote {
  id: number;
  title: string;
  content: string;
  content_hash: string;
  source_type: string;
  word_count: number;
  character_count: number;
  tags: string | null;
  created_at: string;
  imported_at: string;
  processed_at: string | null;
  exported_at: string | null;
  status: string;
  exported_to_obsidian: number;
  test_run: string | null;
  calendar_event: string | null;
  capture_type: string;
}

// Helper: Get pending notes for processing
export function getPendingNotes(limit = 10): RawNote[] {
  return db
    .prepare('SELECT * FROM raw_notes WHERE status = ? ORDER BY created_at ASC LIMIT ?')
    .all('pending', limit) as RawNote[];
}

// Helper: Mark note as processed
export function markProcessed(id: number): void {
  db.prepare('UPDATE raw_notes SET status = ?, processed_at = ? WHERE id = ?').run(
    'processed',
    new Date().toISOString(),
    id
  );
}

// Helper: Check for duplicate by content hash
export function findByContentHash(hash: string): RawNote | undefined {
  return db.prepare('SELECT * FROM raw_notes WHERE content_hash = ?').get(hash) as
    | RawNote
    | undefined;
}

// Helper: Insert new note
export function insertNote(note: {
  title: string;
  content: string;
  contentHash: string;
  tags: string[];
  createdAt: string;
  testRun?: string;
  captureType?: string;
}): number {
  const wordCount = note.content.split(/\s+/).filter(Boolean).length;
  const characterCount = note.content.length;

  const result = db
    .prepare(
      `INSERT INTO raw_notes
       (title, content, content_hash, tags, word_count, character_count, created_at, status, test_run, capture_type)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
    )
    .run(
      note.title,
      note.content,
      note.contentHash,
      JSON.stringify(note.tags),
      wordCount,
      characterCount,
      note.createdAt,
      note.testRun || null,
      note.captureType || 'drafts'
    );

  return result.lastInsertRowid as number;
}

// Helper: Update calendar event metadata on a note
export function updateCalendarEvent(noteId: number, calendarEvent: CalendarEvent): void {
  db.prepare('UPDATE raw_notes SET calendar_event = ? WHERE id = ?')
    .run(JSON.stringify(calendarEvent), noteId);
}

// Helper: Get all notes with processed data
export function getAllNotes(limit = 100): RawNote[] {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM raw_notes r
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE r.test_run IS NULL
    ORDER BY r.created_at DESC
    LIMIT ?
  `);
  return stmt.all(limit) as RawNote[];
}

// Helper: Get note by ID with processed data
export function getNoteById(id: number): RawNote | undefined {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM raw_notes r
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE r.id = ? AND r.test_run IS NULL
  `);
  return stmt.get(id) as RawNote | undefined;
}

// Helper: Keyword search across notes
export function searchNotesKeyword(query: string, limit = 50): RawNote[] {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM raw_notes r
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE r.test_run IS NULL
      AND (r.content LIKE ? OR r.title LIKE ?)
    ORDER BY r.created_at DESC
    LIMIT ?
  `);
  const pattern = '%' + query + '%';
  return stmt.all(pattern, pattern, limit) as RawNote[];
}

// Helper: Get recent notes within N days
export function getRecentNotes(days: number, limit = 10): RawNote[] {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM raw_notes r
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE r.test_run IS NULL
      AND r.created_at >= datetime('now', '-' || ? || ' days')
    ORDER BY r.created_at DESC
    LIMIT ?
  `);
  return stmt.all(days, limit) as RawNote[];
}

// Helper: Get notes since a specific date
export function getNotesSince(date: string, limit = 20): RawNote[] {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM raw_notes r
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE r.test_run IS NULL
      AND r.created_at >= ?
    ORDER BY r.created_at DESC
    LIMIT ?
  `);
  return stmt.all(date, limit) as RawNote[];
}

// Helper: Get thread assignments for a batch of note IDs
export function getThreadAssignmentsForNotes(noteIds: number[]): Array<{ noteId: number; threadName: string; threadId: number }> {
  if (noteIds.length === 0) return [];
  const placeholders = noteIds.map(() => '?').join(',');
  const stmt = db.prepare(`
    SELECT tn.raw_note_id as noteId, t.name as threadName, t.id as threadId
    FROM thread_notes tn
    JOIN threads t ON tn.thread_id = t.id
    WHERE tn.raw_note_id IN (${placeholders})
  `);
  return stmt.all(...noteIds) as Array<{ noteId: number; threadName: string; threadId: number }>;
}

// Type for threads table
export interface Thread {
  id: number;
  name: string;
  why: string | null;
  summary: string | null;
  status: string;
  note_count: number;
  last_activity_at: string | null;
  emotional_charge: number | null;
  momentum_score: number | null;
  created_at: string;
  updated_at: string;
}

// Type for thread_tasks table
export interface ThreadTask {
  id: number;
  thread_id: number;
  things_task_id: string;
  created_at: string;
  completed_at: string | null;
}

// Type for notes joined with processed data (used by thread queries)
export interface NoteWithProcessedData extends RawNote {
  concepts: string | null;
  concept_confidence: string | null;
  primary_theme: string | null;
  secondary_themes: string | null;
  overall_sentiment: string | null;
  sentiment_score: number | null;
  emotional_tone: string | null;
  energy_level: string | null;
}

// Helper: Get active threads ordered by momentum
export function getActiveThreads(limit = 10): Thread[] {
  const stmt = db.prepare(`
    SELECT t.*,
      (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) as note_count
    FROM threads t
    WHERE t.status = 'active'
    ORDER BY t.momentum_score DESC NULLS LAST, t.last_activity_at DESC
    LIMIT ?
  `);
  return stmt.all(limit) as Thread[];
}

// Helper: Get thread by ID
export function getThreadById(id: number): Thread | undefined {
  const stmt = db.prepare(`
    SELECT t.*,
      (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) as note_count
    FROM threads t
    WHERE t.id = ?
  `);
  return stmt.get(id) as Thread | undefined;
}

// Helper: Fuzzy search thread by name
export function searchThreadByName(name: string): Thread | undefined {
  const stmt = db.prepare(`
    SELECT t.*,
      (SELECT COUNT(*) FROM thread_notes tn WHERE tn.thread_id = t.id) as note_count
    FROM threads t
    WHERE LOWER(t.name) LIKE LOWER(?)
    ORDER BY t.momentum_score DESC NULLS LAST
    LIMIT 1
  `);
  return stmt.get('%' + name + '%') as Thread | undefined;
}

// Helper: Get notes belonging to a thread with processed data
export function getThreadNotes(threadId: number, limit = 20): NoteWithProcessedData[] {
  const stmt = db.prepare(`
    SELECT r.*, p.concepts, p.concept_confidence, p.primary_theme,
           p.secondary_themes, p.overall_sentiment, p.sentiment_score,
           p.emotional_tone, p.energy_level
    FROM thread_notes tn
    JOIN raw_notes r ON tn.raw_note_id = r.id
    LEFT JOIN processed_notes p ON r.id = p.raw_note_id
    WHERE tn.thread_id = ?
    ORDER BY r.created_at DESC
    LIMIT ?
  `);
  return stmt.all(threadId, limit) as NoteWithProcessedData[];
}

// Helper: Get tasks associated with a thread
export function getTasksForThread(threadId: number): ThreadTask[] {
  const stmt = db.prepare(`
    SELECT * FROM thread_tasks
    WHERE thread_id = ?
    ORDER BY created_at DESC
  `);
  return stmt.all(threadId) as ThreadTask[];
}

// Type for chat_sessions table
export interface ChatSession {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
  message_count: number;
  is_pinned: number;
  compression_state: 'full' | 'processing' | 'compressed';
  compressed_at: string | null;
  full_messages_json: string | null;
  summary_text: string | null;
}

// Type for conversations table
export interface ConversationMessage {
  id: number;
  session_id: string;
  role: 'user' | 'assistant';
  content: string;
  created_at: string;
}

// Helper: List all sessions ordered by updated_at desc
export function listSessions(): ChatSession[] {
  const stmt = db.prepare(`
    SELECT * FROM chat_sessions
    ORDER BY updated_at DESC
  `);
  return stmt.all() as ChatSession[];
}

// Helper: Get a session by ID
export function getSessionById(id: string): ChatSession | undefined {
  const stmt = db.prepare('SELECT * FROM chat_sessions WHERE id = ?');
  return stmt.get(id) as ChatSession | undefined;
}

// Helper: Upsert a session (INSERT OR REPLACE)
export function upsertSession(session: {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
  message_count: number;
  is_pinned: number;
  compression_state: string;
  compressed_at: string | null;
  full_messages_json: string | null;
  summary_text: string | null;
}): void {
  const stmt = db.prepare(`
    INSERT OR REPLACE INTO chat_sessions
      (id, title, created_at, updated_at, message_count, is_pinned,
       compression_state, compressed_at, full_messages_json, summary_text)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  stmt.run(
    session.id,
    session.title,
    session.created_at,
    session.updated_at,
    session.message_count,
    session.is_pinned,
    session.compression_state,
    session.compressed_at,
    session.full_messages_json,
    session.summary_text
  );
}

// Helper: Delete a session and its conversation messages
export function deleteSession(id: string): boolean {
  const deleteConversations = db.prepare('DELETE FROM conversations WHERE session_id = ?');
  const deleteSession = db.prepare('DELETE FROM chat_sessions WHERE id = ?');

  const transaction = db.transaction(() => {
    deleteConversations.run(id);
    const result = deleteSession.run(id);
    return result.changes > 0;
  });

  return transaction();
}

// Helper: Toggle pin state for a session
export function updateSessionPin(id: string, isPinned: boolean): boolean {
  const stmt = db.prepare(`
    UPDATE chat_sessions SET is_pinned = ?, updated_at = ? WHERE id = ?
  `);
  const result = stmt.run(isPinned ? 1 : 0, new Date().toISOString(), id);
  return result.changes > 0;
}

// Helper: Get conversation messages for a session
export function getSessionMessages(sessionId: string, limit = 100): ConversationMessage[] {
  const stmt = db.prepare(`
    SELECT * FROM conversations
    WHERE session_id = ?
    ORDER BY created_at ASC
    LIMIT ?
  `);
  return stmt.all(sessionId, limit) as ConversationMessage[];
}

// Helper: Save a conversation message
export function saveConversationMessage(message: {
  session_id: string;
  role: 'user' | 'assistant';
  content: string;
}): number {
  const stmt = db.prepare(`
    INSERT INTO conversations (session_id, role, content, created_at)
    VALUES (?, ?, ?, ?)
  `);
  const result = stmt.run(
    message.session_id,
    message.role,
    message.content,
    new Date().toISOString()
  );
  return result.lastInsertRowid as number;
}

// Type for conversation_memories table
export type MemoryType = 'preference' | 'fact' | 'pattern' | 'context';

export interface ConversationMemory {
  id: number;
  content: string;
  source_session_id: string | null;
  embedding: Buffer | null;
  memory_type: MemoryType | null;
  confidence: number;
  last_accessed: string | null;
  created_at: string;
  updated_at: string;
}

// Helper: List memories ordered by confidence desc, last_accessed desc
export function listMemories(limit = 50): ConversationMemory[] {
  const stmt = db.prepare(`
    SELECT * FROM conversation_memories
    ORDER BY confidence DESC, last_accessed DESC NULLS LAST
    LIMIT ?
  `);
  return stmt.all(limit) as ConversationMemory[];
}

// Helper: Get a memory by ID
export function getMemoryById(id: number): ConversationMemory | undefined {
  const stmt = db.prepare('SELECT * FROM conversation_memories WHERE id = ?');
  return stmt.get(id) as ConversationMemory | undefined;
}

// Helper: Create a new memory
export function createMemory(memory: {
  content: string;
  memory_type: MemoryType;
  confidence?: number;
  source_session_id?: string | null;
  embedding?: string | null;
}): number {
  const stmt = db.prepare(`
    INSERT INTO conversation_memories
      (content, memory_type, confidence, source_session_id, embedding, last_accessed, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const now = new Date().toISOString();
  const embeddingBlob = memory.embedding ? Buffer.from(memory.embedding, 'utf-8') : null;
  const result = stmt.run(
    memory.content,
    memory.memory_type,
    memory.confidence ?? 1.0,
    memory.source_session_id ?? null,
    embeddingBlob,
    now,
    now,
    now
  );
  return result.lastInsertRowid as number;
}

// Helper: Update an existing memory (only provided fields)
export function updateMemory(
  id: number,
  updates: {
    content?: string;
    confidence?: number;
    embedding?: string | null;
  }
): boolean {
  const fields: string[] = [];
  const values: (string | number | Buffer | null)[] = [];

  if (updates.content !== undefined) {
    fields.push('content = ?');
    values.push(updates.content);
  }
  if (updates.confidence !== undefined) {
    fields.push('confidence = ?');
    values.push(updates.confidence);
  }
  if (updates.embedding !== undefined) {
    fields.push('embedding = ?');
    values.push(updates.embedding ? Buffer.from(updates.embedding, 'utf-8') : null);
  }

  if (fields.length === 0) return false;

  fields.push('updated_at = ?');
  values.push(new Date().toISOString());
  values.push(id);

  const stmt = db.prepare(`UPDATE conversation_memories SET ${fields.join(', ')} WHERE id = ?`);
  const result = stmt.run(...values);
  return result.changes > 0;
}

// Helper: Delete a memory by ID
export function deleteMemory(id: number): boolean {
  const stmt = db.prepare('DELETE FROM conversation_memories WHERE id = ?');
  const result = stmt.run(id);
  return result.changes > 0;
}

// Helper: Touch memories to update last_accessed for multiple IDs
export function touchMemories(ids: number[]): number {
  if (ids.length === 0) return 0;
  const placeholders = ids.map(() => '?').join(',');
  const now = new Date().toISOString();
  const stmt = db.prepare(
    `UPDATE conversation_memories SET last_accessed = ? WHERE id IN (${placeholders})`
  );
  const result = stmt.run(now, ...ids);
  return result.changes;
}

// Type for cross-thread association result
export interface CrossThreadAssociation {
  noteAId: number;
  noteBId: number;
  similarity: number;
}

// Helper: Get high-similarity note pairs where the two notes are in different threads
export function getCrossThreadAssociations(options: {
  minSimilarity?: number;
  recentDays?: number;
  limit?: number;
}): CrossThreadAssociation[] {
  const { minSimilarity = 0.7, recentDays = 7, limit = 10 } = options;

  const stmt = db.prepare(`
    SELECT na.note_a_id AS noteAId, na.note_b_id AS noteBId, na.similarity_score AS similarity
    FROM note_associations na
    JOIN thread_notes tn_a ON tn_a.raw_note_id = na.note_a_id
    JOIN thread_notes tn_b ON tn_b.raw_note_id = na.note_b_id
    WHERE na.similarity_score >= ?
      AND tn_a.thread_id != tn_b.thread_id
      AND na.created_at >= datetime('now', '-' || ? || ' days')
    ORDER BY na.similarity_score DESC
    LIMIT ?
  `);

  return stmt.all(minSimilarity, recentDays, limit) as CrossThreadAssociation[];
}

// Ensure device_tokens table exists
db.exec(`
  CREATE TABLE IF NOT EXISTS device_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'ios',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// Helper: Register a device token (upsert)
export function registerDevice(token: string, platform = 'ios'): void {
  const stmt = db.prepare(`
    INSERT INTO device_tokens (token, platform, created_at, last_seen_at)
    VALUES (?, ?, datetime('now'), datetime('now'))
    ON CONFLICT(token) DO UPDATE SET last_seen_at = datetime('now')
  `);
  stmt.run(token, platform);
}

// Helper: Unregister a device token
export function unregisterDevice(token: string): void {
  db.prepare('DELETE FROM device_tokens WHERE token = ?').run(token);
}

// Helper: Get all device tokens, optionally filtered by platform
export function getDeviceTokens(platform?: string): string[] {
  if (platform) {
    const rows = db.prepare('SELECT token FROM device_tokens WHERE platform = ?')
      .all(platform) as Array<{ token: string }>;
    return rows.map(r => r.token);
  }
  const rows = db.prepare('SELECT token FROM device_tokens')
    .all() as Array<{ token: string }>;
  return rows.map(r => r.token);
}

// Cleanup on process exit
process.on('exit', () => {
  db.close();
});
