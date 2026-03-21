import { FastifyInstance } from 'fastify';
import { registerDevice, unregisterDevice } from '../lib/db';

export async function devicesRoutes(server: FastifyInstance) {
  // POST /api/devices/register
  server.post<{ Body: { token: string; platform?: string } }>('/api/devices/register', async (request, reply) => {
    const { token, platform = 'ios' } = request.body || {};
    if (!token || typeof token !== 'string') {
      reply.status(400);
      return { error: 'token is required' };
    }
    registerDevice(token, platform);
    return { status: 'registered' };
  });

  // POST /api/devices/unregister
  server.post<{ Body: { token: string } }>('/api/devices/unregister', async (request, reply) => {
    const { token } = request.body || {};
    if (!token || typeof token !== 'string') {
      reply.status(400);
      return { error: 'token is required' };
    }
    unregisterDevice(token);
    return { status: 'unregistered' };
  });
}
