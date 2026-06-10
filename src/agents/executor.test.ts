import assert from 'assert';

// executor → agent-db → ./db opens a real connection on import. Redirect the
// singleton to throwaway temp files BEFORE importing the module under test, so
// the import is harmless and the _selene_metadata guard does not throw under jest.
import { redirectSeleneSingleton } from '../lib/test-two-file-db';
const { restore } = redirectSeleneSingleton('selene-executor-test-');

import { ActionExecutor } from './executor';

describe('executor', () => {
  afterAll(() => restore());

  it('ActionExecutor is exported', () => {
    assert.strictEqual(typeof ActionExecutor, 'function', 'ActionExecutor is a constructor');
  });

  it('Handlers can be registered and checked', () => {
    const executor = new ActionExecutor();
    executor.register('test.action', async (_action) => { /* no-op */ });
    assert.ok(executor.hasHandler('test.action'), 'Handler is registered');
    assert.ok(!executor.hasHandler('test.other'), 'Unknown handler returns false');
  });

  it('Unregistered action type throws descriptive error', async () => {
    const executor = new ActionExecutor();
    try {
      await executor.execute({ id: '1', job_id: 'j1', action_type: 'unknown.action', target_id: 't1', target_type: 'things_task', payload: '{}', rationale: '', confidence: 0.9, status: 'approved', created_at: '', reviewed_at: null, executed_at: null });
      assert.fail('Should have thrown');
    } catch (err) {
      const error = err as Error;
      assert.ok(error.message.includes('unknown.action'), 'Error names the unknown action type');
    }
  });
});
