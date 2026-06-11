import { parseYourNoteSection, extractSeleneId, YOUR_NOTE_HEADING } from './vault-feedback';

describe('parseYourNoteSection', () => {
  it('returns hasSection=false when the heading is absent', () => {
    expect(parseYourNoteSection('# Title\n\nbody')).toEqual({ hasSection: false, newFeedback: null });
  });

  it('empty section -> no feedback', () => {
    const md = `# T\n\n${YOUR_NOTE_HEADING}\n`;
    expect(parseYourNoteSection(md)).toEqual({ hasSection: true, newFeedback: null });
  });

  it('plain text in the section is new feedback (trimmed, multi-line preserved)', () => {
    const md = `# T\n\n${YOUR_NOTE_HEADING}\n\nThis is a skill I enjoy.\nRemember it.\n`;
    expect(parseYourNoteSection(md).newFeedback).toBe('This is a skill I enjoy.\nRemember it.');
  });

  it('blockquote lines (applied history) are NOT feedback', () => {
    const md = `${YOUR_NOTE_HEADING}\n\n> old feedback\n> — applied 2026-06-10 ✓\n`;
    expect(parseYourNoteSection(md).newFeedback).toBeNull();
  });

  it('mixed: plain text below an applied block is new feedback', () => {
    const md = `${YOUR_NOTE_HEADING}\n\n> old\n> — applied 2026-06-10 ✓\n\nnewer thought\n`;
    expect(parseYourNoteSection(md).newFeedback).toBe('newer thought');
  });

  it('whitespace-only section -> no feedback', () => {
    const md = `${YOUR_NOTE_HEADING}\n   \n\t\n`;
    expect(parseYourNoteSection(md).newFeedback).toBeNull();
  });

  it('stops at the next ## heading (section is bounded)', () => {
    const md = `${YOUR_NOTE_HEADING}\nfeedback here\n## Other\nnot feedback`;
    expect(parseYourNoteSection(md).newFeedback).toBe('feedback here');
  });
});

describe('extractSeleneId', () => {
  it('reads selene_id from frontmatter', () => {
    expect(extractSeleneId('---\ntitle: "x"\nselene_id: 42\ndate: 2026-06-10\n---\n')).toBe(42);
  });
  it('returns null when absent', () => {
    expect(extractSeleneId('---\ntitle: "x"\n---\n')).toBeNull();
  });
});
