import assert from 'assert';

async function runTests() {
  const agentDb = await import('../lib/agent-db');

  const TEST_AGENT = 'e2e-test-agent-' + Date.now();

  // Register a test agent
  agentDb.upsertAgent({
    agent_name: TEST_AGENT,
    description: 'E2E smoke test agent',
    allowed_action_types: ['things.update_notes', 'things.add_tag'],
    config: { project: 'TestProject' },
  });

  const registered = agentDb.getAgentByName(TEST_AGENT);
  assert.ok(registered, 'Agent should be registered');
  assert.strictEqual(registered.agent_name, TEST_AGENT);
  console.log('  ✓ Agent registered');

  // Simulate a full job lifecycle: running → paused
  const jobId = agentDb.createJob(TEST_AGENT);
  assert.ok(typeof jobId === 'string' && jobId.length > 0, 'createJob should return an ID string');

  const job = agentDb.getJob(jobId);
  assert.strictEqual(job?.status, 'running');
  console.log('  ✓ Job lifecycle: created as running');

  // Write actions (no Things/Ollama — pure SQLite)
  agentDb.insertActions([{
    job_id: jobId,
    action_type: 'things.update_notes',
    target_id: 'fake-task-e2e',
    target_type: 'things_task' as const,
    payload: { notes: 'E2E test context note', taskName: 'Test Task' },
    rationale: 'E2E smoke test',
    confidence: 0.95,
  }]);

  // Write report and pause job
  agentDb.insertReport({ job_id: jobId, title: 'E2E Test Report', body: '## E2E\nTest content' });
  agentDb.updateJobStatus(jobId, 'paused', '1 action pending approval');
  console.log('  ✓ Actions and report written, job paused');

  // Verify paused job appears in queue
  const paused = agentDb.getPausedJobs();
  assert.ok(paused.find((j) => j.id === jobId), 'Job should appear in paused list');
  console.log('  ✓ Job appears in paused queue');

  // Verify action appears as pending
  const pending = agentDb.getPendingActions(jobId);
  assert.strictEqual(pending.length, 1, 'Should have 1 pending action');
  assert.strictEqual(pending[0].status, 'pending');
  console.log('  ✓ Action appears in pending queue');

  // Simulate rejection (safe — no AppleScript)
  agentDb.updateActionStatus(pending[0].id, 'rejected');
  const afterReject = agentDb.getPendingActions(jobId);
  assert.strictEqual(afterReject.length, 0, 'Pending queue should be empty after rejection');
  console.log('  ✓ Action removed from pending after rejection');

  // Complete job
  agentDb.updateJobStatus(jobId, 'complete', 'E2E test complete');
  const completed = agentDb.getJob(jobId);
  assert.strictEqual(completed?.status, 'complete');
  console.log('  ✓ Job completed');

  console.log('\nAll E2E smoke tests passed!');
}

runTests().catch((err) => {
  console.error('E2E tests failed:', err);
  process.exit(1);
});
