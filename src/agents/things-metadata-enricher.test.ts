import assert from 'assert';

async function runTests() {
  const { ThingsMetadataEnricher, buildEnrichmentPrompt, parseOllamaResponse } = await import('./things-metadata-enricher');

  // Test 1: Agent exports correctly
  {
    const agent = new ThingsMetadataEnricher('Test Project');
    assert.strictEqual(agent.name, 'things-metadata-enricher', 'Name is correct');
    assert.ok(agent.allowedActionTypes.includes('things.update_notes'), 'Allows update_notes');
    assert.ok(agent.allowedActionTypes.includes('things.add_tag'), 'Allows add_tag');
    console.log('  ✓ ThingsMetadataEnricher has correct name and allowed action types');
  }

  // Test 2: buildEnrichmentPrompt includes task name and related notes
  {
    const prompt = buildEnrichmentPrompt('Doctor appointment', 'Recent notes about health checks and insurance');
    assert.ok(prompt.includes('Doctor appointment'), 'Prompt includes task name');
    assert.ok(prompt.includes('Recent notes about health checks'), 'Prompt includes related notes');
    console.log('  ✓ Enrichment prompt includes task name and related notes');
  }

  // Test 3: parseOllamaResponse handles valid JSON
  {
    const response = '{"tags": ["health", "admin"], "notes": "Annual checkup scheduling"}';
    const parsed = parseOllamaResponse(response);
    assert.deepStrictEqual(parsed?.tags, ['health', 'admin'], 'Tags parsed');
    assert.strictEqual(parsed?.notes, 'Annual checkup scheduling', 'Notes parsed');
    console.log('  ✓ Ollama response parsing works');
  }

  // Test 4: parseOllamaResponse handles malformed response gracefully
  {
    const result = parseOllamaResponse('not json at all');
    assert.strictEqual(result, null, 'Returns null for malformed response');
    console.log('  ✓ Malformed Ollama response returns null gracefully');
  }

  console.log('\nAll things-metadata-enricher tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
