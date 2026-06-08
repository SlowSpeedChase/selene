/** Extract the first fenced code block following a markdown heading that contains `heading`. */
export function extractAsciiBlock(markdown: string, heading: string): string {
  const lines = markdown.split('\n');
  const headingIdx = lines.findIndex(
    (l) => /^#{1,6}\s/.test(l) && l.toLowerCase().includes(heading.toLowerCase()),
  );
  if (headingIdx === -1) throw new Error(`Seed heading not found: "${heading}"`);
  const start = lines.findIndex((l, i) => i > headingIdx && l.trim().startsWith('```'));
  if (start === -1) throw new Error(`No code block under heading: "${heading}"`);
  const end = lines.findIndex((l, i) => i > start && l.trim().startsWith('```'));
  if (end === -1) throw new Error(`Unterminated code block under heading: "${heading}"`);
  return lines.slice(start + 1, end).join('\n').replace(/\s+$/, '');
}

const escapeHtml = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** Wrap ASCII content in a clean, high-contrast monospace page for screenshotting. */
export function buildSeedHtml(content: string, title: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    body { margin: 0; background: #ffffff; color: #111; }
    .wrap { padding: 40px; display: inline-block; }
    h1 { font: 600 28px -apple-system, system-ui, sans-serif; margin: 0 0 24px; }
    pre { font: 16px/1.35 ui-monospace, "SF Mono", Menlo, monospace; white-space: pre; margin: 0; }
  </style></head><body><div class="wrap">
    <h1>${escapeHtml(title)}</h1><pre>${escapeHtml(content)}</pre>
  </div></body></html>`;
}
