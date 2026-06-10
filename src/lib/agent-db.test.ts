import assert from 'assert';

import { redirectSeleneSingleton } from './test-two-file-db';

// Redirect the db.ts singleton to throwaway files BEFORE agent-db (which imports ./db) is
// imported — db.ts opens a real connection on import and the dev/test guard would throw on a
// fresh throwaway DB. Forcing production env via the helper skips that guard.
const { restore: restoreSingletonEnv } = redirectSeleneSingleton('selene-agent-db-test-');

import { runAgentMigrations, getAgentRegistry } from './agent-db';

describe('agent-db', () => {
  afterAll(() => {
    restoreSingletonEnv();
  });

  it('agent_registry table exists and is queryable after migration', () => {
    runAgentMigrations();
    const rows = getAgentRegistry();
    assert.ok(Array.isArray(rows), 'getAgentRegistry returns an array');
  });
});
