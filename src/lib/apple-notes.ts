// @map purpose: Single shared primitive for find-or-create + set/append an Apple Note body via osascript
import { execSync } from 'child_process';

/**
 * Escape a string for safe interpolation into the osascript scaffold below.
 *
 * The scaffold runs as a single shell command of the form
 *   osascript -e 'tell application "Notes"' -e 'set noteBody to "<value>"' ...
 * so an interpolated value must survive TWO layers:
 *   1. The AppleScript string literal it sits inside ("...") — backslash and
 *      double-quote must be backslash-escaped, and a real newline must become
 *      the AppleScript escape \n.
 *   2. The surrounding shell single-quotes (osascript -e '...') — a literal
 *      single-quote must be emitted as '"'"' (close-quote, quoted-quote, reopen).
 *
 * ORDER IS LOAD-BEARING — do not reorder:
 *   - backslash first, so backslashes introduced by later steps (\" and \n) are
 *     not doubled.
 *   - double-quote BEFORE single-quote, because the single-quote shell-escape
 *     ('"'"') itself introduces double-quotes that must NOT be AppleScript-escaped.
 */
function escapeForAppleScript(value: string): string {
  return value
    .replace(/\\/g, '\\\\') // 1. backslash → \\  (must be first)
    .replace(/"/g, '\\"') // 2. double-quote → \"  (before single-quote step)
    .replace(/'/g, "'\"'\"'") // 3. single-quote → '"'"'  (shell-level escape)
    .replace(/\n/g, '\\n'); // 4. newline → \n  (AppleScript escape)
}

/**
 * Build the `osascript` shell command that finds (or creates) the note named
 * `noteName` in Notes and either replaces or appends to its body.
 *
 * Returns the FULL shell command string (the same form the callers used to
 * hand-roll) — it is meant to be passed straight to execSync. Only the injected
 * name and body are escaped; the static AppleScript lines are emitted verbatim.
 *
 * - mode 'replace': `set body of targetNote to noteBody`
 * - mode 'append':  `set body of targetNote to body of targetNote & "<br><hr><br>" & noteBody`
 *
 * In both modes a missing note is created with the given name and body.
 */
export function buildAppleNotesScript(noteName: string, body: string, mode: 'replace' | 'append'): string {
  const escapedName = escapeForAppleScript(noteName);
  const escapedBody = escapeForAppleScript(body);

  const setBodyLine =
    mode === 'append'
      ? `set body of targetNote to body of targetNote & "<br><hr><br>" & noteBody`
      : `set body of targetNote to noteBody`;

  return `osascript -e 'tell application "Notes"' \
    -e 'set noteName to "${escapedName}"' \
    -e 'set noteBody to "${escapedBody}"' \
    -e 'try' \
    -e 'set targetNote to first note whose name is noteName' \
    -e '${setBodyLine}' \
    -e 'on error' \
    -e 'make new note with properties {name:noteName, body:noteBody}' \
    -e 'end try' \
    -e 'end tell'`;
}

/**
 * Find-or-create the Apple Note named `noteName` and set (replace) or append its
 * body. Defaults to 'replace'. Side-effecting thin wrapper around
 * buildAppleNotesScript + execSync.
 */
export function upsertAppleNote(noteName: string, body: string, opts?: { mode?: 'replace' | 'append' }): void {
  const script = buildAppleNotesScript(noteName, body, opts?.mode ?? 'replace');
  execSync(script, { timeout: 15000, stdio: 'pipe' });
}
