/**
 * Obsidian feedback loop ("Your note") — pure parsing + DI'd scan/ingest helpers.
 *
 * The vault's exported notes end with a `## ✍️ Your note` section. The PROTOCOL (mirrors
 * obsidian-render.ts, which renders the other side): blockquoted lines in the section are
 * Selene's applied-feedback history; any other non-whitespace text is NEW author feedback.
 * Feedback is precious (human words) → facts.note_feedback, keyed on captured_notes.id
 * (total + stable: facts.db is never rebuilt). Design:
 * docs/plans/2026-06-10-obsidian-feedback-loop-design.md
 *
 * Takes an explicit `db` (no module singleton) so it is unit-testable via makeTwoFileTestDb,
 * matching obsidian-render.ts / note-state.ts.
 */

export const YOUR_NOTE_HEADING = '## ✍️ Your note';

export interface ParsedSection {
  hasSection: boolean;
  newFeedback: string | null;
}

/** Apply the section protocol to a note file's markdown. */
export function parseYourNoteSection(markdown: string): ParsedSection {
  const lines = markdown.split('\n');
  const start = lines.findIndex((l) => l.trim() === YOUR_NOTE_HEADING);
  if (start === -1) return { hasSection: false, newFeedback: null };

  const section: string[] = [];
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('## ')) break;
    section.push(lines[i]);
  }
  const fresh = section
    .filter((l) => !l.trimStart().startsWith('>'))
    .join('\n')
    .trim();
  return { hasSection: true, newFeedback: fresh.length > 0 ? fresh : null };
}

/** The note's captured_notes.id from the `selene_id:` frontmatter line. */
export function extractSeleneId(markdown: string): number | null {
  const m = markdown.match(/^selene_id: (\d+)$/m);
  return m ? parseInt(m[1], 10) : null;
}
