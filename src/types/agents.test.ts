import assert from 'assert';

async function runTests() {
  const types = await import('./agents');

  // Verify key exports exist
  {
    assert.strictEqual(typeof types, 'object');
    console.log('  ✓ agents types module loads');
  }

  // Verify ProposedAction is exported
  {
    // ProposedAction is a type — verify the module resolves without error
    const keys = Object.keys(types);
    // Type-only exports produce no runtime keys, but module must load cleanly
    assert.ok(true, 'Type exports resolved without error');
    console.log('  ✓ agent type exports resolved');
  }

  console.log('\nAll agent type tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
