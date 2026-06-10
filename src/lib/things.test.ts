import assert from 'assert';
import * as things from './things';

describe('things', () => {
  it('exports all required functions', () => {
    assert.strictEqual(typeof things.getTasksFromProject, 'function', 'getTasksFromProject exported');
    assert.strictEqual(typeof things.updateTaskNotes, 'function', 'updateTaskNotes exported');
    assert.strictEqual(typeof things.addTagToTask, 'function', 'addTagToTask exported');
    assert.strictEqual(typeof things.buildAppleScript, 'function', 'buildAppleScript exported');
  });

  it('buildAppleScript produces valid string', () => {
    const script = things.buildAppleScript(`
      tell application "Things3"
        name of first to do
      end tell
    `);
    assert.ok(script.includes('Things3'), 'Script references Things3');
  });
});
