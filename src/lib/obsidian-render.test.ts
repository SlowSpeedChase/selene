import { renderNoteMarkdown, exportHash, RenderableNote } from './obsidian-render';
import { parseYourNoteSection } from './vault-feedback';

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

describe('friend:: block rendering', () => {
  const friendNote: RenderableNote = {
    id: 1,
    title: 'Morning pages',
    content: 'A few lines about the day.',
    created_at: '2026-05-01T08:00:00.000Z',
    primary_theme: 'reflection',
    concepts: JSON.stringify(['journaling', 'habits']),
    essence: null,
  };

  it('injects friend:: lines when friendBasenames are provided', () => {
    const md = renderNoteMarkdown(
      friendNote,
      [],   // parentClusters
      [],   // appliedFeedback
      ['2025-11-02-sentence-diagramming', '2025-11-03-running-notes']
    );
    expect(md).toContain('friend:: [[2025-11-02-sentence-diagramming]]');
    expect(md).toContain('friend:: [[2025-11-03-running-notes]]');
  });

  it('friend block appears before the Your note heading', () => {
    const md = renderNoteMarkdown(
      friendNote,
      [],
      [],
      ['2025-11-02-sentence-diagramming']
    );
    const friendPos = md.indexOf('friend::');
    const yourNotePos = md.indexOf('## ✍️ Your note');
    expect(friendPos).toBeGreaterThan(-1);
    expect(friendPos).toBeLessThan(yourNotePos);
  });

  it('renders cleanly with no friend basenames (default param)', () => {
    const md = renderNoteMarkdown(friendNote, []);
    expect(md).not.toContain('friend::');
  });
});

describe('frontmatter fields — essence and updated', () => {
  it('includes essence in frontmatter when present', () => {
    const md = renderNoteMarkdown(
      { ...note, essence: 'a thought', processed_at: null },
      []
    );
    expect(md).toMatch(/^essence: "a thought"$/m);
  });

  it('omits essence from frontmatter when essence is null', () => {
    const md = renderNoteMarkdown(
      { ...note, essence: null, processed_at: null },
      []
    );
    expect(md).not.toMatch(/^essence: /m);
  });

  it('sets updated from processed_at when present', () => {
    const md = renderNoteMarkdown(
      { ...note, processed_at: '2026-05-15T10:00:00.000Z' },
      []
    );
    expect(md).toMatch(/^updated: 2026-05-15$/m);
  });

  it('falls back to created_at date for updated when processed_at is null', () => {
    const md = renderNoteMarkdown(
      { ...note, processed_at: null },
      []
    );
    // note.created_at is 2026-05-01T08:00:00.000Z → date portion is 2026-05-01
    expect(md).toMatch(/^updated: 2026-05-01$/m);
  });

  it('escapes double quotes in essence for YAML', () => {
    const md = renderNoteMarkdown(
      { ...note, essence: 'She said "hello"', processed_at: null },
      []
    );
    expect(md).toMatch(/^essence: "She said \\"hello\\""$/m);
  });
});

describe('feedback loop rendering', () => {
  const fbNote: RenderableNote = {
    id: 42, title: 'T', content: 'body', created_at: '2026-06-01T00:00:00.000Z',
    primary_theme: 'theme', concepts: null, essence: null,
  };

  it('emits selene_id in frontmatter', () => {
    expect(renderNoteMarkdown(fbNote, [])).toMatch(/^selene_id: 42$/m);
  });

  it('always ends with an empty Your-note section (the invitation)', () => {
    const md = renderNoteMarkdown(fbNote, []);
    expect(md.trimEnd().endsWith('## ✍️ Your note')).toBe(true);
  });

  it('renders applied feedback as blockquote + applied-date line', () => {
    const md = renderNoteMarkdown(fbNote, [], [
      { feedback_text: 'a skill I enjoy\nremember it', applied_at: '2026-06-10T12:00:00.000Z' },
    ]);
    expect(md).toContain('> a skill I enjoy\n> remember it\n> — applied 2026-06-10 ✓');
  });

  it('round-trips with the parser: applied blocks are not re-ingested as new feedback', () => {
    const md = renderNoteMarkdown(fbNote, [], [
      { feedback_text: 'old', applied_at: '2026-06-10T12:00:00.000Z' },
    ]);
    expect(parseYourNoteSection(md)).toEqual({ hasSection: true, newFeedback: null });
  });
});
