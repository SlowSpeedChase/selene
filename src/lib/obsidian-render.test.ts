import { renderNoteMarkdown, exportHash, RenderableNote } from './obsidian-render';

const note: RenderableNote = {
  id: 1,
  title: 'Morning pages',
  content: 'A few lines about the day.',
  created_at: '2026-05-01T08:00:00.000Z',
  primary_theme: 'reflection',
  concepts: JSON.stringify(['journaling', 'habits']),
  essence: 'Showing up daily matters more than the words.',
};

describe('exportHash', () => {
  it('is deterministic for identical rendered markdown', () => {
    const md = renderNoteMarkdown(note, ['Daily Systems']);
    expect(exportHash(md)).toBe(exportHash(md));
  });

  // THE correctness constraint: the hash must cover the parent:: block, not just the body.
  // If it covered only the body, a cluster-membership change (same body) would hash-match
  // and be skipped — re-freezing the exact parent:: edges this work exists to fix.
  it('changes when cluster membership changes even though the body is identical', () => {
    const oneCluster = renderNoteMarkdown(note, ['Daily Systems']);
    const twoClusters = renderNoteMarkdown(note, ['Daily Systems', 'Creativity & Expression']);
    expect(exportHash(oneCluster)).not.toBe(exportHash(twoClusters));
  });
});

describe('renderNoteMarkdown', () => {
  it('emits one parent:: edge per cluster the note belongs to (multi-membership)', () => {
    const md = renderNoteMarkdown(note, ['Daily Systems', 'Creativity & Expression']);
    expect(md).toContain('parent:: [[Daily Systems]]');
    expect(md).toContain('parent:: [[Creativity & Expression]]');
  });

  it('renders frontmatter, body blockquote, and essence', () => {
    const md = renderNoteMarkdown(note, []);
    expect(md).toContain('theme: reflection');
    expect(md).toContain('> A few lines about the day.');
    expect(md).toContain('*Showing up daily matters more than the words.*');
  });
});

describe('noteAlias (content-chunk node labels)', () => {
  const { noteAlias } = require('./obsidian-render') as typeof import('./obsidian-render');

  it('flattens multi-line content to one prose line', () => {
    expect(noteAlias('# Heading\n> quoted\n- bullet line')).toBe('Heading quoted bullet line');
  });

  it('truncates long content at the cap with an ellipsis', () => {
    const alias = noteAlias('word '.repeat(40), 80);
    expect(alias.length).toBeLessThanOrEqual(81); // 80 + ellipsis char
    expect(alias.endsWith('…')).toBe(true);
  });

  it('returns empty string for empty/whitespace content', () => {
    expect(noteAlias('')).toBe('');
    expect(noteAlias('   \n  ')).toBe('');
  });

  it('renderNoteMarkdown emits the alias in frontmatter with quotes escaped', () => {
    const md = renderNoteMarkdown(
      { id: 1, title: '2026-06-09', content: 'She said "do the thing" today', created_at: '2026-06-09T10:00:00Z', primary_theme: null, concepts: null, essence: null },
      []
    );
    expect(md).toContain('aliases:');
    expect(md).toContain('  - "She said \\"do the thing\\" today"');
  });

  it('renderNoteMarkdown omits the aliases block entirely when content is empty', () => {
    const md = renderNoteMarkdown(
      { id: 1, title: 'x', content: '', created_at: '2026-06-09T10:00:00Z', primary_theme: null, concepts: null, essence: null },
      []
    );
    expect(md).not.toContain('aliases:');
  });
});
