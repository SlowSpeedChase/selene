import { describe, it, expect } from 'vitest';
import { parseFolioTitle, buildFeedbackFilename, buildFeedbackContent } from './folio-feedback';

describe('parseFolioTitle', () => {
  it('parses a valid folio title into projectDir and filePath', () => {
    const result = parseFolioTitle('Folio: /Users/chase/selene-docs :: src/server.ts');
    expect(result).not.toBeNull();
    expect(result!.projectDir).toBe('/Users/chase/selene-docs');
    expect(result!.filePath).toBe('src/server.ts');
  });

  it('returns null for a non-folio title', () => {
    expect(parseFolioTitle('E-Ink: 2026-05-25 kindle journal')).toBeNull();
    expect(parseFolioTitle('Some random note')).toBeNull();
    expect(parseFolioTitle('')).toBeNull();
  });

  it('handles projectDir and filePath with spaces trimmed', () => {
    const result = parseFolioTitle('Folio: /Users/chase/my project  ::  docs/readme.md');
    expect(result).not.toBeNull();
    expect(result!.projectDir).toBe('/Users/chase/my project');
    expect(result!.filePath).toBe('docs/readme.md');
  });
});

describe('buildFeedbackFilename', () => {
  it('builds filename from date and simple file path', () => {
    const result = buildFeedbackFilename('2026-05-25T14:32:00', 'src/server.ts');
    expect(result).toBe('2026-05-25-src-server-kindle.md');
  });

  it('builds filename from nested path with multiple separators', () => {
    const result = buildFeedbackFilename('2026-05-25T09:00:00', 'docs/plans/feature.md');
    expect(result).toBe('2026-05-25-docs-plans-feature-kindle.md');
  });

  it('strips only the final extension', () => {
    const result = buildFeedbackFilename('2026-01-15T00:00:00', 'src/lib/my.util.ts');
    expect(result).toBe('2026-01-15-src-lib-my.util-kindle.md');
  });
});

describe('buildFeedbackContent', () => {
  const baseNote = {
    id: 42,
    title: 'Folio: /Users/chase/selene-docs :: src/server.ts',
    content: 'This is the OCR-transcribed handwriting from the Kindle Scribe.',
    created_at: '2026-05-25T14:32:00',
  };

  it('produces correct frontmatter and body when concepts and primary_theme are present', () => {
    const result = buildFeedbackContent(
      baseNote,
      'src/server.ts',
      ['error handling', 'async patterns'],
      'error handling'
    );
    expect(result).toContain('source: kindle-scribe');
    expect(result).toContain('doc: src/server.ts');
    expect(result).toContain('date: 2026-05-25T14:32:00');
    expect(result).toContain('concepts: ["error handling", "async patterns"]');
    expect(result).toContain('primary_theme: error handling');
    expect(result).toContain(baseNote.content);
    // Frontmatter delimiters
    const lines = result.split('\n');
    expect(lines[0]).toBe('---');
    expect(lines.filter(l => l === '---').length).toBe(2);
  });

  it('omits primary_theme line when primary_theme is null', () => {
    const result = buildFeedbackContent(baseNote, 'src/server.ts', [], null);
    expect(result).not.toContain('primary_theme');
  });

  it('omits primary_theme line when primary_theme is empty string', () => {
    const result = buildFeedbackContent(baseNote, 'src/server.ts', [], '');
    expect(result).not.toContain('primary_theme');
  });

  it('renders empty concepts as an empty array', () => {
    const result = buildFeedbackContent(baseNote, 'src/server.ts', [], null);
    expect(result).toContain('concepts: []');
  });

  it('includes the note body after the closing frontmatter delimiter', () => {
    const result = buildFeedbackContent(
      baseNote,
      'src/server.ts',
      [],
      null
    );
    const closingFence = result.indexOf('---', result.indexOf('---') + 3);
    const body = result.slice(closingFence + 3).trimStart();
    expect(body).toBe(baseNote.content);
  });
});
