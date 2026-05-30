/**
 * PKM Browse — HTML rendering (Track 2). Plain TS template literals, no build step, no client
 * JS. One `layout()` wraps every page with a single inline stylesheet (system font, 760px
 * column, dark-mode aware, iPad-readable, ≥44px tap targets). All user-controlled text goes
 * through `esc()`.
 */
import type { ConceptCount, NoteSummary, EssenceRow, CategoryCount } from './pkm-queries';

export interface NoteDetail {
  id: number;
  title: string;
  content: string;
  essence: string | null;
  concepts: string[];
  category: string | null;
  primary_theme: string | null;
}

/** Escape HTML metacharacters. null/undefined -> ''. */
export function esc(s: unknown): string {
  if (s === null || s === undefined) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const STYLE = `
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    max-width: 760px; margin: 0 auto; padding: 1.5rem; font-size: 17px; line-height: 1.5;
    color: #1a1a1a; background: #fbfbfa; }
  a { color: #2563eb; text-decoration: none; }
  a:hover { text-decoration: underline; }
  nav { display: flex; flex-wrap: wrap; gap: .5rem 1rem; margin-bottom: 1.5rem;
    padding-bottom: 1rem; border-bottom: 1px solid #e5e5e5; }
  nav a { display: inline-block; min-height: 44px; line-height: 44px; }
  h1 { font-size: 1.5rem; } h2 { font-size: 1.15rem; margin-top: 2rem; }
  ul { list-style: none; padding: 0; } li { padding: .4rem 0; }
  .chip { display: inline-block; padding: .2rem .6rem; margin: .15rem .2rem .15rem 0;
    background: #eef; border-radius: 999px; font-size: .85rem; }
  .essence { color: #555; font-style: italic; }
  .meta { color: #888; font-size: .85rem; }
  .card { border: 1px solid #e5e5e5; border-radius: 12px; padding: 1rem; margin: 1rem 0; }
  blockquote { border-left: 3px solid #ddd; margin: 1rem 0; padding-left: 1rem; color: #333; }
  @media (prefers-color-scheme: dark) {
    body { color: #e8e8e8; background: #1a1a1a; }
    a { color: #6ea8fe; } nav { border-color: #333; }
    .chip { background: #2a2a3a; } .essence, blockquote { color: #b8b8b8; }
    .card { border-color: #333; } .meta { color: #999; }
  }
`;

function nav(): string {
  return `<nav>
    <a href="/pkm/">Home</a>
    <a href="/pkm/categories">Categories</a>
    <a href="/pkm/concepts">Concepts</a>
    <a href="/pkm/essences">Essences</a>
    <a href="/pkm/review/today">Review</a>
    <a href="/pkm/on-this-day">On this day</a>
  </nav>`;
}

export function layout(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>${STYLE}</style>
</head><body>${nav()}${body}</body></html>`;
}

function noteLink(n: NoteSummary): string {
  const ess = n.essence ? ` <span class="essence">— ${esc(n.essence)}</span>` : '';
  const date = esc((n.created_at || '').slice(0, 10));
  return `<li><a href="/pkm/notes/${n.id}">${esc(n.title)}</a> <span class="meta">${date}</span>${ess}</li>`;
}

export function renderHome(data: {
  essences: EssenceRow[];
  topConcepts: ConceptCount[];
  categoryCounts: CategoryCount[];
  onThisDay: NoteSummary[];
  randomEssence?: EssenceRow;
  dueCount: number;
}): string {
  const concepts = data.topConcepts
    .map((c) => `<a class="chip" href="/pkm/concepts/${encodeURIComponent(c.concept)}">${esc(c.concept)} ${c.n}</a>`)
    .join('');
  const cats = data.categoryCounts
    .map((c) => `<a class="chip" href="/pkm/categories/${encodeURIComponent(c.category)}">${esc(c.category)} ${c.n}</a>`)
    .join('');
  const essences = data.essences
    .map((e) => `<li><a href="/pkm/notes/${e.id}">${esc(e.title)}</a> <span class="essence">${esc(e.essence)}</span></li>`)
    .join('');
  const otd = data.onThisDay.length
    ? `<ul>${data.onThisDay.map(noteLink).join('')}</ul>`
    : `<p class="meta">Nothing from this day in prior years.</p>`;
  const random = data.randomEssence
    ? `<div class="card"><a href="/pkm/notes/${data.randomEssence.id}">${esc(data.randomEssence.title)}</a><br><span class="essence">${esc(data.randomEssence.essence)}</span></div>`
    : '';
  const body = `<h1>Selene</h1>
    <p><a href="/pkm/review/today">${data.dueCount} notes due for review →</a></p>
    <h2>Categories</h2><div>${cats}</div>
    <h2>Top concepts</h2><div>${concepts}</div>
    <h2>A note to revisit</h2>${random}
    <h2>Recent essences</h2><ul>${essences}</ul>
    <h2>On this day</h2>${otd}`;
  return layout('Selene', body);
}

export function renderCategories(categoryCounts: CategoryCount[]): string {
  const items = categoryCounts
    .map((c) => `<li><a href="/pkm/categories/${encodeURIComponent(c.category)}">${esc(c.category)}</a> <span class="meta">${c.n}</span></li>`)
    .join('');
  return layout('Categories', `<h1>Categories</h1><ul>${items}</ul>`);
}

export function renderCategory(name: string, notes: NoteSummary[]): string {
  const body = `<h1>${esc(name)}</h1><p class="meta">${notes.length} notes</p><ul>${notes.map(noteLink).join('')}</ul>`;
  return layout(name, body);
}

export function renderConcepts(concepts: ConceptCount[]): string {
  const items = concepts
    .map((c) => `<li><a href="/pkm/concepts/${encodeURIComponent(c.concept)}">${esc(c.concept)}</a> <span class="meta">${c.n}</span></li>`)
    .join('');
  return layout('Concepts', `<h1>Concepts</h1><ul>${items}</ul>`);
}

export function renderConcept(name: string, notes: NoteSummary[], cooccurring: ConceptCount[]): string {
  const co = cooccurring
    .map((c) => `<a class="chip" href="/pkm/concepts/${encodeURIComponent(c.concept)}">${esc(c.concept)} ${c.n}</a>`)
    .join('');
  const body = `<h1>${esc(name)}</h1>
    <h2>Often appears with</h2><div>${co || '<span class="meta">—</span>'}</div>
    <h2>Notes</h2><ul>${notes.map(noteLink).join('')}</ul>`;
  return layout(name, body);
}

export function renderNote(note: NoteDetail): string {
  const chips = note.concepts
    .map((c) => `<a class="chip" href="/pkm/concepts/${encodeURIComponent(c)}">${esc(c)}</a>`)
    .join('');
  const cat = note.category
    ? `<a class="chip" href="/pkm/categories/${encodeURIComponent(note.category)}">${esc(note.category)}</a>`
    : '';
  const essence = note.essence ? `<p class="essence">${esc(note.essence)}</p>` : '';
  const theme = note.primary_theme ? `<span class="meta">theme: ${esc(note.primary_theme)}</span>` : '';
  const body = `<h1>${esc(note.title)}</h1>
    <div>${cat} ${theme}</div>
    ${essence}
    <blockquote>${esc(note.content).replace(/\n/g, '<br>')}</blockquote>
    <h2>Concepts</h2><div>${chips}</div>`;
  return layout(note.title, body);
}

export function renderEssences(essences: EssenceRow[], page: number): string {
  const items = essences
    .map((e) => `<li><a href="/pkm/notes/${e.id}">${esc(e.title)}</a> <span class="essence">${esc(e.essence)}</span></li>`)
    .join('');
  const next = essences.length > 0 ? `<p><a href="/pkm/essences?page=${page + 1}">Next →</a></p>` : '';
  const prev = page > 0 ? `<a href="/pkm/essences?page=${page - 1}">← Prev</a> ` : '';
  return layout('Essences', `<h1>Essences</h1><ul>${items}</ul><p>${prev}</p>${next}`);
}

export function renderReview(due: NoteSummary[], randomEssence?: EssenceRow): string {
  const random = randomEssence
    ? `<div class="card"><a href="/pkm/notes/${randomEssence.id}">${esc(randomEssence.title)}</a><br><span class="essence">${esc(randomEssence.essence)}</span></div>`
    : '';
  const body = `<h1>Review today</h1>${random}
    <h2>${due.length} due</h2><ul>${due.map(noteLink).join('')}</ul>`;
  return layout('Review', body);
}

export function renderOnThisDay(notes: NoteSummary[]): string {
  const list = notes.length ? `<ul>${notes.map(noteLink).join('')}</ul>` : '<p class="meta">Nothing from this day in prior years.</p>';
  return layout('On this day', `<h1>On this day</h1>${list}`);
}

export function renderError(message: string): string {
  return layout('Not found', `<h1>${esc(message)}</h1><p><a href="/pkm/">← Home</a></p>`);
}
