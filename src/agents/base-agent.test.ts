import assert from 'assert';

async function runTests() {
  const { BaseAgent } = await import('./base-agent');

  // Test 1: BaseAgent is a class
  {
    assert.strictEqual(typeof BaseAgent, 'function', 'BaseAgent is a constructor');
    console.log('  ✓ BaseAgent class is exported');
  }

  // Test 2: Validates action types against allowed list
  {
    class TestAgent extends BaseAgent {
      name = 'test-agent';
      allowedActionTypes = ['test.do_something'];
      async collect() { return { items: [] }; }
      async reason(_data: unknown) {
        return [{ action_type: 'test.do_something', target_id: '1', target_type: 'things_task' as const, payload: {}, rationale: 'test', confidence: 0.9 }];
      }
    }
    const agent = new TestAgent();
    assert.ok(agent.validateActionTypes([{ action_type: 'test.do_something', target_id: '1', target_type: 'things_task', payload: {}, rationale: '', confidence: 0.9 }]), 'Valid action passes');
    assert.ok(!agent.validateActionTypes([{ action_type: 'test.forbidden', target_id: '1', target_type: 'things_task', payload: {}, rationale: '', confidence: 0.9 }]), 'Invalid action fails');
    console.log('  ✓ Action type validation works');
  }

  console.log('\nAll base-agent tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
