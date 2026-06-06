import type { FastifyInstance } from 'fastify';
import {
  getAgentRegistry,
  getAgentByName,
  setAgentEnabled,
  getPausedJobs,
  getPendingActions,
  updateActionStatus,
  getAllReports,
  AgentActionRow,
} from '../lib/agent-db';
import { thingsExecutor } from '../agents/executor';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'agents-route' });

export async function agentRoutes(fastify: FastifyInstance): Promise<void> {

  fastify.get('/agents/status', async () => {
    const registry = getAgentRegistry();
    const pausedJobs = getPausedJobs();
    const pendingActions = getPendingActions();

    return {
      agents: registry,
      pausedJobCount: pausedJobs.length,
      pendingActionCount: pendingActions.length,
    };
  });

  // Single handler for both enable and disable — byte-identical except the boolean.
  // The sole caller (dashboard.ts) builds the URL as `/agents/<name>/<enable|disable>`.
  fastify.post<{ Params: { name: string; action: string } }>('/agents/:name/:action', async (request, reply) => {
    const agent = getAgentByName(request.params.name);
    if (!agent) { reply.status(404); return { error: 'Agent not found' }; }
    setAgentEnabled(request.params.name, request.params.action === 'enable');
    return { ok: true };
  });

  fastify.get('/agents/actions/pending', async () => {
    return { actions: getPendingActions() };
  });

  fastify.post<{ Params: { id: string } }>('/agents/actions/:id/approve', async (request) => {
    updateActionStatus(request.params.id, 'approved');
    void executeApproved(request.params.id);
    return { ok: true };
  });

  fastify.post<{ Params: { id: string } }>('/agents/actions/:id/reject', async (request) => {
    updateActionStatus(request.params.id, 'rejected');
    return { ok: true };
  });

  fastify.put<{
    Params: { id: string };
    Body: { payload: Record<string, unknown> };
  }>('/agents/actions/:id', async (request) => {
    updateActionStatus(request.params.id, 'approved', request.body.payload);
    void executeApproved(request.params.id);
    return { ok: true };
  });

  fastify.get('/agents/reports', async () => {
    return { reports: getAllReports(50) };
  });
}

async function executeApproved(actionId: string): Promise<void> {
  const { db } = await import('../lib/db');
  const action = db.prepare(
    "SELECT * FROM agent_actions WHERE id = ? AND status = 'approved'"
  ).get(actionId) as AgentActionRow | undefined;
  if (!action) return;

  try {
    await thingsExecutor.execute(action);
    log.info({ actionId }, 'Action executed after approval');
  } catch (err) {
    log.error({ err, actionId }, 'Action execution failed after approval');
  }
}
