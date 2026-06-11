import { redirectSeleneSingleton } from '../lib/test-two-file-db';

// eink-ingest imports the ../lib barrel + ./ingest, which open the db singleton on import.
// Redirect that singleton to throwaway temp files BEFORE importing the module-under-test so
// this pure-parser test never touches a real DB. (This file was authored for vitest and never
// actually ran under any runner; converted to jest — vitest's describe/it/expect are jest globals.)
const { restore } = redirectSeleneSingleton('selene-eink-ingest-test-');

import { parseFolioMetadata } from './eink-ingest';

afterAll(() => restore());

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

  it('returns null for filename with empty decoded segments', () => {
    // folio______ has empty parts[1] and parts[2]
    expect(parseFolioMetadata('folio______original.pdf')).toBeNull();
  });
});
