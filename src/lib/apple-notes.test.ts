import { buildAppleNotesScript } from './apple-notes';

describe('buildAppleNotesScript', () => {
  describe('find-or-create skeleton', () => {
    it('emits the osascript scaffold with find-or-create logic', () => {
      const script = buildAppleNotesScript('Note', 'body', 'replace');
      expect(script).toContain(`osascript -e 'tell application "Notes"'`);
      expect(script).toContain(`-e 'set targetNote to first note whose name is noteName'`);
      expect(script).toContain(`-e 'on error'`);
      expect(script).toContain(`-e 'make new note with properties {name:noteName, body:noteBody}'`);
      expect(script).toContain(`-e 'end try'`);
      expect(script).toContain(`-e 'end tell'`);
    });
  });

  describe('mode selects the set-body line', () => {
    it("'append' includes the <br><hr><br> separator", () => {
      const script = buildAppleNotesScript('Note', 'body', 'append');
      expect(script).toContain('set body of targetNote to body of targetNote & "<br><hr><br>" & noteBody');
    });

    it("'replace' sets the body outright and has no separator", () => {
      const script = buildAppleNotesScript('Note', 'body', 'replace');
      expect(script).toContain('set body of targetNote to noteBody');
      expect(script).not.toContain('<br><hr><br>');
    });
  });

  describe('escaping the BODY', () => {
    it('escapes a backslash in the body to \\\\', () => {
      const script = buildAppleNotesScript('Note', 'path C:\\temp', 'replace');
      expect(script).toContain('path C:\\\\temp');
    });

    it('escapes a double-quote in the body so the AppleScript literal is not broken', () => {
      const script = buildAppleNotesScript('Note', 'say "hi"', 'replace');
      // The body sits inside set noteBody to "<body>"; the inner quotes must be \"
      expect(script).toContain('set noteBody to "say \\"hi\\""');
    });

    it('escapes a newline in the body to the AppleScript \\n escape', () => {
      const script = buildAppleNotesScript('Note', 'line1\nline2', 'replace');
      expect(script).toContain('set noteBody to "line1\\nline2"');
      // No raw newline should leak into the body segment
      expect(script).not.toContain('line1\nline2');
    });

    it("escapes a single-quote in the body with the shell escape '\"'\"'", () => {
      const script = buildAppleNotesScript('Note', "don't", 'replace');
      expect(script).toContain(`set noteBody to "don'"'"'t"`);
    });
  });

  describe('escaping the NOTE NAME', () => {
    it('escapes a double-quote in the name', () => {
      const script = buildAppleNotesScript('My "Note"', 'body', 'replace');
      expect(script).toContain('set noteName to "My \\"Note\\""');
    });

    it('escapes a backslash in the name', () => {
      const script = buildAppleNotesScript('Back\\slash', 'body', 'replace');
      expect(script).toContain('set noteName to "Back\\\\slash"');
    });

    it("escapes a single-quote in the name with the shell escape '\"'\"'", () => {
      const script = buildAppleNotesScript("Chase's Note", 'body', 'replace');
      expect(script).toContain(`set noteName to "Chase'"'"'s Note"`);
    });

    it('escapes a newline in the name to the AppleScript \\n escape', () => {
      const script = buildAppleNotesScript('Line1\nLine2', 'body', 'replace');
      expect(script).toContain('set noteName to "Line1\\nLine2"');
    });
  });

  describe('regression guard', () => {
    it('leaves the constant "Selene Daily" name untouched (no-op escape)', () => {
      const script = buildAppleNotesScript('Selene Daily', 'body', 'replace');
      expect(script).toContain('set noteName to "Selene Daily"');
    });
  });
});
