import { describe, it, expect } from 'vitest';
import { parseFolioMetadata } from './eink-ingest';

describe('parseFolioMetadata', () => {
  it('returns null for a regular notebook filename', () => {
    expect(parseFolioMetadata('My Notebook.pdf')).toBeNull();
    expect(parseFolioMetadata('2026-05-25-notes.pdf')).toBeNull();
  });

  it('decodes projectDir and filePath from a folio-prefixed filename', () => {
    const projectDir = '/Users/chaseeasterling/folio';
    const filePath = 'src/server.ts';
    const encodedProject = Buffer.from(projectDir).toString('base64url');
    const encodedFile = Buffer.from(filePath).toString('base64url');
    const filename = `folio__${encodedProject}__${encodedFile}__src-server.ts.pdf`;

    const result = parseFolioMetadata(filename);
    expect(result).not.toBeNull();
    expect(result!.projectDir).toBe(projectDir);
    expect(result!.filePath).toBe(filePath);
  });

  it('returns null if fewer than 4 __ segments', () => {
    expect(parseFolioMetadata('folio__onlyone.pdf')).toBeNull();
    expect(parseFolioMetadata('folio__aaa__bbb.pdf')).toBeNull();
  });
});
