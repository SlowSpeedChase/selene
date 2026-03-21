export { config } from './config';
export { normalizeThreadName } from './strings';
export { logger, createWorkflowLogger } from './logger';
export {
  db,
  getPendingNotes,
  markProcessed,
  findByContentHash,
  insertNote,
  getAllNotes,
  getNoteById,
  searchNotesKeyword,
  getRecentNotes,
  getNotesSince,
  getThreadAssignmentsForNotes,
  updateCalendarEvent,
  getActiveThreads,
} from './db';
export type { RawNote, Thread } from './db';
export { generate, embed, isAvailable } from './ollama';
export {
  getLanceDb,
  closeLanceDb,
  VECTOR_DIMENSIONS,
  getNotesTable,
  indexNote,
  indexNotes,
  deleteNoteVector,
  getIndexedNoteIds,
  searchSimilarNotes,
  type NoteVector,
  type SimilarNote,
  type SearchOptions,
} from './lancedb';
export { ContextBuilder, type NoteContext, type ThreadContext, type FidelityTier } from './context-builder';
export { EXTRACT_PROMPT, ESSENCE_PROMPT, buildEssencePrompt, TOPIC_INDEX_PROMPT, DASHBOARD_PROMPT } from './prompts';
