import assert from 'assert';

process.env.SELENE_ENV = 'test';

async function runTests() {
  const { runAgentMigrations, getAgentRegistry } = await import('./agent-db');

  // Test 1: Tables exist after migration
  {
    runAgentMigrations();
    const rows = getAgentRegistry();
    assert.ok(Array.isArray(rows), 'getAgentRegistry returns an array');
    console.log('  ✓ agent_registry table exists and is queryable');
  }

  console.log('\nAll agent-db migration tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
