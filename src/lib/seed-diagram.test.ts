import { extractAsciiBlock, buildSeedHtml } from './seed-diagram';

describe('extractAsciiBlock', () => {
  const md = [
    '## 1. System Architecture Overview',
    '',
    '```',
    'BOX A --> BOX B',
    '```',
    '',
    '## 2. Other',
    '```',
    'unrelated',
    '```',
  ].join('\n');

  it('returns the fenced block under the requested heading', () => {
    expect(extractAsciiBlock(md, 'System Architecture Overview')).toBe('BOX A --> BOX B');
  });

  it('throws a clear error when the heading is absent', () => {
    expect(() => extractAsciiBlock(md, 'Nope')).toThrow(/heading not found/i);
  });
});

describe('buildSeedHtml', () => {
  it('embeds the content in a monospace <pre> and escapes HTML', () => {
    const html = buildSeedHtml('a --> b <tag>', 'Title');
    expect(html).toContain('<pre');
    expect(html).toContain('a --&gt; b &lt;tag&gt;');
    expect(html).toContain('Title');
  });
});
