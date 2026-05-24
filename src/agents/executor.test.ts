import assert from 'assert';

async function runTests() {
  const { ActionExecutor } = await import('./executor');

  // Test 1: ActionExecutor exists
  {
    assert.strictEqual(typeof ActionExecutor, 'function', 'ActionExecutor is a constructor');
    console.log('  ✓ ActionExecutor is exported');
  }

  // Test 2: Can register and retrieve handlers
  {
    const executor = new ActionExecutor();
    executor.register('test.action', async (_action) => { /* no-op */ });
    assert.ok(executor.hasHandler('test.action'), 'Handler is registered');
    assert.ok(!executor.hasHandler('test.other'), 'Unknown handler returns false');
    console.log('  ✓ Handlers can be registered and checked');
  }

  // Test 3: Unregistered action type throws with descriptive error
  {
    const executor = new ActionExecutor();
    try {
      await executor.execute({ id: '1', job_id: 'j1', action_type: 'unknown.action', target_id: 't1', target_type: 'things_task', payload: '{}', rationale: '', confidence: 0.9, status: 'approved', created_at: '', reviewed_at: null, executed_at: null });
      assert.fail('Should have thrown');
    } catch (err) {
      const error = err as Error;
      assert.ok(error.message.includes('unknown.action'), 'Error names the unknown action type');
      console.log('  ✓ Unregistered action type throws descriptive error');
    }
  }

  console.log('\nAll executor tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
