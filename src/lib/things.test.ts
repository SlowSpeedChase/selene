import assert from 'assert';

async function runTests() {
  const things = await import('./things');

  // Test 1: Module exports expected functions
  {
    assert.strictEqual(typeof things.getTasksFromProject, 'function', 'getTasksFromProject exported');
    assert.strictEqual(typeof things.updateTaskNotes, 'function', 'updateTaskNotes exported');
    assert.strictEqual(typeof things.addTagToTask, 'function', 'addTagToTask exported');
    assert.strictEqual(typeof things.buildAppleScript, 'function', 'buildAppleScript exported');
    console.log('  ✓ Things bridge exports all required functions');
  }

  // Test 2: buildAppleScript produces valid AppleScript string
  {
    const script = things.buildAppleScript(`
      tell application "Things3"
        name of first to do
      end tell
    `);
    assert.ok(script.includes('Things3'), 'Script references Things3');
    console.log('  ✓ buildAppleScript produces valid string');
  }

  console.log('\nAll things bridge tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
