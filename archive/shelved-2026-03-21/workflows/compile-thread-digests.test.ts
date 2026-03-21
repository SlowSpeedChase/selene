import assert from 'assert';

async function runTests() {
  const { buildDigestPrompt } = await import('./compile-thread-digests');

  // Test 1: Prompt includes thread name, summary, and note essences
  {
    const prompt = buildDigestPrompt(
      'ADHD Systems',
      'Exploring ADHD coping strategies.',
      'Need structure without rigidity.',
      [
        { essence: 'Tried time-blocking but found it too rigid.' },
        { essence: 'Body doubling works well for deep work sessions.' },
      ]
    );
    assert.ok(prompt.includes('ADHD Systems'), 'should include thread name');
    assert.ok(prompt.includes('Exploring ADHD'), 'should include summary');
    assert.ok(prompt.includes('time-blocking'), 'should include first essence');
    assert.ok(prompt.includes('Body doubling'), 'should include second essence');
    console.log('  \u2713 digest prompt includes all context');
  }

  // Test 2: Prompt handles null summary and why
  {
    const prompt = buildDigestPrompt(
      'New Thread',
      null,
      null,
      [{ essence: 'First note essence.' }]
    );
    assert.ok(prompt.includes('New Thread'), 'should include name');
    assert.ok(prompt.includes('(none)'), 'should show (none) for null fields');
    assert.ok(prompt.includes('First note essence'), 'should include essence');
    console.log('  \u2713 digest prompt handles null summary and why');
  }

  console.log('\nAll compile-thread-digests tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
