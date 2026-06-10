import assert from 'assert';

// Redirect the db.ts singleton (imported transitively via agent-db) to throwaway temp files
// BEFORE agent-db is imported. db.ts opens a real connection on import and would otherwise
// throw the _selene_metadata guard against a fresh DB. The const must sit physically above the
// agent-db import so the env redirect runs first (CommonJS preserves source order).
import { redirectSeleneSingleton } from '../lib/test-two-file-db';
const { restore } = redirectSeleneSingleton('selene-e2e-test-');

import {
  upsertAgent,
  getAgentByName,
  createJob,
  getJob,
  insertActions,
  insertReport,
  updateJobStatus,
  getPausedJobs,
  getPendingActions,
  updateActionStatus,
  runAgentMigrations,
} from '../lib/agent-db';

describe('agents e2e', () => {
  beforeAll(() => {
    // The redirected throwaway DB only has the facts-split schema; create the agent_* tables.
    runAgentMigrations();
  });

  afterAll(() => restore());

  it('E2E smoke test: full agent job lifecycle', () => {
    const TEST_AGENT = 'e2e-test-agent-' + Date.now();

    // Register a test agent
    upsertAgent({
      agent_name: TEST_AGENT,
      description: 'E2E smoke test agent',
      allowed_action_types: ['things.update_notes', 'things.add_tag'],
      config: { project: 'TestProject' },
    });

    const registered = getAgentByName(TEST_AGENT);
    assert.ok(registered, 'Agent should be registered');
    assert.strictEqual(registered.agent_name, TEST_AGENT);

    // Simulate a full job lifecycle: running → paused
    const jobId = createJob(TEST_AGENT);
    assert.ok(typeof jobId === 'string' && jobId.length > 0, 'createJob should return an ID string');

    const job = getJob(jobId);
    assert.strictEqual(job?.status, 'running');

    // Write actions (no Things/Ollama — pure SQLite)
    insertActions([{
      job_id: jobId,
      action_type: 'things.update_notes',
      target_id: 'fake-task-e2e',
      target_type: 'things_task' as const,
      payload: { notes: 'E2E test context note', taskName: 'Test Task' },
      rationale: 'E2E smoke test',
      confidence: 0.95,
    }]);

    // Write report and pause job
    insertReport({ job_id: jobId, title: 'E2E Test Report', body: '## E2E\nTest content' });
    updateJobStatus(jobId, 'paused', '1 action pending approval');

    // Verify paused job appears in queue
    const paused = getPausedJobs();
    assert.ok(paused.find((j) => j.id === jobId), 'Job should appear in paused list');

    // Verify action appears as pending
    const pending = getPendingActions(jobId);
    assert.strictEqual(pending.length, 1, 'Should have 1 pending action');
    assert.strictEqual(pending[0].status, 'pending');

    // Simulate rejection (safe — no AppleScript)
    updateActionStatus(pending[0].id, 'rejected');
    const afterReject = getPendingActions(jobId);
    assert.strictEqual(afterReject.length, 0, 'Pending queue should be empty after rejection');

    // Complete job
    updateJobStatus(jobId, 'complete', 'E2E test complete');
    const completed = getJob(jobId);
    assert.strictEqual(completed?.status, 'complete');
  });
});
