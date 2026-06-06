import type { FastifyInstance } from 'fastify';
import type { Database as DatabaseType } from 'better-sqlite3';
import { db as prodDb } from '../lib/db';
import { requireAuth } from '../lib/auth';
import crypto from 'crypto';

// ---------------------------------------------------------------------------
// DB helpers — extracted so tests can inject an in-memory database
// ---------------------------------------------------------------------------

export function buildNotesDb(db: DatabaseType) {
  function getClusters() {
    return db
      .prepare(
        `SELECT id, name, slug, synthesis_text, note_count
         FROM topic_clusters
         WHERE is_proto = 0 AND parent_id IS NULL
         ORDER BY note_count DESC`
      )
      .all() as Array<{
        id: string;
        name: string;
        slug: string;
        synthesis_text: string | null;
        note_count: number;
      }>;
  }

  function getNotesForCluster(clusterId: string) {
    return db
      .prepare(
        `SELECT r.id, r.title, r.created_at, r.word_count, r.tags
         FROM raw_notes r
         JOIN topic_note_links l ON l.note_id = r.id
         WHERE l.topic_id = ?
         ORDER BY r.created_at DESC`
      )
      .all(clusterId) as Array<{
        id: number;
        title: string;
        created_at: string;
        word_count: number;
        tags: string | null;
      }>;
  }

  function getNoteById(noteId: number) {
    const row = db
      .prepare(
        `SELECT r.id, r.title, r.content, r.created_at, r.tags, r.capture_type, r.source_note_id,
                p.essence, p.concepts, p.primary_theme
         FROM raw_notes r
         LEFT JOIN processed_notes p ON p.raw_note_id = r.id
         WHERE r.id = ?`
      )
      .get(noteId) as {
        id: number;
        title: string;
        content: string;
        created_at: string;
        tags: string | null;
        capture_type: string;
        source_note_id: number | null;
        essence: string | null;
        concepts: string | null;
        primary_theme: string | null;
      } | undefined;
    return row ?? null;
  }

  function insertAnnotation({
    parentNoteId,
    text,
  }: {
    parentNoteId: number;
    text: string;
  }): number {
    const contentHash = crypto.createHash('sha256').update(text).digest('hex');
    const now = new Date().toISOString();
    // Fact-store split: an annotation is a captured FACT — write it to facts.captured_notes
    // (the real table), NOT the read-only raw_notes view. No `status`: the view's
    // COALESCE(...,'pending') reads it back as pending.
    const result = db
      .prepare(
        `INSERT INTO facts.captured_notes
         (title, content, content_hash, word_count, character_count,
          created_at, capture_type, source_note_id)
         VALUES (?, ?, ?, ?, ?, ?, 'annotation', ?)`
      )
      .run(
        `Annotation on note ${parentNoteId}`,
        text,
        contentHash,
        text.split(/\s+/).filter(Boolean).length,
        text.length,
        now,
        parentNoteId,
      );
    return result.lastInsertRowid as number;
  }

  return { getClusters, getNotesForCluster, getNoteById, insertAnnotation };
}

// ---------------------------------------------------------------------------
// Fastify plugin
// ---------------------------------------------------------------------------

export async function notesRoutes(fastify: FastifyInstance): Promise<void> {
  const q = buildNotesDb(prodDb);

  // Every route in this (encapsulated) plugin requires auth — apply once via a plugin hook
  // instead of repeating `{ preHandler: requireAuth }` per route.
  fastify.addHook('preHandler', requireAuth);

  fastify.get('/api/clusters', async () => {
    return { clusters: q.getClusters() };
  });

  fastify.get<{ Params: { id: string } }>(
    '/api/clusters/:id/notes',
    async (request, reply) => {
      const notes = q.getNotesForCluster(request.params.id);
      if (!notes.length) {
        const clusters = q.getClusters();
        const exists = clusters.some(c => c.id === request.params.id);
        if (!exists) {
          reply.status(404);
          return { error: 'Cluster not found' };
        }
      }
      return { notes };
    }
  );

  fastify.get<{ Params: { id: string } }>(
    '/api/notes/:id',
    async (request, reply) => {
      const noteId = parseInt(request.params.id, 10);
      if (isNaN(noteId)) {
        reply.status(400);
        return { error: 'Invalid note id' };
      }
      const note = q.getNoteById(noteId);
      if (!note) {
        reply.status(404);
        return { error: 'Note not found' };
      }
      return { note };
    }
  );

  fastify.post<{ Params: { id: string }; Body: { text: string } }>(
    '/api/notes/:id/annotations',
    async (request, reply) => {
      const parentId = parseInt(request.params.id, 10);
      if (isNaN(parentId)) {
        reply.status(400);
        return { error: 'Invalid note id' };
      }
      const { text } = request.body;
      if (!text || text.trim().length === 0) {
        reply.status(400);
        return { error: 'text is required' };
      }
      const parent = q.getNoteById(parentId);
      if (!parent) {
        reply.status(404);
        return { error: 'Parent note not found' };
      }
      const newId = q.insertAnnotation({ parentNoteId: parentId, text: text.trim() });
      reply.status(201);
      return { id: newId, status: 'created' };
    }
  );
}
