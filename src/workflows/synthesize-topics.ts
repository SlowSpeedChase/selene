// @map purpose: Group processed notes into the 8 category clusters and LLM-synthesize each topic + evolution
// @map reads: raw_notes, processed_notes
// @map writes: topic_clusters, topic_note_links, synthesis_meta
import { randomUUID } from 'crypto';
import { db, generate, isAvailable, createWorkflowLogger } from '../lib';
import { testRunFilter } from '../lib/test-run';
import { initSynthesisSchema } from '../lib/synthesis-db';
import { CATEGORIES } from '../lib/prompts';
import { groupNotesByCategory, parseCrossRefs, slugForCategory, uncategorizedNoteIds } from '../lib/category-clusters';

const log = createWorkflowLogger('synthesize-topics');

initSynthesisSchema(db);

interface CategoryMember {
  noteId: number;
  title: string;
  essence: string | null;
  concepts: string | null;
  category: string | null;
  crossRefs: string[];
}

function loadClassifiedNotes(): CategoryMember[] {
  const rows = db.prepare(`
    SELECT rn.id AS noteId, rn.title AS title,
           pn.essence, pn.concepts, pn.category, pn.cross_ref_categories
    FROM raw_notes rn
    JOIN processed_notes pn ON rn.id = pn.raw_note_id
    WHERE rn.status = 'processed' ${testRunFilter('rn')}
  `).all() as Array<{
    noteId: number; title: string; essence: string | null;
    concepts: string | null; category: string | null; cross_ref_categories: string | null;
  }>;
  return rows.map((r) => ({
    noteId: r.noteId,
    title: r.title,
    essence: r.essence,
    concepts: r.concepts,
    category: r.category,
    crossRefs: parseCrossRefs(r.cross_ref_categories),
  }));
}

async function generateSynthesis(
  clusterName: string,
  members: Array<{ title: string; essence: string | null }>,
  topConcepts: string[],
): Promise<string> {
  const capped = members.slice(0, 40);
  if (capped.length < members.length) {
    log.info({ clusterName, shown: capped.length, total: members.length }, 'Capped synthesis members');
  }
  const noteLines = capped.map((n) => `Title: ${n.title}\nEssence: ${n.essence ?? n.title}`).join('\n\n');
  const conceptLine = topConcepts.length
    ? `\nRecurring concepts across these notes: ${topConcepts.slice(0, 15).join(', ')}\n`
    : '';
  const prompt = `You are synthesizing a personal knowledge base.
Topic: "${clusterName}"
${conceptLine}Notes (${members.length} total):

${noteLines}

Write in second person ("You've been exploring..."):
1. 3-5 sentences capturing the recurring questions, tensions, and through-line.
2. The open question that keeps resurfacing (one sentence, start with "The open question:").
3. Keep it under 200 words total.

Do not invent information not present in the notes.`;
  // num_ctx 4096 (vs mistral:7b's 2048 default): a 40-member category can exceed 2048
  // tokens, which Ollama would silently truncate — degrading the synthesis invisibly.
  return generate(prompt, { timeoutMs: 60000, numCtx: 4096 });
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

  // One-shot full rebuild (clean transition from old embedding clusters)
  if (process.env.SELENE_REBUILD_CLUSTERS === '1') {
    db.exec('DELETE FROM topic_note_links; DELETE FROM topic_clusters;');
    log.info('Full cluster rebuild: wiped topic_clusters + topic_note_links');
  }

  const notes = loadClassifiedNotes();
  const byId = new Map(notes.map((n) => [n.noteId, n]));
  const groups = groupNotesByCategory(notes.map((n) => ({ noteId: n.noteId, category: n.category, crossRefs: n.crossRefs })));

  // No silent drops: surface the IDs of notes that matched zero valid categories.
  const ungroupedIds = uncategorizedNoteIds(
    notes.map((n) => ({ noteId: n.noteId, category: n.category, crossRefs: n.crossRefs }))
  );
  log.info(
    { total: notes.length, ungrouped: ungroupedIds.length, ungroupedIds: ungroupedIds.slice(0, 50) },
    'Loaded classified notes'
  );

  let clustersProcessed = 0;
  let evolved = 0;
  const now = new Date().toISOString();

  for (const cat of CATEGORIES) {
    const noteIds = groups.get(cat) ?? [];
    const slug = slugForCategory(cat);

    // Category emptied out (e.g. all its notes reclassified away): delete its stale row +
    // links so the iPad never shows a category cluster with a wrong count. The orphan
    // cleanup below can't catch this — an empty category still has a valid slug.
    if (noteIds.length === 0) {
      const stale = db.prepare('SELECT id FROM topic_clusters WHERE slug = ?').get(slug) as { id: string } | undefined;
      if (stale) {
        db.prepare('DELETE FROM topic_note_links WHERE topic_id = ?').run(stale.id);
        db.prepare('DELETE FROM topic_clusters WHERE id = ?').run(stale.id);
        log.info({ category: cat }, 'Removed now-empty category cluster');
      }
      continue;
    }

    const members = noteIds.map((id) => byId.get(id)).filter((m): m is CategoryMember => m !== undefined);

    // Aggregate recurring concepts for this category (retained from old per-cluster logic).
    const conceptFreq = new Map<string, number>();
    for (const m of members) {
      if (!m.concepts) continue;
      try {
        const parsed = JSON.parse(m.concepts) as unknown;
        if (Array.isArray(parsed)) {
          for (const c of parsed) if (typeof c === 'string') conceptFreq.set(c, (conceptFreq.get(c) ?? 0) + 1);
        }
      } catch (err) {
        log.debug({ noteId: m.noteId, err }, 'Skipping malformed concepts JSON');
      }
    }
    const topConcepts = [...conceptFreq.entries()].sort((a, b) => b[1] - a[1]).map(([c]) => c);

    const existing = db.prepare(
      'SELECT id, synthesis_text FROM topic_clusters WHERE slug = ?'
    ).get(slug) as { id: string; synthesis_text: string | null } | undefined;
    const id = existing?.id ?? randomUUID();

    // Delta-guard: pure set comparison BEFORE touching topic_note_links.
    const desired = new Set(noteIds);
    const currentLinks = existing
      ? new Set((db.prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?')
          .all(existing.id) as Array<{ note_id: number }>).map((r) => r.note_id))
      : new Set<number>();
    const unchanged =
      existing != null &&
      existing.synthesis_text != null &&
      desired.size === currentLinks.size &&
      [...desired].every((n) => currentLinks.has(n));
    if (unchanged) { clustersProcessed++; continue; }

    const prevSynthesis = existing?.synthesis_text ?? null;
    const newSynthesis = await generateSynthesis(cat, members, topConcepts);

    db.prepare(`
      INSERT INTO topic_clusters
        (id, name, slug, synthesis_text, prev_synthesis_text, synthesis_updated_at, note_count, is_proto, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
      ON CONFLICT(slug) DO UPDATE SET
        name = excluded.name,
        synthesis_text = excluded.synthesis_text,
        prev_synthesis_text = excluded.prev_synthesis_text,
        synthesis_updated_at = excluded.synthesis_updated_at,
        note_count = excluded.note_count,
        is_proto = 0
    `).run(id, cat, slug, newSynthesis, prevSynthesis, now, noteIds.length, now);

    // Reconcile links (insert missing, delete stale).
    for (const { note_id } of (db.prepare('SELECT note_id FROM topic_note_links WHERE topic_id = ?')
        .all(id) as Array<{ note_id: number }>)) {
      if (!desired.has(note_id)) {
        db.prepare('DELETE FROM topic_note_links WHERE topic_id = ? AND note_id = ?').run(id, note_id);
      }
    }
    for (const noteId of noteIds) {
      db.prepare('INSERT OR IGNORE INTO topic_note_links (topic_id, note_id, added_at) VALUES (?, ?, ?)')
        .run(id, noteId, now);
    }

    // Evolution detection: compare prev vs new synthesis
    if (prevSynthesis && newSynthesis && prevSynthesis !== newSynthesis) {
      try {
        const safe = (s: string) => s.substring(0, 300).replace(/"/g, "'");
        const evolutionPrompt = `Old synthesis: "${safe(prevSynthesis)}"

New synthesis: "${safe(newSynthesis)}"

Did the understanding meaningfully change (not just grow)? JSON only: { "changed": boolean, "summary": string }`;

        const response = await generate(evolutionPrompt, { temperature: 0, timeoutMs: 30000 });
        const jsonMatch = response.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          const parsed = JSON.parse(jsonMatch[0]) as unknown;
          if (
            parsed !== null &&
            typeof parsed === 'object' &&
            'changed' in parsed &&
            typeof (parsed as { changed: unknown }).changed === 'boolean' &&
            (parsed as { changed: boolean }).changed
          ) {
            const summary = 'summary' in parsed
              ? String((parsed as { summary: unknown }).summary)
              : '';
            db.prepare(
              `UPDATE topic_clusters SET evolution_detected_at = ?, evolution_summary = ? WHERE id = ?`
            ).run(now, summary, id);
            evolved++;
          }
        }
      } catch (err) {
        log.warn({ clusterId: id, err }, 'Evolution detection failed');
      }
    }

    clustersProcessed++;
  }

  // Always-on orphan cleanup: remove any cluster whose slug isn't one of the 8 category slugs
  // (self-heals if the scheduled agent ran before a one-shot rebuild). Safe: category slugs
  // cannot collide with the old `${concept}-${hash}` slugs.
  const keepSlugs = CATEGORIES.map(slugForCategory);
  const placeholders = keepSlugs.map(() => '?').join(',');
  const orphanIds = (db.prepare(
    `SELECT id FROM topic_clusters WHERE slug NOT IN (${placeholders})`
  ).all(...keepSlugs) as Array<{ id: string }>).map((r) => r.id);
  for (const oid of orphanIds) {
    db.prepare('DELETE FROM topic_note_links WHERE topic_id = ?').run(oid);
    db.prepare('DELETE FROM topic_clusters WHERE id = ?').run(oid);
  }
  if (orphanIds.length) log.info({ removed: orphanIds.length }, 'Removed non-category (orphan) clusters');

  if (new Date().getDay() === 0) {
    await generateWeeklyRollup();
  }

  log.info({ clusters: clustersProcessed, evolved, proto: 0 }, 'synthesize-topics complete');
  return { clusters: clustersProcessed, evolved, proto: 0 };
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
