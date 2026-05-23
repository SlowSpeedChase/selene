import { execSync } from 'child_process';
import { logger } from './logger';

const thingsLogger = logger.child({ module: 'things' });

export interface ThingsTask {
  id: string;
  name: string;
  notes: string;
  tags: string[];
  projectName: string;
  dueDate: string | null;
  completed: boolean;
}

export function buildAppleScript(body: string): string {
  return body.trim();
}

function runAppleScriptFile(script: string): string {
  const lines = script.trim().split('\n');
  const args = lines.map((line) => `-e '${line.replace(/'/g, "'\"'\"'")}'`).join(' ');
  try {
    return execSync(`osascript ${args}`, {
      timeout: 30000,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (err) {
    const error = err as Error & { stderr?: string };
    thingsLogger.error({ err: error.message, stderr: error.stderr }, 'AppleScript failed');
    throw new Error(`Things AppleScript failed: ${error.message}`);
  }
}

export function getTasksFromProject(projectName: string): ThingsTask[] {
  thingsLogger.info({ projectName }, 'Fetching tasks from Things project');

  // Returns tab-separated fields: id\tname\tnotes\ttags\n
  const script = `
tell application "Things3"
  set output to ""
  set theProject to first project whose name is "${projectName.replace(/"/g, '\\"')}"
  repeat with t in to dos of theProject
    set taskId to id of t
    set taskName to name of t
    set taskNotes to notes of t
    set taskTags to tag names of t
    set tagStr to ""
    repeat with tg in taskTags
      set tagStr to tagStr & tg & ","
    end repeat
    set output to output & taskId & "\t" & taskName & "\t" & taskNotes & "\t" & tagStr & "\n"
  end repeat
  return output
end tell
  `.trim();

  try {
    const raw = runAppleScriptFile(script);
    if (!raw) return [];

    return raw
      .split('\n')
      .filter((line) => line.trim())
      .map((line) => {
        const [id, name, notes, tagsRaw] = line.split('\t');
        const tags = tagsRaw
          ? tagsRaw.split(',').map((t) => t.trim()).filter(Boolean)
          : [];
        return { id: id ?? '', name: name ?? '', notes: notes ?? '', tags, projectName, dueDate: null, completed: false };
      });
  } catch (err) {
    thingsLogger.error({ err, projectName }, 'Failed to get tasks from project');
    return [];
  }
}

export function updateTaskNotes(taskId: string, notes: string): boolean {
  thingsLogger.info({ taskId }, 'Updating task notes');

  const escapedNotes = notes.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const script = `
tell application "Things3"
  set t to to do id "${taskId}"
  set notes of t to "${escapedNotes}"
end tell
  `.trim();

  try {
    runAppleScriptFile(script);
    thingsLogger.info({ taskId }, 'Task notes updated');
    return true;
  } catch (err) {
    thingsLogger.error({ err, taskId }, 'Failed to update task notes');
    return false;
  }
}

export function addTagToTask(taskId: string, tagName: string): boolean {
  thingsLogger.info({ taskId, tagName }, 'Adding tag to task');

  const script = `
tell application "Things3"
  set t to to do id "${taskId}"
  set existing to tag names of t
  if "${tagName.replace(/"/g, '\\"')}" is not in existing then
    set tag names of t to existing & {"${tagName.replace(/"/g, '\\"')}"}
  end if
end tell
  `.trim();

  try {
    runAppleScriptFile(script);
    thingsLogger.info({ taskId, tagName }, 'Tag added');
    return true;
  } catch (err) {
    thingsLogger.error({ err, taskId, tagName }, 'Failed to add tag');
    return false;
  }
}
