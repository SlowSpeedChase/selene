import { randomUUID } from 'crypto';
import { db, embed, generate, isAvailable, createWorkflowLogger } from '../lib';
import { initSynthesisSchema } from '../lib/synthesis-db';
import { cosineSimilarity } from '../lib/cosine';

const log = createWorkflowLogger('synthesize-topics');

const CLUSTER_SIMILARITY_THRESHOLD = 0.65;
const MIN_CLUSTER_SIZE = 4;

initSynthesisSchema(db);

interface NoteEmbedding {
  noteId: number;
  title: string;
  essence: string | null;
  concepts: string | null;
  createdAt: string;
  vector: number[];
}

async function backfillEmbeddings(): Promise<number> {
  const missing = db.prepare(`
    SELECT rn.id, rn.content
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.test_run IS NULL
      AND rn.status = 'processed'
      AND NOT EXISTS (SELECT 1 FROM note_embeddings ne WHERE ne.raw_note_id = rn.id)
    LIMIT 200
  `).all() as Array<{ id: number; content: string }>;

  if (missing.length === 0) {
    log.info('No embeddings to backfill');
    return 0;
  }

  log.info({ count: missing.length }, 'Backfilling embeddings');
  let backfilled = 0;

  for (const note of missing) {
    try {
      const vector = await embed(note.content);
      db.prepare(
        `INSERT OR REPLACE INTO note_embeddings (raw_note_id, embedding, model_version, created_at)
         VALUES (?, ?, 'nomic-embed-text', ?)`
      ).run(note.id, JSON.stringify(vector), new Date().toISOString());
      backfilled++;
    } catch (err) {
      log.warn({ noteId: note.id, err }, 'Backfill embedding failed for note');
    }
  }

  log.info({ backfilled }, 'Embedding backfill complete');
  return backfilled;
}

function loadAllEmbeddings(): NoteEmbedding[] {
  const rows = db.prepare(`
    SELECT rn.id AS noteId, rn.title, rn.created_at AS createdAt,
           pn.essence, pn.concepts,
           ne.embedding
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    JOIN note_embeddings ne ON rn.id = ne.raw_note_id
    WHERE rn.test_run IS NULL AND rn.status = 'processed'
  `).all() as Array<{
    noteId: number; title: string; createdAt: string;
    essence: string | null; concepts: string | null; embedding: string;
  }>;

  return rows.map(r => ({
    noteId: r.noteId,
    title: r.title,
    createdAt: r.createdAt,
    essence: r.essence,
    concepts: r.concepts,
    vector: JSON.parse(r.embedding) as number[],
  }));
}

function clusterNotes(notes: NoteEmbedding[]): Map<string, number[]> {
  const assigned = new Set<number>();
  const clusters = new Map<string, number[]>();

  for (let i = 0; i < notes.length; i++) {
    if (assigned.has(notes[i].noteId)) continue;

    const members: number[] = [notes[i].noteId];

    for (let j = i + 1; j < notes.length; j++) {
      if (assigned.has(notes[j].noteId)) continue;
      const sim = cosineSimilarity(notes[i].vector, notes[j].vector);
      if (sim >= CLUSTER_SIMILARITY_THRESHOLD) {
        members.push(notes[j].noteId);
        assigned.add(notes[j].noteId);
      }
    }

    assigned.add(notes[i].noteId);
    clusters.set(randomUUID(), members);
  }

  return clusters;
}

async function generateClusterName(concepts: string[]): Promise<string> {
  const topConcepts = concepts.slice(0, 5).join(', ');
  const prompt = `Given these recurring concepts from a person's notes: ${topConcepts}
Give this cluster a 2-4 word topic name that captures the essence. No explanation, just the name.`;
  const response = await generate(prompt, { temperature: 0 });
  return response.trim().replace(/^["']|["']$/g, '');
}

async function generateSynthesis(clusterName: string, members: NoteEmbedding[]): Promise<string> {
  const noteLines = members
    .map(n => `Title: ${n.title}\nEssence: ${n.essence ?? n.title}`)
    .join('\n\n');

  const prompt = `You are synthesizing a personal knowledge base.
Topic: "${clusterName}"
Notes (${members.length} total):

${noteLines}

Write in second person ("You've been exploring..."):
1. 3-5 sentences capturing the recurring questions, tensions, and through-line.
2. The open question that keeps resurfacing (one sentence, start with "The open question:").
3. Keep it under 200 words total.

Do not invent information not present in the notes.`;

  return generate(prompt, { timeoutMs: 60000 });
}

async function generateWeeklyRollup(): Promise<void> {
  const evolutions = db.prepare(`
    SELECT name, evolution_summary
    FROM topic_clusters
    WHERE evolution_detected_at > datetime('now', '-7 days')
      AND is_proto = 0
      AND evolution_summary IS NOT NULL
  `).all() as Array<{ name: string; evolution_summary: string }>;

  if (evolutions.length === 0) return;

  const lines = evolutions.map(e => `${e.name}: ${e.evolution_summary}`).join('\n');
  const prompt = `Summarize this week's shifts in someone's personal notes in 2-3 sentences. Write in second person.\n\n${lines}`;

  const rollup = await generate(prompt, { timeoutMs: 45000 });
  const now = new Date().toISOString();

  db.prepare(
    `INSERT INTO synthesis_meta (key, value, updated_at)
     VALUES ('weekly_evolution', ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
  ).run(rollup, now);

  log.info('Weekly rollup generated');
}

export async function synthesizeTopics(): Promise<{ clusters: number; evolved: number; proto: number }> {
  log.info('Starting synthesize-topics');

  if (!(await isAvailable())) {
    log.error('Ollama not available');
    return { clusters: 0, evolved: 0, proto: 0 };
  }

  await backfillEmbeddings();

  const notes = loadAllEmbeddings();
  log.info({ noteCount: notes.length }, 'Loaded embeddings');

  if (notes.length < MIN_CLUSTER_SIZE) {
    log.info('Not enough notes to cluster');
    return { clusters: 0, evolved: 0, proto: 0 };
  }

  const rawClusters = clusterNotes(notes);
  const noteById = new Map(notes.map(n => [n.noteId, n]));
  let clustersProcessed = 0;
  let evolved = 0;
  let proto = 0;
  const now = new Date().toISOString();

  for (const [, noteIds] of rawClusters) {
    const isProto = noteIds.length < MIN_CLUSTER_SIZE;
    const members = noteIds.map(id => noteById.get(id)!).filter(Boolean);

    // Extract top concept strings for cluster naming
    const conceptFreq = new Map<string, number>();
    for (const m of members) {
      if (!m.concepts) continue;
      try {
        const parsed = JSON.parse(m.concepts) as string[];
        for (const c of parsed) {
          conceptFreq.set(c, (conceptFreq.get(c) ?? 0) + 1);
        }
      } catch { /* ignore malformed JSON */ }
    }
    const sortedConcepts = [...conceptFreq.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([c]) => c);

    const slug = sortedConcepts[0]
      ? sortedConcepts[0].toLowerCase().replace(/[^a-z0-9]+/g, '-')
      : `cluster-${randomUUID().substring(0, 8)}`;

    const existing = db.prepare(
      'SELECT id, synthesis_text, synthesis_updated_at FROM topic_clusters WHERE slug = ?'
    ).get(slug) as { id: string; synthesis_text: string | null; synthesis_updated_at: string | null } | undefined;

    // Delta guard: skip if cluster exists and no new notes since last synthesis
    if (existing && !isProto) {
      const hasNewNotes = db.prepare(`
        SELECT 1 FROM topic_note_links
        WHERE topic_id = ? AND added_at > ?
        LIMIT 1
      `).get(existing.id, existing.synthesis_updated_at ?? '1970-01-01');
      if (!hasNewNotes) {
        log.debug({ slug }, 'Delta guard: skipping unchanged cluster');
        continue;
      }
    }

    const clusterName = sortedConcepts.length > 0
      ? await generateClusterName(sortedConcepts)
      : 'General Notes';

    const id = existing?.id ?? randomUUID();
    const prevSynthesis = existing?.synthesis_text ?? null;
    const newSynthesis = isProto ? null : await generateSynthesis(clusterName, members);

    db.prepare(`
      INSERT INTO topic_clusters
        (id, name, slug, synthesis_text, prev_synthesis_text, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(slug) DO UPDATE SET
        name = excluded.name,
        synthesis_text = excluded.synthesis_text,
        prev_synthesis_text = excluded.prev_synthesis_text,
        synthesis_updated_at = excluded.synthesis_updated_at,
        note_count = excluded.note_count,
        is_proto = excluded.is_proto
    `).run(id, clusterName, slug, newSynthesis, prevSynthesis, now, noteIds.length, isProto ? 1 : 0, now);

    for (const noteId of noteIds) {
      db.prepare(
        `INSERT OR IGNORE INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)`
      ).run(id, noteId, now);
    }

    // Evolution detection: compare prev vs new synthesis
    if (!isProto && prevSynthesis && newSynthesis && prevSynthesis !== newSynthesis) {
      try {
        const evolutionPrompt = `Old synthesis: "${prevSynthesis.substring(0, 300)}"

New synthesis: "${newSynthesis.substring(0, 300)}"

Did the understanding meaningfully change (not just grow)? JSON only: { "changed": boolean, "summary": string }`;

        const response = await generate(evolutionPrompt, { temperature: 0, timeoutMs: 30000 });
        const jsonMatch = response.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          const result = JSON.parse(jsonMatch[0]) as { changed: boolean; summary: string };
          if (result.changed) {
            db.prepare(
              `UPDATE topic_clusters SET evolution_detected_at = ?, evolution_summary = ? WHERE id = ?`
            ).run(now, result.summary, id);
            evolved++;
          }
        }
      } catch (err) {
        log.warn({ clusterId: id, err }, 'Evolution detection failed');
      }
    }

    if (isProto) proto++; else clustersProcessed++;
  }

  if (new Date().getDay() === 0) {
    await generateWeeklyRollup();
  }

  log.info({ clusters: clustersProcessed, evolved, proto }, 'synthesize-topics complete');
  return { clusters: clustersProcessed, evolved, proto };
}

// CLI entry point
if (require.main === module) {
  synthesizeTopics()
    .then(result => {
      console.log('Synthesize-topics complete:', result);
      process.exit(0);
    })
    .catch(err => {
      console.error('Synthesize-topics failed:', err);
      process.exit(1);
    });
}
