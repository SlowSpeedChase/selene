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

  it('consumes to EOF: a ## heading inside the section is PART of the feedback (no silent word loss)', () => {
    // The canonical render guarantees the Your-note section is the document TAIL, so a `## ` break
    // protects nothing — it only drops everything the author wrote below their own subheading.
    const md = `${YOUR_NOTE_HEADING}\nfeedback here\n## a subheading\nmore words below it`;
    expect(parseYourNoteSection(md).newFeedback).toBe(
      'feedback here\n## a subheading\nmore words below it'
    );
  });

  it('multi-line feedback containing a ## heading round-trips intact through parse', () => {
    const feedback = 'first thought\n\n## a subheading\n\nsecond thought under it';
    const md = `# T\n\n${YOUR_NOTE_HEADING}\n\n${feedback}\n`;
    expect(parseYourNoteSection(md).newFeedback).toBe(feedback);
  });

  it('CRLF document parses identically to LF (no \\r in feedback_text)', () => {
    const lf = `# T\n\n${YOUR_NOTE_HEADING}\n\nThis is a skill I enjoy.\nRemember it.\n`;
    const crlf = lf.replace(/\n/g, '\r\n');
    expect(parseYourNoteSection(crlf)).toEqual(parseYourNoteSection(lf));
    expect(parseYourNoteSection(crlf).newFeedback).toBe('This is a skill I enjoy.\nRemember it.');
  });
});

describe('extractSeleneId', () => {
  it('reads selene_id from frontmatter', () => {
    expect(extractSeleneId('---\ntitle: "x"\nselene_id: 42\ndate: 2026-06-10\n---\n')).toBe(42);
  });
  it('returns null when absent', () => {
    expect(extractSeleneId('---\ntitle: "x"\n---\n')).toBeNull();
  });
  it('ignores selene_id in the BODY after frontmatter (no mis-attribution)', () => {
    expect(extractSeleneId('---\ntitle: "x"\n---\n\nbody mentions\nselene_id: 12\nin passing\n')).toBeNull();
  });
  it('ignores selene_id when the document has no frontmatter at all', () => {
    expect(extractSeleneId('# hand-made note\nselene_id: 12\n')).toBeNull();
  });
  it('tolerates extra whitespace around the id inside frontmatter', () => {
    expect(extractSeleneId('---\ntitle: "x"\nselene_id:  42 \n---\n')).toBe(42);
  });
  it('reads frontmatter in a CRLF document', () => {
    expect(extractSeleneId('---\r\ntitle: "x"\r\nselene_id: 42\r\n---\r\n')).toBe(42);
  });
});
