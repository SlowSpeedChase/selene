const fs = require('fs');
const path = require('path');

const DOCS = '/Users/chaseeasterling/selene/docs';
const OUT_DIR = '/Users/chaseeasterling/folio/reports';
const OUT = path.join(OUT_DIR, 'selene-complete-user-guide.md');

const sections = [
  { title: 'Daily Guide Overview', file: path.join(DOCS, 'USER-EXPERIENCE.md'), anchor: 'daily-guide-overview' },
  { title: 'Capturing Notes',      file: path.join(DOCS, 'guides/features/capturing-notes.md'),    anchor: 'capturing-notes' },
  { title: 'Obsidian Library',     file: path.join(DOCS, 'guides/features/obsidian-library.md'),    anchor: 'obsidian-library' },
  { title: 'Daily Digest',         file: path.join(DOCS, 'guides/features/daily-digest.md'),        anchor: 'daily-digest' },
  { title: 'Folio Delivery',       file: path.join(DOCS, 'guides/features/folio-delivery.md'),      anchor: 'folio-delivery' },
  { title: 'Agent Enrichments',    file: path.join(DOCS, 'guides/features/agent-enrichments.md'),   anchor: 'agent-enrichments' },
];

// filename (any path form) -> in-document anchor
const linkMap = [
  ['guides/features/capturing-notes.md', '#capturing-notes'],
  ['guides/features/obsidian-library.md', '#obsidian-library'],
  ['guides/features/daily-digest.md', '#daily-digest'],
  ['guides/features/folio-delivery.md', '#folio-delivery'],
  ['guides/features/agent-enrichments.md', '#agent-enrichments'],
  ['capturing-notes.md', '#capturing-notes'],
  ['obsidian-library.md', '#obsidian-library'],
  ['daily-digest.md', '#daily-digest'],
  ['folio-delivery.md', '#folio-delivery'],
  ['agent-enrichments.md', '#agent-enrichments'],
];

function processBody(raw, title) {
  // Drop the original first H1 line (and a following blank line), prepend controlled section title.
  const lines = raw.split('\n');
  let i = 0;
  while (i < lines.length && lines[i].trim() === '') i++;
  if (i < lines.length && /^#\s/.test(lines[i])) {
    i++;
    if (i < lines.length && lines[i].trim() === '') i++;
  }
  let body = lines.slice(i).join('\n');

  // Rewrite known cross-file links to anchors.
  for (const [from, to] of linkMap) {
    body = body.split('](' + from + ')').join('](' + to + ')');
  }
  // Delink any remaining markdown links pointing at .md files (keep the label text only).
  body = body.replace(/\[([^\]]+)\]\([^)]*\.md\)/g, '$1');

  return '# ' + title + '\n\n' + body.trim() + '\n';
}

let out = '';
out += '# Selene — Complete User Guide\n\n';
out += '*The consolidated daily guide plus all five feature guides, in one document. Tap a contents entry to jump to that section.*\n\n';
out += '## Contents\n\n';
for (const s of sections) out += `- [${s.title}](#${s.anchor})\n`;
out += '\n';

for (const s of sections) {
  const raw = fs.readFileSync(s.file, 'utf-8');
  out += '\n---\n\n' + processBody(raw, s.title) + '\n';
}

fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT, out);
console.log('Wrote ' + OUT + ' (' + out.length + ' bytes, ' + out.split('\n').length + ' lines)');
