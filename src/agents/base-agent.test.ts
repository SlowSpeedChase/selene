import assert from 'assert';
import { redirectSeleneSingleton } from '../lib/test-two-file-db';

// base-agent imports ../lib/agent-db which imports ./db (opens a real connection on
// import). Redirect the db.ts singleton to throwaway files BEFORE importing the module
// under test, so the import is harmless under jest.
const { restore } = redirectSeleneSingleton('selene-base-agent-test-');

import { BaseAgent } from './base-agent';

describe('base-agent', () => {
  afterAll(() => restore());

  it('BaseAgent class is exported', () => {
    assert.strictEqual(typeof BaseAgent, 'function', 'BaseAgent is a constructor');
  });

  it('Action type validation works', () => {
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
  });
});
