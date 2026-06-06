export { config } from './config';
export { logger, createWorkflowLogger } from './logger';
export {
  db,
  getPendingNotes,
  markProcessed,
  findByContentHash,
  insertNote,
  searchNotesKeyword,
  updateCalendarEvent,
} from './db';
export type { RawNote } from './db';
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
export { EXTRACT_PROMPT, ESSENCE_PROMPT, buildEssencePrompt, MOC_PROMPT, CATEGORIES } from './prompts';
export type { Category } from './prompts';
export * from './anonymize';
export * from './agent-db';
export * from './things';
