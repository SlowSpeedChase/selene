import assert from 'assert';

async function runTests() {
  const { buildEssencePrompt } = await import('../lib/prompts');

  // Test 1: Prompt includes title, content, and existing concepts
  {
    const prompt = buildEssencePrompt(
      'Morning Reflection',
      'Woke up feeling scattered. Need to find a system for tracking tasks.',
      '["task management", "morning routine"]',
      'productivity'
    );
    assert.ok(prompt.includes('Morning Reflection'), 'should include title');
    assert.ok(prompt.includes('scattered'), 'should include content');
    assert.ok(prompt.includes('task management'), 'should include concepts');
    assert.ok(prompt.includes('productivity'), 'should include theme');
    console.log('  ✓ essence prompt includes all context');
  }

  // Test 2: Prompt works with null concepts and null theme
  {
    const prompt = buildEssencePrompt('Quick Note', 'Just a thought.', null, null);
    assert.ok(prompt.includes('Quick Note'), 'should include title');
    assert.ok(prompt.includes('Just a thought'), 'should include content');
    // Should not crash or include "null"
    assert.ok(!prompt.includes('null'), 'should not include literal null');
    console.log('  ✓ essence prompt handles null concepts and theme');
  }

  // Test 3: Prompt handles malformed JSON in concepts
  {
    const prompt = buildEssencePrompt('Bad JSON', 'Content here.', 'not valid json', 'test');
    assert.ok(prompt.includes('Bad JSON'), 'should include title');
    assert.ok(prompt.includes('Content here'), 'should include content');
    // Should not crash
    console.log('  ✓ essence prompt handles malformed JSON concepts');
  }

  console.log('\nAll process-llm essence tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
