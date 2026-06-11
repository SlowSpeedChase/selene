import {
  clusterNoteFilename,
  buildParentFields,
  buildClusterNote,
  buildFriendFields,
} from './constellation';

describe('clusterNoteFilename', () => {
  it('passes wikilink-safe category names through unchanged (incl. &)', () => {
    expect(clusterNoteFilename('Relationships & Social')).toBe('Relationships & Social');
    expect(clusterNoteFilename('Projects & Tech')).toBe('Projects & Tech');
  });
  it('replaces wikilink-breaking chars ([ ] / \\ : # ^ |) with a space and collapses', () => {
    expect(clusterNoteFilename('AI / Metadata Tools')).toBe('AI Metadata Tools');
    expect(clusterNoteFilename('[[weird]] / name')).toBe('weird name');
  });
  it('does not lowercase (names are human-facing node labels)', () => {
    expect(clusterNoteFilename('Health & Body')).toBe('Health & Body');
  });
  it('falls back to a non-empty basename when everything is stripped', () => {
    expect(clusterNoteFilename('///').length).toBeGreaterThan(0);
    expect(clusterNoteFilename('///')).toBe('cluster');
  });
});

describe('buildParentFields', () => {
  it('emits one parent:: line per cluster (multi-membership)', () => {
    expect(buildParentFields(['Relationships & Social', 'Health & Body'])).toBe(
      'parent:: [[Relationships & Social]]\nparent:: [[Health & Body]]'
    );
  });
  it('returns empty string when a note belongs to no cluster', () => {
    expect(buildParentFields([])).toBe('');
  });
  it('passes names through clusterNoteFilename so links resolve', () => {
    expect(buildParentFields(['AI / Tools'])).toBe('parent:: [[AI Tools]]');
  });
});

describe('buildFriendFields', () => {
  it('returns empty string for empty input', () => {
    expect(buildFriendFields([])).toBe('');
  });

  it('emits one friend:: line for a single basename', () => {
    expect(buildFriendFields(['2025-11-01-grammar-intuition']))
      .toBe('friend:: [[2025-11-01-grammar-intuition]]');
  });

  it('emits one line per basename, joined by newline', () => {
    expect(buildFriendFields(['2025-11-01-foo', '2025-11-02-bar']))
      .toBe('friend:: [[2025-11-01-foo]]\nfriend:: [[2025-11-02-bar]]');
  });
});

describe('buildClusterNote', () => {
  it('renders a cluster index note with type + title, no parent when root', () => {
    const md = buildClusterNote({ name: 'Relationships & Social' });
    expect(md).toContain('type: cluster');
    expect(md).toContain('# Relationships & Social');
    expect(md).not.toContain('parent::');
  });
  it('emits parent:: when the cluster has a parent (future hierarchy)', () => {
    const md = buildClusterNote({ name: 'Dating' }, 'Relationships & Social');
    expect(md).toContain('parent:: [[Relationships & Social]]');
  });
});
