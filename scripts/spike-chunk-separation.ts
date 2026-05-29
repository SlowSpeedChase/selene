// scripts/spike-chunk-separation.ts
// THROWAWAY SPIKE (Phase 0 gate) — v2, content-level.
// The gate is NOT a cosine aggregate. It is: when we cluster e-ink CHUNKS and keep
// clusters with >=4 DISTINCT NOTES, are those clusters coherent themes or grab-bags?
//
// Reads the dev DB only. Caches embeddings to /tmp so re-runs with new thresholds are cheap.
// Run: SELENE_ENV=development npx ts-node scripts/spike-chunk-separation.ts
import { embed } from '../src/lib/ollama';
import { cosineSimilarity } from '../src/lib/cosine';
import Database from 'better-sqlite3';
import { homedir } from 'os';
import { join } from 'path';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { createHash } from 'crypto';

const DEV_DB = process.env.SPIKE_DB || join(homedir(), 'selene-data-dev', 'selene.db');
const CACHE = '/tmp/spike-embeds.json';
const MAX_CHUNKS_PER_NOTE = 8;
const MIN_SEGMENT_CHARS = 40;
const MIN_DISTINCT_NOTES = 4; // mirrors MIN_CLUSTER_SIZE in synthesize-topics

function debias(content: string): string {
  return content
    .replace(/^#\s*E-Ink:.*$/gim, '')
    .replace(/^-{2,}\s*Page\s*\d+\s*-{2,}\s*$/gim, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
function segment(content: string): string[] {
  const segs = debias(content)
    .split(/\n-{2,}\s*Page\s*\d+\s*-{2,}\n|\n#{1,6}\s|\n\s*\n/g)
    .map((s) => s.trim())
    .filter((s) => s.length >= MIN_SEGMENT_CHARS)
    .slice(0, MAX_CHUNKS_PER_NOTE);
  return segs.length > 0 ? segs : [debias(content)].filter((s) => s.length > 0);
}
const key = (s: string) => createHash('sha1').update(s).digest('hex');
const snippet = (s: string) => s.replace(/\s+/g, ' ').trim().slice(0, 90);

interface Chunk { noteId: number; source: string; text: string; vec: number[] }

(async () => {
  const db = new Database(DEV_DB, { readonly: true });
  const eink = db.prepare(`
    SELECT r.id, r.content FROM raw_notes r
    JOIN topic_note_links l ON l.note_id=r.id JOIN topic_clusters t ON t.id=l.topic_id
    WHERE r.capture_type='eink' AND t.note_count>50
  `).all() as Array<{ id: number; content: string }>;
  const drafts = db.prepare(`SELECT id, content FROM raw_notes WHERE capture_type='drafts' ORDER BY id LIMIT 30`)
    .all() as Array<{ id: number; content: string }>;

  const cache: Record<string, number[]> = existsSync(CACHE) ? JSON.parse(readFileSync(CACHE, 'utf8')) : {};
  let embedded = 0, cached = 0;
  async function vec(text: string): Promise<number[]> {
    const k = key(text);
    if (cache[k]) { cached++; return cache[k]; }
    const v = await embed(text); cache[k] = v; embedded++;
    if (embedded % 50 === 0) console.log(`  embedded ${embedded}...`);
    return v;
  }

  const chunks: Chunk[] = [];
  for (const n of [...eink.map((n) => ({ ...n, source: 'eink' })), ...drafts.map((n) => ({ ...n, source: 'drafts' }))])
    for (const t of segment(n.content)) chunks.push({ noteId: n.id, source: n.source, text: t, vec: await vec(t) });
  writeFileSync(CACHE, JSON.stringify(cache));
  const einkChunks = chunks.filter((c) => c.source === 'eink');
  console.log(`Notes: ${eink.length} eink + ${drafts.length} drafts | chunks: ${einkChunks.length} eink, ${chunks.length - einkChunks.length} draft | embeds: ${embedded} new, ${cached} cached\n`);

  // Greedy cluster a chunk pool at θ. Returns clusters of Chunk.
  function greedy(pool: Chunk[], th: number): Chunk[][] {
    const used = new Set<number>(); const out: Chunk[][] = [];
    for (let i = 0; i < pool.length; i++) {
      if (used.has(i)) continue; used.add(i); const m = [pool[i]];
      for (let j = i + 1; j < pool.length; j++) {
        if (used.has(j)) continue;
        if (cosineSimilarity(pool[i].vec, pool[j].vec) >= th) { m.push(pool[j]); used.add(j); }
      }
      out.push(m);
    }
    return out;
  }
  const distinctNotes = (c: Chunk[]) => new Set(c.map((x) => x.noteId)).size;

  // ===== PRIMARY GATE: does the e-ink blob split into themed clusters (>=4 distinct notes)? =====
  for (const th of [0.68, 0.70, 0.72]) {
    const cl = greedy(einkChunks, th).sort((a, b) => distinctNotes(b) - distinctNotes(a));
    const themed = cl.filter((c) => distinctNotes(c) >= MIN_DISTINCT_NOTES);
    const notesCovered = new Set(themed.flatMap((c) => c.map((x) => x.noteId))).size;
    console.log(`===== θ=${th} : ${cl.length} raw clusters | ${themed.length} themed (>=${MIN_DISTINCT_NOTES} notes) covering ${notesCovered}/${eink.length} eink notes =====`);
    themed.slice(0, 8).forEach((c, i) => {
      console.log(`  [${i + 1}] ${distinctNotes(c)} notes, ${c.length} chunks:`);
      c.slice(0, 6).forEach((ch) => console.log(`        • ${snippet(ch.text)}`));
    });
    console.log('');
  }

  // ===== SECONDARY: targeted cross-source probe on shared themes (cannot gate at 10:1, just signal) =====
  const themes = ['procrastinat', 'relationship', 'money|budget|financ', 'anxiet|stress', 'habit|routine'];
  console.log('Cross-source probe (mean cosine eink-chunk vs draft-chunk on a shared keyword):');
  for (const t of themes) {
    const re = new RegExp(t, 'i');
    const e = einkChunks.filter((c) => re.test(c.text));
    const d = chunks.filter((c) => c.source === 'drafts' && re.test(c.text));
    if (!e.length || !d.length) { console.log(`  "${t}": eink=${e.length} draft=${d.length} (insufficient)`); continue; }
    const ps: number[] = [];
    for (const a of e) for (const b of d) ps.push(cosineSimilarity(a.vec, b.vec));
    const m = ps.reduce((x, y) => x + y, 0) / ps.length;
    console.log(`  "${t}": eink=${e.length} draft=${d.length} mean-cross-cosine=${m.toFixed(3)}`);
  }
  db.close();
})().catch((e) => { console.error('SPIKE ERROR:', e); process.exit(1); });
